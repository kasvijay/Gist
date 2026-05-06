import Foundation

final class OllamaProvider: SummarizationProvider, Sendable {
    let providerID: ProviderID = .ollama

    private let baseURL = "http://localhost:11434"

    func summarize(
        transcript: Transcript,
        modelID: String,
        systemPrompt: String,
        userPrompt: String,
        stream: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        // Check if Ollama is running
        let tagsURL = URL(string: "\(baseURL)/api/tags")!
        var checkRequest = URLRequest(url: tagsURL)
        checkRequest.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: checkRequest)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                throw ProviderError.providerUnavailable("Ollama is not responding. Make sure Ollama is running.")
            }
        } catch is URLError {
            throw ProviderError.providerUnavailable("Could not connect to Ollama at localhost:11434. Start Ollama and try again.")
        }

        struct OllamaRequest: Encodable {
            let model: String
            let messages: [Message]
            let stream: Bool

            struct Message: Encodable {
                let role: String
                let content: String
            }
        }

        let request = OllamaRequest(
            model: modelID,
            messages: [
                OllamaRequest.Message(role: "system", content: systemPrompt),
                OllamaRequest.Message(role: "user", content: userPrompt),
            ],
            stream: true
        )

        let url = URL(string: "\(baseURL)/api/chat")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw ProviderError.providerUnavailable("Ollama request failed")
        }

        let accumulator = StreamAccumulator()

        // Ollama streams NDJSON
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                accumulator.append(content)
                stream(accumulator.value)
            }
        }

        return SummaryPromptBuilder.parseSummary(output: accumulator.value, model: modelID)
    }
}
