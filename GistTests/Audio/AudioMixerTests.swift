import XCTest
import AVFoundation
@testable import Gist

final class AudioMixerTests: XCTestCase {
    private let mixer = AudioMixer()

    private func makeBuffer(frameCount: AVAudioFrameCount, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = 0
        return buffer
    }

    func testMicMutedOutputsOnlySystemAudio() {
        let buffer = makeBuffer(frameCount: 4)
        let mic: [Float] = [0.1, 0.2, 0.3, 0.4]
        let system: [Float] = [0.5, 0.6, 0.7, 0.8]

        let result = mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: true, micPtr: micPtr.baseAddress!, micCount: 4, systemSamples: system)
        }

        XCTAssertTrue(result)
        XCTAssertEqual(buffer.frameLength, 4)
        let output = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 4))
        for i in 0..<4 {
            XCTAssertEqual(output[i], system[i], accuracy: 0.001)
        }
    }

    func testLoudMicDucksSystemAudio() {
        let buffer = makeBuffer(frameCount: 100)
        // Loud mic signal — RMS well above 0.01 threshold
        let mic = [Float](repeating: 0.5, count: 100)
        let system = [Float](repeating: 0.5, count: 100)

        let result = mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: false, micPtr: micPtr.baseAddress!, micCount: 100, systemSamples: system)
        }

        XCTAssertTrue(result)
        let output = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 100))
        // Expected: mic(0.5) + system(0.5 * 0.3 ducking) = 0.5 + 0.15 = 0.65
        XCTAssertEqual(output[50], 0.65, accuracy: 0.02)
    }

    func testQuietMicNoDucking() {
        let buffer = makeBuffer(frameCount: 100)
        // Very quiet mic — RMS below 0.01
        let mic = [Float](repeating: 0.001, count: 100)
        let system = [Float](repeating: 0.5, count: 100)

        let result = mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: false, micPtr: micPtr.baseAddress!, micCount: 100, systemSamples: system)
        }

        XCTAssertTrue(result)
        let output = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 100))
        // Expected: mic(0.001) + system(0.5 * 1.0 no ducking) = 0.501
        XCTAssertEqual(output[50], 0.501, accuracy: 0.01)
    }

    func testOutputClippedToUnitRange() {
        let buffer = makeBuffer(frameCount: 4)
        // Loud signals that sum > 1.0
        let mic: [Float] = [0.8, 0.8, 0.8, 0.8]
        let system: [Float] = [0.8, 0.8, 0.8, 0.8]

        mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: false, micPtr: micPtr.baseAddress!, micCount: 4, systemSamples: system)
        }

        let output = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 4))
        for sample in output {
            XCTAssertLessThanOrEqual(sample, 1.0)
            XCTAssertGreaterThanOrEqual(sample, -1.0)
        }
    }

    func testCountIsMinOfMicAndSystem() {
        let buffer = makeBuffer(frameCount: 10)
        let mic = [Float](repeating: 0.1, count: 3)
        let system = [Float](repeating: 0.2, count: 5)

        let result = mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: false, micPtr: micPtr.baseAddress!, micCount: 3, systemSamples: system)
        }

        XCTAssertTrue(result)
        XCTAssertEqual(buffer.frameLength, 3) // min(3, 5) = 3
    }

    func testEmptyInputsReturnsFalse() {
        let buffer = makeBuffer(frameCount: 10)
        let mic: [Float] = []
        let system: [Float] = []

        let result = mic.withUnsafeBufferPointer { micPtr in
            mixer.mixInto(outputBuffer: buffer, micMuted: false, micPtr: micPtr.baseAddress!, micCount: 0, systemSamples: system)
        }

        XCTAssertFalse(result)
    }
}
