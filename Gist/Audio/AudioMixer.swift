import AVFoundation
import Accelerate
import os

/// Mixes microphone and system audio streams.
/// Applies RMS-based ducking: reduces system audio when mic detects speech.
final class AudioMixer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "AudioMixer")

    private let duckingThreshold: Float = 0.01  // RMS level above which mic is "active"
    private let duckingAmount: Float = 0.3       // Multiply system audio by this when ducking

    /// Mix system audio buffer list into a PCM buffer compatible with our pipeline.
    /// Returns mono Float samples at the system audio's sample rate.
    func samplesFromBufferList(_ bufferList: UnsafePointer<AudioBufferList>) -> [Float]? {
        let abl = bufferList.pointee
        guard abl.mNumberBuffers > 0 else { return nil }

        let buffer = abl.mBuffers
        guard buffer.mDataByteSize > 0, let data = buffer.mData else { return nil }

        let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        let floatPtr = data.bindMemory(to: Float.self, capacity: floatCount)
        let channels = Int(buffer.mNumberChannels)

        if channels <= 1 {
            return Array(UnsafeBufferPointer(start: floatPtr, count: floatCount))
        }

        // Deinterleave stereo to mono by averaging channels
        let frameCount = floatCount / channels
        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<channels {
                sum += floatPtr[i * channels + ch]
            }
            mono[i] = sum / Float(channels)
        }
        return mono
    }

    // Pre-allocated working buffer — resized only when frame count grows
    private var _scaledSystem = [Float]()

    /// Mix mic and system audio, writing result directly into outputBuffer.
    /// micPtr points to the AVAudioPCMBuffer's float channel data (no copy needed).
    /// Returns true if mixing succeeded, false if caller should fall back to raw mic.
    @discardableResult
    func mixInto(
        outputBuffer: AVAudioPCMBuffer,
        micMuted: Bool = false,
        micPtr: UnsafePointer<Float>,
        micCount: Int,
        systemSamples: [Float]
    ) -> Bool {
        let count = min(micCount, systemSamples.count)
        guard count > 0 else { return false }
        guard let channelData = outputBuffer.floatChannelData else { return false }

        if _scaledSystem.count < count {
            _scaledSystem = [Float](repeating: 0, count: count)
        }

        let output = channelData[0]

        if micMuted {
            // Mic muted: write only system audio (no ducking, full volume)
            memcpy(output, systemSamples, count * MemoryLayout<Float>.size)
        } else {
            // RMS directly from pointer — no array copy
            var rms: Float = 0
            vDSP_rmsqv(micPtr, 1, &rms, vDSP_Length(count))
            let ducking: Float = rms > duckingThreshold ? duckingAmount : 1.0

            // Scale system audio by ducking factor
            var duckFactor = ducking
            vDSP_vsmul(systemSamples, 1, &duckFactor, &_scaledSystem, 1, vDSP_Length(count))

            // Add mic + ducked system directly into output buffer's channel data
            vDSP_vadd(micPtr, 1, _scaledSystem, 1, output, 1, vDSP_Length(count))
        }

        // Clip prevention: soft clamp to [-1, 1]
        var lo: Float = -1.0
        var hi: Float = 1.0
        vDSP_vclip(output, 1, &lo, &hi, output, 1, vDSP_Length(count))

        // Copy to other channels if multi-channel
        let channels = Int(outputBuffer.format.channelCount)
        for ch in 1..<channels {
            memcpy(channelData[ch], output, count * MemoryLayout<Float>.size)
        }

        outputBuffer.frameLength = AVAudioFrameCount(count)
        return true
    }
}
