import Foundation

struct Session: Codable, Identifiable {
    var version: String = "1.0"
    var id: String // e.g. "2026-04-04_1400_untitled"
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    var status: Status
    var devices: Devices?

    enum Status: String, Codable {
        case recording
        case complete
        case recovered
    }

    struct Devices: Codable {
        var microphone: String?
        var systemAudio: String?
    }

    var folderName: String { id }

    static func makeID(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }

    init(id: String, name: String, startedAt: Date, endedAt: Date? = nil, durationSeconds: Double? = nil, status: Status, devices: Devices? = nil) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.devices = devices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(String.self, forKey: .version)) ?? "1.0"
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        self.durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        self.status = try container.decode(Status.self, forKey: .status)
        self.devices = try container.decodeIfPresent(Devices.self, forKey: .devices)
    }
}
