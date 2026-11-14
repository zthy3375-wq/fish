import XCTest
@testable import Hanyuantong

final class CampusStoreTests: XCTestCase {
    @MainActor private func withStore(_ body: (CampusStore, ProtectedStorage, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        try body(CampusStore(storage: storage), storage, directory)
    }
    @MainActor func testTaskEditsAndRichFieldsSurviveRelaunch() throws {
        try withStore { store, storage, _ in
            var task = TaskRules.makeTask(title: "合成待办", now: Date(timeIntervalSince1970: 1_800_000_000))
            task.steps = [TaskStep(title: "检查")]; task.priority = 3; task.pinned = true
            try store.saveTask(task)
            task.title = "修改后"; task.notes = "仅测试"; task.steps[0].completed = true
            try store.saveTask(task)
            let reopened = CampusStore(storage: storage)
            XCTAssertEqual(reopened.tasks.count, 1)
            XCTAssertEqual(reopened.tasks[0].title, "修改后")
            XCTAssertTrue(reopened.tasks[0].steps[0].completed)
            XCTAssertEqual(reopened.tasks[0].priority, 3)
            XCTAssertTrue(reopened.tasks[0].pinned)
        }
    }
    @MainActor func testFailedWriteDoesNotPublishTaskOrCourseChanges() throws {
        try withStore { store, _, directory in
            let task = TaskRules.makeTask(title: "保留任务")
            try store.saveTask(task)
            let previous = store.tasks
            try FileManager.default.removeItem(at: directory)
            XCTAssertThrowsError(try store.saveTask(TaskRules.makeTask(title: "不应保存")))
            XCTAssertEqual(store.tasks, previous)
            XCTAssertThrowsError(try store.saveCourse(Course(name: "不应保存", day: 1, start: "08:00", end: "09:00", weeks: [1])))
            XCTAssertTrue(store.courses.isEmpty)
            store.deleteTask(task.id)
            XCTAssertEqual(store.tasks, previous)
            XCTAssertNotNil(store.message)
        }
    }
    @MainActor func testPersonalSemesterSwitchKeepsIndependentSchoolStartAndAllTerms() throws {
        try withStore { store, storage, _ in
            let schoolStart = store.schoolSemesterStart
            var state = try XCTUnwrap(store.personalSchedule)
            let originalID = state.activeSemesterId
            let first = try PersonalSemesterRules.activeSemester(in: state)
            state.semesters.append(AndroidSemester(id: "synthetic-second", academicYear: "2027-2028", season: "秋季", startDate: "2027-09-13", weekStartDate: "2027-09-13", weekCount: 18, timeTableId: first.timeTableId))
            state.activeSemesterId = "synthetic-second"
            try store.savePersonalSchedule(state)
            XCTAssertEqual(store.schoolSemesterStart, schoolStart)
            XCTAssertNotEqual(store.semesterStart, schoolStart)
            let backup = try PersonalBackup.decode(store.makePersonalBackup().encode())
            XCTAssertEqual(backup.personalSchedule?.semesters.count, 2)
            let reopened = CampusStore(storage: storage)
            XCTAssertEqual(reopened.personalSchedule?.activeSemesterId, "synthetic-second")
            XCTAssertEqual(reopened.schoolSemesterStart, schoolStart)
            var restored = try XCTUnwrap(reopened.personalSchedule); restored.activeSemesterId = originalID
            try reopened.savePersonalSchedule(restored)
            XCTAssertEqual(reopened.personalSchedule?.semesters.count, 2)
        }
    }
    @MainActor func testUnknownPersistedVersionLocksWritesWithoutReplacingData() throws {
        struct Unsupported: Encodable {
            let version = 99
            let courses: [Course] = []
            let tasks: [CampusTask] = []
            let semesterStart = Date(timeIntervalSince1970: 1_800_000_000)
        }
        try withStore { _, storage, directory in
            try storage.write(Unsupported(), name: "personal")
            let file = directory.appendingPathComponent("personal.sealed")
            let original = try Data(contentsOf: file)
            let reopened = CampusStore(storage: storage)
            XCTAssertNotNil(reopened.message)
            XCTAssertThrowsError(try reopened.saveTask(TaskRules.makeTask(title: "不应覆盖")))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }
    func testNativeBackupValidatesCompleteManagedStateAndProjection() throws {
        let start = BackupValue.dayDate("2026-09-14")
        let state = try PersonalSemesterRules.migrateLegacy(courses: [Course(name: "合成课程", day: 1, start: "08:00", end: "09:00", weeks: [1, 3])], semesterStart: start)
        let courses = try PersonalSemesterRules.activeCourses(in: state)
        var backup = PersonalBackup(courses: courses, tasks: [], semesterStart: start, personalSchedule: state)
        XCTAssertEqual(try PersonalBackup.decode(backup.encode()).personalSchedule, state)
        backup.courses[0].name = "与规范状态不匹配"
        XCTAssertThrowsError(try backup.validate())
        backup.courses = courses; backup.semesterStart = start.addingTimeInterval(86400)
        XCTAssertThrowsError(try backup.validate())
    }
}
