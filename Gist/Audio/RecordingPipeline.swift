import AVFoundation
import Accelerate
import CoreAudio
import WhisperKit
import os

/// Handles all audio thread work outside of @MainActor.
/// Owns mic capture, system audio capture, mixing, and file writing.
/// RecordingManager delegates to this class and only holds @Published UI state.
final class RecordingPipeline: @unchecked Sendable {
    private let mic = MicrophoneCapture()
    private let systemCapture = SystemAudioCapture()
    private let mixer = AudioMixer()
    private let writer = AudioFileWriter()
    private let state = AudioSharedState()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "RecordingPipeline")

    private(set) var systemAudioActive = false

    /// Callback invoked when an audio device change is detected during recording.
    /// Parameter is true if mic auto-recovered, false if recovery failed.
    var onDeviceChanged: ((_ recovered: Bool) -> Void)?

    /// Callback invoked with audio RMS levels for UI metering.
    var onAudioLevels: ((_ micRMS: Float, _ systemRMS: Float) -> Void)?

    /// Name of the current mic input device.
    var micDeviceName: String? { mic.inputDeviceName }

    private var inputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    // Pause and mic mute state — accessed from audio threads via lock
    private let controlLock = NSLock()
    private var _isPaused = false
    private var _isMicMuted = false
    private var _levelCallbackCount = 0
    private var _lastSystemRMS: Float = 0

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

        // Start system audio
        do {
            let capturedControlLock = controlLock
            systemCapture.bufferHandler = { [weak self, mixer, state] bufferList in
                capturedControlLock.lock()
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

        // Pre-allocated buffer holder for mixed output — class wrapper so the
        // @Sendable closure captures a let reference, not a mutable var.
        class MixBufferHolder: @unchecked Sendable {
            var buffer: AVAudioPCMBuffer?
        }
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
                    } else if !micMuted {
                        capturedWriter.append(buffer: buffer)
                    }
                } else if !micMuted {
                    capturedWriter.append(buffer: buffer)
                }
            } else if !micMuted {
                capturedWriter.append(buffer: buffer)
            }
        }

        try mic.startWithHandler()

        // Wire mic recovery callback — when mic auto-recovers after device switch,
        // notify the pipeline so the warning can be cleared
        mic.onRecovered = { [weak self] in
            self?.onDeviceChanged?(true)
        }

        guard let format = mic.inputFormat else {
            throw MicrophoneCapture.CaptureError.invalidFormat
        }

        // Note: writer starts after mic because we need mic.inputFormat.
        // A few initial buffers may be dropped (writer.append checks _isWriting).
        // With WAV format, this is safe — no crash-corruption risk.
        try writer.start(outputURL: audioURL, sourceFormat: format)

        // Start streaming
        if let streamer {
            streamer.onSegmentsUpdated = onSegmentsUpdated
        }

        startDeviceChangeMonitoring()

        logger.info("Recording pipeline started, systemAudio: \(self.systemAudioActive)")
    }

    func stop() {
        stopDeviceChangeMonitoring()
        mic.stop()
        systemCapture.stop()
        writer.finish()
        state.reset()
        systemAudioActive = false
        onDeviceChanged = nil
        onAudioLevels = nil
        controlLock.lock()
        _isPaused = false
        _isMicMuted = false
        _levelCallbackCount = 0
        _lastSystemRMS = 0
        controlLock.unlock()
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
