import Foundation

struct TaskStep: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var completed: Bool = false
    var originalID: String? = nil
    enum CodingKeys: String, CodingKey, CaseIterable { case id, title, completed, originalID }
}

enum TaskReminderAnchor: String, Codable, Hashable, CaseIterable {
    case start, deadline, absolute
    var label: String {
        switch self { case .start: return "开始前"; case .deadline: return "截止前"; case .absolute: return "指定时间" }
    }
}

struct TaskReminder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var anchor: TaskReminderAnchor
    var minutes: Int = 30
    var at: Date? = nil
    var originalID: String? = nil
    enum CodingKeys: String, CodingKey, CaseIterable { case id, anchor, minutes, at, originalID }
}

enum TaskRepeatKind: String, Codable, Hashable, CaseIterable {
    case daily, weekdays, weekly, days, interval
    var label: String {
        switch self {
        case .daily: return "每天"
        case .weekdays: return "周一至周五"
        case .weekly: return "每周"
        case .days: return "指定星期"
        case .interval: return "自定义天数"
        }
    }
}

struct TaskRepeatRule: Codable, Hashable {
    var kind: TaskRepeatKind
    var interval: Int = 1
    /// Monday = 1, Sunday = 7.
    var weekdays: [Int] = []
    enum CodingKeys: String, CodingKey, CaseIterable { case kind, interval, weekdays }
}

enum TaskListScope: String, Hashable, CaseIterable, Identifiable {
    case pending, today, planned, inbox, due, completed, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pending: return "未完成"
        case .today: return "今天"
        case .planned: return "接下来"
        case .inbox: return "未安排"
        case .due: return "即将截止"
        case .completed: return "已完成"
        case .all: return "全部"
        }
    }
}

enum TaskSort: String, Hashable, CaseIterable, Identifiable {
    case smart, deadline, priority, title
    var id: String { rawValue }
    var label: String {
        switch self { case .smart: return "智能排序"; case .deadline: return "截止时间"; case .priority: return "重要程度"; case .title: return "标题" }
    }
}

struct TaskFilter {
    var scope: TaskListScope = .pending
    var search: String = ""
    var course: String = ""
    var priority: Int = -1
    var sort: TaskSort = .smart
    var groupByCourse: Bool = false
}

struct TaskDateGroup: Identifiable {
    var id: String
    var title: String
    var tasks: [CampusTask]
}

struct TaskReminderCandidate: Equatable, Identifiable {
    var id: String
    var taskID: UUID
    var date: Date
    var title: String
    var body: String
}

/// All task dates follow the same Beijing calendar as the existing Android planner.
enum TaskClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
    static func day(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func start(_ day: String) -> Date? {
        let bytes = Array(day.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(day.prefix(4)), (2000...2099).contains(year),
              let month = Int(day.dropFirst(5).prefix(2)), let date = Int(day.suffix(2)),
              let result = calendar.date(from: DateComponents(year: year, month: month, day: date)),
              self.day(result) == day else { return nil }
        return result
    }
    static func shifted(_ date: Date, days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: date) }
    static func shifted(_ day: String, days: Int) -> String? {
        guard let date = start(day), let next = shifted(date, days: days) else { return nil }
        let result = self.day(next)
        return start(result) == nil ? nil : result
    }
    static func weekday(_ date: Date) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 + 1 }
}
