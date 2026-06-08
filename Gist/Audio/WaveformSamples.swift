import AVFoundation
import Accelerate

/// Reads an audio file and produces downsampled RMS samples for waveform
/// visualization. Used by the trim selector to render the recording's
/// shape so the user can find the cut point by sight.
enum WaveformSamples {
    /// Returns `bucketCount` RMS values in [0, 1] across the file's duration.
    /// Reads at the file's native rate, mixes to mono, downsamples to fit.
    /// Returns nil if the file can't be read.
    static func extract(from url: URL, bucketCount: Int = 600) async -> [Float]? {
        guard bucketCount > 0 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }

        let descs = (try? await track.load(.formatDescriptions)) ?? []
        guard let fmt = descs.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee
        else { return nil }
        let sourceChannels = max(1, Int(asbd.mChannelsPerFrame))

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: sourceChannels,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        let effectiveSampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 16_000
        let totalFrames = Int(durationSeconds * effectiveSampleRate)
        guard totalFrames > 0 else { return nil }

        let framesPerBucket = max(1, totalFrames / bucketCount)
        var buckets = [Float](repeating: 0, count: bucketCount)
        var bucketIndex = 0
        var bucketAccum: Float = 0
        var bucketFrames = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &data)
            CMSampleBufferInvalidate(sample)

            // data is interleaved across `sourceChannels`. Mix to mono on the fly.
            let frameCount = data.count / sourceChannels
            for f in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<sourceChannels {
                    sum += abs(data[f * sourceChannels + c])
                }
                let mono = sum / Float(sourceChannels)
                bucketAccum += mono * mono
                bucketFrames += 1
                if bucketFrames >= framesPerBucket, bucketIndex < bucketCount {
                    let rms = sqrtf(bucketAccum / Float(bucketFrames))
                    buckets[bucketIndex] = rms
                    bucketIndex += 1
                    bucketAccum = 0
                    bucketFrames = 0
                }
            }
        }
        if bucketIndex < bucketCount, bucketFrames > 0 {
            let rms = sqrtf(bucketAccum / Float(bucketFrames))
            buckets[bucketIndex] = rms
        }

        // Normalize to peak so quiet recordings still render visibly.
        var peak: Float = 0
        vDSP_maxv(buckets, 1, &peak, vDSP_Length(buckets.count))
        if peak > 0 {
            var scale = 1.0 / peak
            vDSP_vsmul(buckets, 1, &scale, &buckets, 1, vDSP_Length(buckets.count))
        }
        return buckets
    }
}
