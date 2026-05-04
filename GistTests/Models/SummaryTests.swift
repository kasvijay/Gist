import XCTest
@testable import Gist

final class SummaryTests: XCTestCase {
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

    func testCodableRoundTripAllFields() throws {
        let original = Summary(
            created: Date(),
            model: "gemma-3",
            content: "Full content here",
            overview: "This was a meeting about X.",
            decisions: ["Decision 1", "Decision 2"],
            actionItems: ["Action 1"],
            keyPoints: ["Point A", "Point B", "Point C"]
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Summary.self, from: data)

        XCTAssertEqual(decoded.model, "gemma-3")
        XCTAssertEqual(decoded.content, "Full content here")
        XCTAssertEqual(decoded.overview, "This was a meeting about X.")
        XCTAssertEqual(decoded.decisions, ["Decision 1", "Decision 2"])
        XCTAssertEqual(decoded.actionItems, ["Action 1"])
        XCTAssertEqual(decoded.keyPoints?.count, 3)
    }

    func testCodableWithMissingOptionalFields() throws {
        let json = """
        {
            "created": "2026-01-01T12:00:00Z",
            "model": "gemma-3",
            "content": "raw output"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Summary.self, from: json)
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertNil(decoded.overview)
        XCTAssertNil(decoded.decisions)
        XCTAssertNil(decoded.actionItems)
        XCTAssertNil(decoded.keyPoints)
    }

    func testCodableWithMissingVersion() throws {
        let json = """
        {
            "created": "2026-01-01T12:00:00Z",
            "model": "gemma-3",
            "content": "output"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(Summary.self, from: json)
        XCTAssertEqual(decoded.version, "1.0")
    }
}
