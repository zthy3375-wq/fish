import Foundation

/// All edits operate on value copies. The caller persists before publishing the returned state.
/// This model has no access to school caches, sessions or shared live-service records.
enum PersonalSemesterRules {
    static let colors = ["blue", "purple", "green", "orange"]

    static func activeSemester(in state: AndroidScheduleState) throws -> AndroidSemester {
        guard let semester = state.semesters.first(where: { $0.id == state.activeSemesterId }) else {
            throw BackupCompatibilityFailure("当前个人学期不存在，请重新打开管理页面。")
        }
        return semester
    }

    static func table(for semester: AndroidSemester, in state: AndroidScheduleState) throws -> AndroidTimeTable {
        guard let table = state.timeTables.first(where: { $0.id == semester.timeTableId }) else {
            throw BackupCompatibilityFailure("学期关联的作息方案不存在。")
        }
        return table
    }

    static func activeCourses(in state: AndroidScheduleState) throws -> [Course] {
        try state.projectedCourses(semesterID: state.activeSemesterId)
    }

    static func validated(_ state: AndroidScheduleState) throws -> AndroidScheduleState {
        try state.validated()
    }

    static func migrateLegacy(courses: [Course], semesterStart: Date, now: Date = Date()) throws -> AndroidScheduleState {
        guard courses.allSatisfy({ $0.source == "personal" && $0.externalID == nil }) else {
            throw BackupCompatibilityFailure("学校课程不能迁入个人课表。")
        }
        guard semesterStart.timeIntervalSince1970.isFinite, ScheduleMath.weekday(on: semesterStart) == 1 else {
            throw BackupCompatibilityFailure("旧个人课表第一周不是周一，请先校准；原记录尚未修改。")
        }
        let date = BackupValue.dayString(semesterStart)
        _ = try BackupValue.day(date)
        let year = ScheduleMath.calendar.component(.year, from: semesterStart)
        let autumn = ScheduleMath.calendar.component(.month, from: semesterStart) >= 7
        let firstYear = autumn ? year : year - 1
        let count = max(19, courses.flatMap(\.weeks).max() ?? 19)
        guard count <= 40 else { throw BackupCompatibilityFailure("旧个人课表含超过40周的安排，请先调整；原记录尚未修改。") }
        let semester = AndroidSemester(id: "native-personal-" + date, academicYear: "\(firstYear)–\(firstYear + 1)", season: autumn ? "秋季" : "春季", startDate: date, weekStartDate: date, weekCount: count, timeTableId: "standard-45")
        var state = AndroidScheduleState(version: 2, timeTables: [standardTimeTable()], mode: "personal", activeSemesterId: semester.id, semesters: [semester], courses: [], reminders: AndroidScheduleReminders(enabled: false, minutes: 10), updatedAt: BackupValue.timestampString(now))
        for flat in courses {
            let arrangement = try flatArrangement(flat, id: "native-arrangement-" + flat.id.uuidString)
            state.courses.append(AndroidManagedCourse(id: "native-course-" + flat.id.uuidString, semesterId: semester.id, name: flat.name, teacher: flat.teacher, color: flat.color, notes: flat.notes, arrangements: [arrangement]))
        }
        return try validated(state)
    }

    static func standardTimeTable(id: String = "standard-45") -> AndroidTimeTable {
        AndroidScheduleImportPlan.standardTimeTable(id: id)
    }

    static func handanTimeTable(id: String = "handan-40min-student-supplied") -> AndroidTimeTable {
        AndroidTimeTable(id: id, name: "邯郸学院 · 40分钟 · 13节（用户提供）", slots: ScheduleMath.starts.indices.map { AndroidTimeSlot(number: $0 + 1, start: ScheduleMath.starts[$0], end: ScheduleMath.ends[$0]) })
    }

    static func selectSemester(id: String, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard state.semesters.contains(where: { $0.id == id }) else { throw BackupCompatibilityFailure("个人学期不存在。") }
        var next = state; next.activeSemesterId = id
        return try changed(next, now: now)
    }

    static func saveSemester(_ semester: AndroidSemester, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        var next = state
        if let index = next.semesters.firstIndex(where: { $0.id == semester.id }) { next.semesters[index] = semester }
        else { next.semesters.append(semester) }
        next.activeSemesterId = semester.id
        return try changed(next, now: now)
    }

    static func deleteSemester(id: String, confirmed: Bool, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard confirmed else { throw BackupCompatibilityFailure("请先确认删除该学期及其中的个人课程。") }
        guard state.semesters.contains(where: { $0.id == id }), state.semesters.count > 1 else {
            throw BackupCompatibilityFailure("至少保留一个个人学期；可先新建学期。")
        }
        var next = state
        next.semesters.removeAll { $0.id == id }
        next.courses.removeAll { $0.semesterId == id }
        if next.activeSemesterId == id { next.activeSemesterId = next.semesters[0].id }
        // Keep all time tables, including plans referenced by other semesters.
        return try changed(next, now: now)
    }

    /// Saving a new copy only rebinds the selected semester; never mutate a shared time table.
    static func applyTimeTable(_ table: AndroidTimeTable, to semesterID: String, saveCopy: Bool, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard let index = state.semesters.firstIndex(where: { $0.id == semesterID }) else { throw BackupCompatibilityFailure("个人学期不存在。") }
        var next = state
        if saveCopy {
            guard !next.timeTables.contains(where: { $0.id == table.id }) else { throw BackupCompatibilityFailure("新作息方案编号重复，请重新另存。") }
            next.timeTables.append(table)
        } else {
            guard let existing = next.timeTables.first(where: { $0.id == table.id }), existing == table else {
                throw BackupCompatibilityFailure("修改作息请另存为新方案，避免影响其他学期。")
            }
        }
        next.semesters[index].timeTableId = table.id
        return try changed(next, now: now)
    }

    static func saveCourse(_ course: AndroidManagedCourse, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard course.semesterId == state.activeSemesterId else { throw BackupCompatibilityFailure("当前学期已变化，请重新编辑课程。") }
        var next = state
        if let index = next.courses.firstIndex(where: { $0.id == course.id }) {
            guard next.courses[index].semesterId == course.semesterId else { throw BackupCompatibilityFailure("不能把其他学期的课程覆盖到当前学期。") }
            next.courses[index] = course
        } else { next.courses.append(course) }
        return try changed(next, now: now)
    }

    static func deleteCourse(id: String, confirmed: Bool, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard confirmed else { throw BackupCompatibilityFailure("请先确认删除课程及其全部上课安排。") }
        guard state.courses.contains(where: { $0.id == id && $0.semesterId == state.activeSemesterId }) else { throw BackupCompatibilityFailure("当前学期课程不存在。") }
        var next = state
        next.courses.removeAll { $0.id == id && $0.semesterId == state.activeSemesterId }
        return try changed(next, now: now)
    }

    /// Flat editors update one arrangement while preserving its original ID and all sibling arrangements.
    /// Shared course fields remain shared. A clock edit deliberately converts that arrangement to custom.
    static func upsertFlatCourse(_ flat: Course, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        var next = try validated(state)
        let existing = position(of: flat.id, in: next)
        try writeFlatCourse(flat, to: &next, position: existing)
        return try changed(next, now: now)
    }

    private static func writeFlatCourse(_ flat: Course, to next: inout AndroidScheduleState, position: (course: Int, arrangement: Int)?) throws {
        guard flat.source == "personal", flat.externalID == nil else { throw BackupCompatibilityFailure("学校课程不能修改为个人课程。") }
        if let position {
            guard next.courses[position.course].semesterId == next.activeSemesterId else { throw BackupCompatibilityFailure("当前学期已变化，请重新打开课程。") }
            let previous = next.courses[position.course].arrangements[position.arrangement]
            var arrangement = try flatArrangement(flat, id: previous.id)
            if previous.start == flat.start, previous.end == flat.end,
               previous.startPeriod == flat.startPeriod, previous.endPeriod == flat.endPeriod {
                arrangement.timeMode = previous.timeMode
            }
            if previous.weeks.sorted() == flat.weeks.sorted() {
                arrangement.startWeek = previous.startWeek; arrangement.endWeek = previous.endWeek
                arrangement.rule = previous.rule; arrangement.customWeeks = previous.customWeeks
            }
            next.courses[position.course].name = flat.name; next.courses[position.course].teacher = flat.teacher
            next.courses[position.course].color = flat.color; next.courses[position.course].notes = flat.notes
            next.courses[position.course].arrangements[position.arrangement] = arrangement
        } else {
            let arrangement = try flatArrangement(flat, id: "native-arrangement-" + flat.id.uuidString)
            next.courses.append(AndroidManagedCourse(id: "native-course-" + flat.id.uuidString, semesterId: next.activeSemesterId, name: flat.name, teacher: flat.teacher, color: flat.color, notes: flat.notes, arrangements: [arrangement]))
        }
    }

    static func deleteFlatCourse(id: UUID, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard let position = position(of: id, in: state), state.courses[position.course].semesterId == state.activeSemesterId else {
            throw BackupCompatibilityFailure("当前学期安排不存在，请重新打开课程。")
        }
        var next = state
        next.courses[position.course].arrangements.remove(at: position.arrangement)
        if next.courses[position.course].arrangements.isEmpty { next.courses.remove(at: position.course) }
        return try changed(next, now: now)
    }

    /// Replacement targets the active semester only. Course-file import never discards other semesters.
    static func importFlatCourses(_ courses: [Course], replacingActive: Bool, in state: AndroidScheduleState, now: Date = Date()) throws -> AndroidScheduleState {
        guard Set(courses.map(\.id)).count == courses.count else { throw BackupCompatibilityFailure("导入记录含重复编号。") }
        var next = try validated(state)
        if replacingActive {
            let active = next.activeSemesterId
            next.courses.removeAll { $0.semesterId == active }
        }
        // Construct identity lookup once, rather than revalidating the whole database per imported row.
        var positions: [UUID: (course: Int, arrangement: Int)] = [:]
        for c in next.courses.indices {
            for a in next.courses[c].arrangements.indices {
                positions[AndroidScheduleImportPlan.nativeCourseID(course: next.courses[c].id, arrangement: next.courses[c].arrangements[a].id)] = (c, a)
                let prefix = "native-course-"
                if next.courses[c].id.hasPrefix(prefix), let id = UUID(uuidString: String(next.courses[c].id.dropFirst(prefix.count))),
                   next.courses[c].arrangements[a].id == "native-arrangement-" + id.uuidString { positions[id] = (c, a) }
            }
        }
        for course in courses { try writeFlatCourse(course, to: &next, position: positions[course.id]) }
        return try changed(next, now: now)
    }

    static func newCourse(semester: AndroidSemester, table: AndroidTimeTable) -> AndroidManagedCourse {
        AndroidManagedCourse(id: UUID().uuidString, semesterId: semester.id, name: "", teacher: "", color: "purple", notes: "", arrangements: [newArrangement(semester: semester, table: table)])
    }

    static func newArrangement(semester: AndroidSemester, table: AndroidTimeTable) -> AndroidArrangement {
        AndroidArrangement(id: UUID().uuidString, day: 1, startPeriod: 1, endPeriod: 1, start: table.slots.first?.start ?? "08:00", end: table.slots.first?.end ?? "08:45", room: "", startWeek: 1, endWeek: semester.weekCount, rule: "all", customWeeks: [], timeMode: "period")
    }

    static func conflicts(in state: AndroidScheduleState, semesterID: String) throws -> [String] {
        let courses = try state.projectedCourses(semesterID: semesterID)
        var messages: [String] = []
        for i in courses.indices {
            for j in courses.indices where j < i {
                let a = courses[i], b = courses[j]
                if a.day == b.day, a.start < b.end, b.start < a.end, !Set(a.weeks).isDisjoint(with: b.weeks) {
                    messages.append("\(a.name) 与 \(b.name)：周\(a.day) \(a.start)–\(a.end) 教学周重叠")
                    if messages.count >= 100 { return messages }
                }
            }
        }
        return messages
    }

    static func parseCustomWeeks(_ text: String) throws -> [Int] {
        let normalized = text.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "－", with: "-")
        guard normalized.utf8.count <= 400 else { throw BackupCompatibilityFailure("指定周内容过长。") }
        var weeks = Set<Int>()
        for raw in normalized.split(separator: ",", omittingEmptySubsequences: false) {
            let token = raw.trimmingCharacters(in: .whitespaces)
            guard token.range(of: "^[0-9]{1,2}(-[0-9]{1,2})?$", options: .regularExpression) != nil else {
                throw BackupCompatibilityFailure("指定周请填写数字或范围，用逗号分隔，例如 1-4,8。")
            }
            let parts = token.split(separator: "-").compactMap { Int($0) }
            guard let first = parts.first, let last = parts.last, (1...40).contains(first), (first...40).contains(last) else {
                throw BackupCompatibilityFailure("指定周必须在1–40之间，范围不能倒序。")
            }
            weeks.formUnion(first...last)
        }
        guard !weeks.isEmpty else { throw BackupCompatibilityFailure("至少选择一个教学周。") }
        return weeks.sorted()
    }

    private static func changed(_ state: AndroidScheduleState, now: Date) throws -> AndroidScheduleState {
        var next = state; next.mode = "personal"; next.updatedAt = BackupValue.timestampString(now)
        return try validated(next)
    }

    private static func flatArrangement(_ flat: Course, id: String) throws -> AndroidArrangement {
        // Android stores numeric period bounds, not arbitrary native display labels. Never discard an
        // unsupported legacy label during migration/import; leave the original encrypted data intact.
        let label = flat.period.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty && label != "未指定节次" {
            var normalized = label.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "－", with: "-").replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "节", with: "")
            normalized.removeAll(where: { $0.isWhitespace })
            guard let first = flat.startPeriod, let last = flat.endPeriod,
                  normalized == "\(first)-\(last)" || (first == last && normalized == String(first)) else {
                throw BackupCompatibilityFailure("旧课程含无法转换的节次说明，请先调整节次；原记录尚未修改。")
            }
        }
        let weeks = flat.weeks.sorted()
        guard let first = weeks.first, let last = weeks.last, Set(weeks).count == weeks.count, first >= 1, last <= 40 else {
            throw BackupCompatibilityFailure("个人课程教学周须为1–40，且不能为空或重复。")
        }
        return AndroidArrangement(id: id, day: flat.day, startPeriod: flat.startPeriod, endPeriod: flat.endPeriod, start: flat.start, end: flat.end, room: flat.room, startWeek: first, endWeek: last, rule: "custom", customWeeks: weeks, timeMode: "custom")
    }

    private static func position(of id: UUID, in state: AndroidScheduleState) -> (course: Int, arrangement: Int)? {
        for courseIndex in state.courses.indices {
            let course = state.courses[courseIndex]
            for arrangementIndex in course.arrangements.indices {
                let arrangement = course.arrangements[arrangementIndex]
                let projected = AndroidScheduleImportPlan.nativeCourseID(course: course.id, arrangement: arrangement.id)
                let legacyAlias = course.id == "native-course-" + id.uuidString && arrangement.id == "native-arrangement-" + id.uuidString
                if projected == id || legacyAlias { return (courseIndex, arrangementIndex) }
            }
        }
        return nil
    }
}
