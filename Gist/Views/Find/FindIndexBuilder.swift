import Foundation

/// Produces the ordered list of searchable elements for each screen. This is the
/// single source of element ordering for Find — `elements(forSummary:)` MUST stay in
/// lockstep with `SummaryView.summaryContent`'s render order, or next/previous won't
/// follow visual order. Both sides reference `SummaryAnchor`.
enum FindIndexBuilder {

    static func elements(forTranscript transcript: Transcript) -> [FindElement] {
        transcript.segments.map { FindElement(anchor: $0.id, text: $0.text) }
    }

    /// Mirrors `SummaryView.summaryContent` exactly:
    /// blockquote(overview) → overview → decisions → action items → key points,
    /// or the legacy fallback when no structured sections exist.
    static func elements(forSummary summary: Summary) -> [FindElement] {
        var elements: [FindElement] = []

        if let overview = summary.overview, !overview.isEmpty {
            elements.append(FindElement(anchor: SummaryAnchor.blockquote, text: overview))
            elements.append(FindElement(anchor: SummaryAnchor.overview, text: overview))
        }
        if let decisions = summary.decisions {
            for (i, item) in decisions.enumerated() {
                elements.append(FindElement(anchor: SummaryAnchor.decision(i), text: item))
            }
        }
        if let actions = summary.actionItems {
            for (i, item) in actions.enumerated() {
                elements.append(FindElement(anchor: SummaryAnchor.action(i), text: item))
            }
        }
        if let keyPoints = summary.keyPoints {
            for point in keyPoints {
                elements.append(FindElement(anchor: SummaryAnchor.keyPoint(point.id), text: point.text))
            }
        }

        // Legacy summaries with no parsed sections — mirror `fallbackContent`.
        let hasStructured = summary.overview != nil || summary.decisions != nil
            || summary.actionItems != nil || summary.keyPoints != nil
        if !hasStructured {
            let overviewText = extractOverview(from: summary.content)
            if !overviewText.isEmpty {
                elements.append(FindElement(anchor: SummaryAnchor.blockquote, text: overviewText))
                elements.append(FindElement(anchor: SummaryAnchor.overview, text: overviewText))
            } else {
                elements.append(FindElement(anchor: SummaryAnchor.fallback, text: summary.content))
            }
        }

        return elements
    }

    /// Mirrors `SummaryView.extractOverview(from:)`.
    private static func extractOverview(from content: String) -> String {
        if let headerRange = content.range(of: "\n## ") {
            return String(content[content.startIndex..<headerRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
