import XCTest
import AVFoundation
@testable import Gist

final class AudioFileWriterTests: XCTestCase {

    // MARK: - makePCMSettings

    func testPCMSettingsMonoFormat() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
    }

    func testPCMSettingsStereoFormat() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    }

    func testPCMSettingsChannelsClamped() {
        // 5-channel format — should be clamped to 2
        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_AudioUnit_5_0)!
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channelLayout: layout)
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 2)
    }

    func testPCMSettingsValidSampleRatePassedThrough() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 48000)
    }

    func testPCMSettingsBitDepthIs16() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVLinearPCMBitDepthKey] as? Int, 16)
    }

    func testPCMSettingsIsNotFloat() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let settings = AudioFileWriter.makePCMSettings(for: format)
        XCTAssertEqual(settings[AVLinearPCMIsFloatKey] as? Bool, false)
    }

    // MARK: - repairWAVHeader

    func testRepairWAVHeaderValidFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_repair_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        // Create a minimal valid WAV file with wrong sizes
        var wavData = Data()
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(Data(repeating: 0, count: 4)) // wrong RIFF size
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        var fmtSize: UInt32 = 16
        wavData.append(Data(bytes: &fmtSize, count: 4))
        wavData.append(Data(repeating: 0, count: 16)) // fmt chunk body
        wavData.append("data".data(using: .ascii)!)
        wavData.append(Data(repeating: 0, count: 4)) // wrong data size
        // Audio data (100 bytes of silence)
        wavData.append(Data(repeating: 0, count: 100))

        try wavData.write(to: url)
        let originalSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64

        try AudioFileWriter.repairWAVHeader(url: url)

        // Read back and verify the RIFF chunk size was corrected
        let repairedData = try Data(contentsOf: url)
        let riffSize = repairedData.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self)
        }
        XCTAssertEqual(UInt64(riffSize), originalSize - 8, "RIFF size should be fileSize - 8")
    }

    func testRepairWAVHeaderNonWAVFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_nonwav_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write a non-WAV file with >= 44 bytes
        let data = Data(repeating: 0x42, count: 100)
        try! data.write(to: url)

        XCTAssertThrowsError(try AudioFileWriter.repairWAVHeader(url: url)) { error in
            XCTAssertTrue(error is AudioFileWriter.ConversionError)
        }
    }

    func testRepairWAVHeaderTooSmallThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_small_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write < 44 bytes
        let data = Data(repeating: 0, count: 20)
        try! data.write(to: url)

        XCTAssertThrowsError(try AudioFileWriter.repairWAVHeader(url: url)) { error in
            XCTAssertTrue(error is AudioFileWriter.ConversionError)
        }
    }
}
