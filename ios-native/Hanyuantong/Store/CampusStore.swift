import Foundation
import Combine
import UIKit

@MainActor
final class CampusStore: ObservableObject {
    let reminders = NativeReminders()
    let widget = NativeWidgetPublisher()
    @Published var selectedTab: AppTab = .home
    @Published private(set) var courses: [Course] = []
    @Published private(set) var tasks: [CampusTask] = []
    @Published private(set) var grades: [GradeRecord] = []
    @Published private(set) var academicProfile: AcademicProfile?
    @Published private(set) var exams: [ExamRecord] = []
    @Published private(set) var semesterStart = ScheduleMath.calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    @Published private(set) var schoolSemesterStart = ScheduleMath.calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
    @Published private(set) var personalSchedule: AndroidScheduleState?
    var personalWeekCount: Int { personalSchedule?.semesters.first { $0.id == personalSchedule?.activeSemesterId }?.weekCount ?? 60 }
    @Published var selectedDate = Date()
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private(set) var isConnected = false
    @Published private(set) var lastSynced: Date?
    @Published var showSchoolLogin = false
    @Published private(set) var practice: [AcademicPractice] = []
    @Published private(set) var semesters: [AcademicTerm] = []
    @Published var selectedTerm: AcademicTerm?
    private var storage: ProtectedStorage?
    private var session: AcademicSession?
    private var snapshot: AcademicSnapshot?
    private var personalCourses: [Course] = []
    private var requestGeneration = 0
    private var loadedPersonal = false
    private struct PersonalData: Codable {
        let version: Int
        let courses: [Course]
        let tasks: [CampusTask]
        let semesterStart: Date
        var personalSchedule: AndroidScheduleState? = nil
        var schoolSemesterStart: Date? = nil
    }
    init(storage suppliedStorage: ProtectedStorage? = nil) {
        do {
            let storage = try suppliedStorage ?? ProtectedStorage(); self.storage = storage
            if let saved = try storage.read("personal", as: PersonalData.self) {
                try PersonalBackup(version: saved.version, courses: saved.courses, tasks: saved.tasks,
                                   semesterStart: saved.semesterStart, personalSchedule: saved.personalSchedule).validate()
                guard TaskRules.validDate(saved.schoolSemesterStart ?? saved.semesterStart) else { throw PersonalBackup.Failure.invalid }
                personalCourses = saved.courses
                tasks = try TaskRules.validatedTasks(saved.tasks); semesterStart = saved.semesterStart
                schoolSemesterStart = saved.schoolSemesterStart ?? saved.semesterStart
                if let state = saved.personalSchedule {
                    personalSchedule = try state.validated()
                    personalCourses = try PersonalSemesterRules.activeCourses(in: state)
                    semesterStart = try BackupValue.dayDate(PersonalSemesterRules.activeSemester(in: state).weekStartDate)
                }
            }
            if personalSchedule == nil {
                do {
                    personalSchedule = try PersonalSemesterRules.migrateLegacy(courses: personalCourses, semesterStart: semesterStart)
                    if let state = personalSchedule { personalCourses = try PersonalSemesterRules.activeCourses(in: state) }
                } catch { message = "旧个人课表暂不符合多学期格式，原记录保留。请先在课表设置校准日期或导出备份。" }
            }
            courses = personalCourses
            loadedPersonal = true
            refreshReminders()
        } catch { message = "本机加密数据暂时无法读取。请解锁设备后重试；不会用空数据覆盖原记录。" }
    }
    func attachPresenter(_ controller: UIViewController) {
        if let session { session.updatePresenter(controller); return }
        let service = AcademicSession(controller: controller)
        session = service
        service.onSessionInvalidated = { [weak self] in _ = self?.clearAcademic() }
        do {
            let savedScope = try service.validatedSavedScope()
            if let saved = try storage?.read("academic", as: AcademicSnapshot.self), saved.scope == savedScope {
                snapshot = saved; isConnected = true; apply(saved)
            } else if savedScope != nil { try storage?.remove("academic") }
        } catch { message = "学校离线缓存暂时无法读取，可重新连接后同步。" }
    }
    func connectSchool() { query(interactive: true) }
    func refreshSchool() { query(interactive: false) }
    func cancelSchool() {
        requestGeneration += 1; session?.cancel(); isBusy = false
    }
    func disconnectSchool() {
        requestGeneration += 1; isBusy = false
        do {
            message = nil
            try session?.logout()
            if clearAcademic(), message == nil { message = "已退出学校账号，个人课程和待办保留。" }
        }
        catch { message = error.localizedDescription }
    }
    private func query(interactive: Bool) {
        guard !isBusy else { return }
        guard let session else { message = "页面正在准备，请稍后重试。"; return }
        isBusy = true; message = nil
        requestGeneration += 1
        let generation = requestGeneration
        session.run(interactive: interactive, term: interactive ? nil : selectedTerm) { [weak self] result in
            guard let self, generation == self.requestGeneration else { return }
            self.isBusy = false
            switch result {
            case .success(let new):
                guard new.courses != nil || new.grades != nil || new.exams != nil else {
                    self.message = "本次各模块未能读取，已保留原来的成功记录，请重试。"
                    return
                }
                if let previous = self.snapshot, previous.scope == new.scope, new.term != previous.term, new.courses == nil {
                    self.message = "所选学期课表未能读取，仍显示原学期记录，请重试。"
                    return
                }
                let merged = new.merging(previous: self.snapshot)
                self.snapshot = merged; self.isConnected = true
                self.apply(merged)
                do {
                    guard let storage = self.storage else { throw ProtectedStorage.Failure.unavailable }
                    try storage.write(merged, name: "academic")
                    if self.message == nil { self.message = new.moduleErrors.isEmpty ? "学校数据已更新。" : "部分模块读取未完成，已保留同账号上次成功记录。" }
                } catch { self.message = "数据已读取，但离线保存失败。请勿将本次结果视为已保存。" }
            case .failure(let error):
                self.message = error.localizedDescription
            }
        }
    }
    @discardableResult private func clearAcademic() -> Bool {
        snapshot = nil; isConnected = false; lastSynced = nil; selectedTerm = nil
        academicProfile = nil
        grades = []; exams = []; practice = []; semesters = []; courses = personalCourses
        let widgetCleared = widget.clearForAccountChange()
        if widgetCleared { refreshWidget() }
        do {
            try storage?.remove("academic")
            if !widgetCleared { message = "学校记录已从页面移除，但小组件旧副本清理失败，请解锁后重试退出。" }
            return widgetCleared
        }
        catch { message = "学校数据已从当前页面移除，但本机缓存清理未完成，请重试退出。"; return false }
    }
    private func apply(_ value: AcademicSnapshot) {
        var unmapped = 0
        let school: [Course] = (value.courses ?? []).compactMap { row in
            let periods = ScheduleMath.parseRange(row.periods, limit: 24)
            let weeks = ScheduleMath.parseRange(row.weeks, limit: 60)
            guard let first = periods.first, let last = periods.last, !weeks.isEmpty else { unmapped += 1; return nil }
            let officialStart = value.periods?.first { $0.number == first }?.start
            let officialEnd = value.periods?.first { $0.number == last }?.end
            guard let start = officialStart ?? (first <= ScheduleMath.starts.count ? ScheduleMath.starts[first - 1] : nil),
                  let end = officialEnd ?? (last <= ScheduleMath.ends.count ? ScheduleMath.ends[last - 1] : nil) else { unmapped += 1; return nil }
            return Course(name: row.name, teacher: row.teacher, room: row.room, day: row.weekday, start: start, end: end, period: row.periods + "节", weeks: weeks, color: "purple", startPeriod: first, endPeriod: last, notes: "学校同步", source: "school", externalID: row.id)
        }
        courses = school + personalCourses
        academicProfile = value.profile
        grades = (value.grades ?? []).map { GradeRecord(name: $0.name, score: $0.scoreText, credit: $0.credit.map { String(format: "%g", $0) } ?? "", term: $0.term, kind: $0.kind, schoolGPA: $0.gpa, courseCode: $0.courseCode, recordId: $0.recordId, year: $0.year, termCode: $0.termCode, examType: $0.examType) }
        exams = (value.exams ?? []).map { ExamRecord(name: $0.name, date: $0.date, time: $0.time, room: $0.room, seat: $0.seat) }
        practice = value.practice ?? []; semesters = value.semesters
        lastSynced = value.moduleUpdatedAt["timetable"]
        refreshWidget()
        if unmapped > 0 { message = "有 \(unmapped) 条学校课程的周次或节次暂无法展示，原始同步记录已保留，请对照官方课表。" }
    }
    func week(for date: Date) -> Int { ScheduleMath.week(on: date, start: isConnected ? schoolSemesterStart : semesterStart) }
    func courses(on date: Date) -> [Course] {
        let day = ScheduleMath.weekday(on: date)
        return courses.filter {
            $0.day == day && $0.weeks.contains(ScheduleMath.week(on: date, start: $0.source == "school" ? schoolSemesterStart : semesterStart))
        }.sorted { $0.start < $1.start }
    }
    private func commitPersonal(courses nextCourses: [Course], tasks nextTasks: [CampusTask], semesterStart nextStart: Date,
                                schedule: AndroidScheduleState?, schoolStart: Date? = nil) throws {
        guard loadedPersonal, let storage else { throw ProtectedStorage.Failure.unavailable }
        let nextTasks = try TaskRules.validatedTasks(nextTasks)
        let backup = PersonalBackup(courses: nextCourses, tasks: nextTasks, semesterStart: nextStart, personalSchedule: schedule)
        _ = try backup.encode() // Bound the whole transaction so every stored record remains exportable.
        let nextSchoolStart = schoolStart ?? schoolSemesterStart
        guard TaskRules.validDate(nextSchoolStart) else { throw PersonalBackup.Failure.invalid }
        try storage.write(PersonalData(version: 2, courses: nextCourses, tasks: nextTasks, semesterStart: nextStart,
                                       personalSchedule: schedule, schoolSemesterStart: nextSchoolStart), name: "personal")
        personalSchedule = schedule; personalCourses = nextCourses; tasks = nextTasks
        semesterStart = nextStart; schoolSemesterStart = nextSchoolStart
        courses = courses.filter { $0.source != "personal" } + nextCourses
        refreshReminders()
    }
    func saveTask(_ task: CampusTask) throws {
        var value = try TaskRules.validated(task)
        var next = tasks
        if let index = next.firstIndex(where: { $0.id == value.id }) {
            let previous = next[index]
            value.createdAt = previous.createdAt
            value.generatedFrom = previous.generatedFrom; value.seriesID = previous.seriesID
            value.originalID = previous.originalID; value.generatedFromOriginalID = previous.generatedFromOriginalID
            value.seriesOriginalID = previous.seriesOriginalID
            value.updatedAt = Date(); next[index] = value
        } else { value.updatedAt = Date(); next.append(value) }
        try commitPersonal(courses: personalCourses, tasks: next, semesterStart: semesterStart, schedule: personalSchedule)
    }
    func toggleTask(_ id: UUID) {
        guard let current = tasks.first(where: { $0.id == id }) else { return }
        do {
            let next = try TaskRules.settingCompleted(tasks, id: id, completed: !current.completed)
            try commitPersonal(courses: personalCourses, tasks: next, semesterStart: semesterStart, schedule: personalSchedule)
        } catch { message = error.localizedDescription }
    }
    func addTask(title: String, date: Date) {
        do { try saveTask(CampusTask(title: title, date: date)) } catch { message = error.localizedDescription }
    }
    func deleteTask(_ id: UUID) {
        do { try commitPersonal(courses: personalCourses, tasks: tasks.filter { $0.id != id }, semesterStart: semesterStart, schedule: personalSchedule) }
        catch { message = error.localizedDescription }
    }
    func savePersonalSchedule(_ state: AndroidScheduleState) throws {
        let next = try state.validated()
        let projection = try PersonalSemesterRules.activeCourses(in: next)
        let start = try BackupValue.dayDate(PersonalSemesterRules.activeSemester(in: next).weekStartDate)
        try commitPersonal(courses: projection, tasks: tasks, semesterStart: start, schedule: next)
    }
    func saveCourse(_ course: Course) throws {
        if let state = personalSchedule { try savePersonalSchedule(PersonalSemesterRules.upsertFlatCourse(course, in: state)) }
        else {
            var next = personalCourses.filter { $0.id != course.id }; next.append(course)
            try commitPersonal(courses: next, tasks: tasks, semesterStart: semesterStart, schedule: nil)
        }
    }
    func addCourse(_ course: Course) { do { try saveCourse(course) } catch { message = error.localizedDescription } }
    func deleteCourse(_ id: UUID) {
        guard personalCourses.contains(where: { $0.id == id }) else { return }
        do {
            if let state = personalSchedule { try savePersonalSchedule(PersonalSemesterRules.deleteFlatCourse(id: id, in: state)) }
            else { try commitPersonal(courses: personalCourses.filter { $0.id != id }, tasks: tasks, semesterStart: semesterStart, schedule: nil) }
        } catch { message = error.localizedDescription }
    }
    func makePersonalBackup() throws -> PersonalBackup {
        guard loadedPersonal else { throw ProtectedStorage.Failure.unavailable }
        let backup = PersonalBackup(courses: personalCourses, tasks: tasks, semesterStart: semesterStart, personalSchedule: personalSchedule)
        try backup.validate(); return backup
    }
    func restorePersonalBackup(_ backup: PersonalBackup) throws {
        try backup.validate()
        // A v1 snapshot can remain in legacy form if its dates/weeks cannot be migrated without changes.
        let state = try backup.personalSchedule?.validated()
        try commitPersonal(courses: backup.courses, tasks: backup.tasks, semesterStart: backup.semesterStart, schedule: state)
    }
    func restoreAndroidSchedule(_ plan: AndroidScheduleImportPlan, semesterID: String) throws {
        var next = try plan.state.validated()
        next.activeSemesterId = semesterID // Preserve Android metadata; native notification consent is separate.
        try savePersonalSchedule(next)
    }
    func mergeAndroidTasks(_ plan: AndroidTaskImportPlan) throws -> AndroidTaskMergePreview {
        let result = try plan.merge(into: tasks)
        try commitPersonal(courses: personalCourses, tasks: result.tasks, semesterStart: semesterStart, schedule: personalSchedule)
        return result
    }
    func refreshReminders() {
        reminders.reconcile(courses: personalCourses, tasks: tasks, semesterStart: semesterStart)
        refreshWidget()
    }
    func refreshWidget() { widget.publish(courses: courses, semesterStart: semesterStart, schoolSemesterStart: schoolSemesterStart) }
    func importPersonalCourses(_ incoming: [Course]) throws {
        if let state = personalSchedule { try savePersonalSchedule(PersonalSemesterRules.importFlatCourses(incoming, replacingActive: false, in: state)) }
        else { try commitPersonal(courses: personalCourses + incoming, tasks: tasks, semesterStart: semesterStart, schedule: nil) }
    }
    func replacePersonalCourses(_ incoming: [Course]) throws {
        if let state = personalSchedule { try savePersonalSchedule(PersonalSemesterRules.importFlatCourses(incoming, replacingActive: true, in: state)) }
        else { try commitPersonal(courses: incoming, tasks: tasks, semesterStart: semesterStart, schedule: nil) }
    }
    func calibrateLegacyPersonalStart(_ date: Date) throws {
        let start = ScheduleMath.calendar.startOfDay(for: date)
        let state = try PersonalSemesterRules.migrateLegacy(courses: personalCourses, semesterStart: start)
        try savePersonalSchedule(state)
    }
    func calibrateSchoolStart(_ date: Date) {
        guard ScheduleMath.weekday(on: date) == 1 else { message = "学校第一教学周请选星期一。"; return }
        do { try commitPersonal(courses: personalCourses, tasks: tasks, semesterStart: semesterStart, schedule: personalSchedule,
                                schoolStart: ScheduleMath.calendar.startOfDay(for: date)) }
        catch { message = error.localizedDescription }
    }
}
