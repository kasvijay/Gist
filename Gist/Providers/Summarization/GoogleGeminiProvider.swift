import Foundation

final class GoogleGeminiProvider: SummarizationProvider, Sendable {
    let providerID: ProviderID = .googleGemini

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        guard let apiKey = KeychainService.shared.getKey(for: "google-api-key") else {
            throw ProviderError.notConfigured(.googleGemini)
        }

        struct GeminiRequest: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let role: String
                let parts: [Part]
            }
            struct GenerationConfig: Encodable {
                let temperature: Double
                let maxOutputTokens: Int
            }
            let contents: [Content]
            let generationConfig: GenerationConfig
        }

        let request = GeminiRequest(
            contents: [
                GeminiRequest.Content(role: "user", parts: [
                    GeminiRequest.Content.Part(text: systemPrompt + "\n\n" + userPrompt),
                ]),
            ],
            generationConfig: GeminiRequest.GenerationConfig(temperature: 0.3, maxOutputTokens: 4096)
        )

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent?key=\(apiKey)&alt=sse")!

        let accumulator = StreamAccumulator()

        _ = try await CloudHTTPClient.shared.stream(
            url: url,
            headers: [:],
            body: request
        ) { chunk in
            if let data = chunk.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                accumulator.append(text)
                stream(accumulator.value)
            }
        }

        return SummaryPromptBuilder.parseSummary(output: accumulator.value, model: modelID, transcript: transcript)
    }
}
