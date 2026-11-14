import XCTest
@testable import Hanyuantong

/// Synthetic, pure planner regressions. No accounts, permission prompts or delivered notifications.
final class AgendaParityTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T04:00:00Z")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func task(_ title: String = "读一章书") -> CampusTask { TaskRules.makeTask(title: title, now: now) }
    private func planned(_ value: String = "2026-11-06T01:00:00Z") -> CampusTask {
        var result = task(); result.plannedAt = date(value); return result
    }
    private func repeating(_ kind: TaskRepeatKind, interval: Int = 1, weekdays: [Int] = [1, 3]) -> CampusTask {
        var value = planned()
        value.repeatRule = TaskRepeatRule(kind: kind, interval: interval, weekdays: weekdays)
        return value
    }

    func testPickerSelectionDropsOnlyHiddenSecondsAndIsIdempotent() {
        let selected = now.addingTimeInterval(59.875)
        XCTAssertEqual(TaskRules.pickerMinute(selected), now)
        XCTAssertEqual(TaskRules.pickerMinute(TaskRules.pickerMinute(selected)), now)
        XCTAssertEqual(TaskRules.pickerMinute(now), now)
        let prior = date("2026-11-05T15:59:59Z").addingTimeInterval(0.75)
        XCTAssertEqual(TaskRules.pickerMinute(prior), date("2026-11-05T15:59:00Z"))
        XCTAssertEqual(TaskClock.day(TaskRules.pickerMinute(prior)), "2026-11-05")
    }
    func testNewReminderDefaultsRoundUpWithoutFiringEarly() {
        let fractionalNow = now.addingTimeInterval(12.75)
        for minutes in [10, 30, 60] {
            let value = TaskRules.futurePickerMinute(minutes: minutes, now: fractionalNow)
            XCTAssertEqual(value, now.addingTimeInterval(Double(minutes + 1) * 60))
            XCTAssertGreaterThanOrEqual(value.timeIntervalSince(fractionalNow), Double(minutes) * 60)
            XCTAssertEqual(value, TaskRules.pickerMinute(value))
            XCTAssertEqual(TaskRules.futurePickerMinute(minutes: minutes, now: now), now.addingTimeInterval(Double(minutes) * 60))
        }
        XCTAssertEqual(TaskRules.futurePickerMinute(minutes: 10, now: date("2026-11-05T15:55:59Z")), date("2026-11-05T16:06:00Z"))
    }
    func testValidationAndUnrelatedEditsKeepExistingImportedPrecision() throws {
        var value = task()
        value.plannedAt = now.addingTimeInterval(12.125)
        value.deadline = now.addingTimeInterval(3612.25)
        value.snoozedUntil = now.addingTimeInterval(612.5)
        value.reminders = [TaskReminder(anchor: .absolute, minutes: 0, at: now.addingTimeInterval(1212.75))]
        value.createdAt = now.addingTimeInterval(-0.875); value.updatedAt = now.addingTimeInterval(0.125)
        value.completedAt = now.addingTimeInterval(-0.25)
        value.notes = "Only the note was edited"
        let clean = try TaskRules.validated(value)
        let decoded = try JSONDecoder().decode(CampusTask.self, from: JSONEncoder().encode(clean))
        XCTAssertEqual(decoded.plannedAt, value.plannedAt); XCTAssertEqual(decoded.deadline, value.deadline)
        XCTAssertEqual(decoded.snoozedUntil, value.snoozedUntil); XCTAssertEqual(decoded.reminders[0].at, value.reminders[0].at)
        XCTAssertEqual(decoded.createdAt, value.createdAt); XCTAssertEqual(decoded.updatedAt, value.updatedAt)
        XCTAssertEqual(decoded.completedAt, value.completedAt)
        XCTAssertThrowsError(try AndroidTaskImportPlan.export(tasks: [clean], now: now))
    }
    func testNewPickerMinuteValuesExportWithoutTruncatingMetadata() throws {
        let fractionalNow = now.addingTimeInterval(12.75)
        var value = TaskRules.makeTask(title: "Minute precision", now: fractionalNow)
        value.plannedAt = TaskRules.pickerMinute(fractionalNow.addingTimeInterval(60))
        value.deadline = TaskRules.futurePickerMinute(minutes: 60, now: fractionalNow)
        value.snoozedUntil = TaskRules.futurePickerMinute(minutes: 10, now: fractionalNow)
        value.reminders = [TaskReminder(anchor: .absolute, minutes: 0, at: TaskRules.futurePickerMinute(minutes: 30, now: fractionalNow))]
        let data = try AndroidTaskImportPlan.export(tasks: [value], now: fractionalNow)
        guard case .androidTasks(let imported) = try PersonalBackupImport.parse(data) else { return XCTFail("Expected Android tasks") }
        XCTAssertEqual(imported.tasks[0].plannedAt, value.plannedAt); XCTAssertEqual(imported.tasks[0].deadline, value.deadline)
        XCTAssertEqual(imported.tasks[0].snoozedUntil, value.snoozedUntil); XCTAssertEqual(imported.tasks[0].reminders[0].at, value.reminders[0].at)
        XCTAssertEqual(imported.tasks[0].createdAt, fractionalNow); XCTAssertEqual(imported.tasks[0].updatedAt, fractionalNow)
    }
    func testQuickCaptureIsUnplannedAndDoesNotInventDeadlineOrReminder() throws {
        let value = try TaskRules.validated(task())
        XCTAssertNil(value.plannedAt); XCTAssertNil(value.plannedDay); XCTAssertNil(value.deadline)
        XCTAssertFalse(value.legacyReminder); XCTAssertEqual(value.reminders, [])
        XCTAssertEqual(TaskRules.select([value], filter: TaskFilter(scope: .inbox), now: now).count, 1)
        XCTAssertEqual(TaskRules.reminderCandidates([value], now: now), [])
    }
    func testOldNativeCacheDecodesIntoPlanWithoutDeadline() throws {
        let id = UUID()
        let data = Data("""
        {"id":"\(id.uuidString)","title":"旧待办","date":815457600,"completed":true,"notes":"保留备注"}
        """.utf8)
        let value = try JSONDecoder().decode(CampusTask.self, from: data)
        XCTAssertEqual(value.id, id); XCTAssertEqual(value.notes, "保留备注")
        XCTAssertTrue(value.completed); XCTAssertTrue(value.legacyReminder)
        XCTAssertEqual(value.plannedAt, value.date); XCTAssertNil(value.deadline)
        XCTAssertEqual(value.priority, 0); XCTAssertEqual(value.durationMinutes, 30)
        XCTAssertEqual(value.steps, []); XCTAssertEqual(value.reminders, [])
        XCTAssertEqual(value.createdAt, value.date); XCTAssertEqual(value.updatedAt, value.date)
        XCTAssertEqual(value.schemaVersion, 2)
    }
    func testRichUnplannedCacheRoundTripCannotResurrectLegacyPlan() throws {
        let value = task()
        let decoded = try JSONDecoder().decode(CampusTask.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value); XCTAssertNil(decoded.plannedAt)
        XCTAssertFalse(decoded.legacyReminder)
    }
    func testRichRoundTripPreservesEveryPersonalField() throws {
        var value = repeating(.days)
        value.notes = "先做笔记"; value.course = "高数"; value.priority = 3; value.pinned = true; value.prepared = true
        value.deadline = date("2026-11-07T10:00:00Z"); value.durationMinutes = 90
        value.steps = [TaskStep(title: "第一步", completed: true, originalID: "android-step")]
        value.reminders = [TaskReminder(anchor: .deadline, minutes: 30, originalID: "android-reminder")]
        value.snoozedUntil = now.addingTimeInterval(600)
        value.originalID = "android-task"; value.generatedFrom = UUID(); value.seriesID = UUID()
        value.generatedFromOriginalID = "android-parent"; value.seriesOriginalID = "android-series"
        value.completedAt = now; value.completed = true
        let clean = try TaskRules.validated(value)
        let decoded = try JSONDecoder().decode(CampusTask.self, from: JSONEncoder().encode(clean))
        XCTAssertEqual(decoded, clean)
    }
    func testUnknownTaskSchemaFailsInsteadOfIgnoringMetadata() throws {
        let encoded = try JSONEncoder().encode(task())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(CampusTask.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    func testValidationRejectsInvalidRichFields() {
        var variants: [CampusTask] = []
        var value = task(); value.priority = 4; variants.append(value)
        value = task(); value.durationMinutes = 0; variants.append(value)
        value = task(); value.plannedDay = "2026-02-30"; variants.append(value)
        value = task(); value.repeatRule = TaskRepeatRule(kind: .daily); variants.append(value)
        value = planned(); value.repeatRule = TaskRepeatRule(kind: .days); variants.append(value)
        value = planned(); value.repeatRule = TaskRepeatRule(kind: .interval, interval: 366); variants.append(value)
        value = task(); value.steps = [TaskStep(title: " ")]; variants.append(value)
        value = task(); value.steps = Array(repeating: TaskStep(title: "重复编号"), count: 2); variants.append(value)
        value = task(); value.reminders = [TaskReminder(anchor: .absolute)]; variants.append(value)
        value = task(); value.reminders = [TaskReminder(anchor: .start, minutes: -1)]; variants.append(value)
        value = task(); value.reminders = Array(repeating: TaskReminder(anchor: .deadline), count: 2); variants.append(value)
        value = task(); value.reminders = (0..<6).map { _ in TaskReminder(anchor: .deadline) }; variants.append(value)
        value = task(); value.originalID = " "; variants.append(value)
        value = task(); value.snoozedUntil = Date(timeIntervalSince1970: .infinity); variants.append(value)
        value = task(); value.generatedFrom = value.id; variants.append(value)
        for (index, value) in variants.enumerated() { XCTAssertThrowsError(try TaskRules.validated(value), "variant \(index)") }
    }
    func testValidationNormalizesTrimDuplicateWeekdaysAndPlanPrecedence() throws {
        var value = repeating(.days, weekdays: [3, 1, 3])
        value.title = " 阅读 "; value.plannedDay = "2026-11-08"
        value.reminders = [TaskReminder(anchor: .deadline, minutes: 0, at: now)]
        let clean = try TaskRules.validated(value)
        XCTAssertEqual(clean.title, "阅读"); XCTAssertNil(clean.plannedDay)
        XCTAssertEqual(clean.repeatRule?.weekdays, [1, 3]); XCTAssertNil(clean.reminders[0].at)
        XCTAssertEqual(clean.date, clean.plannedAt)
    }
    func testNativeLegacyTextLimitsRemainReadable() throws {
        var value = task(String(repeating: "字", count: 200)); value.notes = String(repeating: "记", count: 4000)
        XCTAssertNoThrow(try TaskRules.validated(value))
        value.title.append("字"); XCTAssertThrowsError(try TaskRules.validated(value))
    }
    func testCollectionRejectsDuplicateAndExcessTasksWithoutChangingInput() {
        let value = task()
        XCTAssertThrowsError(try TaskRules.validatedTasks([value, value]))
        XCTAssertThrowsError(try TaskRules.validatedTasks(Array(repeating: value, count: 5001)))
        XCTAssertFalse(value.completed)
    }
    func testTodayUsesPlansAndIncludesUnfinishedEarlierDaysOnly() {
        var today = task("今天"); today.plannedDay = "2026-11-06"
        var missed = task("以前"); missed.plannedDay = "2026-11-04"
        var future = task("以后"); future.plannedDay = "2026-11-08"
        var deadlineOnly = task("仅截止"); deadlineOnly.deadline = now.addingTimeInterval(3600)
        var complete = today; complete.id = UUID(); complete.completed = true
        let selected = TaskRules.select([today, missed, future, deadlineOnly, complete], filter: TaskFilter(scope: .today), now: now)
        XCTAssertEqual(Set(selected.map(\.id)), Set([today.id, missed.id]))
        XCTAssertEqual(TaskRules.select([deadlineOnly], filter: TaskFilter(scope: .inbox), now: now).count, 1)
        XCTAssertEqual(TaskRules.select([deadlineOnly], filter: TaskFilter(scope: .due), now: now).count, 1)
    }
    func testBeijingMidnightAndDateOnlyValidation() {
        XCTAssertEqual(TaskClock.day(date("2026-11-05T16:01:00Z")), "2026-11-06")
        XCTAssertEqual(TaskClock.start("2026-11-06"), date("2026-11-05T16:00:00Z"))
        for invalid in ["2026-2-01", "2026-02-29", "2026-00-01", "2026-13-01", "２０２６-01-01", "1999-12-31"] { XCTAssertNil(TaskClock.start(invalid)) }
        XCTAssertNotNil(TaskClock.start("2028-02-29"))
    }
    func testFiltersSearchNotesCoursePriorityAndCompletion() {
        var future = task("未来任务"); future.plannedDay = "2026-11-07"; future.course = "高数"; future.priority = 2; future.notes = "Review"
        var other = task("别的任务"); other.course = "英语"
        var completed = future; completed.id = UUID(); completed.completed = true
        let values = [future, other, completed]
        XCTAssertEqual(TaskRules.select(values, filter: TaskFilter(scope: .planned, search: " review ", course: "高数", priority: 2), now: now).map(\.id), [future.id])
        XCTAssertEqual(TaskRules.select(values, filter: TaskFilter(scope: .completed), now: now).map(\.id), [completed.id])
        XCTAssertEqual(TaskRules.select(values, filter: TaskFilter(scope: .all), now: now).count, 3)
        XCTAssertEqual(TaskRules.select(values, filter: TaskFilter(priority: 0), now: now).map(\.id), [other.id])
    }
    func testPinnedThenOverdueThenPriorityAndDeadlineOrdering() {
        var pinned = task("置顶"); pinned.pinned = true
        var overdue = task("逾期"); overdue.deadline = now.addingTimeInterval(-60)
        var high = task("高"); high.priority = 3
        var low = task("低"); low.priority = 1
        let selected = TaskRules.select([low, high, overdue, pinned], filter: TaskFilter(), now: now)
        XCTAssertEqual(selected.map(\.id), [pinned.id, overdue.id, high.id, low.id])
    }
    func testGroupingDoesNotCreatePlanForDeadlineOnlyTask() {
        var deadlineOnly = task(); deadlineOnly.deadline = now.addingTimeInterval(60)
        XCTAssertEqual(TaskRules.groups([deadlineOnly], filter: TaskFilter(), now: now).first?.title, "未安排")
        XCTAssertEqual(TaskRules.groups([deadlineOnly], filter: TaskFilter(scope: .due), now: now).first?.title, "今天")
        deadlineOnly.course = "高数"
        XCTAssertEqual(TaskRules.groups([deadlineOnly], filter: TaskFilter(groupByCourse: true), now: now).first?.title, "高数")
    }
    func testReplanPreservesClockDeadlineAndCourseAndClearsSnooze() throws {
        var value = planned("2026-11-04T06:00:00Z")
        value.deadline = date("2026-11-06T10:00:00Z"); value.course = "高数"; value.snoozedUntil = now
        let result = try TaskRules.replanned(value, day: "2026-11-07", now: now)
        XCTAssertEqual(result.plannedAt, date("2026-11-07T06:00:00Z"))
        XCTAssertEqual(result.deadline, value.deadline); XCTAssertEqual(result.course, value.course); XCTAssertNil(result.snoozedUntil)
        XCTAssertEqual(value.plannedAt, date("2026-11-04T06:00:00Z"))
    }
    func testDateOnlyReplanAndRepeatNeverInventClockTime() throws {
        var value = task(); value.plannedDay = "2026-11-06"; value.repeatRule = TaskRepeatRule(kind: .daily)
        let next = try XCTUnwrap(TaskRules.nextOccurrence(value, now: now))
        XCTAssertNil(next.plannedAt); XCTAssertEqual(next.plannedDay, "2026-11-07")
        let replanned = try TaskRules.replanned(value, day: "2026-11-08", now: now)
        XCTAssertNil(replanned.plannedAt); XCTAssertEqual(replanned.plannedDay, "2026-11-08")
    }
    func testEachRepeatRuleGeneratesCorrectNextFutureOccurrence() throws {
        let cases: [(TaskRepeatKind, String)] = [(.daily, "2026-11-07T01:00:00Z"), (.weekdays, "2026-11-09T01:00:00Z"), (.weekly, "2026-11-13T01:00:00Z"), (.days, "2026-11-09T01:00:00Z"), (.interval, "2026-11-09T01:00:00Z")]
        for (kind, expected) in cases {
            let next = try XCTUnwrap(TaskRules.nextOccurrence(repeating(kind, interval: 3), now: now))
            XCTAssertEqual(next.plannedAt, date(expected), kind.rawValue); XCTAssertFalse(next.completed)
        }
    }
    func testRepeatSkipsBacklogPreservesGapAndResetsStepsAndPrepared() throws {
        var value = repeating(.interval, interval: 3)
        value.plannedAt = date("2026-10-01T01:00:00Z"); value.deadline = date("2026-10-02T10:00:00Z")
        value.steps = [TaskStep(title: "练习", completed: true)]; value.prepared = true; value.snoozedUntil = now
        value.reminders = [TaskReminder(anchor: .absolute, minutes: 0, at: date("2026-10-01T00:30:00Z"))]
        let next = try XCTUnwrap(TaskRules.nextOccurrence(value, now: now))
        XCTAssertEqual(next.plannedAt, date("2026-11-09T01:00:00Z")); XCTAssertEqual(next.deadline, date("2026-11-10T10:00:00Z"))
        XCTAssertEqual(next.reminders[0].at, date("2026-11-09T00:30:00Z"))
        XCTAssertFalse(next.steps[0].completed); XCTAssertFalse(next.prepared); XCTAssertNil(next.snoozedUntil)
    }
    func testRepeatCrossesYearBoundaryAndHasStableIdentity() throws {
        var value = repeating(.daily); value.plannedAt = date("2026-12-31T01:00:00Z"); value.deadline = date("2027-01-02T10:00:00Z")
        let next = try XCTUnwrap(TaskRules.nextOccurrence(value, now: date("2026-12-31T04:00:00Z")))
        XCTAssertEqual(next.plannedAt, date("2027-01-01T01:00:00Z")); XCTAssertEqual(next.deadline, date("2027-01-03T10:00:00Z"))
        XCTAssertEqual(try TaskRules.nextOccurrence(value, now: date("2026-12-31T04:00:00Z"))?.id, next.id)
        XCTAssertEqual(next.seriesID, value.id); XCTAssertEqual(next.generatedFrom, value.id)
    }
    func testCompletionIsIdempotentAndUndoRemovesOnlyUntouchedNext() throws {
        let value = try TaskRules.validated(repeating(.daily))
        let once = try TaskRules.settingCompleted([value], id: value.id, completed: true, now: now)
        let twice = try TaskRules.settingCompleted(once, id: value.id, completed: true, now: now.addingTimeInterval(1))
        XCTAssertEqual(once, twice); XCTAssertEqual(once.count, 2); XCTAssertEqual(once[0].completedAt, now)
        let undone = try TaskRules.settingCompleted(once, id: value.id, completed: false, now: now.addingTimeInterval(60))
        XCTAssertEqual(undone.count, 1); XCTAssertFalse(undone[0].completed); XCTAssertNil(undone[0].completedAt)
        XCTAssertFalse(value.completed)
    }
    func testUndoCannotDestroyEditedOrCompletedNextTask() throws {
        let value = repeating(.daily)
        let result = try TaskRules.settingCompleted([value], id: value.id, completed: true, now: now)
        var edited = result; edited[1].updatedAt = now.addingTimeInterval(1)
        XCTAssertThrowsError(try TaskRules.settingCompleted(edited, id: value.id, completed: false, now: now))
        var sameTimestamp = result; sameTimestamp[1].notes = "同一秒内编辑"
        XCTAssertThrowsError(try TaskRules.settingCompleted(sameTimestamp, id: value.id, completed: false, now: now))
        var completed = result; completed[1].completed = true
        XCTAssertThrowsError(try TaskRules.settingCompleted(completed, id: value.id, completed: false, now: now))
        XCTAssertTrue(edited[0].completed); XCTAssertEqual(edited.count, 2)
    }
    func testUndoHandlesImportedChildBeforeParentOrder() throws {
        let value = repeating(.daily)
        let result = try TaskRules.settingCompleted([value], id: value.id, completed: true, now: now)
        let reversed = Array(result.reversed())
        let undone = try TaskRules.settingCompleted(reversed, id: value.id, completed: false, now: now)
        XCTAssertEqual(undone.count, 1); XCTAssertEqual(undone[0].id, value.id); XCTAssertFalse(undone[0].completed)
    }
    func testUntouchedImportedRepeatIdentityCanBeUndone() throws {
        var value = repeating(.daily); value.originalID = "android-root"
        var result = try TaskRules.settingCompleted([value], id: value.id, completed: true, now: now)
        result[1].id = UUID(); result[1].originalID = "android-occurrence-id"
        let undone = try TaskRules.settingCompleted(result, id: value.id, completed: false, now: now)
        XCTAssertEqual(undone.count, 1); XCTAssertFalse(undone[0].completed)
    }
    private func importedRepeatPair() throws -> [CampusTask] {
        let stamp = "2026-11-06T04:00:00.000Z"
        func record(id: String, day: String, completed: Bool) -> [String: Any] {
            ["id": id, "title": "合成每日练习", "course": "合成课程", "notes": "先复习再练习",
             "plannedAt": day + "T09:00", "deadline": day + "T18:00", "completed": completed,
             "completedAt": completed ? stamp as Any : NSNull(), "remindMinutes": 30,
             "createdAt": stamp, "updatedAt": stamp,
             "steps": [["id": "android-step-a", "title": "复习", "completed": completed],
                       ["id": "android-step-b", "title": "练习", "completed": completed]] as [[String: Any]],
             "reminders": [["id": "android-reminder-absolute", "anchor": "absolute", "minutes": 0, "at": day + "T08:30"],
                           ["id": "android-reminder-deadline", "anchor": "deadline", "minutes": 30]] as [[String: Any]],
             "repeat": ["kind": "daily", "interval": 1, "weekdays": []] as [String: Any]]
        }
        let parent = record(id: "android-parent", day: "2026-11-06", completed: true)
        var child = record(id: "android-next-occurrence", day: "2026-11-07", completed: false)
        child["generatedFrom"] = "android-parent"; child["seriesId"] = "android-parent"
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "tasks": [parent, child], "notificationsEnabled": false, "updatedAt": stamp])
        guard case .androidTasks(let plan) = try PersonalBackupImport.parse(data) else { throw TaskRules.Failure("测试导入格式无效") }
        return plan.tasks
    }
    func testUndoImportedAndroidRepeatWithNamespacedStepsAndReminders() throws {
        let tasks = try importedRepeatPair()
        XCTAssertNotEqual(tasks[0].steps[0].id, tasks[1].steps[0].id)
        XCTAssertEqual(tasks[0].steps[0].originalID, tasks[1].steps[0].originalID)
        XCTAssertNotEqual(tasks[0].reminders[0].id, tasks[1].reminders[0].id)
        XCTAssertEqual(tasks[0].reminders[0].originalID, tasks[1].reminders[0].originalID)
        let undone = try TaskRules.settingCompleted(tasks, id: tasks[0].id, completed: false, now: now)
        XCTAssertEqual(undone.count, 1); XCTAssertEqual(undone[0].id, tasks[0].id)
        XCTAssertFalse(undone[0].completed); XCTAssertNil(undone[0].completedAt)
        XCTAssertTrue(tasks[0].completed); XCTAssertEqual(tasks.count, 2)
    }
    func testImportedRepeatAliasNormalizationStillRejectsEveryContentEdit() throws {
        let tasks = try importedRepeatPair()
        var variants: [[CampusTask]] = []
        var value = tasks; value[1].steps[0].title = "修改步骤"; variants.append(value)
        value = tasks; value[1].steps[0].completed = true; variants.append(value)
        value = tasks; value[1].steps.swapAt(0, 1); variants.append(value)
        value = tasks; value[1].steps[0].originalID = "different-step"; variants.append(value)
        value = tasks; value[1].steps[0].originalID = nil; variants.append(value)
        value = tasks; value[1].reminders[1].minutes = 60; variants.append(value)
        value = tasks; value[1].reminders[1].anchor = .start; variants.append(value)
        value = tasks; value[1].reminders[0].at = value[1].reminders[0].at?.addingTimeInterval(60); variants.append(value)
        value = tasks; value[1].reminders.swapAt(0, 1); variants.append(value)
        value = tasks; value[1].reminders[0].originalID = "different-reminder"; variants.append(value)
        value = tasks; value[1].notes = "同时间戳修改备注"; variants.append(value)
        value = tasks; value[1].updatedAt = now.addingTimeInterval(1); variants.append(value)
        value = tasks; value[1].completed = true; variants.append(value)
        for (index, variant) in variants.enumerated() {
            XCTAssertThrowsError(try TaskRules.settingCompleted(variant, id: tasks[0].id, completed: false, now: now), "edit \(index)")
            XCTAssertTrue(variant[0].completed); XCTAssertEqual(variant.count, 2)
        }
    }
    func testUndoStillRejectsChangedNativeElementIDsWithoutAliases() throws {
        var parent = repeating(.daily)
        parent.steps = [TaskStep(title: "本机步骤")]
        parent.reminders = [TaskReminder(anchor: .start, minutes: 0)]
        let tasks = try TaskRules.settingCompleted([parent], id: parent.id, completed: true, now: now)
        var changedStep = tasks; changedStep[1].steps[0].id = UUID()
        XCTAssertThrowsError(try TaskRules.settingCompleted(changedStep, id: parent.id, completed: false, now: now))
        var changedReminder = tasks; changedReminder[1].reminders[0].id = UUID()
        XCTAssertThrowsError(try TaskRules.settingCompleted(changedReminder, id: parent.id, completed: false, now: now))
    }
    func testReminderAnchorsDeduplicateAndSortByInstant() {
        var value = task(); value.plannedAt = date("2026-11-06T08:00:00Z"); value.deadline = date("2026-11-06T10:00:00Z")
        value.reminders = [TaskReminder(anchor: .start, minutes: 30), TaskReminder(anchor: .deadline, minutes: 0), TaskReminder(anchor: .absolute, minutes: 500, at: date("2026-11-06T07:30:00Z"))]
        let plan = TaskRules.reminderCandidates([value], now: now)
        XCTAssertEqual(plan.map(\.date), [date("2026-11-06T07:30:00Z"), date("2026-11-06T10:00:00Z")])
        XCTAssertEqual(Set(plan.map(\.id)).count, 2)
        XCTAssertEqual(plan[0].taskID, value.id)
    }
    func testMissingAnchorsDateOnlyAndCompletedTasksProduceNoReminders() {
        var value = task(); value.plannedDay = "2026-11-06"
        value.reminders = [TaskReminder(anchor: .start), TaskReminder(anchor: .deadline)]
        XCTAssertEqual(TaskRules.reminderCandidates([value], now: now), [])
        value.snoozedUntil = now.addingTimeInterval(600)
        XCTAssertEqual(TaskRules.reminderCandidates([value], now: now).count, 1)
        value.completed = true
        XCTAssertEqual(TaskRules.reminderCandidates([value], now: now), [])
    }
    func testSnoozeValidationAndClearDoNotChangePlanOrDeadline() throws {
        let value = planned()
        let result = try TaskRules.snoozed(value, until: now.addingTimeInterval(600), now: now)
        XCTAssertEqual(result.plannedAt, value.plannedAt)
        XCTAssertNil(try TaskRules.snoozed(result, until: nil, now: now).snoozedUntil)
        XCTAssertThrowsError(try TaskRules.snoozed(value, until: now, now: now))
        var done = value; done.completed = true
        XCTAssertThrowsError(try TaskRules.snoozed(done, until: now.addingTimeInterval(600), now: now))
    }
    func testLegacyReminderFallbackOnlyForOldTimedTasksAndFutureLimit() {
        let legacy = CampusTask(title: "旧版计划", date: now.addingTimeInterval(3600))
        XCTAssertEqual(TaskRules.reminderCandidates([legacy], legacyMinutes: 10, now: now).first?.date, now.addingTimeInterval(3000))
        var modern = task(); modern.plannedAt = legacy.date
        XCTAssertEqual(TaskRules.reminderCandidates([modern], now: now), [])
        let values = (0..<40).map { index -> CampusTask in
            var value = task("任务\(index)"); value.snoozedUntil = now.addingTimeInterval(Double(index + 1) * 60); return value
        }
        XCTAssertEqual(TaskRules.reminderCandidates(values, now: now).count, 30)
        XCTAssertEqual(TaskRules.reminderCandidates(values, now: now, limit: 2).count, 2)
        XCTAssertEqual(TaskRules.reminderCandidates(values, now: now, limit: -1), [])
    }
}
