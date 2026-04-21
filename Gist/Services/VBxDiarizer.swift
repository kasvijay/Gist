import Foundation
import FluidAudio
import os

/// Offline speaker diarization using FluidAudio's VBx pipeline.
/// Runs post-recording. Supports unlimited speakers with better accuracy than LS-EEND.
final class VBxDiarizer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "VBxDiarizer")
    private var manager: OfflineDiarizerManager?
    private(set) var isInitialized = false

    func initialize() async throws {
        let config = OfflineDiarizerConfig.default
        let mgr = OfflineDiarizerManager(config: config)
        try await mgr.prepareModels()
        self.manager = mgr
        self.isInitialized = true
        logger.info("FluidAudio VBx offline diarizer initialized")
    }

    /// Diarize an audio file. Returns speaker labels aligned to transcript segments.
    func diarize(
        audioFileURL: URL,
        transcriptSegments: [(start: Float, end: Float)]
    ) async throws -> (labels: [String], speakers: [String: Speaker]) {
        guard let manager else {
            throw VBxDiarizationError.notInitialized
        }

        logger.info("Running VBx diarization on \(audioFileURL.lastPathComponent)")

        let result = try await manager.process(audioFileURL)

        // Build speaker dictionary from unique speaker IDs
        var speakers: [String: Speaker] = [:]
        let uniqueSpeakers = Set(result.segments.map(\.speakerId)).sorted()
        for (index, id) in uniqueSpeakers.enumerated() {
            speakers[id] = Speaker(id: id, source: .vbxIdentification, label: "Speaker \(index + 1)")
        }

        // Assign speakers to transcript segments by maximum time overlap
        let labels: [String] = transcriptSegments.map { tSeg in
            var bestSpeaker = uniqueSpeakers.first ?? "SPEAKER_0"
            var bestOverlap: Float = 0

            for dSeg in result.segments {
                let overlapStart = max(tSeg.start, dSeg.startTimeSeconds)
                let overlapEnd = min(tSeg.end, dSeg.endTimeSeconds)
                let overlap = max(0, overlapEnd - overlapStart)

                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = dSeg.speakerId
                }
            }

            return bestSpeaker
        }

        let segCount = result.segments.count
        logger.info("VBx diarization complete: \(uniqueSpeakers.count) speakers, \(segCount) segments")
        return (labels: labels, speakers: speakers)
    }

    enum VBxDiarizationError: LocalizedError {
        case notInitialized

        var errorDescription: String? {
            "VBx diarizer not initialized. Call initialize() first."
        }
    }
}
