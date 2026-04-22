import AVFoundation
import AudioToolbox
import os

/// Writes microphone PCM buffers to a WAV file during recording for crash safety.
/// WAV (LPCM) files are linearly written — even if the process is killed, the audio
/// data survives and can be recovered by fixing the RIFF header.
///
/// After recording stops, call `convertToAAC` to compress the WAV into an M4A.
///
/// Thread safety: `append` is called from the audio IO thread,
/// `start`/`finish` from the main thread. Lock protects `audioFile`.
final class AudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var audioFile: AVAudioFile?
    private let logger = Logger(subsystem: "com.vijaykas.gist", category: "AudioFileWriter")
    private var _isWriting = false
    private var _outputURL: URL?

    /// Serial queue for disk writes — keeps I/O off the audio thread.
    private let writeQueue = DispatchQueue(label: "com.vijaykas.gist.audiowriter", qos: .userInitiated)

    var isWriting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isWriting
    }

    /// Start writing audio as WAV (LPCM) to the given file URL.
    func start(outputURL: URL, sourceFormat: AVAudioFormat) throws {
        let settings = Self.makePCMSettings(for: sourceFormat)

        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        lock.lock()
        audioFile = file
        _isWriting = true
        _outputURL = outputURL
        lock.unlock()

        let outputSampleRate = settings[AVSampleRateKey] as? Double ?? 0
        let outputChannelCount = settings[AVNumberOfChannelsKey] as? Int ?? 0
        logger.info(
            "Audio writer started (WAV): \(outputURL.lastPathComponent), source: \(sourceFormat.sampleRate)Hz \(sourceFormat.channelCount)ch, wav: \(outputSampleRate)Hz \(outputChannelCount)ch"
        )
    }

    static func makePCMSettings(for sourceFormat: AVAudioFormat) -> [String: Any] {
        let channelCount = max(1, min(Int(sourceFormat.channelCount), 2))
        let sampleRate = sourceFormat.sampleRate > 0 ? sourceFormat.sampleRate : 44_100

        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Append a PCM buffer. Call from the audio tap callback.
    /// Copies the buffer and dispatches the disk write to a background queue
    /// so the audio thread is never blocked by I/O.
    func append(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }

        lock.lock()
        guard _isWriting else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Copy buffer data for async write — the original buffer may be reused by Core Audio
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                memcpy(dst[ch], src[ch], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        writeQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self._isWriting, let file = self.audioFile else {
                self.lock.unlock()
                return
            }
            do {
                try file.write(from: copy)
            } catch {
                self.logger.error("Failed to write audio buffer: \(error)")
            }
            self.lock.unlock()
        }
    }

    /// Finish writing. Waits for pending writes, then closes the file.
    /// Returns the WAV output URL for conversion.
    @discardableResult
    func finish() -> URL? {
        // Drain pending writes before closing
        writeQueue.sync {}

        lock.lock()
        guard _isWriting else {
            lock.unlock()
            return nil
        }
        let url = _outputURL
        audioFile = nil
        _isWriting = false
        _outputURL = nil
        lock.unlock()
        logger.info("Audio writer finished")
        return url
    }

    // MARK: - WAV to M4A Conversion

    /// Convert a WAV file to AAC M4A for storage efficiency.
    /// Returns the M4A URL on success. The caller is responsible for deleting the WAV.
    static func convertToAAC(wavURL: URL, m4aURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: wavURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConversionError.exportSessionFailed
        }

        if #available(macOS 15.0, *) {
            try await session.export(to: m4aURL, as: .m4a)
        } else {
            session.outputURL = m4aURL
            session.outputFileType = .m4a
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw ConversionError.exportFailed }
        }
        return m4aURL
    }

    // MARK: - WAV Header Repair (for crash recovery)

    /// Repair a WAV file whose RIFF/data chunk sizes are wrong (e.g. process was killed).
    /// Rewrites the RIFF file size and data chunk size based on actual file size.
    static func repairWAVHeader(url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }

        let headerData = try handle.availableData(upTo: 44)
        guard headerData.count >= 44 else { throw ConversionError.invalidWAV }

        // Verify RIFF header
        let riff = String(data: headerData[0..<4], encoding: .ascii)
        let wave = String(data: headerData[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else { throw ConversionError.invalidWAV }

        let fileSize = try handle.seekToEnd()
        guard fileSize > 44 else { throw ConversionError.invalidWAV }

        // Fix RIFF chunk size (file size - 8)
        handle.seek(toFileOffset: 4)
        var riffSize = UInt32(min(fileSize - 8, UInt64(UInt32.max)))
        handle.write(Data(bytes: &riffSize, count: 4))

        // Find "data" subchunk — usually at offset 36, but could vary
        handle.seek(toFileOffset: 12)
        var dataChunkOffset: UInt64 = 12
        while dataChunkOffset < min(fileSize, 200) {
            handle.seek(toFileOffset: dataChunkOffset)
            let subchunkHeader = try handle.availableData(upTo: 8)
            guard subchunkHeader.count >= 8 else { break }
            let subchunkID = String(data: subchunkHeader[0..<4], encoding: .ascii)
            if subchunkID == "data" {
                // Fix data chunk size
                let dataSize = UInt32(min(fileSize - dataChunkOffset - 8, UInt64(UInt32.max)))
                handle.seek(toFileOffset: dataChunkOffset + 4)
                var size = dataSize
                handle.write(Data(bytes: &size, count: 4))
                return
            }
            let subchunkSize = subchunkHeader.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
            dataChunkOffset += 8 + UInt64(subchunkSize)
        }

        throw ConversionError.invalidWAV
    }

    // MARK: - Errors

    enum ConversionError: LocalizedError {
        case exportSessionFailed
        case exportFailed
        case exportCancelled
        case invalidWAV

        var errorDescription: String? {
            switch self {
            case .exportSessionFailed: return "Cannot create audio export session"
            case .exportFailed: return "Audio conversion failed"
            case .exportCancelled: return "Audio conversion was cancelled"
            case .invalidWAV: return "Not a valid WAV file"
            }
        }
    }
}

private extension FileHandle {
    func availableData(upTo maxLength: Int) throws -> Data {
        try read(upToCount: maxLength) ?? Data()
    }
}
