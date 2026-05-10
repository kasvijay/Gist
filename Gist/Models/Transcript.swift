import Foundation
import WhisperKit

/// Gist's transcript format, wrapping WhisperKit segments with session metadata.
struct Transcript: Codable {
    enum Source: String, Codable {
        case recorded   // produced by the in-app recording + transcription pipeline
        case imported   // pasted, dropped, or opened from an external file
    }

    var version: String = "1.0"
    var created: Date
    var durationSeconds: Double
    var model: String
    var speakers: [String: Speaker]?
    var segments: [Segment]
    var source: Source = .recorded
    /// Last time the transcript text was edited by the user. Used to show
    /// the "Transcript edited since summary was generated" banner.
    var editedAt: Date?

    init(version: String = "1.0",
         created: Date,
         durationSeconds: Double,
         model: String,
         speakers: [String: Speaker]? = nil,
         segments: [Segment],
         source: Source = .recorded,
         editedAt: Date? = nil) {
        self.version = version
        self.created = created
        self.durationSeconds = durationSeconds
        self.model = model
        self.speakers = speakers
        self.segments = segments
        self.source = source
        self.editedAt = editedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        self.created = try container.decode(Date.self, forKey: .created)
        self.durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        self.model = try container.decode(String.self, forKey: .model)
        self.speakers = try container.decodeIfPresent([String: Speaker].self, forKey: .speakers)
        self.segments = try container.decode([Segment].self, forKey: .segments)
        self.source = (try? container.decodeIfPresent(Source.self, forKey: .source)) ?? .recorded
        self.editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
    }

    struct Segment: Codable, Identifiable {
        var id: UUID
        var segmentIndex: Int
        var start: Float
        var end: Float
        var text: String
        var confidence: Float
        var language: String?
        var speaker: String?

        init(segmentIndex: Int, start: Float, end: Float, text: String, confidence: Float, language: String? = nil, speaker: String? = nil) {
            self.id = UUID()
            self.segmentIndex = segmentIndex
            self.start = start
            self.end = end
            self.text = text
            self.confidence = confidence
            self.language = language
            self.speaker = speaker
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
            self.segmentIndex = (try? container.decode(Int.self, forKey: .segmentIndex)) ?? 0
            self.start = try container.decode(Float.self, forKey: .start)
            self.end = try container.decode(Float.self, forKey: .end)
            self.text = try container.decode(String.self, forKey: .text)
            self.confidence = try container.decode(Float.self, forKey: .confidence)
            self.language = try container.decodeIfPresent(String.self, forKey: .language)
            self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
        }
    }

    /// Convert WhisperKit segments to Gist format, optionally with speaker labels.
    static func from(
        whisperSegments: [TranscriptionSegment],
        duration: Double,
        model: String,
        language: String?,
        speakerLabels: [String?]? = nil,
        speakers: [String: Speaker]? = nil
    ) -> Transcript {
        let allSegments = whisperSegments.enumerated().map { index, seg in
            Segment(
                segmentIndex: index,
                start: seg.start,
                end: seg.end,
                text: Self.cleanText(seg.text),
                confidence: 1.0 - seg.noSpeechProb,
                language: language,
                speaker: speakerLabels?[safe: index] ?? nil
            )
        }
        // Filter hallucinated/empty segments and re-index
        let segments = allSegments
            .filter { $0.confidence > 0.3 && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { index, seg in
                Segment(segmentIndex: index, start: seg.start, end: seg.end, text: seg.text,
                         confidence: seg.confidence, language: seg.language, speaker: seg.speaker)
            }
        return Transcript(
            created: Date(),
            durationSeconds: duration,
            model: model,
            speakers: speakers,
            segments: segments
        )
    }

    /// Strip WhisperKit special tokens from segment text.
    static func cleanText(_ text: String) -> String {
        var cleaned = text
        let pattern = #"<\|[^|]*\|>"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
