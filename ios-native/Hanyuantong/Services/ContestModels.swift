import Foundation

struct NativeContest: Codable, Identifiable {
    let id: String
    var title: String
    var type: String
    var edition: String
    var description: String
    var rules: String
    var state: String
    var paused: Bool
    var startsAt: String
    var submissionEnds: String
    var votingStarts: String
    var votingEnds: String
    var awardAt: String
    var formats: [String]
    var maxEntries: Int
    var votesPerUser: Int
    var minEntries: Int
    var minAccountHours: Int
    var excellence: Int
    var reviewRisk: Bool? = nil
    var version: Int? = nil
    var autoPublish: Bool
    let entryCount: Int
    let participantCount: Int
    var coverPostId: String?
    let cover: TreeholeImage?
    static let labels = ["draft":"草稿", "upcoming":"未开始", "submitting":"投稿中", "waiting":"等待投票", "voting":"投票中", "reviewing":"结果审核中", "ended":"已结束", "cancelled":"已取消"]
    static func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value)
    }
    func phase(at now: Date) -> String {
        if ["draft", "ended", "cancelled"].contains(state) { return state }
        guard let start = Self.date(startsAt), let submission = Self.date(submissionEnds), let voting = Self.date(votingStarts), let end = Self.date(votingEnds) else { return state }
        if now < start { return "upcoming" }
        if now < submission { return "submitting" }
        if now < voting { return "waiting" }
        return now < end ? "voting" : "reviewing"
    }
    func remaining(now: Date) -> String {
        let end: String
        switch phase(at: now) {
        case "upcoming": end = startsAt
        case "submitting": end = submissionEnds
        case "waiting": end = votingStarts
        case "voting": end = votingEnds
        case "reviewing": end = awardAt
        default: return ""
        }
        guard let date = Self.date(end) else { return "" }
        let minutes = Int(ceil(date.timeIntervalSince(now) / 60))
        if minutes <= 0 { return "阶段已到期，点击刷新" }
        return minutes >= 1440 ? "剩余 \(minutes / 1440) 天 \(minutes % 1440 / 60) 小时" : "剩余 \(minutes / 60) 小时 \(minutes % 60) 分"
    }
    func label(at now: Date) -> String { paused ? "已暂停" : Self.labels[phase(at: now)] ?? state }
    var label: String { label(at: Date()) }
    var payload: [String: Any] {
        ["contestId":id, "title":title, "type":type, "edition":edition, "description":description, "rules":rules,
         "startsAt":startsAt, "submissionEnds":submissionEnds, "votingStarts":votingStarts, "votingEnds":votingEnds, "awardAt":awardAt,
         "formats":formats, "maxEntries":maxEntries, "votesPerUser":votesPerUser, "minEntries":minEntries, "minAccountHours":minAccountHours,
         "excellence":excellence, "autoPublish":autoPublish, "reviewRisk":reviewRisk ?? true, "expectedVersion":version as Any? ?? NSNull(), "coverPostId":coverPostId as Any? ?? NSNull()]
    }
    static func draft() -> NativeContest {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, weekday: 2), matchingPolicy: .nextTime)!
        let formatter = ISO8601DateFormatter()
        func time(_ days: Double) -> String { formatter.string(from: start.addingTimeInterval(days * 86400)) }
        return NativeContest(id: UUID().uuidString, title: "", type: "摄影赛", edition: "", description: "", rules: "原创投稿，尊重隐私。同票并列，下一名次连续排列。", state: "draft", paused: false, startsAt: time(0), submissionEnds: time(5), votingStarts: time(5), votingEnds: time(6), awardAt: time(6.5), formats: ["text", "image", "mixed"], maxEntries: 1, votesPerUser: 3, minEntries: 5, minAccountHours: 0, excellence: 3, autoPublish: false, entryCount: 0, participantCount: 0, cover: nil)
    }
}
struct NativeContestEntry: Codable, Identifiable {
    let id: String, contestId: String, memberId: String, title: String, body: String, author: String, status: String
    let postId: String?
    let linked: Bool?
    let mine: Bool
    var voted: Bool
    let version: Int?
    let votes: Int?
    let images: [TreeholeImage]
    let awards: [NativeContestAward]
}
struct NativeContestAward: Codable, Identifiable {
    let id: String, kind: String
    let rank: Int?
    let title: String?
    let contest_id: String?
    let awarded_at: String?
    let revoked_at: String?
    static let labels = ["champion":"冠军", "silver":"亚军", "bronze":"季军", "excellent":"优秀作品", "participation":"参赛纪念"]
    var label: String { Self.labels[kind] ?? kind }
}
struct NativeContestStats: Decodable { let participations: Int, champions: Int, podiums: Int }
struct NativeContestTheme: Decodable, Identifiable { let id: String, title: String, status: String; let votes: Int; let voted: Bool }
struct NativeContestLeader: Decodable, Identifiable { let id: String, nickname: String; let score: Int }
struct NativeContestVote: Decodable, Identifiable { let id: String, entry_id: String; let risk: String?; let excluded: Bool, enabled: Bool }
struct NativeContestAudit: Decodable, Identifiable { let id: String, action: String, reason: String, created_at: String }

struct NativeContestReport: Decodable, Identifiable { let id: String, entry_id: String, reason: String; let entry: NativeContestEntry? }

// Both schema13 (empty acknowledgement) and schema14 (authoritative entry) are supported.
enum NativeContestVoteConfirmation {
    static func apply(_ entry: NativeContestEntry, enabled: Bool, used: Int, response: TreeholeEnvelope) -> (entry: NativeContestEntry, used: Int) {
        var confirmed = response.entry ?? entry
        confirmed.voted = response.entry?.voted ?? enabled
        return (confirmed, response.votesUsed ?? max(0,used + (entry.voted == enabled ? 0 : enabled ? 1 : -1)))
    }
}
