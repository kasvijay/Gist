import Foundation

final class AssemblyAIProvider: TranscriptionProvider, Sendable {
    let providerID: ProviderID = .assemblyAI
    let providesDiarization = true
    let maxFileSizeBytes: Int64? = nil

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        guard let apiKey = KeychainService.shared.getKey(for: "assemblyai-api-key") else {
            throw ProviderError.notConfigured(.assemblyAI)
        }

        let headers = ["Authorization": apiKey]

        // Step 1: Upload audio file
        progress(.uploading(fraction: 0))

        let fileData = try Data(contentsOf: audioURL)
        var uploadRequest = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/upload")!)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(apiKey, forHTTPHeaderField: "Authorization")
        uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = fileData

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        guard let httpResp = uploadResponse as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw ProviderError.transcriptionFailed("AssemblyAI upload failed")
        }

        let uploadResult = try JSONDecoder().decode(AssemblyAIUploadResponse.self, from: uploadData)

        // Step 2: Request transcription
        progress(.processing)

        struct TranscribeRequest: Encodable {
            let audio_url: String
            let speaker_labels: Bool
            let language_detection: Bool
        }

        let transcribeResponse: AssemblyAITranscriptResponse = try await CloudHTTPClient.shared.post(
            url: URL(string: "https://api.assemblyai.com/v2/transcript")!,
            headers: headers,
            body: TranscribeRequest(
                audio_url: uploadResult.upload_url,
                speaker_labels: true,
                language_detection: true
            ),
            responseType: AssemblyAITranscriptResponse.self
        )

        // Step 3: Poll for completion
        let transcriptID = transcribeResponse.id
        let pollURL = URL(string: "https://api.assemblyai.com/v2/transcript/\(transcriptID)")!

        var result: AssemblyAITranscriptResponse
        while true {
            try await Task.sleep(for: .seconds(3))

            result = try await CloudHTTPClient.shared.get(
                url: pollURL,
                headers: headers,
                responseType: AssemblyAITranscriptResponse.self
            )

            if result.status == "completed" { break }
            if result.status == "error" {
                throw ProviderError.transcriptionFailed(result.error ?? "AssemblyAI transcription error")
            }
        }

        progress(.complete)
        return convertToTranscript(response: result, model: modelID, duration: duration)
    }

    private func convertToTranscript(response: AssemblyAITranscriptResponse, model: String, duration: Double) -> Transcript {
        let utterances = response.utterances ?? []
        var speakerMap: [String: String] = [:]
        var speakers: [String: Speaker] = [:]

        let segments = utterances.enumerated().map { index, utt in
            let rawSpeaker = utt.speaker ?? "A"
            let speakerKey: String
            if let mapped = speakerMap[rawSpeaker] {
                speakerKey = mapped
            } else {
                speakerKey = "SPEAKER_\(speakerMap.count)"
                speakerMap[rawSpeaker] = speakerKey
                speakers[speakerKey] = Speaker(
                    id: speakerKey,
                    source: nil,
                    label: "Speaker \(speakerMap.count)"
                )
            }

            return Transcript.Segment(
                segmentIndex: index,
                start: Float(utt.start) / 1000.0,
                end: Float(utt.end) / 1000.0,
                text: utt.text.trimmingCharacters(in: .whitespaces),
                confidence: utt.confidence ?? 0.9,
                language: nil,
                speaker: speakerKey
            )
        }

        let actualDuration = Double(response.audio_duration ?? Int(duration))

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

struct AssemblyAIUploadResponse: Decodable {
    let upload_url: String
}

struct AssemblyAITranscriptResponse: Decodable {
    let id: String
    let status: String
    let text: String?
    let error: String?
    let audio_duration: Int?
    let utterances: [AssemblyAIUtterance]?

    struct AssemblyAIUtterance: Decodable {
        let speaker: String?
        let text: String
        let start: Int
        let end: Int
        let confidence: Float?
    }
}
