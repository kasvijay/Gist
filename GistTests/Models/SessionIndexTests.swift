import XCTest
@testable import Gist

final class SessionIndexTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testCodableRoundTrip() throws {
        let entry = SessionIndex.SessionEntry(
            id: "test-session",
            name: "My Session",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 120,
            model: "large-v3",
            path: "test-session",
            hasAudio: true,
            hasTranscript: true,
            segmentCount: 42,
            languagesDetected: ["en", "es"],
            isPinned: true
        )
        let index = SessionIndex(sessions: [entry])

        let data = try encoder.encode(index)
        let decoded = try decoder.decode(SessionIndex.self, from: data)

        XCTAssertEqual(decoded.sessions.count, 1)
        XCTAssertEqual(decoded.sessions[0].id, "test-session")
        XCTAssertEqual(decoded.sessions[0].segmentCount, 42)
        XCTAssertEqual(decoded.sessions[0].isPinned, true)
    }

    func testSessionEntryWithNilOptionals() throws {
        let entry = SessionIndex.SessionEntry(
            id: "minimal",
            name: "Minimal",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            model: nil,
            path: "minimal",
            hasAudio: false,
            hasTranscript: false,
            segmentCount: nil,
            languagesDetected: nil,
            isPinned: nil
        )
        let index = SessionIndex(sessions: [entry])

        let data = try encoder.encode(index)
        let decoded = try decoder.decode(SessionIndex.self, from: data)

        XCTAssertNil(decoded.sessions[0].endedAt)
        XCTAssertNil(decoded.sessions[0].durationSeconds)
        XCTAssertNil(decoded.sessions[0].model)
        XCTAssertNil(decoded.sessions[0].segmentCount)
        XCTAssertNil(decoded.sessions[0].isPinned)
    }

    func testMissingVersionDefaultsTo1() throws {
        let json = """
        {
            "sessions": []
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(SessionIndex.self, from: json)
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertTrue(decoded.sessions.isEmpty)
    }
}
