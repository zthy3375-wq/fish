import Foundation

struct AndroidTaskMergePreview {
    let tasks: [CampusTask]
    let addedCount: Int
    let duplicateCount: Int
    /// Same identity with changed content. Existing native records win, matching Android's merge contract.
    let conflictingTitles: [String]
}

struct AndroidTaskImportPlan: Codable, Hashable {
    var sourceVersion: Int
    var tasks: [CampusTask]
    var notificationsEnabled: Bool
    var updatedAt: Date
    var warnings: [String] {
        ["合并按原始编号去重；同编号已有记录保留本机版本，不自动覆盖。",
         "子任务、重复规则和全部提醒已保留；导入不会自动开启通知权限。"]
    }

    func merge(into existing: [CampusTask]) throws -> AndroidTaskMergePreview {
        let existing = try TaskRules.validatedTasks(existing)
        let incoming = try TaskRules.validatedTasks(tasks)
        try BackupValue.unique(incoming.compactMap(\.originalID))
        let ids = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var originalIDs: [String: CampusTask] = [:]
        for task in existing {
            if let original = task.originalID {
                guard originalIDs[original] == nil else { throw BackupCompatibilityFailure("本机待办含重复的备份编号，无法安全合并。") }
                originalIDs[original] = task
            }
        }
        // Existing native UUIDs are authoritative. A previous migration may have preserved an
        // Android originalID under a different native UUID, so remap links as well as deduplicating rows.
        var matched: [UUID: CampusTask] = [:]
        for task in incoming {
            var candidates: [CampusTask] = []
            if let prior = ids[task.id] { candidates.append(prior) }
            if let original = task.originalID {
                if let prior = originalIDs[original] { candidates.append(prior) }
                if let uuid = UUID(uuidString: original), let prior = ids[uuid] { candidates.append(prior) }
            }
            guard Set(candidates.map(\.id)).count <= 1 else { throw BackupCompatibilityFailure("待办备份编号对应多个本机记录，无法安全合并。") }
            if let prior = candidates.first { matched[task.id] = prior }
        }
        func remap(_ id: UUID?, original: String?) throws -> UUID? {
            var candidates = Set<UUID>()
            if let id, let target = matched[id]?.id { candidates.insert(target) }
            else if let id, ids[id] != nil { candidates.insert(id) }
            if let original {
                if let target = originalIDs[original]?.id { candidates.insert(target) }
                if let uuid = UUID(uuidString: original), ids[uuid] != nil { candidates.insert(uuid) }
            }
            guard candidates.count <= 1 else { throw BackupCompatibilityFailure("重复待办的来源或系列编号有歧义，未导入。") }
            return candidates.first ?? id
        }
        var added: [CampusTask] = [], duplicates = 0, conflicts: [String] = []
        for incomingTask in incoming {
            var task = incomingTask
            task.generatedFrom = try remap(task.generatedFrom, original: task.generatedFromOriginalID)
            task.seriesID = try remap(task.seriesID, original: task.seriesOriginalID)
            if let prior = matched[task.id] {
                duplicates += 1
                task.id = prior.id
                if Self.comparable(prior) != Self.comparable(task) { conflicts.append(task.title) }
            } else { added.append(task) }
        }
        return AndroidTaskMergePreview(tasks: try TaskRules.validatedTasks(existing + added), addedCount: added.count,
                                       duplicateCount: duplicates, conflictingTitles: conflicts)
    }

    /// Transport aliases are not content edits. Keep all IDs, dates, ordering and user-visible fields.
    private static func comparable(_ task: CampusTask) -> CampusTask {
        var value = task
        value.originalID = nil; value.generatedFromOriginalID = nil; value.seriesOriginalID = nil
        value.steps = value.steps.map { var step = $0; step.originalID = nil; return step }
        value.reminders = value.reminders.map { var reminder = $0; reminder.originalID = nil; return reminder }
        return value
    }

    static func parse(_ root: [String: Any]) throws -> AndroidTaskImportPlan {
        let value = try BackupValue.object(root, required: ["version", "tasks", "notificationsEnabled", "updatedAt"])
        let version = try BackupValue.integer(value["version"], 1...2)
        let tasks = try BackupValue.array(value["tasks"], max: 500).map(parseTask)
        try BackupValue.unique(tasks.compactMap(\.originalID))
        return AndroidTaskImportPlan(sourceVersion: version, tasks: try TaskRules.validatedTasks(tasks),
                                     notificationsEnabled: try BackupValue.boolean(value["notificationsEnabled"]), updatedAt: try BackupValue.timestamp(value["updatedAt"]))
    }

    private static func identifier(_ value: Any?) throws -> String {
        try BackupValue.string(value, max: 100, required: true).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func parseTask(_ input: Any) throws -> CampusTask {
        // Official learning status is not a personal task, even when its fields resemble a task record.
        if let input = input as? [String: Any], !Set(input.keys).isDisjoint(with: ["source", "externalId", "platformStatus", "platformStatusText", "platformStale", "platformDescription", "platformKind", "platformStartAt", "timeText"]) {
            throw BackupCompatibilityFailure("待办文件包含学习平台记录或状态，不能转成可手动完成的个人待办。请仅导出个人待办。")
        }
        let row = try BackupValue.object(input, required: ["id", "title", "course", "deadline", "notes", "completed", "remindMinutes", "createdAt", "updatedAt"],
                                         optional: ["plannedAt", "plannedDay", "prepared", "durationMinutes", "priority", "pinned", "steps", "repeat", "reminders", "completedAt", "generatedFrom", "seriesId", "snoozedUntil"])
        let original = try identifier(row["id"])
        let created = try BackupValue.timestamp(row["createdAt"])
        var task = CampusTask(id: BackupValue.stableID(original, namespace: "task"), title: try BackupValue.string(row["title"], max: 100, required: true),
                              date: created, completed: try BackupValue.boolean(row["completed"]), notes: try BackupValue.string(row["notes"], max: 1000))
        task.originalID = original; task.legacyReminder = false
        task.course = try BackupValue.string(row["course"], max: 100)
        task.deadline = try BackupValue.optionalLocalDate(row["deadline"])
        task.plannedAt = try BackupValue.optionalLocalDate(row["plannedAt"])
        if let planned = row["plannedDay"], !(planned is NSNull) { task.plannedDay = try BackupValue.day(planned, task: true) }
        guard task.plannedAt == nil || task.plannedDay == nil else { throw BackupCompatibilityFailure("一条待办同时含计划日期和计划时刻，请先在 Android 确认计划后重新导出。") }
        task.prepared = try row["prepared"].map { try BackupValue.boolean($0) } ?? false
        task.durationMinutes = try row["durationMinutes"].map { try BackupValue.integer($0, 5...1440) } ?? 30
        task.priority = try row["priority"].map { try BackupValue.integer($0, 0...3) } ?? 0
        task.pinned = try row["pinned"].map { try BackupValue.boolean($0) } ?? false
        task.createdAt = created; task.updatedAt = try BackupValue.timestamp(row["updatedAt"])
        task.completedAt = try BackupValue.optionalTimestamp(row["completedAt"])
        task.snoozedUntil = try BackupValue.optionalLocalDate(row["snoozedUntil"])
        if let value = row["generatedFrom"] {
            let original = try identifier(value)
            task.generatedFromOriginalID = original; task.generatedFrom = BackupValue.stableID(original, namespace: "task")
        }
        if let value = row["seriesId"] {
            let original = try identifier(value)
            task.seriesOriginalID = original; task.seriesID = BackupValue.stableID(original, namespace: "task")
        }
        task.steps = try BackupValue.array(row["steps"] ?? [], max: 50).map { value in
            let step = try BackupValue.object(value, required: ["id", "title", "completed"])
            let id = try identifier(step["id"])
            return TaskStep(id: BackupValue.stableID(id, namespace: "task-step/" + original), title: try BackupValue.string(step["title"], max: 100, required: true),
                            completed: try BackupValue.boolean(step["completed"]), originalID: id)
        }
        try BackupValue.unique(task.steps.compactMap(\.originalID))
        if let value = row["repeat"], !(value is NSNull) {
            let rule = try BackupValue.object(value, required: ["kind", "interval", "weekdays"])
            guard let kind = TaskRepeatKind(rawValue: try BackupValue.string(rule["kind"], max: 10)) else { throw BackupCompatibilityFailure("待办重复规则无效。") }
            let weekdays = try BackupValue.array(rule["weekdays"], max: 7).map { try BackupValue.integer($0, 1...7) }
            task.repeatRule = TaskRepeatRule(kind: kind, interval: try BackupValue.integer(rule["interval"], 1...365), weekdays: weekdays)
        }
        let oldMinutes: Int?
        if row["remindMinutes"] is NSNull { oldMinutes = nil }
        else {
            let minutes = try BackupValue.integer(row["remindMinutes"], 0...1440)
            guard [0, 5, 10, 30, 60, 1440].contains(minutes) else { throw BackupCompatibilityFailure("旧版提醒分钟无效。") }
            oldMinutes = minutes
        }
        if let value = row["reminders"], !(value is NSNull) {
            task.reminders = try BackupValue.array(value, max: 5).map { value in
                let reminder = try BackupValue.object(value, required: ["id", "anchor", "minutes"], optional: ["at"])
                let id = try identifier(reminder["id"])
                guard let anchor = TaskReminderAnchor(rawValue: try BackupValue.string(reminder["anchor"], max: 8)) else { throw BackupCompatibilityFailure("提醒锚点无效。") }
                let at = try BackupValue.optionalLocalDate(reminder["at"])
                guard anchor == .absolute || at == nil else { throw BackupCompatibilityFailure("相对提醒不能同时携带独立提醒时刻。") }
                return TaskReminder(id: BackupValue.stableID(id, namespace: "task-reminder/" + original), anchor: anchor,
                                    minutes: try BackupValue.integer(reminder["minutes"], 0...525600), at: at, originalID: id)
            }
        } else if task.deadline != nil, let minutes = oldMinutes {
            task.reminders = [TaskReminder(id: BackupValue.stableID("legacy", namespace: "task-reminder/" + original), anchor: .deadline, minutes: minutes, originalID: "legacy")]
        }
        try BackupValue.unique(task.reminders.compactMap(\.originalID))
        return try TaskRules.validated(task)
    }

    func exportData() throws -> Data { try Self.export(tasks: tasks, notificationsEnabled: notificationsEnabled, now: updatedAt) }

    /// Export the Android bare TaskSnapshot v2 format. No platform/session fields are representable.
    static func export(tasks: [CampusTask], notificationsEnabled: Bool = false, now: Date = Date()) throws -> Data {
        guard TaskRules.validDate(now) else { throw BackupCompatibilityFailure("导出时间无效。") }
        let tasks = try TaskRules.validatedTasks(tasks)
        guard tasks.count <= 500 else { throw BackupCompatibilityFailure("Android 待办备份最多 500 条。请使用 iPhone 完整个人备份保存全部记录。") }
        guard tasks.allSatisfy({ $0.title.utf16.count <= 100 && $0.course.utf16.count <= 100 && $0.notes.utf16.count <= 1000 }) else {
            throw BackupCompatibilityFailure("Android 待办标题和课程最多 100 字，备注最多 1000 字。请调整过长内容，或导出 iPhone 完整个人备份；不会自动截断。")
        }
        // An old native global reminder depends on current app preferences, not task data. Do not guess it.
        guard !tasks.contains(where: { $0.legacyReminder }) else {
            throw BackupCompatibilityFailure("部分旧版 iPhone 待办使用全局提醒。请先为这些待办保存明确的提醒规则，再导出 Android 备份。")
        }
        let records = try tasks.map { task -> [String: Any] in
            // Android's schedule fields have minute precision. Refuse lossy conversion rather than silently moving a time.
            for date in [task.plannedAt, task.deadline, task.snoozedUntil] + task.reminders.map(\.at) {
                if let date, abs(date.timeIntervalSince1970 - (date.timeIntervalSince1970 / 60).rounded() * 60) > 0.001 {
                    throw BackupCompatibilityFailure("Android 只支持整分钟的计划和提醒。请先将待办时间调整到整分钟后导出。")
                }
            }
            let oldMinutes = task.reminders.first { $0.anchor == .deadline && [0, 5, 10, 30, 60, 1440].contains($0.minutes) }?.minutes
            var row: [String: Any] = [
                "id": task.originalID ?? task.id.uuidString, "title": task.title, "course": task.course, "notes": task.notes,
                "deadline": task.deadline.map(BackupValue.localString) as Any? ?? NSNull(),
                "completed": task.completed, "remindMinutes": (task.deadline == nil ? nil : oldMinutes) as Any? ?? NSNull(),
                "createdAt": BackupValue.timestampString(task.createdAt), "updatedAt": BackupValue.timestampString(task.updatedAt),
                "plannedAt": task.plannedAt.map(BackupValue.localString) as Any? ?? NSNull(), "plannedDay": task.plannedDay as Any? ?? NSNull(),
                "prepared": task.prepared, "durationMinutes": task.durationMinutes, "priority": task.priority, "pinned": task.pinned,
                "steps": task.steps.map { ["id": $0.originalID ?? $0.id.uuidString, "title": $0.title, "completed": $0.completed] as [String: Any] },
                "reminders": task.reminders.map { reminder -> [String: Any] in
                    var row: [String: Any] = ["id": reminder.originalID ?? reminder.id.uuidString, "anchor": reminder.anchor.rawValue, "minutes": reminder.minutes]
                    if let at = reminder.at { row["at"] = BackupValue.localString(at) }
                    return row
                },
                "completedAt": task.completedAt.map(BackupValue.timestampString) as Any? ?? NSNull(),
                "snoozedUntil": task.snoozedUntil.map(BackupValue.localString) as Any? ?? NSNull()
            ]
            if let rule = task.repeatRule { row["repeat"] = ["kind": rule.kind.rawValue, "interval": rule.interval, "weekdays": rule.weekdays] as [String: Any] }
            else { row["repeat"] = NSNull() }
            if let original = task.generatedFromOriginalID ?? task.generatedFrom?.uuidString { row["generatedFrom"] = original }
            if let original = task.seriesOriginalID ?? task.seriesID?.uuidString { row["seriesId"] = original }
            return row
        }
        let root: [String: Any] = ["version": 2, "tasks": records, "notificationsEnabled": notificationsEnabled, "updatedAt": BackupValue.timestampString(now)]
        let bytes = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard bytes.count <= PersonalBackupImport.maximumBytes else { throw BackupCompatibilityFailure("待办导出超过 5 MB。") }
        guard case .androidTasks = try PersonalBackupImport.parse(bytes) else { throw BackupCompatibilityFailure("待办导出校验失败。") }
        return bytes
    }
}
