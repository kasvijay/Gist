import XCTest
@testable import Gist

/// End-to-end happy path for a session's data lifecycle:
/// start → save transcript → save summary → finish, with on-disk round-trips.
/// Covers the SessionStore persistence that the whole app depends on but which
/// had no save/load round-trip coverage before.
@MainActor
final class SessionLifecycleTests: XCTestCase {
    private var store: SessionStore!
    private var sessionID: String?

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            store = SessionStore()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            if let id = sessionID { store.deleteSession(id: id) }
            store = nil
        }
        super.tearDown()
    }

    /// Spin the run loop until `condition` is true or the timeout elapses.
    /// SessionStore writes JSON on a background queue, so loads can briefly race.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func testRecordTranscribeSummarizeLifecycle() {
        // 1. Start recording
        let session = store.startSession()
        sessionID = session.id
        XCTAssertEqual(session.status, .recording)
        XCTAssertTrue(store.sessions.contains { $0.id == session.id })

        // 2. Transcribe → persist → reload
        let transcript = Transcript(
            created: Date(), durationSeconds: 12, model: "test-model", speakers: nil,
            segments: [
                Transcript.Segment(segmentIndex: 0, start: 0, end: 5, text: "Hello team", confidence: 0.95),
                Transcript.Segment(segmentIndex: 1, start: 5, end: 10, text: "Let's begin", confidence: 0.9),
            ]
        )
        store.saveTranscript(transcript, for: session)
        waitUntil { store.loadTranscript(for: session.id) != nil }

        let loadedTranscript = store.loadTranscript(for: session.id)
        XCTAssertEqual(loadedTranscript?.segments.count, 2)
        XCTAssertEqual(loadedTranscript?.segments.first?.text, "Hello team")
        XCTAssertEqual(loadedTranscript?.model, "test-model")
        XCTAssertTrue(store.sessions.first { $0.id == session.id }?.hasTranscript ?? false,
                      "Index should mark the session as having a transcript")

        // 3. Summarize → persist → reload
        let summary = Summary(
            created: Date(), model: "sum-model", content: "full content",
            overview: "We discussed the roadmap.",
            decisions: ["Ship v1"],
            actionItems: ["Email the team"],
            keyPoints: [TimedKeyPoint(text: "Roadmap timing", startSeconds: 3)]
        )
        store.saveSummary(summary, for: session.id)
        waitUntil { store.loadSummary(for: session.id) != nil }

        let loadedSummary = store.loadSummary(for: session.id)
        XCTAssertEqual(loadedSummary?.overview, "We discussed the roadmap.")
        XCTAssertEqual(loadedSummary?.decisions, ["Ship v1"])
        XCTAssertEqual(loadedSummary?.keyPoints?.first?.startSeconds, 3)

        // 4. Finish → session marked complete with a duration
        store.finishSession(duration: 12)
        let entry = store.sessions.first { $0.id == session.id }
        XCTAssertNotNil(entry, "Finished session should remain in the index")
        XCTAssertEqual(entry?.durationSeconds, 12)
    }
}
