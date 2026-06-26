import AVFoundation
import CoreAudio
import os

final class MicrophoneCapture: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "MicrophoneCapture")

    private(set) var isCapturing = false
    private(set) var inputFormat: AVAudioFormat?
    private(set) var inputDeviceName: String?

    /// When set, the capture engine is bound to this specific input device instead
    /// of the system default. Gist uses this to force recording through the built-in
    /// mic when the default input is a Bluetooth device in narrowband call mode.
    /// Set before `start` / `startWithHandler`.
    var preferredDeviceID: AudioDeviceID?

    /// Stored handler for use with RecordingPipeline
    var bufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Callback when mic successfully recovers after a device change
    var onRecovered: (() -> Void)?

    /// Callback when mic recovery permanently fails. The audio file writer is
    /// intentionally NOT torn down by this class — keeping it alive lets the
    /// user stop the recording and retain everything captured up to this point.
    var onRecoveryFailed: (() -> Void)?

    private var configObserver: NSObjectProtocol?

    /// Start using stored bufferHandler
    func startWithHandler() throws {
        guard let handler = bufferHandler else {
            throw CaptureError.invalidFormat
        }
        try start { buffer, _ in handler(buffer) }
    }

    /// Start capturing microphone audio. Calls handler on the audio thread with PCM buffers.
    func start(bufferHandler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        var lastError: Error = CaptureError.invalidFormat
        for attempt in 0..<3 {
            // Each retry uses a fresh engine — a failed installTap or
            // engine.start() can leave the engine in a corrupted state that
            // no amount of stop/removeTap fixes.
            engine = AVAudioEngine()
            stopConfigurationChangeMonitoring()

            // Touch mainMixerNode to force proper audio graph initialization.
            _ = engine.mainMixerNode
            let inputNode = engine.inputNode
            bindPreferredDevice(inputNode)
            let nodeFormat = inputNode.outputFormat(forBus: 0)

            // Validate the node's bus format BEFORE attempting the tap. A
            // zero-rate format means the audio device isn't ready (mid-
            // transition or no input). Bail and let the caller retry.
            guard nodeFormat.sampleRate > 0, nodeFormat.channelCount > 0 else {
                logger.warning("Mic start attempt \(attempt): node format invalid (sr=\(nodeFormat.sampleRate), ch=\(nodeFormat.channelCount))")
                lastError = CaptureError.invalidFormat
                continue
            }

            // Use nil format → engine picks the bus's current format itself.
            // This is the only NSException-proof way; any explicit format we
            // pick can race with a device change between read and install.
            var tapError: NSError?
            let installed = GistInstallAudioTap(inputNode, nil, 0, 4096, { buffer, time in
                bufferHandler(buffer, time)
            }, &tapError)
            guard installed else {
                logger.warning("Mic start attempt \(attempt): installTap raised \(tapError?.localizedDescription ?? "unknown") (bus format was \(nodeFormat.sampleRate)Hz/\(nodeFormat.channelCount)ch)")
                lastError = tapError ?? CaptureError.invalidFormat
                continue
            }
            engine.prepare()

            var startError: NSError?
            let started = GistStartAudioEngine(engine, &startError)
            if started {
                inputFormat = inputNode.outputFormat(forBus: 0)
                isCapturing = true
                inputDeviceName = AudioDeviceUtils.name(for: inputNode.auAudioUnit.deviceID)
                    ?? AVCaptureDevice.default(for: .audio)?.localizedName
                startConfigurationChangeMonitoring()

                let fmt = inputFormat!
                logger.info("Mic capture started: \(fmt.sampleRate)Hz, \(fmt.channelCount)ch, device: \(self.inputDeviceName ?? "unknown")")
                return
            }
            logger.warning("Mic start attempt \(attempt): engine.start failed: \(startError?.localizedDescription ?? "unknown")")
            engine.stop()
            inputNode.removeTap(onBus: 0)
            lastError = startError ?? CaptureError.invalidFormat
        }

        throw lastError
    }

    func stop() {
        guard isCapturing else { return }
        stopConfigurationChangeMonitoring()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        logger.info("Microphone capture stopped")
    }

    /// Bind the engine's input to `preferredDeviceID` (the built-in mic) before the
    /// tap is installed. Best-effort: if the device is gone or the AU rejects it, we
    /// fall back to the system default rather than failing the recording.
    private func bindPreferredDevice(_ inputNode: AVAudioInputNode) {
        guard let deviceID = preferredDeviceID else { return }
        do {
            try inputNode.auAudioUnit.setDeviceID(deviceID)
            logger.info("Bound mic capture to preferred device \(deviceID)")
        } catch {
            logger.warning("Could not bind preferred input device \(deviceID): \(error.localizedDescription) — using default")
        }
    }

    // MARK: - Device Change Recovery

    private func startConfigurationChangeMonitoring() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func stopConfigurationChangeMonitoring() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
    }

    private func handleConfigurationChange() {
        guard let handler = bufferHandler else { return }

        logger.warning("Audio configuration changed — restarting mic capture")

        // Tear down the old engine. The downstream AudioFileWriter is NOT
        // touched — anything captured so far stays in the WAV regardless of
        // whether mic recovery succeeds. That's the "recording is preserved
        // at all costs" guarantee.
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        stopConfigurationChangeMonitoring()

        for attempt in 0..<3 {
            engine = AVAudioEngine()
            _ = engine.mainMixerNode
            let inputNode = engine.inputNode
            bindPreferredDevice(inputNode)
            let nodeFormat = inputNode.outputFormat(forBus: 0)

            // Node format may briefly be 0/0 during a device hot-swap. Sleep
            // a hair and retry — full bail-out happens after `attempt` ≥ 3.
            guard nodeFormat.sampleRate > 0, nodeFormat.channelCount > 0 else {
                logger.warning("Recovery attempt \(attempt): node format not yet valid")
                Thread.sleep(forTimeInterval: 0.15)
                continue
            }

            var tapError: NSError?
            let installed = GistInstallAudioTap(inputNode, nil, 0, 4096, { buffer, _ in
                handler(buffer)
            }, &tapError)
            guard installed else {
                logger.warning("Recovery attempt \(attempt): installTap raised \(tapError?.localizedDescription ?? "unknown")")
                continue
            }
            engine.prepare()

            var startError: NSError?
            if GistStartAudioEngine(engine, &startError) {
                inputFormat = inputNode.outputFormat(forBus: 0)
                isCapturing = true
                startConfigurationChangeMonitoring()
                let fmt = inputFormat!
                logger.info("Mic recovered after device change: \(fmt.sampleRate)Hz, \(fmt.channelCount)ch")
                onRecovered?()
                return
            }
            engine.stop()
            inputNode.removeTap(onBus: 0)
            logger.warning("Recovery attempt \(attempt): engine.start failed: \(startError?.localizedDescription ?? "unknown")")
        }

        logger.error("All mic recovery attempts failed — writer remains active so existing audio is preserved")
        // Flip our local flag so any caller asking knows mic is dead, but
        // do NOT propagate this down to AudioFileWriter. The writer keeps
        // whatever's already on disk.
        isCapturing = false
        onRecoveryFailed?()
    }

    enum CaptureError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "Microphone audio format is invalid. Check microphone permissions in System Settings → Privacy & Security → Microphone."
            }
        }
    }
}
