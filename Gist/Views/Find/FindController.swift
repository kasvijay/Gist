import SwiftUI

/// Drives the in-screen Find experience for the session detail view. One instance
/// is owned by `SessionDetailView` and shared with both `TranscriptView` and
/// `SummaryView`, so the query and match navigation survive tab switches.
/// Used exclusively on the main thread (SwiftUI event handlers + a main-queue
/// debounce), so it stays a plain ObservableObject without actor isolation.
final class FindController: ObservableObject {
    /// Whether the find bar is visible.
    @Published var isActive: Bool = false
    /// Raw search text.
    @Published var query: String = ""

    @Published private(set) var matches: [FindMatch] = []
    @Published private(set) var currentIndex: Int = 0
    /// Bumped whenever a scroll-to-current should fire. Views observe this rather
    /// than `currentMatch` so that pressing Next on the only/last match (which
    /// leaves the match unchanged) still re-triggers a scroll.
    @Published private(set) var scrollNonce: Int = 0

    var matchCount: Int { matches.count }
    var hasMatches: Bool { !matches.isEmpty }

    var currentMatch: FindMatch? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    /// Recompute matches for the active screen's elements (document order). Resets to
    /// the first match and requests a scroll. Call when query, tab, or content change.
    func recompute(elements: [FindElement]) {
        guard !query.isEmpty else {
            matches = []
            currentIndex = 0
            return
        }
        var result: [FindMatch] = []
        for element in elements {
            let count = FindHighlighter.occurrenceCount(of: query, in: element.text)
            for occ in 0..<count {
                result.append(FindMatch(anchor: element.anchor, occurrence: occ))
            }
        }
        matches = result
        currentIndex = 0
        scrollNonce &+= 1
    }

    func next() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        scrollNonce &+= 1
    }

    func previous() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        scrollNonce &+= 1
    }

    /// Which occurrence within `anchor`'s text is the *current* match (drives the
    /// strong tint), or nil if the current match isn't in this element.
    func currentOccurrence(forAnchor anchor: AnyHashable) -> Int? {
        guard let match = currentMatch, match.anchor == anchor else { return nil }
        return match.occurrence
    }

    func open() {
        isActive = true
    }

    func close() {
        isActive = false
        query = ""
        matches = []
        currentIndex = 0
    }
}
