import XCTest
@testable import Gist

@MainActor
final class SummaryExporterTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSummary(withTimedKeyPoints: Bool = true) -> Summary {
        Summary(
            created: Date(),
            model: "gemma-3",
            content: "raw content",
            overview: "A meeting overview paragraph.",
            decisions: ["Decision 1", "Decision 2"],
            actionItems: ["Action 1", "Action 2"],
            keyPoints: withTimedKeyPoints ? [
                TimedKeyPoint(text: "Architecture review came up", startSeconds: 12),
                TimedKeyPoint(text: "Timeline estimation discussion", startSeconds: 95),
                TimedKeyPoint(text: "Budget point with no timestamp", startSeconds: nil)
            ] : [
                TimedKeyPoint(text: "Plain key point", startSeconds: nil)
            ]
        )
    }

    private func makeEntry() -> SessionIndex.SessionEntry {
        SessionIndex.SessionEntry(
            id: "test-id",
            name: "Q3 Review",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            durationSeconds: 600,
            model: "test",
            path: "test-id",
            hasAudio: false,
            hasTranscript: true,
            segmentCount: 5,
            languagesDetected: nil
        )
    }

    // MARK: - Plain text export

    func testPlainTextOmitsTimestampsForTimedKeyPoints() {
        let summary = makeSummary()
        let plain = SummaryExporter.plainText(summary: summary, entry: makeEntry(), transcript: nil)

        XCTAssertFalse(plain.contains("[00:12]"),
                       "Plain text export must not include timestamps; got:\n\(plain)")
        XCTAssertFalse(plain.contains("[01:35]"),
                       "Plain text export must not include timestamps; got:\n\(plain)")
        // A timestamp-shaped bracket anywhere in the KDP section is a regression.
        let pattern = #"\[\d{1,2}:\d{2}\]"#
        XCTAssertNil(plain.range(of: pattern, options: .regularExpression),
                     "Plain text export contained a timestamp-shaped string:\n\(plain)")
    }

    func testPlainTextStillContainsAllKeyPointText() {
        let summary = makeSummary()
        let plain = SummaryExporter.plainText(summary: summary, entry: makeEntry(), transcript: nil)
        XCTAssertTrue(plain.contains("Architecture review came up"))
        XCTAssertTrue(plain.contains("Timeline estimation discussion"))
        XCTAssertTrue(plain.contains("Budget point with no timestamp"))
    }

    func testPlainTextStillContainsStructuralSections() {
        let summary = makeSummary()
        let plain = SummaryExporter.plainText(summary: summary, entry: makeEntry(), transcript: nil)
        XCTAssertTrue(plain.contains("OVERVIEW"))
        XCTAssertTrue(plain.contains("DECISIONS"))
        XCTAssertTrue(plain.contains("ACTION ITEMS"))
        XCTAssertTrue(plain.contains("KEY DISCUSSION POINTS"))
    }

    // MARK: - Attributed string (Copy / Word / PDF source)

    func testAttributedStringOmitsTimestamps() {
        let summary = makeSummary()
        let attr = SummaryExporter.attributedString(summary: summary, entry: makeEntry(), transcript: nil)
        let plainRepresentation = attr.string

        XCTAssertFalse(plainRepresentation.contains("[00:12]"))
        XCTAssertFalse(plainRepresentation.contains("[01:35]"))
        let pattern = #"\[\d{1,2}:\d{2}\]"#
        XCTAssertNil(plainRepresentation.range(of: pattern, options: .regularExpression),
                     "Attributed string export contained a timestamp-shaped string:\n\(plainRepresentation)")
    }

    func testAttributedStringStillContainsAllKeyPointText() {
        let summary = makeSummary()
        let attr = SummaryExporter.attributedString(summary: summary, entry: makeEntry(), transcript: nil)
        let plainRepresentation = attr.string
        XCTAssertTrue(plainRepresentation.contains("Architecture review came up"))
        XCTAssertTrue(plainRepresentation.contains("Timeline estimation discussion"))
        XCTAssertTrue(plainRepresentation.contains("Budget point with no timestamp"))
    }

    // MARK: - Edge cases

    func testKeyPointsWithoutAnyTimestamps() {
        let summary = makeSummary(withTimedKeyPoints: false)
        let plain = SummaryExporter.plainText(summary: summary, entry: makeEntry(), transcript: nil)
        XCTAssertTrue(plain.contains("Plain key point"))
        XCTAssertNil(plain.range(of: #"\[\d{1,2}:\d{2}\]"#, options: .regularExpression))
    }

    func testEmptyKeyPointsListOmitsHeader() {
        let summary = Summary(
            created: Date(),
            model: "test",
            content: "",
            overview: "Just an overview.",
            decisions: nil,
            actionItems: nil,
            keyPoints: nil
        )
        let plain = SummaryExporter.plainText(summary: summary, entry: makeEntry(), transcript: nil)
        XCTAssertFalse(plain.contains("KEY DISCUSSION POINTS"))
    }
}
