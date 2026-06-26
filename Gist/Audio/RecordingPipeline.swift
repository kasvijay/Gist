import AVFoundation
import Accelerate
import CoreAudio
import WhisperKit
import os

/// Handles all audio thread work outside of @MainActor.
/// Owns mic capture, system audio capture, mixing, and file writing.
/// RecordingManager delegates to this class and only holds @Published UI state.
/// Pre-allocated buffer holder for mixed output — class wrapper so
/// @Sendable closures capture a let reference, not a mutable var.
final class MixBufferHolder: @unchecked Sendable {
    var buffer: AVAudioPCMBuffer?
}

/// Details of the input device actually used for a recording, surfaced to the UI
/// (for the Bluetooth warning banner) and persisted to session metadata.
struct MicCaptureInfo: Sendable {
    var deviceName: String
    var transport: String
    var sampleRate: Double
    /// Name of the Bluetooth device we declined to record from (forcing the built-in
    /// mic instead), or nil if no override happened.
    var switchedFromBluetooth: String?
    var systemOutputName: String?
}

final class RecordingPipeline: @unchecked Sendable {
    private let mic = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    private let mixer = AudioMixer()
    private let writer = AudioFileWriter()
    private let state = AudioSharedState()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingPipeline")

    private(set) var systemAudioActive = false

    /// Set during `start` once the input device has been chosen. Read by
    /// RecordingManager to warn the user and persist device info to metadata.
    private(set) var micCaptureInfo: MicCaptureInfo?

    /// Callback invoked when an audio device change is detected during recording.
    /// Parameter is true if mic auto-recovered, false if recovery failed.
    var onDeviceChanged: ((_ recovered: Bool) -> Void)?

    /// Callback invoked with audio RMS levels for UI metering.
    var onAudioLevels: ((_ micRMS: Float, _ systemRMS: Float) -> Void)?

    /// Name of the current mic input device.
    var micDeviceName: String? { mic.inputDeviceName }

    private var inputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    // System audio liveness watchdog. The Core Audio tap can silently stop
    // firing its IO proc after an output device/format change (AirPods profile
    // switch) without a default-device-changed notification. A live tap
    // delivers buffers continuously (silence included), so a stale append time
    // reliably means the tap died — at which point we rebuild it.
    private let systemRestartQueue = DispatchQueue(label: "com.vijaykas.gist.systemAudioRestart")
    private var systemWatchdog: DispatchSourceTimer?
    private var pendingSystemRestart: DispatchWorkItem?
    private static let systemStaleThresholdNanos: UInt64 = 2_000_000_000  // 2s without a buffer = dead

    // Pause and mic mute state — accessed from audio threads via lock
    private let controlLock = NSLock()
    private var _isPaused = false
    private var _isMicMuted = false
    private var _levelCallbackCount = 0
    private var _lastSystemRMS: Float = 0
    private var _lastSystemAppendNanos: UInt64 = 0

    func setPaused(_ paused: Bool) {
        controlLock.lock()
        _isPaused = paused
        controlLock.unlock()
    }

    func setMicMuted(_ muted: Bool) {
        controlLock.lock()
        _isMicMuted = muted
        controlLock.unlock()
    }

    private var isPaused: Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return _isPaused
    }

    private var isMicMuted: Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return _isMicMuted
    }

    func start(
        audioURL: URL,
        streamer: StreamingTranscriber?,
        onSegmentsUpdated: @escaping @Sendable ([TranscriptionSegment], [TranscriptionSegment]) -> Void
    ) throws {
        state.reset()
        systemAudioActive = false
        micCaptureInfo = nil

        // Start system audio
        do {
            let capturedControlLock = controlLock
            systemCapture.bufferHandler = { [weak self, mixer, state] bufferList in
                capturedControlLock.lock()
                // Mark the tap alive on every IO proc call (even silent buffers)
                // so the watchdog can tell "no audio playing" from "tap died".
                self?._lastSystemAppendNanos = DispatchTime.now().uptimeNanoseconds
                let paused = self?._isPaused ?? false
                capturedControlLock.unlock()
                if paused { return }

                if let samples = mixer.samplesFromBufferList(bufferList) {
                    state.appendSystemSamples(samples)
                    // Store system RMS for level metering
                    if !samples.isEmpty {
                        var rms: Float = 0
                        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
                        capturedControlLock.lock()
                        self?._lastSystemRMS = rms
                        capturedControlLock.unlock()
                    }
                }
            }
            try systemCapture.start()
            systemAudioActive = true
            controlLock.lock()
            _lastSystemAppendNanos = DispatchTime.now().uptimeNanoseconds
            controlLock.unlock()
            logger.info("System audio capture active")
        } catch {
            logger.info("System audio not available: \(error.localizedDescription)")
        }

        let captureSystem = systemAudioActive

        // Capture everything explicitly — no implicit captures, no self
        let capturedWriter = writer
        let capturedMixer = mixer
        let capturedState = state
        let capturedStreamer = streamer

        let mixHolder = MixBufferHolder()

        // Start mic with mixing
        let capturedControlLock = controlLock
        mic.bufferHandler = { [weak self] buffer in
            // Check pause/mute state
            capturedControlLock.lock()
            let paused = self?._isPaused ?? false
            let micMuted = self?._isMicMuted ?? false
            self?._levelCallbackCount = (self?._levelCallbackCount ?? 0) + 1
            let shouldReportLevels = (self?._levelCallbackCount ?? 0) % 5 == 0
            let systemRMS = self?._lastSystemRMS ?? 0
            capturedControlLock.unlock()

            if paused { return }

            // Send mic audio to streaming transcriber (unless muted)
            if !micMuted {
                capturedStreamer?.appendBuffer(buffer)
            }

            // Compute and report audio levels every 5th callback (~10Hz)
            if shouldReportLevels, let floatData = buffer.floatChannelData {
                let frameCount = Int(buffer.frameLength)
                var micRMS: Float = 0
                vDSP_rmsqv(floatData[0], 1, &micRMS, vDSP_Length(frameCount))
                self?.onAudioLevels?(micMuted ? 0 : micRMS, systemRMS)
            }

            if captureSystem {
                if capturedState.shouldSkipWriter() {
                    return
                }

                if let floatData = buffer.floatChannelData {
                    let frameCount = Int(buffer.frameLength)
                    let sysSamples = capturedState.consumeSystemSamples(count: frameCount)

                    if !sysSamples.isEmpty {
                        if mixHolder.buffer == nil || mixHolder.buffer!.frameCapacity < AVAudioFrameCount(frameCount) {
                            mixHolder.buffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frameCount))
                        }

                        if micMuted {
                            // Mic muted: write only system audio (use system samples directly)
                            if let outBuf = mixHolder.buffer {
                                capturedMixer.mixInto(outputBuffer: outBuf, micMuted: true, micPtr: floatData[0], micCount: frameCount, systemSamples: sysSamples)
                                capturedWriter.append(buffer: outBuf)
                            }
                        } else if let outBuf = mixHolder.buffer,
                           capturedMixer.mixInto(outputBuffer: outBuf, micPtr: floatData[0], micCount: frameCount, systemSamples: sysSamples) {
                            capturedWriter.append(buffer: outBuf)
                        } else {
                            capturedWriter.append(buffer: buffer)
                        }
                    } else if micMuted {
                        // Muted but no system samples yet — write silence to maintain timeline
                        Self.writeSilence(from: buffer, mixHolder: mixHolder, writer: capturedWriter)
                    } else {
                        capturedWriter.append(buffer: buffer)
                    }
                } else if micMuted {
                    Self.writeSilence(from: buffer, mixHolder: mixHolder, writer: capturedWriter)
                } else {
                    capturedWriter.append(buffer: buffer)
                }
            } else if micMuted {
                Self.writeSilence(from: buffer, mixHolder: mixHolder, writer: capturedWriter)
            } else {
                capturedWriter.append(buffer: buffer)
            }
        }

        // Avoid recording through a Bluetooth mic. AirPods (and most BT headsets)
        // drop to the narrowband HFP/SCO "call" profile the moment their mic opens,
        // crushing the captured audio to ~8 kHz telephone quality. If the default
        // input is Bluetooth and a built-in mic exists, record from the built-in mic
        // instead and remember the device we declined so the UI can explain why.
        let defaultInput = AudioDeviceUtils.defaultInput()
        var switchedFromBluetooth: String?
        if let defaultInput, defaultInput.isBluetooth,
           let builtIn = AudioDeviceUtils.builtInInput() {
            mic.preferredDeviceID = builtIn.id
            switchedFromBluetooth = defaultInput.name
            logger.info("Default input '\(defaultInput.name)' is Bluetooth — recording from built-in mic '\(builtIn.name)' instead")
        }

        try mic.startWithHandler()

        // Wire mic recovery callback — when mic auto-recovers after device switch,
        // notify the pipeline so the warning can be cleared
        mic.onRecovered = { [weak self] in
            self?.onDeviceChanged?(true)
        }
        // Recovery permanently failed. We deliberately keep `writer` running
        // so the WAV captured so far stays intact — the user can stop the
        // recording and we'll still have everything up to this point.
        mic.onRecoveryFailed = { [weak self] in
            self?.onDeviceChanged?(false)
        }

        guard let format = mic.inputFormat else {
            throw MicrophoneCapture.CaptureError.invalidFormat
        }

        // Transport of the device actually used: built-in if we overrode a BT default,
        // otherwise whatever the default input reported.
        let usedTransport = switchedFromBluetooth != nil ? "Built-in" : (defaultInput?.transport ?? "Unknown")
        micCaptureInfo = MicCaptureInfo(
            deviceName: mic.inputDeviceName ?? "Unknown Microphone",
            transport: usedTransport,
            sampleRate: format.sampleRate,
            switchedFromBluetooth: switchedFromBluetooth,
            systemOutputName: AudioDeviceUtils.defaultOutput()?.name
        )

        // Note: writer starts after mic because we need mic.inputFormat.
        // A few initial buffers may be dropped (writer.append checks _isWriting).
        // With WAV format, this is safe — no crash-corruption risk.
        try writer.start(outputURL: audioURL, sourceFormat: format)

        // Start streaming
        if let streamer {
            streamer.onSegmentsUpdated = onSegmentsUpdated
        }

        startDeviceChangeMonitoring()
        if systemAudioActive {
            startSystemWatchdog()
        }

        logger.info("Recording pipeline started, systemAudio: \(self.systemAudioActive)")
    }

    func stop() {
        stopDeviceChangeMonitoring()
        stopSystemWatchdog()
        // Gate restarts off, cancel any pending one, then drain the restart
        // queue so an in-flight rebuild can't race systemCapture.stop().
        systemAudioActive = false
        controlLock.lock()
        pendingSystemRestart?.cancel()
        pendingSystemRestart = nil
        controlLock.unlock()
        systemRestartQueue.sync { }
        mic.stop()
        systemCapture.stop()
        writer.finish()
        state.reset()
        onDeviceChanged = nil
        onAudioLevels = nil
        controlLock.lock()
        _isPaused = false
        _isMicMuted = false
        _levelCallbackCount = 0
        _lastSystemRMS = 0
        _lastSystemAppendNanos = 0
        controlLock.unlock()
    }

    // MARK: - Silent Buffer Helper

    /// Write a zeroed buffer to maintain audio timeline when mic is muted
    /// and no system samples are available. Prevents frame drops with Bluetooth audio.
    private static func writeSilence(from sourceBuffer: AVAudioPCMBuffer, mixHolder: MixBufferHolder, writer: AudioFileWriter) {
        let frameCount = sourceBuffer.frameLength
        let outBuf: AVAudioPCMBuffer
        if let existing = mixHolder.buffer, existing.frameCapacity >= frameCount {
            outBuf = existing
        } else if let created = AVAudioPCMBuffer(pcmFormat: sourceBuffer.format, frameCapacity: frameCount) {
            mixHolder.buffer = created
            outBuf = created
        } else {
            return
        }
        outBuf.frameLength = frameCount
        if let ch = outBuf.floatChannelData {
            let byteCount = Int(frameCount) * MemoryLayout<Float>.size
            memset(ch[0], 0, byteCount)
            for c in 1..<Int(outBuf.format.channelCount) {
                memset(ch[c], 0, byteCount)
            }
        }
        writer.append(buffer: outBuf)
    }

    // MARK: - System Audio Liveness & Recovery

    /// Periodically check that the system tap is still delivering buffers.
    /// If it has gone silent (no IO proc call within the stale threshold) while
    /// system capture is supposed to be active, rebuild the tap. This catches
    /// the case where an output format switch kills the tap without changing
    /// the default output device (so the device-change listener never fires).
    private func startSystemWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: systemRestartQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, self.systemAudioActive else { return }
            self.controlLock.lock()
            let last = self._lastSystemAppendNanos
            self.controlLock.unlock()
            let now = DispatchTime.now().uptimeNanoseconds
            if last != 0, now > last, now - last > Self.systemStaleThresholdNanos {
                self.logger.warning("System audio tap went silent — rebuilding")
                self.restartSystemAudio()
            }
        }
        systemWatchdog = timer
        timer.resume()
    }

    private func stopSystemWatchdog() {
        systemWatchdog?.cancel()
        systemWatchdog = nil
    }

    /// Debounced restart — a single routing change emits a burst of
    /// notifications, so collapse them into one rebuild.
    private func scheduleSystemAudioRestart() {
        guard systemAudioActive else { return }
        let work = DispatchWorkItem { [weak self] in self?.restartSystemAudio() }
        controlLock.lock()
        pendingSystemRestart?.cancel()
        pendingSystemRestart = work
        controlLock.unlock()
        systemRestartQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Rebuild the system tap against the current output device. Runs on
    /// `systemRestartQueue` so HAL teardown never blocks an audio thread.
    /// On failure the recording is preserved — the mic callback just falls
    /// back to writing mic-only buffers until the next recovery attempt.
    private func restartSystemAudio() {
        guard systemAudioActive else { return }
        // Bump liveness so the watchdog grants the new tap a grace period to
        // start delivering before judging it stale again — rate-limits retries.
        controlLock.lock()
        _lastSystemAppendNanos = DispatchTime.now().uptimeNanoseconds
        controlLock.unlock()
        do {
            try systemCapture.restart()
            logger.info("System audio capture restarted after device change")
        } catch {
            logger.error("System audio restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio Device Change Monitoring

    private func startDeviceChangeMonitoring() {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.logger.warning("Audio device changed during recording")
            // Report as not-yet-recovered; mic will fire onRecovered if it succeeds
            self?.onDeviceChanged?(false)
            // The default output device changed — the system tap's aggregate
            // device is now likely orphaned. Rebuild it (debounced, since a
            // single routing change emits a burst of notifications).
            self?.scheduleSystemAudioRestart()
        }

        inputDeviceListenerBlock = handler
        outputDeviceListenerBlock = handler

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddress,
            nil,
            handler
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            nil,
            handler
        )
    }

    private func stopDeviceChangeMonitoring() {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let block = inputDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &inputAddress,
                nil,
                block
            )
        }
        if let block = outputDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputAddress,
                nil,
                block
            )
        }
        inputDeviceListenerBlock = nil
        outputDeviceListenerBlock = nil
    }

}
