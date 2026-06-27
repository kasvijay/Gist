import Foundation

/// Shared prompt and parsing logic used by all summarization providers.
enum SummaryPromptBuilder {

    static let systemPrompt = """
        You are a meeting summarizer. Given a transcript, produce a concise, well-structured summary. \
        Base everything strictly on the transcript — never invent decisions, names, people, numbers, \
        dates, or topics that are not explicitly present. If the transcript is empty or too short to \
        summarize, say so briefly instead of fabricating content.
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
        Cover every important point — do not limit the number of bullets. \
        At the very end of each bullet, append the timestamp in the transcript where that point started, \
        in the format `[mm:ss]` (or `[h:mm:ss]` if past one hour). \
        Example: `- The team agreed on the new release schedule. [12:34]`

        Use "- " for each bullet. Do not number the sections. Do not add any text outside these sections.
        """

    static func buildUserPrompt(transcript: Transcript) -> String {
        let transcriptText = formatTranscript(transcript)
        return summaryPromptTemplate + "\n\n" + transcriptText
    }

    /// Format the transcript with a leading `[mm:ss]` timestamp on each segment so the
    /// LLM can copy timestamps into the Key Discussion Points section.
    static func formatTranscript(_ transcript: Transcript) -> String {
        transcript.segments.map { segment in
            let speaker = segment.speaker ?? "Unknown"
            let stamp = formatTimestamp(seconds: segment.start)
            return "[\(stamp)] [\(speaker)] \(segment.text)"
        }.joined(separator: "\n")
    }

    private static func formatTimestamp(seconds: Float) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Parsing

    static func parseSummary(output: String, model: String, transcript: Transcript? = nil) -> Summary {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let overview = extractParagraph(from: trimmed, header: "## Overview")
        let decisions = extractSection(from: trimmed, header: "## Decisions")
        let actionItems = extractSection(from: trimmed, header: "## Action Items")
        let rawKeyPoints = extractSection(from: trimmed, header: "## Key Discussion Points") ?? []

        let resolved = KeyPointTimestampResolver.resolve(
            rawBullets: rawKeyPoints,
            transcript: transcript
        )

        return Summary(
            created: Date(),
            model: model,
            content: trimmed,
            overview: overview,
            decisions: decisions,
            actionItems: actionItems,
            keyPoints: resolved.isEmpty ? nil : resolved
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

// MARK: - Timestamp resolver

/// Extracts trailing `[mm:ss]` timestamps from Key Discussion Point bullets,
/// validates them against the transcript using token-overlap, and falls back
/// to a global similarity search if the LLM's timestamp doesn't match nearby
/// transcript content. Final timestamps are snapped to the closest segment
/// boundary so playback starts at a turn-of-speech.
enum KeyPointTimestampResolver {

    enum Strictness: String {
        case strict
        case balanced
        case lenient

        /// Minimum Jaccard token overlap to consider a region a valid match.
        var threshold: Double {
            switch self {
            case .strict:   return 0.30
            case .balanced: return 0.18
            case .lenient:  return 0.10
            }
        }

        /// Whether to run a global similarity search when the LLM's timestamp fails.
        var allowGlobalFallback: Bool {
            switch self {
            case .strict:   return false
            case .balanced, .lenient: return true
            }
        }

        static var current: Strictness {
            let raw = UserDefaults.standard.string(forKey: "summaryTimestampStrictness") ?? "balanced"
            return Strictness(rawValue: raw) ?? .balanced
        }
    }

    static func resolve(rawBullets: [String], transcript: Transcript?) -> [TimedKeyPoint] {
        let strictness = Strictness.current
        guard let transcript, !transcript.segments.isEmpty else {
            return rawBullets.map { stripTrailingTimestamp(from: $0).text }
                .map { TimedKeyPoint(text: $0, startSeconds: nil) }
        }

        return rawBullets.map { bullet in
            let parsed = stripTrailingTimestamp(from: bullet)
            let resolvedSeconds = resolveTimestamp(
                pointText: parsed.text,
                llmGuess: parsed.seconds,
                transcript: transcript,
                strictness: strictness
            )
            return TimedKeyPoint(text: parsed.text, startSeconds: resolvedSeconds)
        }
    }

    /// Strip a trailing `[mm:ss]` or `[h:mm:ss]` from the bullet text.
    /// Returns the cleaned text and the parsed seconds (if any).
    static func stripTrailingTimestamp(from bullet: String) -> (text: String, seconds: Float?) {
        // Match optional whitespace, `[`, optional `h:`, `mm:ss`, `]`, optional trailing punctuation.
        let pattern = #"\s*\[(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\]\s*[.!?]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (bullet.trimmingCharacters(in: .whitespaces), nil)
        }
        let range = NSRange(bullet.startIndex..., in: bullet)
        guard let match = regex.firstMatch(in: bullet, range: range) else {
            return (bullet.trimmingCharacters(in: .whitespaces), nil)
        }

        func intAt(_ index: Int) -> Int? {
            let r = match.range(at: index)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: bullet) else { return nil }
            return Int(bullet[swiftRange])
        }
        let h = intAt(1) ?? 0
        let m = intAt(2) ?? 0
        let s = intAt(3) ?? 0
        let totalSeconds = Float(h * 3600 + m * 60 + s)

        let textRange = bullet.startIndex..<bullet.index(bullet.startIndex, offsetBy: match.range.location)
        let cleaned = String(bullet[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned, totalSeconds)
    }

    /// Try the LLM-emitted timestamp first; if validation fails, fall back to
    /// global search; if that also fails, return nil.
    private static func resolveTimestamp(pointText: String,
                                         llmGuess: Float?,
                                         transcript: Transcript,
                                         strictness: Strictness) -> Float? {
        let pointTokens = tokenize(pointText)
        guard !pointTokens.isEmpty else { return nil }

        // Step 1: try the LLM's guess against ±20s of context around it.
        if let guess = llmGuess {
            let context = contextTokens(transcript: transcript, around: guess, window: 20)
            let score = jaccard(pointTokens, context)
            if score >= strictness.threshold {
                return snapToSegment(transcript: transcript, target: guess)
            }
        }

        // Step 2: global search across every segment.
        guard strictness.allowGlobalFallback else { return nil }
        var best: (segmentStart: Float, score: Double) = (0, 0)
        for segment in transcript.segments {
            let segmentText = transcript.segments
                .filter { abs($0.start - segment.start) <= 15 }
                .map(\.text)
                .joined(separator: " ")
            let score = jaccard(pointTokens, tokenize(segmentText))
            if score > best.score {
                best = (segment.start, score)
            }
        }
        return best.score >= strictness.threshold ? best.segmentStart : nil
    }

    private static func contextTokens(transcript: Transcript, around seconds: Float, window: Float) -> Set<String> {
        let lo = seconds - window
        let hi = seconds + window
        let text = transcript.segments
            .filter { $0.start >= lo && $0.start <= hi }
            .map(\.text)
            .joined(separator: " ")
        return tokenize(text)
    }

    private static func snapToSegment(transcript: Transcript, target: Float) -> Float {
        // Find the segment whose start is the largest value ≤ target. If none,
        // use the first segment.
        var best: Float? = nil
        for segment in transcript.segments {
            if segment.start <= target {
                best = segment.start
            } else {
                break
            }
        }
        return best ?? transcript.segments.first?.start ?? 0
    }

    // MARK: Tokenization

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "had", "has", "have", "he", "her", "his", "i", "if", "in", "into", "is",
        "it", "its", "of", "on", "or", "she", "so", "than", "that", "the", "their",
        "them", "they", "this", "to", "was", "we", "were", "what", "when", "which",
        "who", "will", "with", "would", "you", "your", "our", "us", "do", "does",
        "did", "not", "no", "yes", "can", "could", "should", "about"
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: " "))
        let scrubbed = String(lowered.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return Set(
            scrubbed.split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}
