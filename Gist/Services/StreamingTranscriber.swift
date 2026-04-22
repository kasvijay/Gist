import Foundation
import AVFoundation
import WhisperKit
import Accelerate
import os

/// Accumulates PCM audio samples and periodically transcribes them with WhisperKit.
/// Produces confirmed and unconfirmed segments for live display.
///
/// Thread safety: `appendBuffer` is called from the audio IO thread,
/// while `start`/`stop`/`allSegments` run on async or main threads.
/// All mutable state is behind `lock`. Locked access is wrapped in
/// synchronous helpers so NSLock is never called from async context.
final class StreamingTranscriber: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "StreamingTranscriber")
    private let lock = NSLock()

    // All mutable state — access only via locked helpers
    private var _audioSamples: [Float] = []
    private var _lastTranscribedCount: Int = 0
    private var _trimmedSampleCount: Int = 0  // total samples removed from front of buffer
    private var _isRunning = false
    private var _confirmedSegments: [TranscriptionSegment] = []
    private var _unconfirmedSegments: [TranscriptionSegment] = []
    private var _lastConfirmedEnd: Float = 0

    private let whisperKit: WhisperKit
    private let sampleRate: Double
    private let minBufferSeconds: Float = 1.5
    private let requiredConfirmations = 2

    var onSegmentsUpdated: (@Sendable ([TranscriptionSegment], [TranscriptionSegment]) -> Void)?

    init(whisperKit: WhisperKit, sampleRate: Double) {
        self.whisperKit = whisperKit
        self.sampleRate = sampleRate
    }

    // MARK: - Locked state accessors (synchronous, safe to call from anywhere)

    private func resetState() {
        lock.lock()
        _isRunning = true
        _confirmedSegments = []
        _unconfirmedSegments = []
        _audioSamples = []
        _lastTranscribedCount = 0
        _trimmedSampleCount = 0
        _lastConfirmedEnd = 0
        lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    private func appendSamples(_ samples: [Float]) {
        lock.lock()
        _audioSamples.append(contentsOf: samples)
        lock.unlock()
    }

    private func snapshotForTranscription() -> (sampleCount: Int, lastCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Use absolute counts (including trimmed samples) so "new samples" detection
        // works correctly even after old samples are removed from the buffer.
        return (_trimmedSampleCount + _audioSamples.count, _lastTranscribedCount)
    }

    private func copySamplesForTranscription() -> (samples: [Float], trimOffset: Float, confirmedEnd: Float) {
        lock.lock()

        // Trim: keep audio from 5s before confirmed end, capped at 30s total.
        // This prevents the buffer from growing unboundedly during long recordings
        // which would make each WhisperKit call progressively slower.
        let contextSamples = 5 * 16000          // 5s overlap for transcription context
        let maxBufferSamples = 30 * 16000       // 30s max (matches WhisperKit window)

        // Convert confirmed end from absolute time to index relative to current buffer
        let confirmedEndAbsolute = Int(_lastConfirmedEnd * 16000)
        let relativeConfirmedEnd = max(0, confirmedEndAbsolute - _trimmedSampleCount)

        let idealStart = max(0, relativeConfirmedEnd - contextSamples)
        let cappedStart = max(idealStart, _audioSamples.count - maxBufferSamples)
        let safeStart = min(cappedStart, _audioSamples.count)

        let samples = safeStart < _audioSamples.count ? Array(_audioSamples[safeStart...]) : []
        let absoluteSafeStart = _trimmedSampleCount + safeStart
        let trimOffset = Float(absoluteSafeStart) / 16000.0
        let confirmedEnd = _lastConfirmedEnd

        // Remove old confirmed samples from the buffer to bound memory usage.
        // After this, _audioSamples only holds recent unprocessed audio.
        if safeStart > 0 {
            _audioSamples.removeFirst(safeStart)
            _trimmedSampleCount += safeStart
        }

        _lastTranscribedCount = _trimmedSampleCount + _audioSamples.count

        lock.unlock()
        return (samples, trimOffset, confirmedEnd)
    }

    private func updateSegments(from segments: [TranscriptionSegment]) -> ([TranscriptionSegment], [TranscriptionSegment]) {
        lock.lock()
        if segments.count > requiredConfirmations {
            let toConfirm = Array(segments.prefix(segments.count - requiredConfirmations))
            let remaining = Array(segments.suffix(requiredConfirmations))

            if let lastConfirmed = toConfirm.last, lastConfirmed.end > _lastConfirmedEnd {
                _lastConfirmedEnd = lastConfirmed.end

                for seg in toConfirm {
                    if !_confirmedSegments.contains(where: { $0.id == seg.id && $0.start == seg.start }) {
                        _confirmedSegments.append(seg)
                    }
                }
            }

            _unconfirmedSegments = remaining
        } else {
            _unconfirmedSegments = segments
        }

        let confirmed = _confirmedSegments
        let unconfirmed = _unconfirmedSegments
        lock.unlock()
        return (confirmed, unconfirmed)
    }

    // MARK: - Public API

    /// Append PCM samples from the microphone tap.
    /// Called on the audio IO thread — must not touch actor-isolated state.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Mix to mono if stereo
        var monoSamples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: floatData[0], count: frameCount))
        } else {
            let left = UnsafeBufferPointer(start: floatData[0], count: frameCount)
            let right = UnsafeBufferPointer(start: floatData[min(1, channelCount - 1)], count: frameCount)
            vDSP.add(left, right, result: &monoSamples)
            vDSP.divide(monoSamples, 2.0, result: &monoSamples)
        }

        // Resample to 16kHz if needed
        let sourceSR = buffer.format.sampleRate
        let samplesToAppend: [Float]
        if abs(sourceSR - 16000) > 1 {
            let ratio = 16000.0 / sourceSR
            let outputCount = Int(Double(frameCount) * ratio)
            var resampled = [Float](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                let srcIdx = Double(i) / ratio
                let lo = Int(srcIdx)
                let hi = min(lo + 1, frameCount - 1)
                let frac = Float(srcIdx - Double(lo))
                resampled[i] = monoSamples[lo] * (1 - frac) + monoSamples[hi] * frac
            }
            samplesToAppend = resampled
        } else {
            samplesToAppend = monoSamples
        }

        appendSamples(samplesToAppend)
    }

    /// Start the transcription loop. Runs until stop() is called.
    func start() async {
        resetState()

        while isRunning {
            do {
                try await transcribeCurrentBuffer()
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                if isRunning {
                    logger.error("Streaming transcription error: \(error)")
                }
                break
            }
        }
    }

    func stop() {
        lock.lock()
        _isRunning = false
        lock.unlock()
    }

    /// Get all segments (confirmed + unconfirmed) for final output.
    func allSegments() -> [TranscriptionSegment] {
        lock.lock()
        let result = _confirmedSegments + _unconfirmedSegments
        lock.unlock()
        return result
    }

    // MARK: - Private

    private func transcribeCurrentBuffer() async throws {
        let (currentCount, lastCount) = snapshotForTranscription()

        let newSamples = currentCount - lastCount
        let newSeconds = Float(newSamples) / 16000.0
        guard newSeconds >= minBufferSeconds else { return }

        let (samples, trimOffset, confirmedEnd) = copySamplesForTranscription()
        guard !samples.isEmpty else { return }

        // clipStart is relative to the trimmed buffer
        let relativeClipStart = max(0, confirmedEnd - trimOffset)

        var options = DecodingOptions(usePrefillPrompt: false, detectLanguage: true, wordTimestamps: true)
        options.clipTimestamps = [relativeClipStart]

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        guard let result = results.first else { return }

        // Offset segment timestamps from trimmed-buffer-relative to absolute
        var adjustedSegments = result.segments
        for i in adjustedSegments.indices {
            adjustedSegments[i].start += trimOffset
            adjustedSegments[i].end += trimOffset
        }

        let (confirmed, unconfirmed) = updateSegments(from: adjustedSegments)
        onSegmentsUpdated?(confirmed, unconfirmed)
    }
}
