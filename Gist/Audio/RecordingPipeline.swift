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

    private var inputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?

    func start(
        audioURL: URL,
        streamer: StreamingTranscriber?,
        onSegmentsUpdated: @escaping @Sendable ([TranscriptionSegment], [TranscriptionSegment]) -> Void
    ) throws {
        state.reset()
        systemAudioActive = false

        // Start system audio
        do {
            systemCapture.bufferHandler = { [mixer, state] bufferList in
                if let samples = mixer.samplesFromBufferList(bufferList) {
                    state.appendSystemSamples(samples)
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

        // Pre-allocated buffer for mixed output — avoids heap allocation on every callback
        var mixOutputBuffer: AVAudioPCMBuffer?

        // Start mic with mixing
        mic.bufferHandler = { buffer in
            capturedStreamer?.appendBuffer(buffer)

            if captureSystem {
                if capturedState.shouldSkipWriter() {
                    return
                }

                if let floatData = buffer.floatChannelData {
                    let frameCount = Int(buffer.frameLength)
                    let sysSamples = capturedState.consumeSystemSamples(count: frameCount)

                    if !sysSamples.isEmpty {
                        // Ensure reusable output buffer exists with enough capacity
                        if mixOutputBuffer == nil || mixOutputBuffer!.frameCapacity < AVAudioFrameCount(frameCount) {
                            mixOutputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frameCount))
                        }

                        // Mix directly into pre-allocated buffer — zero intermediate allocations
                        if let outBuf = mixOutputBuffer,
                           capturedMixer.mixInto(outputBuffer: outBuf, micPtr: floatData[0], micCount: frameCount, systemSamples: sysSamples) {
                            capturedWriter.append(buffer: outBuf)
                        } else {
                            capturedWriter.append(buffer: buffer)
                        }
                    } else {
                        capturedWriter.append(buffer: buffer)
                    }
                } else {
                    capturedWriter.append(buffer: buffer)
                }
            } else {
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
