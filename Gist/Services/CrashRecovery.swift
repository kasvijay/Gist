import Foundation
import os

/// On launch, scans for sessions with status "recording" — these were interrupted
/// by a crash or force-quit. Recovers WAV audio files and marks sessions as recovered.
struct CrashRecovery {
    private static let logger = Logger(subsystem: "com.vijaykas.gist", category: "CrashRecovery")

    struct RecoveryResult {
        let recoveredIDs: [String]
        let pendingConversions: [(wav: URL, m4a: URL, sessionID: String)]
    }

    static func recoverSessions(in baseURL: URL) -> RecoveryResult {
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var recoveredIDs: [String] = []
        var conversions: [(wav: URL, m4a: URL, sessionID: String)] = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil
        ) else { return RecoveryResult(recoveredIDs: [], pendingConversions: []) }

        for folder in contents where folder.hasDirectoryPath {
            let metadataURL = folder.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  var session = try? decoder.decode(Session.self, from: data) else { continue }

            if session.status == .recording {
                session.status = .recovered
                session.endedAt = session.endedAt ?? Date()

                let wavURL = folder.appendingPathComponent("audio.wav")
                let m4aURL = folder.appendingPathComponent("audio.m4a")

                if fileManager.fileExists(atPath: wavURL.path) {
                    // Repair WAV header (RIFF/data sizes may be wrong after crash)
                    do {
                        try AudioFileWriter.repairWAVHeader(url: wavURL)
                        logger.info("Repaired WAV header for: \(session.id)")
                    } catch {
                        logger.warning("WAV header repair failed for \(session.id): \(error.localizedDescription)")
                    }
                    conversions.append((wav: wavURL, m4a: m4aURL, sessionID: session.id))
                    logger.info("Recovered session: \(session.id) — WAV audio intact")
                } else if fileManager.fileExists(atPath: m4aURL.path) {
                    logger.warning("Recovered session: \(session.id) — M4A may be corrupt (no moov atom)")
                }

                // Rename partial transcript if it exists
                let partialURL = folder.appendingPathComponent("transcript.partial.json")
                let transcriptURL = folder.appendingPathComponent("transcript.json")
                if fileManager.fileExists(atPath: partialURL.path) && !fileManager.fileExists(atPath: transcriptURL.path) {
                    try? fileManager.moveItem(at: partialURL, to: transcriptURL)
                    logger.info("Recovered partial transcript for: \(session.id)")
                }

                if let encoded = try? encoder.encode(session) {
                    try? encoded.write(to: metadataURL, options: .atomic)
                }

                recoveredIDs.append(session.id)
                logger.info("Session recovered: \(session.id)")
            }
        }

        return RecoveryResult(recoveredIDs: recoveredIDs, pendingConversions: conversions)
    }

    /// Convert recovered WAV files to M4A. Call after app launch completes.
    static func convertPendingRecoveries(_ conversions: [(wav: URL, m4a: URL, sessionID: String)]) async {
        for entry in conversions {
            do {
                _ = try await AudioFileWriter.convertToAAC(wavURL: entry.wav, m4aURL: entry.m4a)
                try? FileManager.default.removeItem(at: entry.wav)
                logger.info("Converted recovered WAV → M4A for: \(entry.sessionID)")
            } catch {
                // Keep the WAV — it's still playable
                logger.error("Failed to convert recovered WAV for \(entry.sessionID): \(error.localizedDescription)")
            }
        }
    }
}
