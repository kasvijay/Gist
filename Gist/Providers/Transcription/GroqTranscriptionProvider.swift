import Foundation

final class GroqTranscriptionProvider: TranscriptionProvider, Sendable {
    let providerID: ProviderID = .groqTranscription
    let providesDiarization = false
    let maxFileSizeBytes: Int64? = 25 * 1_048_576 // 25 MB

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        guard let apiKey = KeychainService.shared.getKey(for: "groq-api-key") else {
            throw ProviderError.notConfigured(.groqTranscription)
        }

        let chunks = try await AudioPreparer.prepare(audioURL: audioURL, maxSizeBytes: maxFileSizeBytes)
        var transcripts: [(Transcript, TimeInterval)] = []
        var chunkOffset: TimeInterval = 0

        for (index, chunkURL) in chunks.enumerated() {
            progress(.uploading(fraction: Double(index) / Double(chunks.count)))

            // Groq uses OpenAI-compatible API
            let response: OpenAITranscriptionResponse = try await CloudHTTPClient.shared.uploadMultipart(
                url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                headers: ["Authorization": "Bearer \(apiKey)"],
                fileURL: chunkURL,
                fieldName: "file",
                mimeType: AudioPreparer.mimeType(for: chunkURL),
                additionalFields: [
                    "model": modelID,
                    "response_format": "verbose_json",
                    "timestamp_granularities[]": "segment",
                ],
                responseType: OpenAITranscriptionResponse.self
            )

            let transcript = convertToTranscript(response: response, model: modelID)
            transcripts.append((transcript, chunkOffset))
            chunkOffset += response.duration ?? duration / Double(chunks.count)
        }

        progress(.complete)

        if transcripts.count == 1 {
            return transcripts[0].0
        }
        return AudioPreparer.mergeTranscripts(transcripts, model: modelID)
    }

    private func convertToTranscript(response: OpenAITranscriptionResponse, model: String) -> Transcript {
        let segments = (response.segments ?? []).enumerated().map { index, seg in
            Transcript.Segment(
                segmentIndex: index,
                start: seg.start,
                end: seg.end,
                text: seg.text.trimmingCharacters(in: .whitespaces),
                confidence: 1.0 - (seg.no_speech_prob ?? 0),
                language: response.language,
                speaker: nil
            )
        }

        return Transcript(
            created: Date(),
            durationSeconds: response.duration ?? 0,
            model: model,
            speakers: nil,
            segments: segments
        )
    }
}
