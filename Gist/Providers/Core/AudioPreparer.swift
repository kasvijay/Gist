import AVFoundation
import Foundation

enum AudioPreparer {

    /// Returns the best audio URL for upload, compressing WAV to M4A if needed.
    /// If the file exceeds maxSizeBytes, returns chunked URLs.
    static func prepare(audioURL: URL, maxSizeBytes: Int64?) async throws -> [URL] {
        let fileSize = try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 ?? 0

        // If within limits, return as-is
        if let max = maxSizeBytes, fileSize <= max {
            return [audioURL]
        }

        // If WAV and too large, compress to M4A first
        if audioURL.pathExtension.lowercased() == "wav" {
            let m4aURL = audioURL.deletingPathExtension().appendingPathExtension("upload.m4a")
            try await compressToM4A(source: audioURL, destination: m4aURL)

            let m4aSize = try FileManager.default.attributesOfItem(atPath: m4aURL.path)[.size] as? Int64 ?? 0
            if let max = maxSizeBytes, m4aSize <= max {
                return [m4aURL]
            }
            // Still too large — chunk
            return try await splitAudio(url: m4aURL, maxChunkDuration: 600)
        }

        // M4A but too large — chunk
        if let max = maxSizeBytes, fileSize > max {
            return try await splitAudio(url: audioURL, maxChunkDuration: 600)
        }

        return [audioURL]
    }

    /// Compress WAV to M4A using AVAssetWriter
    static func compressToM4A(source: URL, destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)

        let asset = AVURLAsset(url: source)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ProviderError.transcriptionFailed("Could not create export session for audio compression")
        }
        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw ProviderError.transcriptionFailed("Audio compression failed: \(exportSession.error?.localizedDescription ?? "unknown")")
        }
    }

    /// Split audio into chunks of maxChunkDuration seconds
    static func splitAudio(url: URL, maxChunkDuration: TimeInterval) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        var chunks: [URL] = []
        var startTime: Double = 0

        while startTime < totalSeconds {
            let endTime = min(startTime + maxChunkDuration, totalSeconds)
            let chunkURL = url.deletingPathExtension()
                .appendingPathExtension("chunk\(chunks.count).m4a")

            try? FileManager.default.removeItem(at: chunkURL)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw ProviderError.transcriptionFailed("Could not create export session for chunking")
            }
            exportSession.outputURL = chunkURL
            exportSession.outputFileType = .m4a
            exportSession.timeRange = CMTimeRange(
                start: CMTime(seconds: startTime, preferredTimescale: 44100),
                end: CMTime(seconds: endTime, preferredTimescale: 44100)
            )

            await exportSession.export()
            guard exportSession.status == .completed else {
                throw ProviderError.transcriptionFailed("Audio chunking failed at \(startTime)s")
            }

            chunks.append(chunkURL)
            startTime = endTime
        }

        return chunks
    }

    /// Merge transcripts from chunked transcriptions, adjusting timestamps by offset
    static func mergeTranscripts(_ transcripts: [(Transcript, TimeInterval)], model: String) -> Transcript {
        var allSegments: [Transcript.Segment] = []
        var allSpeakers: [String: Speaker] = [:]
        var totalDuration: Double = 0

        for (transcript, offset) in transcripts {
            for var segment in transcript.segments {
                segment.start += Float(offset)
                segment.end += Float(offset)
                segment.segmentIndex = allSegments.count
                allSegments.append(segment)
            }
            if let speakers = transcript.speakers {
                allSpeakers.merge(speakers) { existing, _ in existing }
            }
            totalDuration = max(totalDuration, transcript.durationSeconds + offset)
        }

        return Transcript(
            created: Date(),
            durationSeconds: totalDuration,
            model: model,
            speakers: allSpeakers.isEmpty ? nil : allSpeakers,
            segments: allSegments
        )
    }

    /// Determine MIME type for audio file
    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        default: return "application/octet-stream"
        }
    }
}
