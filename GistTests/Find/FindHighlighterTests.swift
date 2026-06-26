import XCTest
import SwiftUI
@testable import Gist

final class FindHighlighterTests: XCTestCase {

    // MARK: - matchRanges

    func testEmptyQueryReturnsNoRanges() {
        XCTAssertTrue(FindHighlighter.matchRanges(of: "", in: "hello world").isEmpty)
    }

    func testEmptySourceReturnsNoRanges() {
        XCTAssertTrue(FindHighlighter.matchRanges(of: "x", in: "").isEmpty)
    }

    func testSingleMatch() {
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "world", in: "hello world"), 1)
    }

    func testMultipleNonOverlappingMatches() {
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "ab", in: "ab_ab_ab"), 3)
    }

    func testOverlappingPatternCountsNonOverlapping() {
        // "aa" in "aaaa" → 2 non-overlapping matches (standard Find semantics)
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "aa", in: "aaaa"), 2)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "ceo", in: "The CEO and the ceo"), 2)
    }

    func testDiacriticInsensitive() {
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "cafe", in: "We met at the café"), 1)
    }

    func testNoMatch() {
        XCTAssertEqual(FindHighlighter.occurrenceCount(of: "zzz", in: "hello world"), 0)
    }

    // MARK: - attributed

    func testAttributedPreservesCharacters() {
        let source = "The quick brown café"
        let attr = FindHighlighter.attributed(source, query: "quick", currentOccurrence: 0)
        XCTAssertEqual(String(attr.characters), source, "Highlighting must not alter the underlying text")
    }

    func testAttributedEmptyQueryIsUnchangedText() {
        let source = "nothing to highlight"
        let attr = FindHighlighter.attributed(source, query: "", currentOccurrence: nil)
        XCTAssertEqual(String(attr.characters), source)
    }

    func testAttributedWithCurrentOccurrenceDoesNotCrash() {
        let source = "match match match"
        // Exercises the strong-tint branch and out-of-range currentOccurrence.
        _ = FindHighlighter.attributed(source, query: "match", currentOccurrence: 1)
        _ = FindHighlighter.attributed(source, query: "match", currentOccurrence: 99)
        _ = FindHighlighter.attributed(source, query: "match", currentOccurrence: nil)
    }

    func testAttributedHandlesMatchAtStartAndEnd() {
        let source = "aa middle aa"
        let attr = FindHighlighter.attributed(source, query: "aa", currentOccurrence: 0)
        XCTAssertEqual(String(attr.characters), source)
    }
}
