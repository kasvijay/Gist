import Foundation

/// Parses transcripts pasted, dropped, or opened from external sources.
/// Auto-detects VTT, SRT, plain-text-with-speaker-labels, and falls back to a
/// single-segment plain-text dump. Speaker names and timestamps are preserved
/// verbatim when present.
enum TranscriptImporter {

    static let maxCharacters = 1_000_000

    enum Format: String {
        case vtt
        case srt
        case speakerPlain     // "Speaker: text"
        case paragraph        // single segment, no structure

        var displayName: String {
            switch self {
            case .vtt: return "VTT"
            case .srt: return "SRT"
            case .speakerPlain: return "Plain text with speakers"
            case .paragraph: return "Plain text"
            }
        }
    }

    enum ImportError: LocalizedError {
        case empty
        case tooLong(actual: Int, max: Int)
        case noSegments
        case fileReadFailed(Error)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "The transcript appears to be empty."
            case .tooLong(let actual, let max):
                return "Transcript is \(actual) characters — exceeds the \(max)-character limit."
            case .noSegments:
                return "Couldn't parse this as a transcript. Try a .vtt or .srt file, or paste with \"Speaker: text\" on each line."
            case .fileReadFailed(let e):
                return "Couldn't read file: \(e.localizedDescription)"
            }
        }
    }

    struct PreviewInfo {
        let format: Format
        let segmentCount: Int
        let speakerCount: Int
        let firstLine: String
        let durationSeconds: Double?
    }

    // MARK: - Entry points

    /// Parse a string and return a complete `Transcript` ready to persist.
    static func parse(_ raw: String) -> Result<Transcript, ImportError> {
        let cleaned = sanitize(raw)
        guard !cleaned.isEmpty else { return .failure(.empty) }
        guard cleaned.count <= maxCharacters else {
            return .failure(.tooLong(actual: cleaned.count, max: maxCharacters))
        }

        let format = detectFormat(in: cleaned)
        let segments: [Transcript.Segment]
        switch format {
        case .vtt:
            segments = parseVTT(cleaned)
        case .srt:
            segments = parseSRT(cleaned)
        case .speakerPlain:
            segments = parseSpeakerPlain(cleaned)
        case .paragraph:
            segments = parseParagraph(cleaned)
        }

        guard !segments.isEmpty else { return .failure(.noSegments) }

        let duration = Double(segments.last?.end ?? 0)
        let speakers = uniqueSpeakers(from: segments)
        let speakerMap: [String: Speaker]? = speakers.isEmpty ? nil : Dictionary(
            uniqueKeysWithValues: speakers.map { name in
                (name, Speaker(id: name, source: nil, label: name))
            }
        )

        let transcript = Transcript(
            created: Date(),
            durationSeconds: duration,
            model: "imported",
            speakers: speakerMap,
            segments: segments,
            source: .imported,
            editedAt: nil
        )
        return .success(transcript)
    }

    /// Read a file URL into a String, handling UTF-8/UTF-16 BOMs.
    static func readFile(at url: URL) -> Result<String, ImportError> {
        do {
            let data = try Data(contentsOf: url)
            if let text = decode(data) {
                return .success(text)
            }
            return .failure(.fileReadFailed(NSError(domain: "TranscriptImporter", code: 1,
                                                    userInfo: [NSLocalizedDescriptionKey: "Could not decode file as UTF-8 or UTF-16"])))
        } catch {
            return .failure(.fileReadFailed(error))
        }
    }

    /// Lightweight preview for the import sheet — runs the same detection but
    /// without constructing the full Transcript.
    static func preview(_ raw: String) -> PreviewInfo? {
        let cleaned = sanitize(raw)
        guard !cleaned.isEmpty else { return nil }
        let format = detectFormat(in: cleaned)
        let segments: [Transcript.Segment]
        switch format {
        case .vtt:           segments = parseVTT(cleaned)
        case .srt:           segments = parseSRT(cleaned)
        case .speakerPlain:  segments = parseSpeakerPlain(cleaned)
        case .paragraph:     segments = parseParagraph(cleaned)
        }
        guard !segments.isEmpty else { return nil }
        let speakers = uniqueSpeakers(from: segments)
        let firstLine = segments.first?.text.prefix(160).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = Double(segments.last?.end ?? 0)
        return PreviewInfo(
            format: format,
            segmentCount: segments.count,
            speakerCount: speakers.count,
            firstLine: String(firstLine),
            durationSeconds: duration > 0 ? duration : nil
        )
    }

    // MARK: - Sanitization

    private static func decode(_ data: Data) -> String? {
        // UTF-8 BOM
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        // UTF-16 LE BOM
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        // UTF-16 BE BOM
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func sanitize(_ raw: String) -> String {
        var s = raw
        // Strip a UTF-8 BOM if it slipped through.
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        // Normalize Windows / Mac line endings.
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\r", with: "\n")
        // Strip lightweight HTML tags that sometimes appear in pasted content.
        // (VTT's <v Speaker> tags are handled later before this is called for VTT.)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Format detection

    private static func detectFormat(in text: String) -> Format {
        // VTT is unambiguous via its header.
        if text.hasPrefix("WEBVTT") || text.range(of: "(?m)^WEBVTT\\b", options: .regularExpression) != nil {
            return .vtt
        }
        // SRT: numbered cues followed by `00:00:23,456 --> 00:00:25,789`.
        if text.range(of: #"\n?\d+\n\d{2}:\d{2}:\d{2}[,\.]\d{3}\s+-->\s+\d{2}:\d{2}:\d{2}[,\.]\d{3}"#,
                      options: .regularExpression) != nil {
            return .srt
        }
        // Speaker-labelled plain text: scoring threshold of ~30% of non-empty lines
        // matching `Name: ` to avoid false positives on prose.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return .paragraph }
        let labeled = lines.filter { line in
            line.range(of: #"^[A-Z][A-Za-z0-9 .'\-_]{0,40}:"#, options: .regularExpression) != nil
        }.count
        if Double(labeled) / Double(lines.count) >= 0.3 { return .speakerPlain }

        return .paragraph
    }

    // MARK: - VTT

    private static func parseVTT(_ text: String) -> [Transcript.Segment] {
        // Remove the WEBVTT header line and any NOTE blocks.
        let body = text.replacingOccurrences(of: #"^WEBVTT.*?(?=\n\d|\n\d{2}:|\Z)"#,
                                              with: "", options: .regularExpression)
        // Cue regex: optional cue id line, timing line, content lines until blank.
        let cuePattern = #"(?ms)(?:^([^\n]+)\n)?(\d{1,2}:)?(\d{1,2}):(\d{1,2}\.\d{1,3})\s+-->\s+(\d{1,2}:)?(\d{1,2}):(\d{1,2}\.\d{1,3})[^\n]*\n((?:.+\n?)+?)(?=\n|\Z)"#
        return parseCues(body, pattern: cuePattern, secondaryFractionSeparator: ".")
    }

    // MARK: - SRT

    private static func parseSRT(_ text: String) -> [Transcript.Segment] {
        let cuePattern = #"(?ms)\n?\d+\n(\d{1,2}:)?(\d{1,2}):(\d{1,2})[,\.](\d{1,3})\s+-->\s+(\d{1,2}:)?(\d{1,2}):(\d{1,2})[,\.](\d{1,3})[^\n]*\n((?:.+\n?)+?)(?=\n\d+\n\d|\Z)"#
        guard let regex = try? NSRegularExpression(pattern: cuePattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var segments: [Transcript.Segment] = []
        for (idx, match) in matches.enumerated() {
            let startH = intIn(text, match: match, group: 1) ?? 0
            let startM = intIn(text, match: match, group: 2) ?? 0
            let startS = intIn(text, match: match, group: 3) ?? 0
            let startMs = intIn(text, match: match, group: 4) ?? 0
            let endH = intIn(text, match: match, group: 5) ?? 0
            let endM = intIn(text, match: match, group: 6) ?? 0
            let endS = intIn(text, match: match, group: 7) ?? 0
            let endMs = intIn(text, match: match, group: 8) ?? 0
            let raw = stringIn(text, match: match, group: 9) ?? ""

            let start = Float(startH * 3600 + startM * 60 + startS) + Float(startMs) / 1000
            let end = Float(endH * 3600 + endM * 60 + endS) + Float(endMs) / 1000

            let (speaker, body) = splitSpeakerPrefix(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            if body.isEmpty { continue }
            segments.append(Transcript.Segment(
                segmentIndex: idx, start: start, end: end,
                text: body, confidence: 1.0, speaker: speaker
            ))
        }
        return segments
    }

    /// Shared cue-walking for VTT (same group layout as parseSRT but using `.` as the
    /// fractional separator). Kept simple: parse via NSRegularExpression and iterate.
    private static func parseCues(_ text: String, pattern: String, secondaryFractionSeparator: String) -> [Transcript.Segment] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var segments: [Transcript.Segment] = []
        for (idx, match) in matches.enumerated() {
            // VTT pattern groups: (cueId)? (sH:)?(sM:)(sS.fff) (eH:)?(eM:)(eS.fff) (text)
            let startHStr = stringIn(text, match: match, group: 2) ?? ""
            let startH = Int(startHStr.replacingOccurrences(of: ":", with: "")) ?? 0
            let startM = intIn(text, match: match, group: 3) ?? 0
            let startSStr = stringIn(text, match: match, group: 4) ?? "0"
            let endHStr = stringIn(text, match: match, group: 5) ?? ""
            let endH = Int(endHStr.replacingOccurrences(of: ":", with: "")) ?? 0
            let endM = intIn(text, match: match, group: 6) ?? 0
            let endSStr = stringIn(text, match: match, group: 7) ?? "0"
            let raw = stringIn(text, match: match, group: 8) ?? ""

            let start = Float(startH * 3600 + startM * 60) + (Float(startSStr) ?? 0)
            let end = Float(endH * 3600 + endM * 60) + (Float(endSStr) ?? 0)

            let (speaker, body) = extractVTTSpeaker(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            if body.isEmpty { continue }
            segments.append(Transcript.Segment(
                segmentIndex: idx, start: start, end: end,
                text: body, confidence: 1.0, speaker: speaker
            ))
        }
        return segments
    }

    // MARK: - Speaker plain

    private static func parseSpeakerPlain(_ text: String) -> [Transcript.Segment] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var segments: [Transcript.Segment] = []
        var index = 0
        for line in lines {
            let (speaker, body) = splitSpeakerPrefix(line.trimmingCharacters(in: .whitespacesAndNewlines))
            guard speaker != nil, !body.isEmpty else { continue }
            segments.append(Transcript.Segment(
                segmentIndex: index, start: 0, end: 0,
                text: body, confidence: 1.0, speaker: speaker
            ))
            index += 1
        }
        return segments
    }

    // MARK: - Plain paragraph fallback

    private static func parseParagraph(_ text: String) -> [Transcript.Segment] {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }
        return [
            Transcript.Segment(
                segmentIndex: 0, start: 0, end: 0,
                text: body, confidence: 1.0, speaker: nil
            )
        ]
    }

    // MARK: - Helpers

    private static func splitSpeakerPrefix(_ line: String) -> (speaker: String?, text: String) {
        // `Name: text` — only treat as speaker if the prefix looks plausible
        // (capitalized, < 40 chars, alphanumeric/space/punctuation only).
        guard let colonIndex = line.firstIndex(of: ":") else { return (nil, line) }
        let prefix = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let suffix = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, !suffix.isEmpty,
              prefix.count <= 40,
              prefix.range(of: #"^[A-Z][A-Za-z0-9 .'\-_]+$"#, options: .regularExpression) != nil
        else {
            return (nil, line)
        }
        return (prefix, suffix)
    }

    /// VTT supports `<v Speaker>text</v>` voice tags. Extract speaker from those
    /// or fall back to the colon-prefix heuristic.
    private static func extractVTTSpeaker(_ raw: String) -> (speaker: String?, text: String) {
        let voicePattern = #"^<v\s+([^>]+)>(.*?)(?:</v>)?$"#
        if let regex = try? NSRegularExpression(pattern: voicePattern, options: .dotMatchesLineSeparators),
           let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let speakerRange = Range(match.range(at: 1), in: raw),
           let textRange = Range(match.range(at: 2), in: raw) {
            return (String(raw[speakerRange]).trimmingCharacters(in: .whitespaces),
                    String(raw[textRange]).trimmingCharacters(in: .whitespaces))
        }
        return splitSpeakerPrefix(raw)
    }

    private static func uniqueSpeakers(from segments: [Transcript.Segment]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for s in segments {
            if let speaker = s.speaker, !seen.contains(speaker) {
                seen.insert(speaker)
                ordered.append(speaker)
            }
        }
        return ordered
    }

    private static func intIn(_ text: String, match: NSTextCheckingResult, group: Int) -> Int? {
        let r = match.range(at: group)
        guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
        return Int(text[swiftRange])
    }

    private static func stringIn(_ text: String, match: NSTextCheckingResult, group: Int) -> String? {
        let r = match.range(at: group)
        guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
