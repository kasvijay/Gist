import SwiftUI

/// Builds highlighted `AttributedString`s for the Find feature and is the single
/// source of match ranges — `FindController` counts occurrences via `matchRanges`
/// so the count, the highlight, and the current-match index always agree.
enum FindHighlighter {

    /// All non-overlapping, case- and diacritic-insensitive ranges of `query` in
    /// `source`, in order.
    static func matchRanges(of query: String, in source: String) -> [Range<String.Index>] {
        guard !query.isEmpty, !source.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = source.startIndex
        while searchStart < source.endIndex,
              let r = source.range(
                  of: query,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<source.endIndex,
                  locale: .current
              ) {
            ranges.append(r)
            // Advance past this match; guard against an empty match never advancing.
            searchStart = r.upperBound > r.lowerBound ? r.upperBound : source.index(after: r.lowerBound)
        }
        return ranges
    }

    static func occurrenceCount(of query: String, in source: String) -> Int {
        matchRanges(of: query, in: source).count
    }

    /// `source` with every match tinted, and the match at `currentOccurrence` (if
    /// any) tinted more strongly. Passing `currentOccurrence == nil` means this
    /// element holds no current match, so all hits get the base tint. The result is
    /// plain text with attributes, so `Text(_:)` keeps `.textSelection(.enabled)`.
    static func attributed(_ source: String, query: String, currentOccurrence: Int?) -> AttributedString {
        var attr = AttributedString(source)
        let ranges = matchRanges(of: query, in: source)
        guard !ranges.isEmpty else { return attr }

        let chars = attr.characters
        for (i, r) in ranges.enumerated() {
            // Plain-text AttributedString is 1:1 with the source String by character,
            // so map via character offsets — never reuse a String.Index here.
            let lo = source.distance(from: source.startIndex, to: r.lowerBound)
            let len = source.distance(from: r.lowerBound, to: r.upperBound)
            let start = chars.index(chars.startIndex, offsetBy: lo)
            let end = chars.index(start, offsetBy: len)

            let isCurrent = (i == currentOccurrence)
            attr[start..<end].backgroundColor = isCurrent ? Color.orange.opacity(0.9) : Color.yellow.opacity(0.35)
            if isCurrent {
                attr[start..<end].foregroundColor = Color.black
            }
        }
        return attr
    }
}
