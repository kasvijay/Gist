import Foundation

final class DeepgramProvider: TranscriptionProvider, Sendable {
    let providerID: ProviderID = .deepgram
    let providesDiarization = true
    let maxFileSizeBytes: Int64? = nil

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        guard let apiKey = KeychainService.shared.getKey(for: "deepgram-api-key") else {
            throw ProviderError.notConfigured(.deepgram)
        }

        progress(.uploading(fraction: 0))

        let contentType = AudioPreparer.mimeType(for: audioURL)
        var urlComponents = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        urlComponents.queryItems = [
            URLQueryItem(name: "model", value: modelID),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
        ]

        progress(.processing)

        let response: DeepgramResponse = try await CloudHTTPClient.shared.uploadRaw(
            url: urlComponents.url!,
            headers: ["Authorization": "Token \(apiKey)"],
            fileURL: audioURL,
            contentType: contentType,
            responseType: DeepgramResponse.self
        )

        progress(.complete)
        return convertToTranscript(response: response, model: modelID, duration: duration)
    }

    private func convertToTranscript(response: DeepgramResponse, model: String, duration: Double) -> Transcript {
        let utterances = response.results?.utterances ?? []
        var speakerMap: [Int: String] = [:]
        var speakers: [String: Speaker] = [:]

        let segments = utterances.enumerated().map { index, utt in
            let speakerKey = "SPEAKER_\(utt.speaker ?? 0)"
            if speakerMap[utt.speaker ?? 0] == nil {
                let label = "Speaker \(speakerMap.count + 1)"
                speakerMap[utt.speaker ?? 0] = speakerKey
                speakers[speakerKey] = Speaker(id: speakerKey, source: nil, label: label)
            }

            return Transcript.Segment(
                segmentIndex: index,
                start: utt.start,
                end: utt.end,
                text: utt.transcript.trimmingCharacters(in: .whitespaces),
                confidence: utt.confidence ?? 0.9,
                language: nil,
                speaker: speakerKey
            )
        }

        let actualDuration = response.metadata?.duration ?? duration

        return Transcript(
            created: Date(),
            durationSeconds: actualDuration,
            model: model,
            speakers: speakers.isEmpty ? nil : speakers,
            segments: segments
        )
    }
}

// MARK: - Response Models

struct DeepgramResponse: Decodable {
    let results: DeepgramResults?
    let metadata: DeepgramMetadata?

    struct DeepgramResults: Decodable {
        let utterances: [DeepgramUtterance]?
    }

    struct DeepgramUtterance: Decodable {
        let start: Float
        let end: Float
        let transcript: String
        let speaker: Int?
        let confidence: Float?
    }

    struct DeepgramMetadata: Decodable {
        let duration: Double?
    }
}
