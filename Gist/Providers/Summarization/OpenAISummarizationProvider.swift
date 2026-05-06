import Foundation

final class OpenAISummarizationProvider: SummarizationProvider, Sendable {
    let providerID: ProviderID = .openAISummarization

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        guard let apiKey = KeychainService.shared.getKey(for: "openai-api-key") else {
            throw ProviderError.notConfigured(.openAISummarization)
        }

        struct ChatRequest: Encodable {
            let model: String
            let stream: Bool
            let temperature: Double
            let messages: [Message]

            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let request = ChatRequest(
            model: modelID,
            stream: true,
            temperature: 0.3,
            messages: [
                ChatRequest.Message(role: "system", content: systemPrompt),
                ChatRequest.Message(role: "user", content: userPrompt),
            ]
        )

        let accumulator = StreamAccumulator()

        _ = try await CloudHTTPClient.shared.stream(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: request
        ) { chunk in
            if let data = chunk.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                accumulator.append(content)
                stream(accumulator.value)
            }
        }

        return SummaryPromptBuilder.parseSummary(output: accumulator.value, model: modelID)
    }
}
