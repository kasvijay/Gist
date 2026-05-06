import FluidAudio
import Foundation

final class LocalParakeetProvider: TranscriptionProvider, @unchecked Sendable {
    let providerID: ProviderID = .localParakeet
    let providesDiarization = false
    let maxFileSizeBytes: Int64? = nil

    private var manager: AsrManager?

    func transcribe(
        audioURL: URL,
        modelID: String,
        duration: Double,
        progress: @escaping @Sendable (CloudTranscriptionProgress) -> Void
    ) async throws -> Transcript {
        progress(.processing)

        // Initialize manager and load models on demand
        let mgr = AsrManager()
        let version: AsrModelVersion = modelID == "parakeet-v2" ? .v2 : .v3
        let models = try await AsrModels.downloadAndLoad(version: version)
        try await mgr.loadModels(models)

        // Transcribe the audio file
        let result = try await mgr.transcribe(audioURL, source: .system)

        // Free memory after transcription
        await mgr.cleanup()

        progress(.complete)

        return convertToTranscript(result: result, modelID: modelID, duration: duration)
    }

    private func convertToTranscript(result: ASRResult, modelID: String, duration: Double) -> Transcript {
        let segments = buildSegments(from: result)
        return Transcript(
            created: Date(),
            durationSeconds: result.duration > 0 ? result.duration : duration,
            model: modelID,
            speakers: nil,
            segments: segments
        )
    }

    /// Group token timings into sentence-level segments based on punctuation and time gaps.
    private func buildSegments(from result: ASRResult) -> [Transcript.Segment] {
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            // No token timings — return single segment with full text
            return [
                Transcript.Segment(
                    segmentIndex: 0,
                    start: 0,
                    end: Float(result.duration),
                    text: result.text.trimmingCharacters(in: .whitespaces),
                    confidence: result.confidence
                )
            ]
        }

        var segments: [Transcript.Segment] = []
        var currentTokens: [TokenTiming] = []
        var segmentIndex = 0

        let sentenceEnders: Set<Character> = [".", "?", "!"]
        let maxSegmentDuration: TimeInterval = 30.0
        let minGapForSplit: TimeInterval = 1.0

        for (i, timing) in timings.enumerated() {
            currentTokens.append(timing)

            let isLast = i == timings.count - 1
            let endsWithPunctuation = timing.token.last.map { sentenceEnders.contains($0) } ?? false
            let segmentDuration = timing.endTime - (currentTokens.first?.startTime ?? timing.startTime)
            let hasLargeGap = !isLast && (timings[i + 1].startTime - timing.endTime) >= minGapForSplit

            let shouldSplit = isLast
                || (endsWithPunctuation && segmentDuration >= 3.0)
                || segmentDuration >= maxSegmentDuration
                || hasLargeGap

            if shouldSplit && !currentTokens.isEmpty {
                let text = currentTokens.map(\.token).joined()
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else {
                    currentTokens = []
                    continue
                }

                let avgConfidence = currentTokens.map(\.confidence).reduce(0, +) / Float(currentTokens.count)
                let segment = Transcript.Segment(
                    segmentIndex: segmentIndex,
                    start: Float(currentTokens.first!.startTime),
                    end: Float(currentTokens.last!.endTime),
                    text: text,
                    confidence: avgConfidence
                )
                segments.append(segment)
                segmentIndex += 1
                currentTokens = []
            }
        }

        return segments
    }
}
