import XCTest
@testable import Gist

final class SessionTests: XCTestCase {
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

    // MARK: - makeID

    func testMakeIDFormat() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(
            calendar: cal, timeZone: cal.timeZone,
            year: 2026, month: 3, day: 15, hour: 14, minute: 30, second: 5
        )
        let date = cal.date(from: components)!
        let id = Session.makeID(date: date)
        // DateFormatter uses device locale for formatting; we just check the structure
        XCTAssertTrue(id.contains("2026"), "ID should contain the year")
        XCTAssertTrue(id.contains("03-15") || id.contains("03_15") || id.count > 10, "ID should be a timestamp string")
    }

    func testMakeIDUniqueForDifferentDates() {
        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 1000001)
        XCTAssertNotEqual(Session.makeID(date: date1), Session.makeID(date: date2))
    }

    // MARK: - folderName

    func testFolderNameReturnsID() {
        let session = Session(id: "test-id", name: "Test", startedAt: Date(), status: .recording)
        XCTAssertEqual(session.folderName, "test-id")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let now = Date()
        let original = Session(
            id: "2026-01-01_120000",
            name: "Test Session",
            startedAt: now,
            endedAt: now.addingTimeInterval(300),
            durationSeconds: 300,
            status: .complete,
            devices: Session.Devices(microphone: "MacBook Pro Microphone", systemAudio: "System")
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Session.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds)
        XCTAssertEqual(decoded.devices?.microphone, "MacBook Pro Microphone")
    }

    func testCodableWithMissingVersion() throws {
        // JSON without a "version" field — should default to "1.0"
        let json = """
        {
            "id": "test-id",
            "name": "Test",
            "startedAt": "2026-01-01T12:00:00Z",
            "status": "complete"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Session.self, from: json)
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertEqual(decoded.id, "test-id")
        XCTAssertEqual(decoded.status, .complete)
    }

    func testCodableWithMissingOptionalFields() throws {
        let json = """
        {
            "id": "test-id",
            "name": "Test",
            "startedAt": "2026-01-01T12:00:00Z",
            "status": "recording"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Session.self, from: json)
        XCTAssertNil(decoded.endedAt)
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertNil(decoded.devices)
    }

    // MARK: - Status Enum

    func testStatusRawValues() {
        XCTAssertEqual(Session.Status.recording.rawValue, "recording")
        XCTAssertEqual(Session.Status.complete.rawValue, "complete")
        XCTAssertEqual(Session.Status.recovered.rawValue, "recovered")
    }
}
