import Foundation

final class GoogleTranscriptionProvider: TranscriptionProvider, Sendable {
    let providerID: ProviderID = .googleTranscription
    let providesDiarization = false
    let maxFileSizeBytes: Int64? = 20 * 1_048_576 // 20 MB (base64 doubles size)

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        guard let apiKey = KeychainService.shared.getKey(for: "google-api-key") else {
            throw ProviderError.notConfigured(.googleTranscription)
        }

        progress(.uploading(fraction: 0))

        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        let mimeType = AudioPreparer.mimeType(for: audioURL)

        progress(.processing)

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent?key=\(apiKey)")!

        struct GeminiRequest: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    var inlineData: InlineData?
                    var text: String?
                }
                struct InlineData: Encodable {
                    let mimeType: String
                    let data: String
                }
                let parts: [Part]
            }
            struct GenerationConfig: Encodable {
                let temperature: Double
            }
            let contents: [Content]
            let generationConfig: GenerationConfig
        }

        let prompt = """
        Transcribe this audio with precise timestamps. Output ONLY a JSON array of segments in this exact format:
        [{"start": 0.0, "end": 2.5, "text": "Hello world"}]
        Each segment should be 5-30 seconds long. Use decimal seconds for timestamps.
        """

        let request = GeminiRequest(
            contents: [GeminiRequest.Content(parts: [
                GeminiRequest.Content.Part(inlineData: GeminiRequest.Content.InlineData(mimeType: mimeType, data: base64Audio), text: nil),
                GeminiRequest.Content.Part(inlineData: nil, text: prompt),
            ])],
            generationConfig: GeminiRequest.GenerationConfig(temperature: 0.1)
        )

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }

        let response: GeminiResponse = try await CloudHTTPClient.shared.post(
            url: url,
            headers: [:],
            body: request,
            responseType: GeminiResponse.self
        )

        let text = response.candidates?.first?.content?.parts?.first?.text ?? ""

        progress(.complete)
        return parseTranscript(from: text, model: modelID, duration: duration)
    }

    private func parseTranscript(from text: String, model: String, duration: Double) -> Transcript {
        struct ParsedSegment: Decodable {
            let start: Float
            let end: Float
            let text: String
        }

        // Extract JSON array from response text
        var jsonText = text
        if let startIdx = text.firstIndex(of: "["), let endIdx = text.lastIndex(of: "]") {
            jsonText = String(text[startIdx...endIdx])
        }

        let parsed = (try? JSONDecoder().decode([ParsedSegment].self, from: Data(jsonText.utf8))) ?? []

        let segments = parsed.enumerated().map { index, seg in
            Transcript.Segment(
                segmentIndex: index,
                start: seg.start,
                end: seg.end,
                text: seg.text.trimmingCharacters(in: .whitespaces),
                confidence: 0.85,
                language: nil,
                speaker: nil
            )
        }

        return Transcript(
            created: Date(),
            durationSeconds: duration,
            model: model,
            speakers: nil,
            segments: segments
        )
    }
}
