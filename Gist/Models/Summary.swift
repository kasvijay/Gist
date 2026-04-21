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
}
