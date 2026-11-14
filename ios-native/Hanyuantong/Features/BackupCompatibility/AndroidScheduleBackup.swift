import Foundation

struct AndroidTimeSlot: Codable, Hashable { var number: Int; var start: String; var end: String }
struct AndroidTimeTable: Codable, Hashable, Identifiable { var id: String; var name: String; var slots: [AndroidTimeSlot] }
struct AndroidSemester: Codable, Hashable, Identifiable {
    var id: String
    var academicYear: String
    var season: String
    var startDate: String
    var weekStartDate: String
    var weekCount: Int
    var timeTableId: String
    var title: String { academicYear + " " + season }
}
struct AndroidArrangement: Codable, Hashable, Identifiable {
    var id: String
    var day: Int
    var startPeriod: Int?
    var endPeriod: Int?
    var start: String
    var end: String
    var room: String
    var startWeek: Int
    var endWeek: Int
    var rule: String
    var customWeeks: [Int]
    var timeMode: String
    var weeks: [Int] {
        guard (1...40).contains(startWeek), (startWeek...40).contains(endWeek) else { return [] }
        return (startWeek...endWeek).filter {
            rule == "all" || (rule == "odd" && $0 % 2 == 1) || (rule == "even" && $0 % 2 == 0) || (rule == "custom" && customWeeks.contains($0))
        }
    }
    // Android requires explicit nulls for unnumbered periods.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(day, forKey: .day)
        try c.encode(startPeriod, forKey: .startPeriod); try c.encode(endPeriod, forKey: .endPeriod)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(room, forKey: .room)
        try c.encode(startWeek, forKey: .startWeek); try c.encode(endWeek, forKey: .endWeek)
        try c.encode(rule, forKey: .rule); try c.encode(customWeeks, forKey: .customWeeks); try c.encode(timeMode, forKey: .timeMode)
    }
}
struct AndroidManagedCourse: Codable, Hashable, Identifiable {
    var id: String; var semesterId: String; var name: String; var teacher: String
    var color: String; var notes: String; var arrangements: [AndroidArrangement]
}
struct AndroidScheduleReminders: Codable, Hashable { var enabled: Bool; var minutes: Int }
struct AndroidScheduleState: Codable, Hashable {
    var version = 2
    var timeTables: [AndroidTimeTable]
    var mode: String
    var activeSemesterId: String
    var semesters: [AndroidSemester]
    var courses: [AndroidManagedCourse]
    var reminders: AndroidScheduleReminders
    var updatedAt: String

    /// Native persisted/backup state must contain personal data only. Do not silently clean school caches here.
    static func parse(_ object: Any) throws -> AndroidScheduleState {
        let plan = try AndroidScheduleImportPlan.parse(["format": "handan-campus-schedule", "exportedAt": "2000-01-01T00:00:00Z", "data": object])
        guard plan.excludedSchoolSemesters == 0, plan.excludedSchoolCourses == 0 else {
            throw BackupCompatibilityFailure("iPhone 个人课表中不得包含旧学校缓存。")
        }
        return plan.state
    }
    func validated() throws -> AndroidScheduleState {
        try Self.parse(JSONSerialization.jsonObject(with: BackupValue.encoded(self)))
    }
    func projectedCourses(semesterID: String) throws -> [Course] {
        try AndroidScheduleImportPlan(sourceVersion: version, exportedAt: updatedAt, state: self,
                                      excludedSchoolSemesters: 0, excludedSchoolCourses: 0).selection(semesterID: semesterID).courses
    }
}

struct AndroidScheduleSelection {
    let semester: AndroidSemester
    let timeTable: AndroidTimeTable
    let courses: [Course]
    let remainingSemesters: [AndroidSemester]
    let courseReminders: AndroidScheduleReminders
}

/// Persist this whole plan, not only the selected projection. Switching semester never discards others.
struct AndroidScheduleImportPlan: Codable, Hashable {
    var sourceVersion: Int
    var exportedAt: String
    var state: AndroidScheduleState
    var excludedSchoolSemesters: Int
    var excludedSchoolCourses: Int

    var warnings: [String] {
        var result = ["课程提醒设置已保留，但导入不会自动开启通知权限。"]
        if state.semesters.count > 1 { result.append("包含 \(state.semesters.count) 个个人学期；请选择要显示的学期，其他学期和作息方案应一并保存。") }
        if sourceVersion == 1 { result.append("旧版课表按 Android 规则迁移为自定义时间，补充原有 45 分钟示例作息。") }
        if excludedSchoolSemesters > 0 { result.append("已排除 \(excludedSchoolSemesters) 个旧学校缓存学期及 \(excludedSchoolCourses) 门学校课程，不作为个人课程恢复。") }
        return result
    }

    func selection(semesterID: String) throws -> AndroidScheduleSelection {
        let state = try self.state.validated()
        guard let semester = state.semesters.first(where: { $0.id == semesterID }),
              let table = state.timeTables.first(where: { $0.id == semester.timeTableId }) else {
            throw BackupCompatibilityFailure("请明确选择备份中的个人学期。")
        }
        let courses = state.courses.filter { $0.semesterId == semesterID }.flatMap { course in
            course.arrangements.map { a in
                Course(id: Self.nativeCourseID(course: course.id, arrangement: a.id), name: course.name,
                       teacher: course.teacher, room: a.room, day: a.day, start: a.start, end: a.end,
                       period: a.startPeriod.map { "\($0)–\(a.endPeriod ?? $0) 节" } ?? "未指定节次",
                       weeks: a.weeks, color: course.color, startPeriod: a.startPeriod, endPeriod: a.endPeriod,
                       notes: course.notes, source: "personal")
            }
        }
        guard courses.count <= 2000 else { throw BackupCompatibilityFailure("所选学期超过 iPhone 的 2000 条课程安排限制，请先拆分。") }
        return AndroidScheduleSelection(semester: semester, timeTable: table, courses: courses,
                                        remainingSemesters: state.semesters.filter { $0.id != semesterID }, courseReminders: state.reminders)
    }

    static func nativeCourseID(course: String, arrangement: String) -> UUID {
        BackupValue.stableID("\(course.utf8.count):\(course)\(arrangement)", namespace: "course-arrangement")
    }

    func exportData() throws -> Data {
        struct Envelope: Encodable { let format = "handan-campus-schedule"; let exportedAt: String; let data: AndroidScheduleState }
        let bytes = try BackupValue.encoded(Envelope(exportedAt: exportedAt, data: state))
        guard case .androidSchedule = try PersonalBackupImport.parse(bytes) else { throw BackupCompatibilityFailure("课表导出校验失败。") }
        return bytes
    }

    static func parse(_ root: [String: Any]) throws -> AndroidScheduleImportPlan {
        let envelope = try BackupValue.object(root, required: ["format", "exportedAt", "data"])
        guard try BackupValue.string(envelope["format"], max: 40) == "handan-campus-schedule" else {
            throw BackupCompatibilityFailure("不是已支持的 Android 个人课表备份。")
        }
        _ = try BackupValue.timestamp(envelope["exportedAt"])
        let data = try BackupValue.object(envelope["data"], required: ["version", "mode", "activeSemesterId", "semesters", "courses", "reminders", "updatedAt"], optional: ["timeTables"])
        let version = try BackupValue.integer(data["version"], 1...2)
        let mode = try BackupValue.string(data["mode"], max: 8)
        guard ["personal", "demo"].contains(mode) else { throw BackupCompatibilityFailure("课表来源无效。") }
        _ = try BackupValue.timestamp(data["updatedAt"])
        let rawSemesters = try BackupValue.array(data["semesters"], max: 30, min: 1)
        var tables: [AndroidTimeTable]
        if version == 1 {
            // Some old exporters retained a timeTables field; validate it even though v1 uses legacy tables.
            if let supplied = data["timeTables"] { _ = try BackupValue.array(supplied, max: 60, min: 1).map(parseTable) }
            tables = rawSemesters.indices.map { standardTimeTable(id: "legacy-times-\($0 + 1)") }
        } else { tables = try BackupValue.array(data["timeTables"], max: 60, min: 1).map(parseTable) }
        try BackupValue.unique(tables.map(\.id))
        let semesters = try rawSemesters.enumerated().map { index, value -> AndroidSemester in
            let row = try BackupValue.object(value, required: ["id", "academicYear", "season", "startDate", "weekStartDate", "weekCount"], optional: ["timeTableId"])
            let id = try BackupValue.string(row["id"], max: 100, required: true)
            let season = try BackupValue.string(row["season"], max: 2)
            guard ["春季", "秋季"].contains(season) else { throw BackupCompatibilityFailure("学期季节无效。") }
            let weekStart = try BackupValue.day(row["weekStartDate"])
            guard ScheduleMath.weekday(on: BackupValue.dayDate(weekStart)) == 1 else { throw BackupCompatibilityFailure("第一教学周须从星期一开始。") }
            if let supplied = row["timeTableId"] { _ = try BackupValue.string(supplied, max: 100, required: true) }
            let tableID: String
            if version == 1 { tableID = tables[index].id }
            else { tableID = try BackupValue.string(row["timeTableId"], max: 100, required: true) }
            guard tables.contains(where: { $0.id == tableID }) else { throw BackupCompatibilityFailure("学期关联的作息方案不存在。") }
            return AndroidSemester(id: id, academicYear: try BackupValue.string(row["academicYear"], max: 30, required: true),
                                   season: season, startDate: try BackupValue.day(row["startDate"]), weekStartDate: weekStart,
                                   weekCount: try BackupValue.integer(row["weekCount"], 1...40), timeTableId: tableID)
        }
        try BackupValue.unique(semesters.map(\.id))
        let active = try BackupValue.string(data["activeSemesterId"], max: 100, required: true)
        guard semesters.contains(where: { $0.id == active }) else { throw BackupCompatibilityFailure("当前学期不存在。") }
        var arrangementCount = 0
        let courses = try BackupValue.array(data["courses"], max: 3000).map { value -> AndroidManagedCourse in
            let row = try BackupValue.object(value, required: ["id", "semesterId", "name", "teacher", "color", "notes", "arrangements"])
            let semesterID = try BackupValue.string(row["semesterId"], max: 100, required: true)
            guard let semester = semesters.first(where: { $0.id == semesterID }), let table = tables.first(where: { $0.id == semester.timeTableId }) else {
                throw BackupCompatibilityFailure("课程所属学期不存在。")
            }
            let raw = try BackupValue.array(row["arrangements"], max: 100, min: 1)
            arrangementCount += raw.count
            guard arrangementCount <= 10000 else { throw BackupCompatibilityFailure("备份课程安排超过 10000 条。") }
            let arrangements = try raw.map { try parseArrangement($0, semester: semester, table: table, version: version) }
            try BackupValue.unique(arrangements.map(\.id))
            let color = try BackupValue.string(row["color"], max: 10)
            guard ["blue", "purple", "green", "orange"].contains(color) else { throw BackupCompatibilityFailure("课程颜色无效。") }
            return AndroidManagedCourse(id: try BackupValue.string(row["id"], max: 100, required: true), semesterId: semesterID,
                                        name: try BackupValue.string(row["name"], max: 150, required: true), teacher: try BackupValue.string(row["teacher"], max: 100),
                                        color: color, notes: try BackupValue.string(row["notes"], max: 2000), arrangements: arrangements)
        }
        try BackupValue.unique(courses.map(\.id))
        let reminders = try BackupValue.object(data["reminders"], required: ["enabled", "minutes"])
        let reminderValue = AndroidScheduleReminders(enabled: try BackupValue.boolean(reminders["enabled"]), minutes: try BackupValue.integer(reminders["minutes"], 1...120))
        // The historical prefix denotes school cache, even when the old backup labels its mode personal.
        let personalSemesters = semesters.filter { !$0.id.hasPrefix("school-page-") }
        guard !personalSemesters.isEmpty else { throw BackupCompatibilityFailure("备份仅含旧学校缓存，没有可恢复的个人学期。请在 iPhone 重新连接学校。") }
        let personalCourses = courses.filter { !$0.semesterId.hasPrefix("school-page-") }
        let schoolTableIDs = Set(semesters.filter { $0.id.hasPrefix("school-page-") }.map(\.timeTableId))
        let personalTableIDs = Set(personalSemesters.map(\.timeTableId))
        tables.removeAll { schoolTableIDs.contains($0.id) && !personalTableIDs.contains($0.id) }
        let normalized = AndroidScheduleState(timeTables: tables, mode: mode, activeSemesterId: personalSemesters.contains(where: { $0.id == active }) ? active : personalSemesters[0].id,
                                              semesters: personalSemesters, courses: personalCourses, reminders: reminderValue,
                                              updatedAt: try BackupValue.string(data["updatedAt"], max: 64))
        return AndroidScheduleImportPlan(sourceVersion: version, exportedAt: try BackupValue.string(envelope["exportedAt"], max: 64), state: normalized,
                                         excludedSchoolSemesters: semesters.count - personalSemesters.count, excludedSchoolCourses: courses.count - personalCourses.count)
    }

    private static func parseTable(_ value: Any) throws -> AndroidTimeTable {
        let row = try BackupValue.object(value, required: ["id", "name", "slots"])
        var previousEnd = ""
        let slots = try BackupValue.array(row["slots"], max: 24, min: 1).enumerated().map { index, value -> AndroidTimeSlot in
            let slot = try BackupValue.object(value, required: ["number", "start", "end"])
            let number = try BackupValue.integer(slot["number"], 1...24), start = try BackupValue.clock(slot["start"]), end = try BackupValue.clock(slot["end"])
            guard number == index + 1, start < end, start >= previousEnd else { throw BackupCompatibilityFailure("作息节次须连续编号，且时间不能重叠。") }
            previousEnd = end
            return AndroidTimeSlot(number: number, start: start, end: end)
        }
        return AndroidTimeTable(id: try BackupValue.string(row["id"], max: 100, required: true), name: try BackupValue.string(row["name"], max: 60, required: true), slots: slots)
    }

    private static func parseArrangement(_ value: Any, semester: AndroidSemester, table: AndroidTimeTable, version: Int) throws -> AndroidArrangement {
        let row = try BackupValue.object(value, required: ["id", "day", "startPeriod", "endPeriod", "start", "end", "room", "startWeek", "endWeek", "rule", "customWeeks"], optional: ["timeMode"])
        let first: Int?, last: Int?
        if row["startPeriod"] is NSNull { first = nil } else { first = try BackupValue.integer(row["startPeriod"], 1...24) }
        if row["endPeriod"] is NSNull { last = nil } else { last = try BackupValue.integer(row["endPeriod"], 1...24) }
        guard (first == nil && last == nil) || (first != nil && last != nil && first! <= last!) else { throw BackupCompatibilityFailure("课程节次范围无效。") }
        let startWeek = try BackupValue.integer(row["startWeek"], 1...semester.weekCount)
        let endWeek = try BackupValue.integer(row["endWeek"], startWeek...semester.weekCount)
        let rule = try BackupValue.string(row["rule"], max: 6)
        guard ["all", "odd", "even", "custom"].contains(rule) else { throw BackupCompatibilityFailure("教学周规则无效。") }
        let customWeeks = try BackupValue.array(row["customWeeks"], max: 40).map { try BackupValue.integer($0, startWeek...endWeek) }
        let suppliedMode = try row["timeMode"].map { try BackupValue.string($0, max: 6) } ?? "custom"
        guard ["custom", "period"].contains(suppliedMode) else { throw BackupCompatibilityFailure("课程时间模式无效。") }
        let mode = version == 1 ? "custom" : suppliedMode
        var start = try BackupValue.clock(row["start"]), end = try BackupValue.clock(row["end"])
        guard start < end else { throw BackupCompatibilityFailure("课程结束时间必须晚于开始时间。") }
        if mode == "period" {
            guard let first, let last, let firstSlot = table.slots.first(where: { $0.number == first }), let lastSlot = table.slots.first(where: { $0.number == last }) else {
                throw BackupCompatibilityFailure("课程引用的作息节次不存在。")
            }
            start = firstSlot.start; end = lastSlot.end
        }
        let result = AndroidArrangement(id: try BackupValue.string(row["id"], max: 100, required: true), day: try BackupValue.integer(row["day"], 1...7), startPeriod: first, endPeriod: last,
                                        start: start, end: end, room: try BackupValue.string(row["room"], max: 150), startWeek: startWeek, endWeek: endWeek,
                                        rule: rule, customWeeks: customWeeks, timeMode: mode)
        guard !result.weeks.isEmpty else { throw BackupCompatibilityFailure("课程安排没有有效教学周。") }
        return result
    }

    static func standardTimeTable(id: String) -> AndroidTimeTable {
        let starts = ["08:00", "08:50", "10:00", "10:50", "14:00", "14:50", "16:00", "16:50", "19:00", "19:50", "20:45", "21:35"]
        let ends = ["08:45", "09:35", "10:45", "11:35", "14:45", "15:35", "16:45", "17:35", "19:45", "20:35", "21:30", "22:20"]
        return AndroidTimeTable(id: id, name: "45 分钟 · 示例作息", slots: starts.indices.map { AndroidTimeSlot(number: $0 + 1, start: starts[$0], end: ends[$0]) })
    }

    /// Export a native-only semester. Refuse unsupported values instead of truncating notes or weeks.
    static func fromNative(courses: [Course], semesterStart: Date, now: Date = Date()) throws -> AndroidScheduleImportPlan {
        guard TaskRules.validDate(semesterStart), TaskRules.validDate(now) else { throw BackupCompatibilityFailure("学期或导出时间无效。") }
        let start = BackupValue.dayString(semesterStart)
        guard ScheduleMath.weekday(on: semesterStart) == 1 else { throw BackupCompatibilityFailure("导出 Android 课表前，请将第一教学周设为星期一。") }
        let year = ScheduleMath.calendar.component(.year, from: semesterStart), autumn = ScheduleMath.calendar.component(.month, from: semesterStart) >= 7
        let id = "native-" + start
        let semester = AndroidSemester(id: id, academicYear: "\(autumn ? year : year - 1)–\(autumn ? year + 1 : year)", season: autumn ? "秋季" : "春季",
                                       startDate: start, weekStartDate: start, weekCount: max(1, courses.flatMap(\.weeks).max() ?? 19), timeTableId: "native-time-table")
        let table = AndroidTimeTable(id: semester.timeTableId, name: "iPhone 当前作息", slots: ScheduleMath.starts.indices.map { AndroidTimeSlot(number: $0 + 1, start: ScheduleMath.starts[$0], end: ScheduleMath.ends[$0]) })
        let records = try courses.map { course -> AndroidManagedCourse in
            guard course.source == "personal", course.externalID == nil, let first = course.weeks.min(), let last = course.weeks.max() else {
                throw BackupCompatibilityFailure("只允许导出有效的个人课程，不包含学校缓存。")
            }
            return AndroidManagedCourse(id: course.id.uuidString, semesterId: id, name: course.name, teacher: course.teacher, color: course.color, notes: course.notes,
                                        arrangements: [AndroidArrangement(id: course.id.uuidString, day: course.day, startPeriod: course.startPeriod, endPeriod: course.endPeriod,
                                                                         start: course.start, end: course.end, room: course.room, startWeek: first, endWeek: last,
                                                                         rule: "custom", customWeeks: course.weeks, timeMode: "custom")])
        }
        let plan = AndroidScheduleImportPlan(sourceVersion: 2, exportedAt: BackupValue.timestampString(now),
                                             state: AndroidScheduleState(timeTables: [table], mode: "personal", activeSemesterId: id, semesters: [semester], courses: records,
                                                                         reminders: AndroidScheduleReminders(enabled: false, minutes: 10), updatedAt: BackupValue.timestampString(now)),
                                             excludedSchoolSemesters: 0, excludedSchoolCourses: 0)
        _ = try plan.exportData()
        return plan
    }
}
