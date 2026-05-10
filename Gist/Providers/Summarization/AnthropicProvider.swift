import Foundation

final class AnthropicProvider: SummarizationProvider, Sendable {
    let providerID: ProviderID = .anthropic

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        guard let apiKey = KeychainService.shared.getKey(for: "anthropic-api-key") else {
            throw ProviderError.notConfigured(.anthropic)
        }

        struct AnthropicRequest: Encodable {
            let model: String
            let max_tokens: Int
            let stream: Bool
            let system: String
            let messages: [Message]

            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let request = AnthropicRequest(
            model: modelID,
            max_tokens: 4096,
            stream: true,
            system: systemPrompt,
            messages: [AnthropicRequest.Message(role: "user", content: userPrompt)]
        )

        let accumulator = StreamAccumulator()

        _ = try await CloudHTTPClient.shared.stream(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ],
            body: request
        ) { chunk in
            if let data = chunk.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                accumulator.append(text)
                stream(accumulator.value)
            }
        }

        return SummaryPromptBuilder.parseSummary(output: accumulator.value, model: modelID, transcript: transcript)
    }
}
