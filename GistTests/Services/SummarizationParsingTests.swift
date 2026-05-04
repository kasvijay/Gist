import XCTest
@testable import Gist

@MainActor
final class SummarizationParsingTests: XCTestCase {
    private var engine: SummarizationEngine!

    override func setUp() {
        super.setUp()
        engine = SummarizationEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - formatTranscript

    func testFormatTranscriptMapsSegments() {
        let transcript = makeTranscript(segments: [
            ("Speaker 1", "Hello everyone"),
            ("Speaker 2", "Hi there"),
        ])
        let result = engine.formatTranscript(transcript)
        XCTAssertEqual(result, "[Speaker 1] Hello everyone\n[Speaker 2] Hi there")
    }

    func testFormatTranscriptNilSpeakerBecomesUnknown() {
        let transcript = makeTranscript(segments: [(nil, "Some text")])
        let result = engine.formatTranscript(transcript)
        XCTAssertEqual(result, "[Unknown] Some text")
    }

    func testFormatTranscriptEmptySegments() {
        let transcript = Transcript(created: Date(), durationSeconds: 0, model: "test", speakers: nil, segments: [])
        let result = engine.formatTranscript(transcript)
        XCTAssertEqual(result, "")
    }

    // MARK: - sampleSegmentsEvenly

    func testSampleEmptyArray() {
        XCTAssertEqual(engine.sampleSegmentsEvenly([], targetCount: 5), "")
    }

    func testSampleTargetCountGreaterThanOrEqualReturnsAll() {
        let segments = ["A", "B", "C"]
        XCTAssertEqual(engine.sampleSegmentsEvenly(segments, targetCount: 3), "A\nB\nC")
        XCTAssertEqual(engine.sampleSegmentsEvenly(segments, targetCount: 10), "A\nB\nC")
    }

    func testSampleTargetCountOneReturnsFirst() {
        let segments = ["A", "B", "C", "D"]
        XCTAssertEqual(engine.sampleSegmentsEvenly(segments, targetCount: 1), "A")
    }

    func testSampleAlwaysIncludesFirstAndLast() {
        let segments = ["First", "B", "C", "D", "E", "F", "G", "H", "I", "Last"]
        let result = engine.sampleSegmentsEvenly(segments, targetCount: 3)
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "First")
        XCTAssertEqual(lines.last, "Last")
    }

    func testSampleNoDuplicateIndices() {
        let segments = (0..<20).map { "Segment \($0)" }
        let result = engine.sampleSegmentsEvenly(segments, targetCount: 5)
        let lines = result.components(separatedBy: "\n")
        // All lines should be unique
        XCTAssertEqual(lines.count, Set(lines).count)
    }

    // MARK: - extractParagraph

    func testExtractParagraphBetweenHeaders() {
        let text = """
        ## Overview
        This is the overview paragraph.

        ## Decisions
        - Decision 1
        """
        let result = engine.extractParagraph(from: text, header: "## Overview")
        XCTAssertEqual(result, "This is the overview paragraph.")
    }

    func testExtractParagraphNotFound() {
        let text = "## Overview\nSome content"
        let result = engine.extractParagraph(from: text, header: "## Missing")
        XCTAssertNil(result)
    }

    func testExtractParagraphLastSection() {
        let text = """
        ## Overview
        First section.

        ## Key Discussion Points
        This is the last section with no next header.
        """
        let result = engine.extractParagraph(from: text, header: "## Key Discussion Points")
        XCTAssertEqual(result, "This is the last section with no next header.")
    }

    // MARK: - extractSection

    func testExtractSectionDashBullets() {
        let text = """
        ## Decisions
        - Use Swift
        - Target macOS 14
        """
        let result = engine.extractSection(from: text, header: "## Decisions")
        XCTAssertEqual(result, ["Use Swift", "Target macOS 14"])
    }

    func testExtractSectionAsteriskBullets() {
        let text = """
        ## Action Items
        * Fix the bug
        * Write tests
        """
        let result = engine.extractSection(from: text, header: "## Action Items")
        XCTAssertEqual(result, ["Fix the bug", "Write tests"])
    }

    func testExtractSectionSkipsNonBulletLines() {
        let text = """
        ## Decisions
        Some preamble text
        - Actual decision
        Another non-bullet
        - Second decision
        """
        let result = engine.extractSection(from: text, header: "## Decisions")
        XCTAssertEqual(result, ["Actual decision", "Second decision"])
    }

    func testExtractSectionReturnsNilWhenNoBullets() {
        let text = """
        ## Decisions
        Just a paragraph, no bullets here.
        """
        let result = engine.extractSection(from: text, header: "## Decisions")
        XCTAssertNil(result)
    }

    func testExtractSectionHeaderNotFound() {
        let result = engine.extractSection(from: "Some text", header: "## Missing")
        XCTAssertNil(result)
    }

    // MARK: - parseSummary

    func testParseSummaryWellFormed() {
        let output = """
        ## Overview
        A productive meeting about the project.

        ## Decisions
        - Use SwiftUI for the UI layer
        - Deploy on macOS 14+

        ## Action Items
        - Write unit tests
        - Set up CI

        ## Key Discussion Points
        - Architecture review
        - Timeline estimation
        """
        let summary = engine.parseSummary(output: output, model: "gemma-3")
        XCTAssertEqual(summary.model, "gemma-3")
        XCTAssertEqual(summary.overview, "A productive meeting about the project.")
        XCTAssertEqual(summary.decisions, ["Use SwiftUI for the UI layer", "Deploy on macOS 14+"])
        XCTAssertEqual(summary.actionItems, ["Write unit tests", "Set up CI"])
        XCTAssertEqual(summary.keyPoints, ["Architecture review", "Timeline estimation"])
    }

    func testParseSummaryMissingSections() {
        let output = """
        ## Overview
        Just an overview, nothing else.
        """
        let summary = engine.parseSummary(output: output, model: "test")
        XCTAssertEqual(summary.overview, "Just an overview, nothing else.")
        XCTAssertNil(summary.decisions)
        XCTAssertNil(summary.actionItems)
        XCTAssertNil(summary.keyPoints)
    }

    func testParseSummaryEmptyOutput() {
        let summary = engine.parseSummary(output: "", model: "test")
        XCTAssertNil(summary.overview)
        XCTAssertNil(summary.decisions)
        XCTAssertNil(summary.actionItems)
        XCTAssertNil(summary.keyPoints)
        XCTAssertEqual(summary.content, "")
    }

    // MARK: - Helpers

    private func makeTranscript(segments: [(String?, String)]) -> Transcript {
        let segs = segments.enumerated().map { index, pair in
            Transcript.Segment(
                segmentIndex: index,
                start: Float(index * 5),
                end: Float((index + 1) * 5),
                text: pair.1,
                confidence: 0.9,
                speaker: pair.0
            )
        }
        return Transcript(created: Date(), durationSeconds: Double(segments.count * 5), model: "test", speakers: nil, segments: segs)
    }
}
