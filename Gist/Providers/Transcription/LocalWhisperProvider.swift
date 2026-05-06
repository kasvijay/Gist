import Foundation

final class LocalWhisperProvider: TranscriptionProvider, @unchecked Sendable {
    let providerID: ProviderID = .localWhisper
    let providesDiarization = false
    let maxFileSizeBytes: Int64? = nil

    private let engine: TranscriptionEngine

    init(engine: TranscriptionEngine) {
        self.engine = engine
    }

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        // Ensure model is loaded
        await MainActor.run {
            if engine.modelName != modelID {
                engine.modelName = modelID
            }
        }

        let isLoaded = await MainActor.run { engine.isModelLoaded }
        if !isLoaded {
            await engine.loadModel()
        }

        progress(.processing)

        guard let transcript = await engine.transcribe(audioPath: audioURL.path, duration: duration) else {
            throw ProviderError.transcriptionFailed("Local Whisper transcription returned no results")
        }

        progress(.complete)
        return transcript
    }
}
