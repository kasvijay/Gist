import AVFoundation
import os

final class MicrophoneCapture: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "MicrophoneCapture")

    private(set) var isCapturing = false
    private(set) var inputFormat: AVAudioFormat?

    /// Stored handler for use with RecordingPipeline
    var bufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Callback when mic successfully recovers after a device change
    var onRecovered: (() -> Void)?

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
        // Attempt strategies in order until one works:
        // 1. Native format from inputNode
        // 2. nil format (engine chooses) on a fresh engine
        // 3. Explicit 48kHz mono on a fresh engine (safe fallback)

        let strategies: [(String, AVAudioFormat?)] = {
            var list: [(String, AVAudioFormat?)] = []

            // Force graph initialization by touching mainMixerNode first
            _ = engine.mainMixerNode
            let native = engine.inputNode.outputFormat(forBus: 0)
            if native.sampleRate > 0 && native.channelCount > 0 {
                list.append(("native \(native.sampleRate)Hz/\(native.channelCount)ch", native))
            }
            list.append(("engine-chosen (nil)", nil))

            if let fallback = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) {
                list.append(("48kHz mono fallback", fallback))
            }
            return list
        }()

        var lastError: Error = CaptureError.invalidFormat

        for (label, format) in strategies {
            // Each retry gets a fresh engine — a failed engine.start() can leave
            // the engine in a corrupted state that no amount of stop/removeTap fixes.
            engine = AVAudioEngine()
            stopConfigurationChangeMonitoring()

            // Touch mainMixerNode to force proper audio graph initialization
            _ = engine.mainMixerNode
            let inputNode = engine.inputNode

            // installTap throws NSException (not Swift error) on format mismatch,
            // so validate channel count before attempting the tap.
            if let fmt = format {
                let nodeFormat = inputNode.outputFormat(forBus: 0)
                if nodeFormat.sampleRate > 0 && fmt.channelCount != nodeFormat.channelCount {
                    logger.warning("Skipping \(label): channel count mismatch (\(fmt.channelCount) vs \(nodeFormat.channelCount))")
                    lastError = CaptureError.invalidFormat
                    continue
                }
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
                bufferHandler(buffer, time)
            }
            engine.prepare()

            do {
                try engine.start()
                // Success — read the actual format
                inputFormat = format ?? inputNode.outputFormat(forBus: 0)
                isCapturing = true
                startConfigurationChangeMonitoring()

                let fmt = inputFormat!
                logger.info("Mic capture started (\(label)): \(fmt.sampleRate)Hz, \(fmt.channelCount)ch")
                return
            } catch {
                logger.warning("Mic start failed with \(label): \(error.localizedDescription)")
                engine.stop()
                inputNode.removeTap(onBus: 0)
                lastError = error
            }
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
        guard isCapturing, let handler = bufferHandler else { return }

        logger.warning("Audio configuration changed — restarting mic capture")

        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        stopConfigurationChangeMonitoring()

        // Build format strategies — fresh engine per attempt (mirrors start())
        // Try: new device's native format, engine-chosen (nil), 48kHz mono fallback
        var strategies: [(String, AVAudioFormat?)] = []

        // Read native format from a fresh engine to pick up the new device
        let probeEngine = AVAudioEngine()
        _ = probeEngine.mainMixerNode
        let native = probeEngine.inputNode.outputFormat(forBus: 0)
        if native.sampleRate > 0 && native.channelCount > 0 {
            strategies.append(("native \(native.sampleRate)Hz/\(native.channelCount)ch", native))
        }
        strategies.append(("engine-chosen (nil)", nil))
        if let fallback = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) {
            strategies.append(("48kHz mono fallback", fallback))
        }

        for (label, format) in strategies {
            // Fresh engine per attempt — a failed installTap/start leaves the engine
            // in a corrupted state that can't be reused.
            engine = AVAudioEngine()
            _ = engine.mainMixerNode
            let inputNode = engine.inputNode

            // installTap throws NSException (not Swift error) on format mismatch,
            // so we must validate the format before attempting the tap.
            if let fmt = format {
                let nodeFormat = inputNode.outputFormat(forBus: 0)
                if nodeFormat.sampleRate > 0 && fmt.channelCount != nodeFormat.channelCount {
                    logger.warning("Skipping \(label): channel count mismatch (\(fmt.channelCount) vs \(nodeFormat.channelCount))")
                    continue
                }
            }

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                handler(buffer)
            }
            engine.prepare()
            do {
                try engine.start()
                inputFormat = format ?? inputNode.outputFormat(forBus: 0)
                isCapturing = true
                startConfigurationChangeMonitoring()
                let fmt = inputFormat!
                logger.info("Mic recovered after device change (\(label)): \(fmt.sampleRate)Hz, \(fmt.channelCount)ch")
                onRecovered?()
                return
            } catch {
                engine.stop()
                inputNode.removeTap(onBus: 0)
                logger.warning("Recovery attempt failed with \(label): \(error.localizedDescription)")
            }
        }

        logger.error("All mic recovery attempts failed")
        isCapturing = false
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
