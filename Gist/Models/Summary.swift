import Foundation

struct Summary: Codable {
    var version: String = "1.0"
    var created: Date
    var model: String
    var content: String
    var overview: String?
    var decisions: [String]?
    var actionItems: [String]?
    var keyPoints: [String]?

    init(created: Date, model: String, content: String, overview: String? = nil, decisions: [String]? = nil, actionItems: [String]? = nil, keyPoints: [String]? = nil) {
        self.created = created
        self.model = model
        self.content = content
        self.overview = overview
        self.decisions = decisions
        self.actionItems = actionItems
        self.keyPoints = keyPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        self.created = try container.decode(Date.self, forKey: .created)
        self.model = try container.decode(String.self, forKey: .model)
        self.content = try container.decode(String.self, forKey: .content)
        self.overview = try container.decodeIfPresent(String.self, forKey: .overview)
        self.decisions = try container.decodeIfPresent([String].self, forKey: .decisions)
        self.actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems)
        self.keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints)
    }
}
