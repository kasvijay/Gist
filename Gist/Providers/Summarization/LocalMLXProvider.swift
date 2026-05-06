import Foundation

final class LocalMLXProvider: SummarizationProvider, @unchecked Sendable {
    let providerID: ProviderID = .localMLX

    private let engine: SummarizationEngine

    init(engine: SummarizationEngine) {
        self.engine = engine
    }

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        // Delegate to the existing SummarizationEngine
        guard let summary = await engine.summarize(transcript: transcript) else {
            throw ProviderError.summarizationFailed("Local MLX summarization returned no results")
        }
        return summary
    }
}
