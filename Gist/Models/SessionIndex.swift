import Foundation

struct SessionIndex: Codable {
    var version: String = "1.0"
    var sessions: [SessionEntry]

    struct SessionEntry: Codable, Identifiable {
        var id: String
        var name: String
        var startedAt: Date
        var endedAt: Date?
        var durationSeconds: Double?
        var model: String?
        var path: String
        var hasAudio: Bool
        var hasTranscript: Bool
        var segmentCount: Int?
        var languagesDetected: [String]?
    }

    init(sessions: [SessionEntry]) {
        self.sessions = sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        self.sessions = try container.decode([SessionEntry].self, forKey: .sessions)
    }
}
