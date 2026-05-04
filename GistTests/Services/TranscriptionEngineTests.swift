import XCTest
@testable import Gist

@MainActor
final class TranscriptionEngineTests: XCTestCase {
    private var engine: TranscriptionEngine!

    override func setUp() {
        super.setUp()
        engine = TranscriptionEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsNotLoaded() {
        XCTAssertEqual(engine.state, .notLoaded)
    }

    // MARK: - unloadModel

    func testUnloadModelSetsStateToNotLoaded() {
        engine.state = .ready
        engine.unloadModel()
        XCTAssertEqual(engine.state, .notLoaded)
    }

    // MARK: - isOfflineModelError

    func testOfflineErrorCode1009() {
        let error = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil)
        XCTAssertTrue(TranscriptionEngine.isOfflineModelError(error))
    }

    func testOfflineErrorCode1020() {
        let error = NSError(domain: NSURLErrorDomain, code: -1020, userInfo: nil)
        XCTAssertTrue(TranscriptionEngine.isOfflineModelError(error))
    }

    func testOfflineErrorCode1200() {
        let error = NSError(domain: NSURLErrorDomain, code: -1200, userInfo: nil)
        XCTAssertTrue(TranscriptionEngine.isOfflineModelError(error))
    }

    func testOtherURLErrorCodeNotOffline() {
        let error = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: nil) // timeout
        XCTAssertFalse(TranscriptionEngine.isOfflineModelError(error))
    }

    func testNestedUnderlyingErrorWalked() {
        let networkError = NSError(domain: NSURLErrorDomain, code: -1009, userInfo: nil)
        let wrapper = NSError(
            domain: "com.example.Hub",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: networkError]
        )
        XCTAssertTrue(TranscriptionEngine.isOfflineModelError(wrapper))
    }

    func testStringFallbackMatchesNotConnected() {
        // Create an error with "not connected" in description but not NSURLErrorDomain
        let error = NSError(
            domain: "com.example.Custom",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "The device is not connected to the internet"]
        )
        XCTAssertTrue(TranscriptionEngine.isOfflineModelError(error))
    }

    func testNonNetworkErrorReturnsFalse() {
        let error = NSError(domain: "com.example.Other", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "File not found"
        ])
        XCTAssertFalse(TranscriptionEngine.isOfflineModelError(error))
    }
}
