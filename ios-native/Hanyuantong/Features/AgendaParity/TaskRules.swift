import Foundation

/// Value-only task operations. Callers must persist the returned collection before publishing it.
enum TaskRules {
    struct Failure: LocalizedError, Equatable {
        var message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }
    static let priorities = ["普通", "低", "中", "高"]
    static let maximumTasks = 5000

    static func makeTask(title: String = "", now: Date = Date()) -> CampusTask {
        var value = CampusTask(title: title, date: now)
        value.plannedAt = nil
        value.legacyReminder = false
        return value
    }

    static func validDate(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite && (-2208988800...7289654400).contains(seconds)
    }
    /// Date pickers expose minutes only. Call on explicit UI selections, never during validation/import.
    static func pickerMinute(_ value: Date) -> Date {
        let seconds = value.timeIntervalSince1970
        guard seconds.isFinite else { return value }
        return Date(timeIntervalSince1970: (seconds / 60).rounded(.down) * 60)
    }
    /// New reminder defaults round up, so "10 minutes later" never fires earlier than requested.
    static func futurePickerMinute(minutes: Int, now: Date = Date()) -> Date {
        let requested = now.addingTimeInterval(Double(minutes) * 60)
        let seconds = requested.timeIntervalSince1970
        guard seconds.isFinite else { return requested }
        return Date(timeIntervalSince1970: (seconds / 60).rounded(.up) * 60)
    }
    private static func bounded(_ value: String, limit: Int, required: Bool = false) throws -> String {
        guard value.count <= limit else { throw Failure("待办内容超过字数限制") }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !required || !clean.isEmpty else { throw Failure("请填写待办标题或步骤内容") }
        return clean
    }
    private static func identity(_ value: String?) throws -> String? {
        guard let value else { return nil }
        return try bounded(value, limit: 100, required: true)
    }
    static func validated(_ task: CampusTask) throws -> CampusTask {
        var value = task
        guard value.schemaVersion == 2 else { throw Failure("待办版本无法识别") }
        // Preserve previously valid native content (200/4000); Android imports apply their own 100/1000 limits.
        value.title = try bounded(value.title, limit: 200, required: true)
        value.course = try bounded(value.course, limit: 100)
        value.notes = try bounded(value.notes, limit: 4000)
        guard [value.date, value.createdAt, value.updatedAt].allSatisfy(validDate),
              [value.plannedAt, value.deadline, value.completedAt, value.snoozedUntil].compactMap({ $0 }).allSatisfy(validDate) else {
            throw Failure("待办日期无效")
        }
        if let day = value.plannedDay, TaskClock.start(day) == nil { throw Failure("计划日期无效") }
        if value.plannedAt != nil { value.plannedDay = nil }
        guard (5...1440).contains(value.durationMinutes), (0...3).contains(value.priority) else { throw Failure("时长或优先级无效") }
        guard value.steps.count <= 50, Set(value.steps.map(\.id)).count == value.steps.count else { throw Failure("子任务最多50项，编号不能重复") }
        value.steps = try value.steps.map { step in
            var step = step
            step.title = try bounded(step.title, limit: 100, required: true)
            step.originalID = try identity(step.originalID)
            return step
        }
        if var rule = value.repeatRule {
            guard (1...365).contains(rule.interval), rule.weekdays.count <= 7,
                  rule.weekdays.allSatisfy({ (1...7).contains($0) }),
                  rule.kind != .days || !rule.weekdays.isEmpty else { throw Failure("重复规则无效") }
            guard value.plannedAt != nil || value.plannedDay != nil || value.deadline != nil else { throw Failure("重复任务需设置计划日期或截止时间") }
            rule.weekdays = Array(Set(rule.weekdays)).sorted()
            value.repeatRule = rule
        }
        guard value.reminders.count <= 5, Set(value.reminders.map(\.id)).count == value.reminders.count else { throw Failure("每项最多5次提醒，编号不能重复") }
        value.reminders = try value.reminders.map { reminder in
            var reminder = reminder
            guard (0...525600).contains(reminder.minutes) else { throw Failure("提醒提前分钟无效") }
            if reminder.anchor == .absolute {
                guard let at = reminder.at, validDate(at) else { throw Failure("请填写提醒时间") }
            } else { reminder.at = nil }
            reminder.originalID = try identity(reminder.originalID)
            return reminder
        }
        value.originalID = try identity(value.originalID)
        value.generatedFromOriginalID = try identity(value.generatedFromOriginalID)
        value.seriesOriginalID = try identity(value.seriesOriginalID)
        guard value.generatedFrom != value.id else { throw Failure("重复任务来源不能是自身") }
        value.date = value.plannedAt ?? value.plannedDay.flatMap(TaskClock.start) ?? value.deadline ?? value.createdAt
        return value
    }

    static func validatedTasks(_ tasks: [CampusTask]) throws -> [CampusTask] {
        guard tasks.count <= maximumTasks else { throw Failure("待办数量超过5000项") }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw Failure("待办编号重复") }
        return try tasks.map(validated)
    }

    static func plannedDay(_ task: CampusTask) -> String? { task.plannedAt.map(TaskClock.day) ?? task.plannedDay }
    static func isOverdue(_ task: CampusTask, now: Date = Date()) -> Bool {
        !task.completed && task.deadline.map { $0 < now } == true
    }

    static func select(_ tasks: [CampusTask], filter: TaskFilter, now: Date = Date()) -> [CampusTask] {
        let today = TaskClock.day(now)
        let soon = TaskClock.shifted(today, days: 7) ?? today
        let search = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            let plan = plannedDay(task)
            let match: Bool
            switch filter.scope {
            case .all: match = true
            case .completed: match = task.completed
            case .pending: match = !task.completed
            case .inbox: match = !task.completed && plan == nil
            case .today: match = !task.completed && plan.map { $0 <= today } == true
            case .planned: match = !task.completed && plan.map { $0 > today } == true
            case .due: match = !task.completed && task.deadline.map { TaskClock.day($0) <= soon } == true
            }
            return match && (filter.course.isEmpty || task.course == filter.course)
                && (filter.priority < 0 || task.priority == filter.priority)
                && (search.isEmpty || "\(task.title) \(task.course) \(task.notes)".localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if filter.groupByCourse && a.course != b.course { return compare(a.course, b.course) }
            if a.pinned != b.pinned { return a.pinned }
            if filter.sort == .title && a.title != b.title { return compare(a.title, b.title) }
            if filter.sort == .smart && isOverdue(a, now: now) != isOverdue(b, now: now) { return isOverdue(a, now: now) }
            if (filter.sort == .smart || filter.sort == .priority) && a.priority != b.priority { return a.priority > b.priority }
            if filter.sort == .smart || filter.sort == .deadline {
                let ad = a.deadline ?? .distantFuture, bd = b.deadline ?? .distantFuture
                if ad != bd { return ad < bd }
            }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }
    private static func compare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive, locale: Locale(identifier: "zh_CN")) == .orderedAscending
    }

    static func groups(_ tasks: [CampusTask], filter: TaskFilter, now: Date = Date()) -> [TaskDateGroup] {
        let selected = select(tasks, filter: filter, now: now)
        var groups: [TaskDateGroup] = []
        let today = TaskClock.day(now), tomorrow = TaskClock.shifted(today, days: 1)
        for task in selected {
            let key: String, title: String
            if filter.groupByCourse {
                key = task.course; title = task.course.isEmpty ? "个人事务" : task.course
            } else {
                let day: String?
                if task.completed { day = task.completedAt.map(TaskClock.day) ?? TaskClock.day(task.updatedAt) }
                else if filter.scope == .due { day = task.deadline.map(TaskClock.day) }
                else { day = plannedDay(task) }
                key = day ?? "undated"
                let label = day == today ? "今天" : day == tomorrow ? "明天" : day ?? "未安排"
                title = task.completed ? "已完成 · \(label)" : label
            }
            let identity = (filter.groupByCourse ? "course/" : task.completed ? "done/" : "plan/") + key
            if let index = groups.firstIndex(where: { $0.id == identity }) { groups[index].tasks.append(task) }
            else { groups.append(TaskDateGroup(id: identity, title: title, tasks: [task])) }
        }
        // Preserve smart-sort priority across groups; never invent a plan for deadline-only tasks.
        return groups
    }

    static func replanned(_ task: CampusTask, day: String, now: Date = Date()) throws -> CampusTask {
        guard let target = TaskClock.start(day) else { throw Failure("计划日期无效") }
        var value = task
        if let old = task.plannedAt {
            let parts = TaskClock.calendar.dateComponents([.hour, .minute, .second], from: old)
            value.plannedAt = TaskClock.calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0, of: target)
            value.plannedDay = nil
        } else { value.plannedDay = day }
        value.snoozedUntil = nil; value.updatedAt = now
        return try validated(value)
    }

    static func snoozed(_ task: CampusTask, until: Date?, now: Date = Date()) throws -> CampusTask {
        guard !task.completed else { throw Failure("已完成的任务无需稍后提醒") }
        if let until, !validDate(until) || until <= now { throw Failure("请选择将来的提醒时间") }
        var value = task
        value.snoozedUntil = until; value.updatedAt = now
        return try validated(value)
    }

    /// A stable, bounded identity only, not a cryptographic/security primitive.
    private static func occurrenceID(root: UUID, day: String) -> UUID {
        let bytes = Array((root.uuidString.lowercased() + "/" + day).utf8)
        var a: UInt64 = 14695981039346656037, b: UInt64 = 7809847782465536322
        for byte in bytes { a = (a ^ UInt64(byte)) &* 1099511628211; b = (b ^ UInt64(byte)) &* 14029467366897019727 }
        let parts = (0..<8).map { UInt8(truncatingIfNeeded: a >> (56 - 8 * $0)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: b >> (56 - 8 * $0)) }
        var p = parts; p[6] = (p[6] & 0x0f) | 0x50; p[8] = (p[8] & 0x3f) | 0x80
        return UUID(uuid: (p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15]))
    }

    static func nextOccurrence(_ task: CampusTask, now: Date = Date()) throws -> CampusTask? {
        let task = try validated(task)
        guard let rule = task.repeatRule,
              let base = task.plannedAt ?? task.plannedDay.flatMap(TaskClock.start) ?? task.deadline else { return nil }
        guard validDate(now) else { throw Failure("当前时间无效") }
        for offset in 1...36600 {
            guard let next = TaskClock.shifted(base, days: offset) else { break }
            if next <= now { continue }
            let weekday = TaskClock.weekday(next)
            if rule.kind == .weekdays && weekday > 5 { continue }
            if rule.kind == .weekly && offset % 7 != 0 { continue }
            if rule.kind == .interval && offset % rule.interval != 0 { continue }
            if rule.kind == .days && !rule.weekdays.contains(weekday) { continue }
            var value = task
            let root = task.seriesID ?? task.id
            value.id = occurrenceID(root: root, day: TaskClock.day(next))
            value.originalID = nil
            value.seriesID = root; value.seriesOriginalID = task.seriesOriginalID ?? task.originalID
            value.generatedFrom = task.id; value.generatedFromOriginalID = task.originalID
            value.plannedAt = task.plannedAt.flatMap { TaskClock.shifted($0, days: offset) }
            value.plannedDay = task.plannedDay.flatMap { TaskClock.shifted($0, days: offset) }
            value.deadline = task.deadline.flatMap { TaskClock.shifted($0, days: offset) }
            value.completed = false; value.completedAt = nil; value.snoozedUntil = nil; value.prepared = false
            value.createdAt = now; value.updatedAt = now
            value.steps = task.steps.map { var step = $0; step.completed = false; return step }
            value.reminders = task.reminders.map { reminder in
                var reminder = reminder
                if reminder.anchor == .absolute { reminder.at = reminder.at.flatMap { TaskClock.shifted($0, days: offset) } }
                return reminder
            }
            return try validated(value)
        }
        throw Failure("未找到有效的下次重复日期，请检查规则")
    }

    /// Idempotent completion and protected undo. Throws before the caller can replace persisted data.
    static func settingCompleted(_ tasks: [CampusTask], id: UUID, completed: Bool, now: Date = Date()) throws -> [CampusTask] {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw Failure("任务已不存在，请重新读取") }
        guard tasks[index].completed != completed else { return tasks }
        var result = tasks
        if completed {
            if let next = try nextOccurrence(result[index], now: now), !result.contains(where: { $0.id == next.id }) { result.append(next) }
            result[index].completed = true; result[index].completedAt = now; result[index].snoozedUntil = nil
        } else {
            let children = result.filter { $0.generatedFrom == id }
            for child in children {
                // Compare content too: second-resolution backups must not hide an edit made in the creation second.
                guard var expected = try nextOccurrence(result[index], now: child.createdAt) else {
                    throw Failure("下次重复任务已修改，请先处理下次任务再撤销")
                }
                // Android uses a different deterministic occurrence ID. Identity mapping is not a content edit.
                expected.id = child.id
                expected.originalID = child.originalID
                // Android repeats keep raw element IDs, but importing namespaces UUIDs by task.
                // Only equivalent nonnil aliases at the same position may normalize UUIDs. The final
                // equality still checks aliases, ordering, text, completion and every reminder field.
                for position in expected.steps.indices where child.steps.indices.contains(position) {
                    if let alias = expected.steps[position].originalID, alias == child.steps[position].originalID {
                        expected.steps[position].id = child.steps[position].id
                    }
                }
                for position in expected.reminders.indices where child.reminders.indices.contains(position) {
                    if let alias = expected.reminders[position].originalID, alias == child.reminders[position].originalID {
                        expected.reminders[position].id = child.reminders[position].id
                    }
                }
                guard !child.completed, child.updatedAt == child.createdAt, child == expected else {
                    throw Failure("下次重复任务已修改，请先处理下次任务再撤销")
                }
            }
            result.removeAll { $0.generatedFrom == id }
            // Removing children can change indices if a backup supplied a different ordering.
            guard let restoredIndex = result.firstIndex(where: { $0.id == id }) else { throw Failure("任务已不存在") }
            result[restoredIndex].completed = false; result[restoredIndex].completedAt = nil
        }
        if let finalIndex = result.firstIndex(where: { $0.id == id }) { result[finalIndex].updatedAt = now }
        return try validatedTasks(result)
    }

    /// Pure plan only. Never requests permission, schedules or sends a live notification.
    static func reminderCandidates(_ tasks: [CampusTask], legacyMinutes: Int = 0, now: Date = Date(), limit: Int = 30) -> [TaskReminderCandidate] {
        var candidates: [TaskReminderCandidate] = []
        for task in tasks where !task.completed {
            func add(_ date: Date?, label: String) {
                guard let date, validDate(date), date > now else { return }
                let key = "handan.task.\(task.id.uuidString).\(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), date.timeIntervalSince1970))"
                candidates.append(TaskReminderCandidate(id: key, taskID: task.id, date: date,
                    title: "待办提醒：\(task.title)", body: "\(label) · \(task.course.isEmpty ? "个人任务" : task.course)"))
            }
            if task.legacyReminder && task.reminders.isEmpty && (0...1440).contains(legacyMinutes) {
                add(task.plannedAt?.addingTimeInterval(-Double(legacyMinutes) * 60), label: "计划开始")
            }
            for reminder in task.reminders where (0...525600).contains(reminder.minutes) {
                switch reminder.anchor {
                case .absolute: add(reminder.at, label: "提醒")
                case .start: add(task.plannedAt?.addingTimeInterval(-Double(reminder.minutes) * 60), label: "计划开始")
                case .deadline: add(task.deadline?.addingTimeInterval(-Double(reminder.minutes) * 60), label: "截止")
                }
            }
            add(task.snoozedUntil, label: "稍后提醒")
        }
        var seen = Set<String>()
        return Array(candidates.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            .filter { seen.insert($0.id).inserted }.prefix(max(0, min(limit, 30))))
    }
}
