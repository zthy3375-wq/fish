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
    @Published private(set) var exams: [ExamRecord] = []
    @Published var semesterStart = ScheduleMath.calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))! {
        didSet { if !restoringBackup { persistPersonal() } }
    }
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
    private var restoringBackup = false
    private struct PersonalData: Codable {
        let version: Int
        let courses: [Course]
        let tasks: [CampusTask]
        let semesterStart: Date
    }
    init() {
        do {
            let storage = try ProtectedStorage(); self.storage = storage
            if let saved = try storage.read("personal", as: PersonalData.self) {
                personalCourses = saved.courses.filter { $0.source == "personal" }
                tasks = saved.tasks; semesterStart = saved.semesterStart
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
        grades = (value.grades ?? []).map { GradeRecord(name: $0.name, score: $0.scoreText, credit: $0.credit.map { String(format: "%g", $0) } ?? "", term: $0.term, kind: $0.kind) }
        exams = (value.exams ?? []).map { ExamRecord(name: $0.name, date: $0.date, time: $0.time, room: $0.room, seat: $0.seat) }
        practice = value.practice ?? []; semesters = value.semesters
        lastSynced = value.moduleUpdatedAt["timetable"]
        refreshWidget()
        if unmapped > 0 { message = "有 \(unmapped) 条学校课程的周次或节次暂无法展示，原始同步记录已保留，请对照官方课表。" }
    }
    func week(for date: Date) -> Int { ScheduleMath.week(on: date, start: semesterStart) }
    func courses(on date: Date) -> [Course] {
        let currentWeek = week(for: date), day = ScheduleMath.weekday(on: date)
        return courses.filter { $0.day == day && $0.weeks.contains(currentWeek) }.sorted { $0.start < $1.start }
    }
    func toggleTask(_ id: UUID) {
        guard loadedPersonal else { message = "本机记录尚未安全读取，暂不能修改，请解锁设备后重新打开。"; return }
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed.toggle(); persistPersonal()
    }
    func addTask(title: String, date: Date) {
        guard loadedPersonal else { message = "本机记录尚未安全读取，暂不能修改，请解锁设备后重新打开。"; return }
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { message = "待办标题应为1–200个字。"; return }
        tasks.append(CampusTask(title: text, date: date)); persistPersonal()
    }
    func deleteTask(_ id: UUID) { guard loadedPersonal else { message = "本机记录尚未读取，暂不能修改。"; return }; tasks.removeAll { $0.id == id }; persistPersonal() }
    func addCourse(_ course: Course) {
        guard loadedPersonal else { message = "本机记录尚未安全读取，暂不能修改，请解锁设备后重新打开。"; return }
        guard course.source == "personal", !course.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...7).contains(course.day), course.start < course.end, !course.weeks.isEmpty else { message = "请检查课程名称、时间和周次。"; return }
        personalCourses.removeAll { $0.id == course.id }; personalCourses.append(course)
        courses.removeAll { $0.id == course.id }; courses.append(course); persistPersonal()
    }
    func deleteCourse(_ id: UUID) {
        guard loadedPersonal else { message = "本机记录尚未安全读取，暂不能修改，请解锁设备后重新打开。"; return }
        guard personalCourses.contains(where: { $0.id == id }) else { return }
        personalCourses.removeAll { $0.id == id }; courses.removeAll { $0.id == id }; persistPersonal()
    }
    func makePersonalBackup() throws -> PersonalBackup {
        guard loadedPersonal else { throw ProtectedStorage.Failure.unavailable }
        let backup = PersonalBackup(version: 1, courses: personalCourses, tasks: tasks, semesterStart: semesterStart)
        try backup.validate()
        return backup
    }
    func restorePersonalBackup(_ backup: PersonalBackup) throws {
        guard loadedPersonal, let storage else { throw ProtectedStorage.Failure.unavailable }
        try backup.validate()
        // Persist first: a failed write cannot replace the current in-memory record set.
        try storage.write(PersonalData(version: 1, courses: backup.courses, tasks: backup.tasks, semesterStart: backup.semesterStart), name: "personal")
        restoringBackup = true
        personalCourses = backup.courses; tasks = backup.tasks; semesterStart = backup.semesterStart
        courses = courses.filter { $0.source != "personal" } + personalCourses
        restoringBackup = false
        refreshReminders()
    }
    func refreshReminders() {
        reminders.reconcile(courses: personalCourses, tasks: tasks, semesterStart: semesterStart)
        refreshWidget()
    }
    func refreshWidget() { widget.publish(courses: courses, semesterStart: semesterStart) }
    func importPersonalCourses(_ incoming: [Course]) throws {
        var backup = try makePersonalBackup()
        backup.courses.append(contentsOf: incoming)
        try restorePersonalBackup(backup)
    }
    func replacePersonalCourses(_ incoming: [Course]) throws {
        var backup = try makePersonalBackup()
        backup.courses = incoming
        try restorePersonalBackup(backup)
    }
    private func persistPersonal() {
        guard loadedPersonal else { return }
        do {
            guard let storage else { throw ProtectedStorage.Failure.unavailable }
            try storage.write(PersonalData(version: 1, courses: personalCourses, tasks: tasks, semesterStart: semesterStart), name: "personal")
            refreshReminders()
        } catch { message = "个人数据未能保存，请解锁设备后重试。" }
    }
}
