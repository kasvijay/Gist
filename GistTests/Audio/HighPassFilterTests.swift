import XCTest
@testable import Gist

final class HighPassFilterTests: XCTestCase {

    func testCoefficientCount() {
        // Access the filter through its apply method behavior — coefficients are private
        // but we can verify the filter initializes without crashing
        var filter = HighPassFilter(cutoffHz: 80.0, sampleRate: 48000.0)
        var samples: [Float] = Array(repeating: 0.5, count: 100)
        filter.apply(to: &samples)
        // If coefficients were wrong or missing, apply would return early
        // Verify the filter actually ran by checking output differs from input
        XCTAssertNotEqual(samples, Array(repeating: 0.5, count: 100))
    }

    func testApplyEmptyArray() {
        var filter = HighPassFilter()
        var samples: [Float] = []
        filter.apply(to: &samples)
        XCTAssertTrue(samples.isEmpty)
    }

    func testDCSignalAttenuated() {
        // A constant (DC) signal should be heavily attenuated by a high-pass filter
        var filter = HighPassFilter(cutoffHz: 80.0, sampleRate: 48000.0)
        let dcLevel: Float = 0.5
        var samples = [Float](repeating: dcLevel, count: 1000)
        filter.apply(to: &samples)

        // After filtering, the tail should be near 0 (DC removed)
        let tail = Array(samples[500...])
        let avgTail = tail.reduce(0, +) / Float(tail.count)
        XCTAssertEqual(avgTail, 0, accuracy: 0.05, "DC signal should be attenuated by high-pass filter")
    }

    func testHighFrequencyPassesThrough() {
        // Generate a sine wave well above the cutoff (e.g., 1000 Hz at 48kHz sample rate)
        let sampleRate: Double = 48000
        let freq: Double = 1000
        let n = 4800 // 0.1 seconds
        var samples = (0..<n).map { Float(sin(2.0 * Double.pi * freq * Double($0) / sampleRate)) }
        let inputRMS = rms(samples)

        var filter = HighPassFilter(cutoffHz: 80.0, sampleRate: sampleRate)
        filter.apply(to: &samples)
        let outputRMS = rms(Array(samples[100...])) // skip transient

        // High-frequency signal should pass with minimal attenuation (>80% of original)
        XCTAssertGreaterThan(outputRMS, inputRMS * 0.8, "1kHz signal should pass through 80Hz high-pass filter")
    }

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }
}
