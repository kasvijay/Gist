import XCTest
@testable import Gist

final class AudioSharedStateTests: XCTestCase {
    private var state: AudioSharedState!

    override func setUp() {
        super.setUp()
        state = AudioSharedState()
    }

    override func tearDown() {
        state = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateNotReady() {
        XCTAssertFalse(state.isReady)
    }

    // MARK: - appendSystemSamples

    func testAppendSetsReady() {
        state.appendSystemSamples([0.1, 0.2, 0.3])
        XCTAssertTrue(state.isReady)
    }

    func testAppendEmptyArrayStillSetsReady() {
        state.appendSystemSamples([])
        XCTAssertTrue(state.isReady)
    }

    // MARK: - consumeSystemSamples

    func testConsumeReturnsCorrectSamples() {
        state.appendSystemSamples([1.0, 2.0, 3.0, 4.0, 5.0])
        let consumed = state.consumeSystemSamples(count: 3)
        XCTAssertEqual(consumed, [1.0, 2.0, 3.0])

        // Remaining should be [4.0, 5.0]
        let rest = state.consumeSystemSamples(count: 10)
        XCTAssertEqual(rest, [4.0, 5.0])
    }

    func testConsumeMoreThanAvailable() {
        state.appendSystemSamples([1.0, 2.0])
        let consumed = state.consumeSystemSamples(count: 100)
        XCTAssertEqual(consumed, [1.0, 2.0])
    }

    func testConsumeFromEmptyBuffer() {
        let consumed = state.consumeSystemSamples(count: 5)
        XCTAssertTrue(consumed.isEmpty)
    }

    // MARK: - shouldSkipWriter

    func testSkipWriterFirstNineCallsWhenNotReady() {
        for i in 1...9 {
            XCTAssertTrue(state.shouldSkipWriter(), "Call \(i) should skip when not ready")
        }
    }

    func testSkipWriterTenthCallStartsWriter() {
        for _ in 1...9 {
            _ = state.shouldSkipWriter()
        }
        // 10th call: _callbackCount = 10, which is NOT < 10, so writer starts
        XCTAssertFalse(state.shouldSkipWriter(), "10th call should start writer")
    }

    func testSkipWriterImmediateWhenReady() {
        state.appendSystemSamples([1.0]) // Sets _ready = true
        // First call: _ready is true, so condition !_ready && _callbackCount < 10 is false → starts writer
        XCTAssertFalse(state.shouldSkipWriter())
    }

    func testSkipWriterOnceStartedAlwaysReturnsFalse() {
        // Start the writer
        state.appendSystemSamples([1.0])
        XCTAssertFalse(state.shouldSkipWriter()) // starts it

        // Subsequent calls should always return false
        XCTAssertFalse(state.shouldSkipWriter())
        XCTAssertFalse(state.shouldSkipWriter())
        XCTAssertFalse(state.shouldSkipWriter())
    }

    // MARK: - reset

    func testResetClearsAllState() {
        state.appendSystemSamples([1.0, 2.0, 3.0])
        _ = state.shouldSkipWriter()

        state.reset()

        XCTAssertFalse(state.isReady)
        let consumed = state.consumeSystemSamples(count: 10)
        XCTAssertTrue(consumed.isEmpty)
        // After reset, shouldSkipWriter should behave as initial state
        XCTAssertTrue(state.shouldSkipWriter(), "After reset, first call should skip again")
    }
}
