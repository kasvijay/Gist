import Foundation
import os

enum DiarizationMethod: String, CaseIterable {
    case lsEend = "lsEend"
    case vbx = "vbx"

    var displayName: String {
        switch self {
        case .lsEend: "LS-EEND (Live)"
        case .vbx: "VBx (Offline)"
        }
    }

    var description: String {
        switch self {
        case .lsEend: "Labels during recording, up to 10 speakers"
        case .vbx: "Labels after recording, unlimited speakers"
        }
    }
}

/// Speaker identification using FluidAudio ML.
/// Supports LS-EEND (live, up to 10 speakers) and VBx (offline, unlimited speakers).
@MainActor
final class DiarizationManager: ObservableObject {
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "DiarizationManager")

    let mlDiarizer = MLDiarizer()
    let vbxDiarizer = VBxDiarizer()

    @Published var mlReady = false
    @Published var vbxReady = false
    @Published var method: DiarizationMethod = .lsEend

    func loadMLModel() async {
        do {
            try await mlDiarizer.initialize()
            mlReady = true
            logger.info("LS-EEND speaker identification ready")
        } catch {
            logger.error("Failed to load LS-EEND model: \(error)")
        }
    }

    func loadVBxModel() async {
        do {
            try await vbxDiarizer.initialize()
            vbxReady = true
            logger.info("VBx speaker identification ready")
        } catch {
            logger.error("Failed to load VBx model: \(error)")
        }
    }

    /// Apply speaker labels using LS-EEND (sync). For VBx, use applySpeakerLabelsAsync().
    func applySpeakerLabels(to transcript: inout Transcript, audioFileURL: URL) {
        applyLSEENDLabels(to: &transcript, audioFileURL: audioFileURL)
    }

    /// Async version for VBx — call this from async contexts for proper await handling.
    func applySpeakerLabelsAsync(to transcript: inout Transcript, audioFileURL: URL) async {
        switch method {
        case .lsEend:
            applyLSEENDLabels(to: &transcript, audioFileURL: audioFileURL)
        case .vbx:
            guard vbxReady else {
                logger.info("VBx not ready, falling back to LS-EEND")
                applyLSEENDLabels(to: &transcript, audioFileURL: audioFileURL)
                return
            }
            do {
                let segments = transcript.segments.map { (start: $0.start, end: $0.end) }
                let result = try await vbxDiarizer.diarize(
                    audioFileURL: audioFileURL,
                    transcriptSegments: segments
                )
                for i in transcript.segments.indices {
                    transcript.segments[i].speaker = i < result.labels.count ? result.labels[i] : nil
                }
                transcript.speakers = result.speakers
                let count = transcript.segments.count
                let speakerCount = result.speakers.count
                logger.info("VBx identification complete: \(speakerCount) speakers, \(count) segments")
            } catch {
                logger.error("VBx identification failed: \(error), falling back to LS-EEND")
                applyLSEENDLabels(to: &transcript, audioFileURL: audioFileURL)
            }
        }
    }

    // MARK: - Private

    private func applyLSEENDLabels(to transcript: inout Transcript, audioFileURL: URL) {
        guard mlReady else {
            logger.info("LS-EEND not ready, skipping speaker identification")
            return
        }

        do {
            let segments = transcript.segments.map { (start: $0.start, end: $0.end) }
            let result = try mlDiarizer.diarize(
                audioFileURL: audioFileURL,
                transcriptSegments: segments
            )

            for i in transcript.segments.indices {
                transcript.segments[i].speaker = i < result.labels.count ? result.labels[i] : nil
            }

            transcript.speakers = result.speakers
            let count = transcript.segments.count
            let speakerCount = result.speakers.count
            logger.info("LS-EEND identification complete: \(speakerCount) speakers, \(count) segments")
        } catch {
            logger.error("LS-EEND identification failed: \(error)")
        }
    }

}
