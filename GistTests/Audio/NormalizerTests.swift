import XCTest
@testable import Gist

final class NormalizerTests: XCTestCase {
    private let normalizer = Normalizer()

    func testEmptyArrayNoOp() {
        var samples: [Float] = []
        normalizer.apply(to: &samples)
        XCTAssertTrue(samples.isEmpty)
    }

    func testSilenceSkipped() {
        // All zeros — RMS is 0, below 0.0001 threshold
        var samples: [Float] = [0, 0, 0, 0, 0]
        normalizer.apply(to: &samples)
        XCTAssertEqual(samples, [0, 0, 0, 0, 0])
    }

    func testNormalizesToTargetRMS() {
        // Uniform signal at 0.5 → RMS = 0.5, gain = 0.1/0.5 = 0.2
        var samples: [Float] = Array(repeating: 0.5, count: 100)
        normalizer.apply(to: &samples)

        // After normalization, samples should be ~0.1
        let expected: Float = 0.1
        XCTAssertEqual(samples[0], expected, accuracy: 0.01)
    }

    func testGainCappedAt10x() {
        // Very quiet signal: RMS = 0.001, gain would be 0.1/0.001 = 100, capped at 10
        var samples: [Float] = Array(repeating: 0.001, count: 100)
        normalizer.apply(to: &samples)

        // With gain capped at 10: 0.001 * 10 = 0.01
        XCTAssertEqual(samples[0], 0.01, accuracy: 0.002)
    }

    func testClippingToUnitRange() {
        // Signal at 0.5, gain would produce values > 1.0? No, but test with louder.
        // Actually let's create a signal that after gain will exceed [-1, 1]
        // RMS of [0.02] = 0.02, gain = 0.1/0.02 = 5.0
        // 0.02 * 5 = 0.1 — that's fine. We need a mixed signal.
        // Use 0.15 average but with a spike at 2.0:
        var samples: [Float] = Array(repeating: 0.02, count: 99) + [2.0]
        normalizer.apply(to: &samples)

        // The spike should be clipped to 1.0
        for sample in samples {
            XCTAssertLessThanOrEqual(sample, 1.0)
            XCTAssertGreaterThanOrEqual(sample, -1.0)
        }
    }

    func testSingleSample() {
        var samples: [Float] = [0.5]
        normalizer.apply(to: &samples)
        // RMS of [0.5] = 0.5, gain = 0.1/0.5 = 0.2
        XCTAssertEqual(samples[0], 0.1, accuracy: 0.01)
    }
}
