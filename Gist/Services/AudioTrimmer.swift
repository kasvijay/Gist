import AVFoundation
import AudioToolbox
import os

/// Trims an .m4a to a [start, end] time range, writing the trimmed file to
/// `destinationURL`. Re-encodes via AVAssetReader/Writer so we preserve the
/// same bitrate logic that `AudioFileWriter.convertToAAC` uses (64 kbps mono,
/// 96 kbps stereo) instead of letting AVAssetExportSession pick a lower one.
enum AudioTrimmer {
    enum TrimError: Error {
        case invalidSource
        case invalidRange
        case noAudioTrack
        case writerSetupFailed
        case underlying(Error)
    }

    private static let logger = Logger(subsystem: "com.vijaykas.gist", category: "AudioTrimmer")

    /// Trim `sourceURL` to [`startSeconds`, `endSeconds`] and write to `destinationURL`.
    /// If a file already exists at `destinationURL` it is replaced.
    static func trim(sourceURL: URL, destinationURL: URL, startSeconds: Double, endSeconds: Double) async throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { throw TrimError.invalidSource }
        guard endSeconds > startSeconds, startSeconds >= 0 else { throw TrimError.invalidRange }

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw TrimError.invalidSource }

        let clampedStart = max(0, startSeconds)
        let clampedEnd = min(duration, endSeconds)
        guard clampedEnd - clampedStart > 0.05 else { throw TrimError.invalidRange }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw TrimError.noAudioTrack }

        let formatDescs = try await track.load(.formatDescriptions)
        guard let fmt = formatDescs.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee
        else { throw TrimError.invalidSource }
        let sampleRate = asbd.mSampleRate
        let channels = max(1, min(Int(asbd.mChannelsPerFrame), 2))
        let bitRate = channels == 1 ? 64_000 : 96_000

        var outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        if sampleRate > 0 {
            outputSettings[AVSampleRateKey] = sampleRate
        }

        // Write to a sibling temp file first, then move into place. Avoids leaving
        // a half-written file at `destinationURL` if the export fails midway.
        let tempURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".trim-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw TrimError.writerSetupFailed }
        writer.add(writerInput)

        let reader = try AVAssetReader(asset: asset)
        let timescale: CMTimeScale = 44100
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: clampedStart, preferredTimescale: timescale),
            duration: CMTime(seconds: clampedEnd - clampedStart, preferredTimescale: timescale)
        )
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        guard reader.canAdd(readerOutput) else { throw TrimError.writerSetupFailed }
        reader.add(readerOutput)

        guard writer.startWriting() else {
            throw writer.error.map(TrimError.underlying) ?? TrimError.writerSetupFailed
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw reader.error.map(TrimError.underlying) ?? TrimError.writerSetupFailed
        }

        let queue = DispatchQueue(label: "com.vijaykas.gist.audio-trim")
        nonisolated(unsafe) let captureWriter = writer
        nonisolated(unsafe) let captureInput = writerInput
        nonisolated(unsafe) let captureReaderOutput = readerOutput
        nonisolated(unsafe) let captureReader = reader
        let startCM = CMTime(seconds: clampedStart, preferredTimescale: timescale)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            captureInput.requestMediaDataWhenReady(on: queue) {
                while captureInput.isReadyForMoreMediaData {
                    if let sample = captureReaderOutput.copyNextSampleBuffer() {
                        // Shift the sample's PTS so the trimmed file starts at t=0.
                        if let shifted = retimedSample(sample, by: startCM), captureInput.append(shifted) {
                            continue
                        }
                        captureInput.markAsFinished()
                        captureWriter.finishWriting { cont.resume() }
                        return
                    } else {
                        captureInput.markAsFinished()
                        captureWriter.finishWriting { cont.resume() }
                        return
                    }
                }
                _ = captureReader  // keep reader alive until pump finishes
            }
        }

        if let err = reader.error {
            try? FileManager.default.removeItem(at: tempURL)
            throw TrimError.underlying(err)
        }
        if let err = writer.error {
            try? FileManager.default.removeItem(at: tempURL)
            throw TrimError.underlying(err)
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw TrimError.writerSetupFailed
        }

        // Atomically replace the destination.
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }
    }

    /// Returns the duration in seconds of an audio file at `url`, or 0 on failure.
    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.duration).seconds) ?? 0
    }

    /// Subtracts `offset` from each timing on `sample` so the trimmed segment
    /// starts at t=0 in the output file.
    private static func retimedSample(_ sample: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return sample }

        var timingCount: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount)
        guard timingCount > 0 else { return sample }

        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: timingCount)
        let status = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: timingCount, arrayToFill: &timings, entriesNeededOut: nil)
        guard status == noErr else { return sample }

        for i in 0..<timings.count {
            if timings[i].presentationTimeStamp.isValid {
                timings[i].presentationTimeStamp = CMTimeSubtract(timings[i].presentationTimeStamp, offset)
            }
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = CMTimeSubtract(timings[i].decodeTimeStamp, offset)
            }
        }

        var out: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: timings.count,
            sampleTimingArray: &timings,
            sampleBufferOut: &out
        )
        return copyStatus == noErr ? out : nil
    }
}
