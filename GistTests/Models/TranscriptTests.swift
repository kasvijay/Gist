import XCTest
@testable import Gist

final class TranscriptTests: XCTestCase {

    // MARK: - cleanText

    func testCleanTextStripsSpecialTokens() {
        XCTAssertEqual(Transcript.cleanText("<|en|> Hello world"), "Hello world")
        XCTAssertEqual(Transcript.cleanText("<|0.00|>Hello<|4.50|>"), "Hello")
        XCTAssertEqual(Transcript.cleanText("<|startoftranscript|>text"), "text")
    }

    func testCleanTextPreservesNormalText() {
        XCTAssertEqual(Transcript.cleanText("Hello world"), "Hello world")
        XCTAssertEqual(Transcript.cleanText(""), "")
    }

    func testCleanTextMultipleTokens() {
        let input = "<|en|> <|0.00|> Hello <|4.50|> world <|endoftext|>"
        let result = Transcript.cleanText(input)
        XCTAssertEqual(result, "Hello  world")
    }

    func testCleanTextMalformedTokensNotStripped() {
        // Incomplete token — should NOT be stripped
        XCTAssertEqual(Transcript.cleanText("<|incomplete"), "<|incomplete")
        // Just pipe brackets — should NOT be stripped
        XCTAssertEqual(Transcript.cleanText("|>text<|"), "|>text<|")
    }

    // MARK: - Safe Subscript

    func testSafeSubscriptValidIndex() {
        let arr = [10, 20, 30]
        XCTAssertEqual(arr[safe: 0], 10)
        XCTAssertEqual(arr[safe: 2], 30)
    }

    func testSafeSubscriptOutOfBounds() {
        let arr = [10, 20, 30]
        XCTAssertNil(arr[safe: 3])
        XCTAssertNil(arr[safe: 100])
    }

    func testSafeSubscriptEmptyCollection() {
        let arr: [Int] = []
        XCTAssertNil(arr[safe: 0])
    }

    // MARK: - Codable Round-Trip

    func testSegmentCodableRoundTrip() throws {
        let segment = Transcript.Segment(
            segmentIndex: 0,
            start: 0.0,
            end: 5.0,
            text: "Hello world",
            confidence: 0.95,
            language: "en",
            speaker: "Speaker 1"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(segment)
        let decoded = try decoder.decode(Transcript.Segment.self, from: data)

        XCTAssertEqual(decoded.segmentIndex, 0)
        XCTAssertEqual(decoded.text, "Hello world")
        XCTAssertEqual(decoded.confidence, 0.95, accuracy: 0.001)
        XCTAssertEqual(decoded.speaker, "Speaker 1")
    }

    func testTranscriptCodableRoundTrip() throws {
        let transcript = Transcript(
            created: Date(),
            durationSeconds: 120.0,
            model: "large-v3",
            speakers: nil,
            segments: [
                Transcript.Segment(segmentIndex: 0, start: 0, end: 5, text: "Hello", confidence: 0.9),
                Transcript.Segment(segmentIndex: 1, start: 5, end: 10, text: "World", confidence: 0.8, speaker: "Alice"),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(transcript)
        let decoded = try decoder.decode(Transcript.self, from: data)

        XCTAssertEqual(decoded.segments.count, 2)
        XCTAssertEqual(decoded.model, "large-v3")
        XCTAssertEqual(decoded.durationSeconds, 120.0)
        XCTAssertEqual(decoded.segments[1].speaker, "Alice")
    }
}
