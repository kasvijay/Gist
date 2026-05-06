import Foundation

/// Shared prompt and parsing logic used by all summarization providers.
enum SummaryPromptBuilder {

    static let systemPrompt = """
        You are a meeting summarizer. Given a transcript, produce a concise, well-structured summary.
        """

    static let summaryPromptTemplate = """
        Summarize this meeting transcript using exactly these four sections in this order:

        ## Overview
        A brief paragraph of what was discussed.

        ## Decisions
        Bullet list of decisions made during the meeting. Omit this section entirely if there are no decisions.

        ## Action Items
        Bullet list of action items with the responsible person if mentioned. Omit this section entirely if there are none.

        ## Key Discussion Points
        Bullet list of all key discussion points, topics, outcomes, and notable exchanges. \
        Cover every important point — do not limit the number of bullets.

        Use "- " for each bullet. Do not number the sections. Do not add any text outside these sections.
        """

    static func buildUserPrompt(transcript: Transcript) -> String {
        let transcriptText = formatTranscript(transcript)
        return summaryPromptTemplate + "\n\n" + transcriptText
    }

    static func formatTranscript(_ transcript: Transcript) -> String {
        transcript.segments.map { segment in
            let speaker = segment.speaker ?? "Unknown"
            return "[\(speaker)] \(segment.text)"
        }.joined(separator: "\n")
    }

    // MARK: - Parsing

    static func parseSummary(output: String, model: String) -> Summary {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let overview = extractParagraph(from: trimmed, header: "## Overview")
        let decisions = extractSection(from: trimmed, header: "## Decisions")
        let actionItems = extractSection(from: trimmed, header: "## Action Items")
        let keyPoints = extractSection(from: trimmed, header: "## Key Discussion Points")

        return Summary(
            created: Date(),
            model: model,
            content: trimmed,
            overview: overview,
            decisions: decisions,
            actionItems: actionItems,
            keyPoints: keyPoints
        )
    }

    private static func extractParagraph(from text: String, header: String) -> String? {
        guard let headerRange = text.range(of: header) else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        let nextHeader = afterHeader.range(of: "\n## ")
        let sectionEnd = nextHeader?.lowerBound ?? afterHeader.endIndex
        let section = String(afterHeader[..<sectionEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? nil : section
    }

    private static func extractSection(from text: String, header: String) -> [String]? {
        guard let headerRange = text.range(of: header) else { return nil }
        let afterHeader = text[headerRange.upperBound...]
        let nextHeader = afterHeader.range(of: "\n## ")
        let sectionEnd = nextHeader?.lowerBound ?? afterHeader.endIndex
        let section = afterHeader[..<sectionEnd]

        let items = section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }
            .map { String($0.dropFirst(2)) }

        return items.isEmpty ? nil : items
    }
}
