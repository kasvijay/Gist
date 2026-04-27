import Foundation
import WhisperKit
import os

@MainActor
final class TranscriptionEngine: ObservableObject {
    enum State: Equatable {
        case notLoaded
        case downloading(String, Float) // model name, progress 0.0–1.0
        case loading(String)
        case ready
        case transcribing(Float)
        case streaming
        case error(String)
    }

    @Published var state: State = .notLoaded
    @Published var lastTranscript: Transcript?
    @Published var liveConfirmedSegments: [TranscriptionSegment] = []
    @Published var liveUnconfirmedSegments: [TranscriptionSegment] = []

    private let worker = TranscriptionWorker()
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "TranscriptionEngine")

    var modelName: String = "large-v3_turbo"
    var customModelFolder: String?

    @Published var showDownloadComplete = false

    func loadModel() async {
        if let customModelFolder {
            state = .loading(modelName)
            do {
                try await worker.load(model: modelName, modelFolder: customModelFolder)
                state = .ready
                logger.info("WhisperKit model loaded from custom folder: \(self.modelName)")
            } catch {
                state = .error("Failed to load model: \(error.localizedDescription)")
                logger.error("Failed to load WhisperKit: \(error)")
            }
            return
        }

        // Check if model is already cached locally
        if let cachedFolder = findCachedModel(modelName) {
            state = .loading(modelName)
            logger.info("Loading WhisperKit model from cache: \(self.modelName)")
            do {
                try await worker.load(modelFolder: cachedFolder)
                state = .ready
                logger.info("WhisperKit model loaded from cache: \(self.modelName)")
            } catch {
                state = .error("Failed to load cached model: \(error.localizedDescription)")
                logger.error("Failed to load cached WhisperKit: \(error)")
            }
            return
        }

        // Model not cached — download it
        state = .downloading(modelName, 0)
        logger.info("Downloading WhisperKit model: \(self.modelName)")

        do {
            let name = modelName
            let modelFolder = try await WhisperKit.download(variant: name) { @Sendable progress in
                let fraction = Float(progress.fractionCompleted)
                Task { @MainActor [weak self] in
                    self?.state = .downloading(name, fraction)
                }
            }
            state = .loading(modelName)
            showDownloadComplete = true
            try await worker.load(modelFolder: modelFolder.path)
            state = .ready
            logger.info("WhisperKit model downloaded and loaded: \(self.modelName)")
        } catch {
            if Self.isOfflineModelError(error) {
                state = .error("Connect to the internet to download this model.")
            } else {
                state = .error("Failed to download model: \(error.localizedDescription)")
            }
            logger.error("Failed to download WhisperKit: \(error)")
        }
    }

    /// Detect network/offline errors from WhisperKit/HuggingFace Hub.
    /// These often wrap the real NSURLError several layers deep.
    private static func isOfflineModelError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            // -1009: not connected, -1020: no internet, -1200: SSL/offline
            return [-1009, -1020, -1200].contains(nsError.code)
        }
        // Walk underlying errors (WhisperKit/Hub wraps network errors)
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOfflineModelError(underlying)
        }
        // String fallback for Hub errors that don't expose the network error cleanly
        let desc = error.localizedDescription.lowercased()
        return desc.contains("offlinemodeerror") || desc.contains("not connected") || desc.contains("network")
    }

    /// Check if a WhisperKit model variant is already cached locally.
    private func findCachedModel(_ model: String) -> String? {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml")
            .appendingPathComponent("snapshots")
        guard let snapshots = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil
        ) else { return nil }
        for snapshot in snapshots {
            let modelDir = snapshot.appendingPathComponent("openai_whisper-\(model)")
            // Verify the model directory exists and has actual model files
            if FileManager.default.fileExists(atPath: modelDir.path),
               let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path),
               files.contains(where: { $0.hasSuffix(".mlmodelc") }) {
                return modelDir.path
            }
        }
        return nil
    }

    /// Check if the model files are cached on disk (no download needed).
    var isModelCached: Bool {
        findCachedModel(modelName) != nil
    }

    /// Check if the model is loaded and usable.
    var isModelLoaded: Bool {
        worker.whisperKit != nil
    }

    /// Unload the WhisperKit model to free memory (e.g. before summarization).
    func unloadModel() {
        worker.unload()
        state = .notLoaded
        logger.info("WhisperKit model unloaded to free memory")
    }

    /// Create a streaming transcriber using the loaded WhisperKit instance.
    func makeStreamingTranscriber(sampleRate: Double) -> StreamingTranscriber? {
        guard let pipe = worker.whisperKit else { return nil }
        return StreamingTranscriber(whisperKit: pipe, sampleRate: sampleRate)
    }

    /// Start live streaming mode.
    func startStreaming() {
        state = .streaming
        liveConfirmedSegments = []
        liveUnconfirmedSegments = []
        lastTranscript = nil
    }

    /// Update live segments from streaming transcriber callback.
    func updateLiveSegments(confirmed: [TranscriptionSegment], unconfirmed: [TranscriptionSegment]) {
        liveConfirmedSegments = confirmed
        liveUnconfirmedSegments = unconfirmed
    }

    /// Finalize streaming: convert live segments to a Transcript.
    func finalizeStreaming(allSegments: [TranscriptionSegment], duration: Double) -> Transcript? {
        guard !allSegments.isEmpty else {
            state = .ready
            return nil
        }

        let transcript = Transcript.from(
            whisperSegments: allSegments,
            duration: duration,
            model: modelName,
            language: "en"
        )

        lastTranscript = transcript
        liveConfirmedSegments = []
        liveUnconfirmedSegments = []
        state = .ready
        return transcript
    }

    /// Transcribe a saved audio file (for re-transcription or non-streaming fallback).
    func transcribe(audioPath: String, duration: Double) async -> Transcript? {
        state = .transcribing(0)
        logger.info("Transcribing: \(audioPath)")

        do {
            let audioDuration = max(duration, 1)
            let expectedWindows = Int(ceil(audioDuration / 30.0))
            let result = try await worker.transcribe(audioPath: audioPath) { progress in
                let pct = Float(min(Double(progress.windowId + 1) / Double(expectedWindows), 0.99))
                Task { @MainActor in
                    self.state = .transcribing(pct)
                }
                return nil // continue transcription
            }

            guard let result else {
                state = .ready // Model still loaded, just no result
                return nil
            }

            let transcript = Transcript.from(
                whisperSegments: result.segments,
                duration: duration,
                model: modelName,
                language: result.language
            )

            lastTranscript = transcript
            state = .ready
            logger.info("Transcription complete: \(result.segments.count) segments")
            return transcript

        } catch {
            logger.error("Transcription failed: \(error)")
            // Model is still loaded — return to ready so user can try again
            if worker.whisperKit != nil {
                state = .ready
            } else {
                state = .error("Transcription failed: \(error.localizedDescription)")
            }
            return nil
        }
    }
}

/// Non-isolated worker that owns WhisperKit to avoid Sendable issues.
final class TranscriptionWorker: @unchecked Sendable {
    private(set) var whisperKit: WhisperKit?

    func unload() {
        whisperKit = nil
    }

    func load(model: String, modelFolder: String? = nil) async throws {
        let config = WhisperKitConfig(
            model: model == "custom" ? nil : model,
            modelFolder: modelFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: modelFolder == nil
        )
        whisperKit = try await WhisperKit(config)
    }

    func load(modelFolder: String) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(
        audioPath: String,
        callback: @escaping @Sendable (TranscriptionProgress) -> Bool?
    ) async throws -> TranscriptionResult? {
        guard let pipe = whisperKit else { return nil }
        let results = try await pipe.transcribe(
            audioPath: audioPath,
            decodeOptions: DecodingOptions(usePrefillPrompt: false, detectLanguage: true, wordTimestamps: true),
            callback: { progress in callback(progress) }
        )
        return results.first
    }
}
