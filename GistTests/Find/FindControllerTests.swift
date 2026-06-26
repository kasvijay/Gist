import XCTest
@testable import Gist

final class FindControllerTests: XCTestCase {

    private func elements(_ pairs: [(AnyHashable, String)]) -> [FindElement] {
        pairs.map { FindElement(anchor: $0.0, text: $0.1) }
    }

    func testRecomputeBuildsMatchesInDocumentOrder() {
        let find = FindController()
        find.query = "cat"
        find.recompute(elements: elements([
            ("a", "the cat sat"),
            ("b", "no animals"),
            ("c", "cat and cat"),
        ]))
        // a:1 + c:2 = 3 matches, in order a, c#0, c#1
        XCTAssertEqual(find.matchCount, 3)
        XCTAssertEqual(find.currentIndex, 0)
        XCTAssertEqual(find.currentMatch?.anchor, AnyHashable("a"))
        XCTAssertEqual(find.matches[1].anchor, AnyHashable("c"))
        XCTAssertEqual(find.matches[1].occurrence, 0)
        XCTAssertEqual(find.matches[2].occurrence, 1)
    }

    func testEmptyQueryProducesNoMatches() {
        let find = FindController()
        find.query = ""
        find.recompute(elements: elements([("a", "cat")]))
        XCTAssertEqual(find.matchCount, 0)
        XCTAssertFalse(find.hasMatches)
    }

    func testNextWrapsAround() {
        let find = FindController()
        find.query = "x"
        find.recompute(elements: elements([("a", "x"), ("b", "x")]))
        XCTAssertEqual(find.currentIndex, 0)
        find.next()
        XCTAssertEqual(find.currentIndex, 1)
        find.next()
        XCTAssertEqual(find.currentIndex, 0, "Next past the end should wrap to the first match")
    }

    func testPreviousWrapsAround() {
        let find = FindController()
        find.query = "x"
        find.recompute(elements: elements([("a", "x"), ("b", "x")]))
        find.previous()
        XCTAssertEqual(find.currentIndex, 1, "Previous before the start should wrap to the last match")
    }

    func testScrollNonceChangesOnNavigation() {
        let find = FindController()
        find.query = "x"
        find.recompute(elements: elements([("a", "x"), ("b", "x")]))
        let n0 = find.scrollNonce
        find.next()
        XCTAssertNotEqual(find.scrollNonce, n0, "Navigation must bump scrollNonce so the view re-scrolls")
    }

    func testCurrentOccurrenceMatchesOnlyCurrentAnchor() {
        let find = FindController()
        find.query = "x"
        find.recompute(elements: elements([("a", "x x"), ("b", "x")]))
        // current = a#0
        XCTAssertEqual(find.currentOccurrence(forAnchor: AnyHashable("a")), 0)
        XCTAssertNil(find.currentOccurrence(forAnchor: AnyHashable("b")))
        find.next() // a#1
        XCTAssertEqual(find.currentOccurrence(forAnchor: AnyHashable("a")), 1)
        find.next() // b#0
        XCTAssertEqual(find.currentOccurrence(forAnchor: AnyHashable("b")), 0)
        XCTAssertNil(find.currentOccurrence(forAnchor: AnyHashable("a")))
    }

    func testCloseClearsState() {
        let find = FindController()
        find.open()
        find.query = "x"
        find.recompute(elements: elements([("a", "x")]))
        XCTAssertTrue(find.hasMatches)
        find.close()
        XCTAssertFalse(find.isActive)
        XCTAssertEqual(find.query, "")
        XCTAssertFalse(find.hasMatches)
    }

    func testNavigationNoOpWhenNoMatches() {
        let find = FindController()
        find.query = "zzz"
        find.recompute(elements: elements([("a", "x")]))
        find.next()
        find.previous()
        XCTAssertEqual(find.currentIndex, 0)
        XCTAssertNil(find.currentMatch)
    }
}
