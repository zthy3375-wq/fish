import Foundation

struct TreeholeBuddyDraft: Codable, Equatable {
    var location = ""
    var startsAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
    var capacity = 1
    var date: Date? { Self.parse(startsAt) }
    static func parse(_ value: String) -> Date? {
        let reader = ISO8601DateFormatter(); reader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = reader.date(from: value) { return date }
        reader.formatOptions = [.withInternetDateTime]; return reader.date(from: value)
    }
    func valid(at now: Date) -> Bool {
        guard let date else { return false }
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return !place.isEmpty && place.count <= 60 && (1...20).contains(capacity) && date > now && date <= now.addingTimeInterval(90 * 86400)
    }
    var valid: Bool { valid(at: Date()) }
    var payload: [String: Any] { ["location": location, "startsAt": startsAt, "capacity": capacity] }
}
struct TreeholeBuddy: Codable, Equatable {
    let version: Int, location: String, startsAt: String, capacity: Int, count: Int
    let joined: Bool, closed: Bool, expired: Bool
    func ended(at date: Date = Date()) -> Bool { expired || (TreeholeBuddyDraft.parse(startsAt).map { $0 <= date } ?? true) }
    var timeLabel: String {
        guard let date = TreeholeBuddyDraft.parse(startsAt) else { return "时间未知" }
        let writer = DateFormatter(); writer.locale = Locale(identifier: "zh_CN"); writer.timeZone = TimeZone(identifier: "Asia/Shanghai"); writer.dateFormat = "yyyy-MM-dd HH:mm"
        return writer.string(from: date) + " · 北京时间"
    }
}
struct TreeholeBuddyMember: Decodable, Identifiable, Equatable {
    let id: String, nickname: String, joinedAt: String
    let avatar: TreeholeImage?
}
