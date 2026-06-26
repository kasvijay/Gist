import XCTest
@testable import Gist

@MainActor
final class SessionStoreTests: XCTestCase {
    private var store: SessionStore!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            store = SessionStore()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            // Clean up any test sessions we created
            if let session = store.currentSession {
                store.deleteSession(id: session.id)
            }
            store = nil
        }
        super.tearDown()
    }

    // MARK: - startSession

    func testStartSessionReturnsSessionWithRecordingStatus() {
        let session = store.startSession()
        XCTAssertEqual(session.status, .recording)
        XCTAssertFalse(session.id.isEmpty)
        XCTAssertFalse(session.name.isEmpty)
        // Clean up
        store.deleteSession(id: session.id)
    }

    func testStartSessionAppearsInIndex() {
        let session = store.startSession()
        let found = store.sessions.contains { $0.id == session.id }
        XCTAssertTrue(found, "Recording session should appear in sidebar index immediately")
        // Clean up
        store.deleteSession(id: session.id)
    }

    func testStartSessionCreatesFolder() {
        let session = store.startSession()
        let folderURL = store.baseURL.appendingPathComponent(session.folderName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
        // Clean up
        store.deleteSession(id: session.id)
    }

    // MARK: - finishSession

    func testFinishSessionSetsComplete() {
        let session = store.startSession()
        store.finishSession(duration: 120.0)

        // After finishing, the index entry should be updated
        let entry = store.sessions.first { $0.id == session.id }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.durationSeconds, 120.0)
        XCTAssertNotNil(entry?.endedAt)
        XCTAssertNil(store.currentSession)

        // Clean up
        store.deleteSession(id: session.id)
    }

    // MARK: - Index Deduplication

    func testUpdateIndexDeduplicates() {
        let session = store.startSession()
        let countBefore = store.sessions.filter { $0.id == session.id }.count
        XCTAssertEqual(countBefore, 1)

        // finishSession calls updateIndex again — should still be 1 entry
        store.finishSession(duration: 60.0)
        let countAfter = store.sessions.filter { $0.id == session.id }.count
        XCTAssertEqual(countAfter, 1)

        // Clean up
        store.deleteSession(id: session.id)
    }

    func testUpdateIndexInsertsAtFront() {
        // Create a first session
        let session1 = store.startSession()
        store.finishSession(duration: 10)

        // Create a second session
        let session2 = store.startSession()
        store.finishSession(duration: 20)

        // Second session should be at front
        XCTAssertEqual(store.sessions.first?.id, session2.id)

        // Clean up
        store.deleteSession(id: session1.id)
        store.deleteSession(id: session2.id)
    }

    // MARK: - deleteSession

    func testDeleteSessionRemovesFromIndex() {
        let session = store.startSession()
        store.finishSession(duration: 5)
        let id = session.id

        store.deleteSession(id: id)
        XCTAssertFalse(store.sessions.contains { $0.id == id })
    }

    // MARK: - renameSession

    func testRenameSessionUpdatesIndex() {
        let session = store.startSession()
        store.finishSession(duration: 5)

        store.renameSession(id: session.id, newName: "My Custom Name")
        let entry = store.sessions.first { $0.id == session.id }
        XCTAssertEqual(entry?.name, "My Custom Name")

        // Clean up
        store.deleteSession(id: session.id)
    }

    // MARK: - Path Construction

    func testPathConstruction() {
        let session = Session(id: "2026-01-01_120000", name: "Test", startedAt: Date(), status: .recording)
        let audioURL = store.audioFileURL(for: session)
        let wavURL = store.recordingAudioFileURL(for: session)
        let transcriptURL = store.transcriptURL(for: session)

        XCTAssertTrue(audioURL.path.hasSuffix("2026-01-01_120000/audio.m4a"))
        XCTAssertTrue(wavURL.path.hasSuffix("2026-01-01_120000/audio.wav"))
        XCTAssertTrue(transcriptURL.path.hasSuffix("2026-01-01_120000/transcript.json"))
    }
}
