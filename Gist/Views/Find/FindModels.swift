import Foundation

/// One searchable text element in document order — a transcript segment, or a
/// summary block. `anchor` doubles as the ScrollViewReader scroll target and the
/// element's identity, so the order produced by `FindIndexBuilder` and the anchors
/// the views attach via `.id(...)` can never drift apart.
struct FindElement {
    let anchor: AnyHashable
    let text: String
}

/// A single match occurrence. Identity is `(anchor, occurrence)`. Several hits in
/// one element produce several matches with the same anchor and increasing
/// `occurrence`. No `String.Index` is stored — ranges are recomputed by
/// `FindHighlighter` from the live text + query, which keeps this value stable.
struct FindMatch: Identifiable, Equatable {
    let id = UUID()
    let anchor: AnyHashable
    let occurrence: Int

    static func == (lhs: FindMatch, rhs: FindMatch) -> Bool {
        lhs.anchor == rhs.anchor && lhs.occurrence == rhs.occurrence
    }
}

/// Stable scroll/identity anchors for the Summary screen. Used for BOTH the
/// `.id(...)` values attached in `SummaryView` and the `FindElement.anchor`s emitted
/// by `FindIndexBuilder.elements(forSummary:)` — keep the two in lockstep.
enum SummaryAnchor: Hashable {
    case blockquote
    case overview
    case decision(Int)
    case action(Int)
    case keyPoint(UUID)
    case fallback
}
