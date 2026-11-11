import Foundation
import Combine
@preconcurrency import UserNotifications

struct ReminderPreferences: Codable, Equatable {
    var courses = false
    var tasks = false
    var courseMinutes = 10
    var taskMinutes = 0
}
struct NativeReminder: Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
}
enum NativeReminderPlan {
    static func make(courses: [Course], tasks: [CampusTask], semesterStart: Date,
                     preferences: ReminderPreferences, now: Date = Date()) -> [NativeReminder] {
        var result: [NativeReminder] = []
        let calendar = ScheduleMath.calendar
        if preferences.courses, (1...120).contains(preferences.courseMinutes) {
            for course in courses where course.source == "personal" {
                let parts = course.start.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]), (1...7).contains(course.day) else { continue }
                for week in Set(course.weeks) where (1...60).contains(week) {
                    guard let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + course.day - 1, to: calendar.startOfDay(for: semesterStart)),
                          let start = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) else { continue }
                    let date = start.addingTimeInterval(-Double(preferences.courseMinutes) * 60)
                    guard date > now else { continue }
                    result.append(NativeReminder(id: "handan.course.\(course.id).\(week)", date: date, title: "即将上课：\(course.name)", body: "\(course.start) · \(course.room.isEmpty ? "地点未填写" : course.room)"))
                }
            }
        }
        if preferences.tasks, (0...1440).contains(preferences.taskMinutes) {
            let pending = TaskRules.reminderCandidates(tasks, legacyMinutes: preferences.taskMinutes, now: now, limit: 30).map {
                NativeReminder(id: "handan.task." + $0.id, date: $0.date, title: $0.title, body: $0.body)
            }
            result.append(contentsOf: pending)
        }
        return Array(result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(60))
    }
}

@MainActor final class NativeReminders: ObservableObject {
    @Published private(set) var preferences = ReminderPreferences()
    @Published private(set) var status = "系统提醒默认关闭"
    @Published private(set) var busy = false
    private let center = UNUserNotificationCenter.current()
    private var storage: ProtectedStorage?
    private var loaded = false
    private var generation = 0
    private var queue: Task<Void, Never>?
    init() {
        do {
            let storage = try ProtectedStorage(); self.storage = storage
            if let saved = try storage.read("reminder-settings", as: ReminderPreferences.self) {
                guard (1...120).contains(saved.courseMinutes), (0...1440).contains(saved.taskMinutes) else { throw PersonalBackup.Failure.invalid }
                preferences = saved
            }
            loaded = true
        } catch { status = "提醒设置暂无法安全读取，原设置未覆盖。" }
    }
    func update(_ value: ReminderPreferences) async {
        guard loaded, !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard (1...120).contains(value.courseMinutes), (0...1440).contains(value.taskMinutes), let storage else { throw PersonalBackup.Failure.invalid }
            if value.courses || value.tasks {
                let settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined {
                    guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { status = "通知权限未授权，提醒未开启。"; return }
                } else if settings.authorizationStatus == .denied {
                    status = "通知权限已关闭，请在 iPhone 系统设置中允许通知。"; return
                }
            }
            try storage.write(value, name: "reminder-settings")
            preferences = value
        } catch { status = "提醒设置保存失败，原开关保留。" }
    }
    func reconcile(courses: [Course], tasks: [CampusTask], semesterStart: Date) {
        guard loaded else { return }
        generation += 1
        let version = generation, previous = queue
        let plan = NativeReminderPlan.make(courses: courses, tasks: tasks, semesterStart: semesterStart, preferences: preferences)
        let enabled = preferences.courses || preferences.tasks
        // Serial replacement prevents a late add from resurrecting a completed/deleted task.
        queue = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == version else { return }
            let pending = await self.center.pendingNotificationRequests()
            self.center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("handan.") }.map(\.identifier))
            let delivered = await self.center.deliveredNotifications()
            self.center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("handan.") }.map { $0.request.identifier })
            guard self.generation == version else { return }
            guard enabled else { self.status = "课程与待办提醒已关闭"; return }
            let permission = await self.center.notificationSettings()
            guard permission.authorizationStatus == .authorized || permission.authorizationStatus == .provisional else { self.status = "系统通知权限未开启，未安排提醒。"; return }
            var count = 0
            do {
                for item in plan {
                    guard self.generation == version else { return }
                    let content = UNMutableNotificationContent()
                    content.title = item.title; content.body = item.body; content.sound = .default
                    var components = ScheduleMath.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
                    components.timeZone = ScheduleMath.calendar.timeZone
                    try await self.center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                    count += 1
                }
                self.status = "已安排 \(count) 条近期提醒；打开 App 后续排，送达时间以 iOS 为准。"
            } catch { self.status = "提醒未全部安排（已安排 \(count) 条），请重试。" }
        }
    }
}
