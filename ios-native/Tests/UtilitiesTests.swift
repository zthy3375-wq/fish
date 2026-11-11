import XCTest
@testable import Hanyuantong

final class UtilitiesTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testRemindersAreOptIn() {
        let task = CampusTask(title: "synthetic", date: Date().addingTimeInterval(1000))
        XCTAssertTrue(NativeReminderPlan.make(courses: [], tasks: [task], semesterStart: Date(), preferences: ReminderPreferences()).isEmpty)
    }
    func testCompletedAndPastTasksNeverScheduled() {
        let now = date("2026-11-11T00:00:00Z")
        let tasks = [CampusTask(title: "done", date: now.addingTimeInterval(600), completed: true), CampusTask(title: "past", date: now.addingTimeInterval(-600)), CampusTask(title: "future", date: now.addingTimeInterval(1200))]
        let plan = NativeReminderPlan.make(courses: [], tasks: tasks, semesterStart: now, preferences: ReminderPreferences(tasks: true), now: now)
        XCTAssertEqual(plan.count, 1); XCTAssertTrue(plan[0].title.contains("future"))
    }
    func testSchoolDataExcludedAndShanghaiTimePreserved() {
        let monday = date("2026-09-13T16:00:00Z")
        let course = Course(name: "synthetic", day: 1, start: "08:00", end: "09:00", weeks: [1])
        var school = course; school.id = UUID(); school.source = "school"
        let plan = NativeReminderPlan.make(courses: [course, school], tasks: [], semesterStart: monday, preferences: ReminderPreferences(courses: true), now: monday)
        XCTAssertEqual(plan.count, 1); XCTAssertEqual(plan[0].date, date("2026-09-13T23:50:00Z"))
    }
    func testTaskLimitAndStableIdentifiers() {
        let now = date("2026-11-11T00:00:00Z")
        let tasks = (1...100).map { CampusTask(title: "task \($0)", date: now.addingTimeInterval(Double($0) * 60)) }
        let first = NativeReminderPlan.make(courses: [], tasks: tasks, semesterStart: now, preferences: ReminderPreferences(tasks: true), now: now)
        let second = NativeReminderPlan.make(courses: [], tasks: Array(tasks.reversed()), semesterStart: now, preferences: ReminderPreferences(tasks: true), now: now)
        XCTAssertEqual(first.count, 30); XCTAssertEqual(first, second)
    }
    func testCombinedNotificationBudget() {
        let monday = date("2026-09-13T16:00:00Z")
        let courses = (1...10).map { Course(name: "course \($0)", day: 1, start: "08:00", end: "09:00", weeks: Array(1...60)) }
        let tasks = (1...40).map { CampusTask(title: "task \($0)", date: monday.addingTimeInterval(Double($0) * 600)) }
        XCTAssertEqual(NativeReminderPlan.make(courses: courses, tasks: tasks, semesterStart: monday, preferences: ReminderPreferences(courses: true, tasks: true), now: monday).count, 60)
    }
    func testFixedDestinationsAreHTTPSOnly() {
        XCTAssertEqual(NativeDestinations.taobao.scheme, "https")
        XCTAssertEqual(NativeDestinations.taobao.host, "pages-fast.m.taobao.com")
        XCTAssertEqual(NativeDestinations.pinduoduo.absoluteString, "https://mobile.yangkeduo.com/")
    }
    func testWidgetWeekAndDayUseShanghai() {
        let monday = date("2026-09-13T16:00:00Z")
        let course = WidgetCourse(id: "synthetic", title: "测试", room: "", day: 1, start: "08:00", end: "09:00", weeks: [1, 3])
        let snapshot = WidgetSnapshot(version: 1, generatedAt: monday, semesterStart: monday, courses: [course])
        XCTAssertEqual(snapshot.today(monday).count, 1)
        XCTAssertTrue(snapshot.today(monday.addingTimeInterval(7 * 86400)).isEmpty)
        XCTAssertEqual(snapshot.today(monday.addingTimeInterval(14 * 86400)).count, 1)
        XCTAssertTrue(snapshot.today(monday.addingTimeInterval(-1)).isEmpty)
    }

    @MainActor func testWidgetCleanupIgnoresUnreadablePreference() {
        var exists = true
        let persistence = WidgetPersistence(readPreference: { throw WidgetSnapshotFile.Failure.unavailable }, savePreference: { _ in }, writeSnapshot: { _ in }, removeSnapshot: { exists = false }, reload: {})
        let publisher = NativeWidgetPublisher(persistence: persistence)
        XCTAssertFalse(publisher.enabled)
        XCTAssertTrue(publisher.clearForAccountChange())
        XCTAssertFalse(exists)
    }
    @MainActor func testWidgetFailedEnableRollsBackSnapshot() {
        var exists = false
        let persistence = WidgetPersistence(readPreference: { false }, savePreference: { _ in throw WidgetSnapshotFile.Failure.unavailable }, writeSnapshot: { _ in exists = true }, removeSnapshot: { exists = false }, reload: {})
        let publisher = NativeWidgetPublisher(persistence: persistence)
        publisher.change(true, courses: [], semesterStart: Date())
        XCTAssertFalse(publisher.enabled)
        XCTAssertFalse(exists)
    }

}
