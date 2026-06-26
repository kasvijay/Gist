import XCTest
@testable import Gist

final class FindIndexBuilderTests: XCTestCase {

    // MARK: - Transcript

    func testTranscriptElementsPreserveOrderAndAnchors() {
        let s0 = Transcript.Segment(segmentIndex: 0, start: 0, end: 1, text: "hello", confidence: 0.9)
        let s1 = Transcript.Segment(segmentIndex: 1, start: 1, end: 2, text: "world", confidence: 0.9)
        let transcript = Transcript(created: Date(), durationSeconds: 2, model: "m", speakers: nil, segments: [s0, s1])

        let elements = FindIndexBuilder.elements(forTranscript: transcript)
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements[0].text, "hello")
        XCTAssertEqual(elements[1].text, "world")
        XCTAssertEqual(elements[0].anchor, AnyHashable(s0.id))
        XCTAssertEqual(elements[1].anchor, AnyHashable(s1.id))
    }

    // MARK: - Structured summary

    func testStructuredSummaryEmitsBlocksInRenderOrder() {
        let k = TimedKeyPoint(text: "Key one", startSeconds: 5)
        let summary = Summary(
            created: Date(), model: "m", content: "full",
            overview: "Overview text",
            decisions: ["D1", "D2"],
            actionItems: ["A1"],
            keyPoints: [k]
        )

        let elements = FindIndexBuilder.elements(forSummary: summary)
        // blockquote, overview, decision0, decision1, action0, keyPoint
        XCTAssertEqual(elements.map(\.text), ["Overview text", "Overview text", "D1", "D2", "A1", "Key one"])
        XCTAssertEqual(elements[0].anchor, AnyHashable(SummaryAnchor.blockquote))
        XCTAssertEqual(elements[1].anchor, AnyHashable(SummaryAnchor.overview))
        XCTAssertEqual(elements[2].anchor, AnyHashable(SummaryAnchor.decision(0)))
        XCTAssertEqual(elements[3].anchor, AnyHashable(SummaryAnchor.decision(1)))
        XCTAssertEqual(elements[4].anchor, AnyHashable(SummaryAnchor.action(0)))
        XCTAssertEqual(elements[5].anchor, AnyHashable(SummaryAnchor.keyPoint(k.id)))
    }

    func testSummaryWithOnlyDecisionsSkipsAbsentSections() {
        let summary = Summary(
            created: Date(), model: "m", content: "full",
            overview: nil, decisions: ["only decision"], actionItems: nil, keyPoints: nil
        )
        let elements = FindIndexBuilder.elements(forSummary: summary)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].anchor, AnyHashable(SummaryAnchor.decision(0)))
    }

    // MARK: - Legacy fallback summary

    func testLegacyFallbackSummaryIndexesContent() {
        // No structured sections → fallback path mirrors SummaryView.fallbackContent.
        let summary = Summary(
            created: Date(), model: "m", content: "Plain legacy summary body",
            overview: nil, decisions: nil, actionItems: nil, keyPoints: nil
        )
        let elements = FindIndexBuilder.elements(forSummary: summary)
        XCTAssertFalse(elements.isEmpty, "Legacy summaries must still be searchable")
        XCTAssertTrue(elements.allSatisfy { $0.text.contains("Plain legacy summary body") })
    }
}
