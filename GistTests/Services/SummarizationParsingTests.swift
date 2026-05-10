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

    // MARK: - formatTranscript (now lives on SummaryPromptBuilder; includes [mm:ss])

    func testFormatTranscriptIncludesTimestampsAndSpeakers() {
        let transcript = makeTranscript(segments: [
            ("Speaker 1", "Hello everyone"),
            ("Speaker 2", "Hi there"),
        ])
        let result = SummaryPromptBuilder.formatTranscript(transcript)
        XCTAssertEqual(result, "[00:00] [Speaker 1] Hello everyone\n[00:05] [Speaker 2] Hi there")
    }

    func testFormatTranscriptNilSpeakerBecomesUnknown() {
        let transcript = makeTranscript(segments: [(nil, "Some text")])
        let result = SummaryPromptBuilder.formatTranscript(transcript)
        XCTAssertEqual(result, "[00:00] [Unknown] Some text")
    }

    func testFormatTranscriptEmptySegments() {
        let transcript = Transcript(created: Date(), durationSeconds: 0, model: "test", speakers: nil, segments: [])
        let result = SummaryPromptBuilder.formatTranscript(transcript)
        XCTAssertEqual(result, "")
    }

    // MARK: - sampleSegmentsEvenly (still on SummarizationEngine)

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
        XCTAssertEqual(lines.count, Set(lines).count)
    }

    // MARK: - parseSummary (now SummaryPromptBuilder.parseSummary)

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
        let summary = SummaryPromptBuilder.parseSummary(output: output, model: "gemma-3")
        XCTAssertEqual(summary.model, "gemma-3")
        XCTAssertEqual(summary.overview, "A productive meeting about the project.")
        XCTAssertEqual(summary.decisions, ["Use SwiftUI for the UI layer", "Deploy on macOS 14+"])
        XCTAssertEqual(summary.actionItems, ["Write unit tests", "Set up CI"])
        XCTAssertEqual(summary.keyPoints?.map(\.text), ["Architecture review", "Timeline estimation"])
    }

    func testParseSummaryStripsTrailingTimestampsFromKeyPoints() {
        let output = """
        ## Overview
        Brief overview.

        ## Key Discussion Points
        - Architecture review [00:34]
        - Timeline estimation [12:45]
        """
        let summary = SummaryPromptBuilder.parseSummary(output: output, model: "test")
        // Without a transcript, timestamps are still parsed and stripped from text,
        // but startSeconds remains nil because there's nothing to validate against.
        XCTAssertEqual(summary.keyPoints?.map(\.text), ["Architecture review", "Timeline estimation"])
        XCTAssertNil(summary.keyPoints?[0].startSeconds)
    }

    func testParseSummaryResolvesTimestampWithTranscript() {
        let transcript = makeTranscript(segments: [
            ("Speaker 1", "Let's discuss the architecture review process."),
            ("Speaker 2", "We should look at the timeline estimation as well."),
        ])
        // Segment 0 starts at 0s, segment 1 starts at 5s.
        let output = """
        ## Key Discussion Points
        - Architecture review process [00:01]
        - Timeline estimation [00:06]
        """
        let summary = SummaryPromptBuilder.parseSummary(
            output: output,
            model: "test",
            transcript: transcript
        )
        XCTAssertEqual(summary.keyPoints?.count, 2)
        // Snapped to nearest segment start.
        XCTAssertEqual(summary.keyPoints?[0].startSeconds, 0)
        XCTAssertEqual(summary.keyPoints?[1].startSeconds, 5)
    }

    func testParseSummaryMissingSections() {
        let output = """
        ## Overview
        Just an overview, nothing else.
        """
        let summary = SummaryPromptBuilder.parseSummary(output: output, model: "test")
        XCTAssertEqual(summary.overview, "Just an overview, nothing else.")
        XCTAssertNil(summary.decisions)
        XCTAssertNil(summary.actionItems)
        XCTAssertNil(summary.keyPoints)
    }

    func testParseSummaryEmptyOutput() {
        let summary = SummaryPromptBuilder.parseSummary(output: "", model: "test")
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
