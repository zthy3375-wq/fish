import XCTest
@testable import Hanyuantong

/// Entirely synthetic fixtures. Never place account exports or school/service responses in these tests.
final class BackupCompatibilityTests: XCTestCase {
    private let stamp = "2026-11-11T08:00:00.000Z"
    private func bytes(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    private func arrangement(_ id: String = "arrangement-a") -> [String: Any] {
        ["id": id, "day": 1, "startPeriod": 1, "endPeriod": 2, "start": "08:00", "end": "09:35", "room": "合成教室", "startWeek": 1, "endWeek": 19, "rule": "odd", "customWeeks": [], "timeMode": "custom"]
    }
    private func semester(_ id: String = "personal-autumn", table: String = "custom-times") -> [String: Any] {
        ["id": id, "academicYear": "2026–2027", "season": "秋季", "startDate": "2026-09-15", "weekStartDate": "2026-09-14", "weekCount": 19, "timeTableId": table]
    }
    private func table(_ id: String = "custom-times") -> [String: Any] {
        ["id": id, "name": "合成作息", "slots": [["number": 1, "start": "08:10", "end": "08:55"], ["number": 2, "start": "09:00", "end": "09:45"]]]
    }
    private func course(_ id: String = "course-a", semester: String = "personal-autumn") -> [String: Any] {
        ["id": id, "semesterId": semester, "name": "合成个人课程", "teacher": "", "color": "purple", "notes": "个人备注", "arrangements": [arrangement()]]
    }
    private func scheduleData() -> [String: Any] {
        ["version": 2, "timeTables": [table()], "mode": "personal", "activeSemesterId": "personal-autumn", "semesters": [semester()], "courses": [course()], "reminders": ["enabled": true, "minutes": 10], "updatedAt": stamp]
    }
    private func schedule(_ data: [String: Any]? = nil) -> [String: Any] {
        ["format": "handan-campus-schedule", "exportedAt": stamp, "data": data ?? scheduleData()]
    }
    private func task(_ id: String = "synthetic-task") -> [String: Any] {
        ["id": id, "title": "合成个人任务", "course": "合成课程", "deadline": "2026-11-12T18:30", "notes": "待办备注", "completed": false, "remindMinutes": 30, "createdAt": stamp, "updatedAt": stamp]
    }
    private func taskSnapshot(_ tasks: [[String: Any]]? = nil, version: Int = 2) -> [String: Any] {
        ["version": version, "tasks": tasks ?? [task()], "notificationsEnabled": true, "updatedAt": stamp]
    }
    private func parsedSchedule(_ data: [String: Any]? = nil) throws -> AndroidScheduleImportPlan {
        guard case .androidSchedule(let value) = try PersonalBackupImport.parse(bytes(schedule(data))) else { throw BackupCompatibilityFailure("测试格式无效") }
        return value
    }
    private func parsedTasks(_ records: [[String: Any]]? = nil, version: Int = 2) throws -> AndroidTaskImportPlan {
        guard case .androidTasks(let value) = try PersonalBackupImport.parse(bytes(taskSnapshot(records, version: version))) else { throw BackupCompatibilityFailure("测试格式无效") }
        return value
    }

    func testNativeVersionOneStillRoutesThroughOriginalDecoder() throws {
        let original: [String: Any] = ["version": 1, "courses": [], "tasks": [["id": UUID().uuidString, "title": "旧待办", "date": "2026-11-11T08:00:00Z", "completed": false, "notes": ""]], "semesterStart": "2026-09-13T16:00:00Z"]
        guard case .native(let value) = try PersonalBackupImport.parse(bytes(original)) else { return XCTFail("Native v1 must stay supported") }
        XCTAssertEqual(value.tasks.count, 1)
        XCTAssertEqual(value.tasks[0].plannedAt, value.tasks[0].date)
        XCTAssertTrue(value.tasks[0].legacyReminder)
    }

    func testSchedulePreservesAllSemestersTimeTablesAndArrangements() throws {
        var data = scheduleData()
        data["semesters"] = [semester(), semester("personal-spring", table: "other-times")]
        data["timeTables"] = [table(), table("other-times"), table("unused-personal-times")]
        var first = course(); first["arrangements"] = [arrangement(), arrangement("arrangement-b")]
        data["courses"] = [first, course("course-b", semester: "personal-spring")]
        let plan = try parsedSchedule(data)
        let selection = try plan.selection(semesterID: "personal-autumn")
        XCTAssertEqual(selection.courses.count, 2)
        XCTAssertEqual(selection.remainingSemesters.map(\.id), ["personal-spring"])
        XCTAssertEqual(plan.state.timeTables.count, 3)
        XCTAssertEqual(plan.state.courses.count, 2)
        XCTAssertTrue(selection.courses.allSatisfy { $0.source == "personal" && $0.externalID == nil })
        XCTAssertEqual(selection.courses[0].weeks, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19])
        XCTAssertTrue(selection.courseReminders.enabled)
        XCTAssertThrowsError(try plan.selection(semesterID: "missing"))
        guard case .androidSchedule(let roundTrip) = try PersonalBackupImport.parse(plan.exportData()) else { return XCTFail() }
        XCTAssertEqual(roundTrip.state, plan.state)
    }

    func testSchedulePeriodModeUsesSelectedTimeTableAndCustomModeKeepsClocks() throws {
        var data = scheduleData(), row = course(), period = arrangement()
        period["timeMode"] = "period"; row["arrangements"] = [period]; data["courses"] = [row]
        let plan = try parsedSchedule(data), projected = try plan.selection(semesterID: "personal-autumn").courses
        XCTAssertEqual(projected[0].start, "08:10"); XCTAssertEqual(projected[0].end, "09:45")
        XCTAssertEqual(try parsedSchedule().selection(semesterID: "personal-autumn").courses[0].start, "08:00")
        XCTAssertEqual(try plan.state.validated(), plan.state)
    }

    func testVersionOneScheduleUsesLegacyTablesAndRetainsOriginalCustomTimes() throws {
        var data = scheduleData(); data["version"] = 1; data.removeValue(forKey: "timeTables")
        var term = semester(); term.removeValue(forKey: "timeTableId"); data["semesters"] = [term]
        var row = course(), period = arrangement(); period.removeValue(forKey: "timeMode"); row["arrangements"] = [period]; data["courses"] = [row]
        let plan = try parsedSchedule(data)
        XCTAssertEqual(plan.sourceVersion, 1); XCTAssertEqual(plan.state.version, 2)
        XCTAssertEqual(plan.state.timeTables[0].id, "legacy-times-1")
        XCTAssertEqual(plan.state.timeTables[0].slots.count, 12)
        XCTAssertEqual(plan.state.courses[0].arrangements[0].timeMode, "custom")
        XCTAssertEqual(plan.state.courses[0].arrangements[0].start, "08:00")
        XCTAssertNoThrow(try plan.exportData())
    }

    func testKnownLegacySchoolPartitionsAreExcludedAndReported() throws {
        var data = scheduleData()
        data["semesters"] = [semester(), semester("school-page-synthetic", table: "school-times")]
        data["timeTables"] = [table(), table("school-times")]
        data["courses"] = [course(), course("school-record", semester: "school-page-synthetic")]
        data["activeSemesterId"] = "school-page-synthetic"
        let plan = try parsedSchedule(data)
        XCTAssertEqual(plan.excludedSchoolSemesters, 1); XCTAssertEqual(plan.excludedSchoolCourses, 1)
        XCTAssertEqual(plan.state.semesters.count, 1); XCTAssertEqual(plan.state.courses.count, 1)
        XCTAssertEqual(plan.state.timeTables.count, 1)
        XCTAssertFalse(String(decoding: try plan.exportData(), as: UTF8.self).contains("school-page-"))
        XCTAssertThrowsError(try AndroidScheduleState.parse(data), "Native state must reject school partitions instead of silently cleaning")
        data["semesters"] = [semester("school-page-synthetic", table: "school-times")]
        data["courses"] = [course("school-record", semester: "school-page-synthetic")]
        XCTAssertThrowsError(try parsedSchedule(data))
    }

    func testScheduleRejectsUnknownFieldsAtEveryRecordLevel() throws {
        var envelope = schedule(); envelope["cookies"] = "synthetic-only"
        XCTAssertThrowsError(try PersonalBackupImport.parse(bytes(envelope)))
        for level in ["state", "semester", "table", "slot", "course", "arrangement", "reminders"] {
            var data = scheduleData()
            switch level {
            case "state": data["account"] = "synthetic"
            case "semester": var row = semester(); row["cookie"] = "synthetic"; data["semesters"] = [row]
            case "table": var row = table(); row["cookie"] = "synthetic"; data["timeTables"] = [row]
            case "slot": var row = table(); row["slots"] = [["number": 1, "start": "08:00", "end": "08:45", "token": "synthetic"]]; data["timeTables"] = [row]
            case "course": var row = course(); row["source"] = "school"; data["courses"] = [row]
            case "arrangement": var row = course(), a = arrangement(); a["session"] = "synthetic"; row["arrangements"] = [a]; data["courses"] = [row]
            default: data["reminders"] = ["enabled": true, "minutes": 10, "token": "synthetic"] as [String: Any]
            }
            XCTAssertThrowsError(try parsedSchedule(data), level)
        }
    }

    func testMalformedScheduleReferencesRulesAndNumericTypesAreRejected() throws {
        var data = scheduleData(); data["version"] = true
        XCTAssertThrowsError(try parsedSchedule(data))
        data = scheduleData(); data["semesters"] = [semester(), semester()]
        XCTAssertThrowsError(try parsedSchedule(data))
        data = scheduleData(); data["courses"] = [course(), course()]
        XCTAssertThrowsError(try parsedSchedule(data))
        data = scheduleData(); data["activeSemesterId"] = "absent"
        XCTAssertThrowsError(try parsedSchedule(data))
        var term = semester(); term["weekStartDate"] = "2026-09-15"; data = scheduleData(); data["semesters"] = [term]
        XCTAssertThrowsError(try parsedSchedule(data))
        for (key, value) in [("day", 0), ("startWeek", 20), ("endWeek", 40), ("startPeriod", 0)] {
            data = scheduleData(); var row = course(), a = arrangement(); a[key] = value; row["arrangements"] = [a]; data["courses"] = [row]
            XCTAssertThrowsError(try parsedSchedule(data), key)
        }
        data = scheduleData(); var row = course(), a = arrangement(); a["timeMode"] = "period"; a["endPeriod"] = 3; row["arrangements"] = [a]; data["courses"] = [row]
        XCTAssertThrowsError(try parsedSchedule(data))
    }

    func testUnnumberedArrangementExportsExplicitNullPeriods() throws {
        var data = scheduleData(), row = course(), a = arrangement()
        a["startPeriod"] = NSNull(); a["endPeriod"] = NSNull(); row["arrangements"] = [a]; data["courses"] = [row]
        let plan = try parsedSchedule(data)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.exportData()) as? [String: Any])
        let exportedData = try XCTUnwrap(exported["data"] as? [String: Any]), records = try XCTUnwrap(exportedData["courses"] as? [[String: Any]])
        let arrangements = try XCTUnwrap(records[0]["arrangements"] as? [[String: Any]])
        XCTAssertTrue(arrangements[0]["startPeriod"] is NSNull)
        XCTAssertTrue(arrangements[0]["endPeriod"] is NSNull)
    }

    func testNativeScheduleConversionRoundTripsWithoutSchoolData() throws {
        let start = try BackupValue.localDate("2026-09-14T00:00")
        let original = Course(name: "合成自建课程", day: 2, start: "08:00", end: "09:00", weeks: [1, 3, 7])
        let plan = try AndroidScheduleImportPlan.fromNative(courses: [original], semesterStart: start)
        XCTAssertEqual(plan.state.courses[0].id, original.id.uuidString)
        XCTAssertEqual(plan.state.courses[0].arrangements[0].weeks, original.weeks)
        var invalid = original; invalid.source = "school"
        XCTAssertThrowsError(try AndroidScheduleImportPlan.fromNative(courses: [invalid], semesterStart: start))
        invalid = original; invalid.weeks = [41]
        XCTAssertThrowsError(try AndroidScheduleImportPlan.fromNative(courses: [invalid], semesterStart: start))
        invalid = original; invalid.notes = String(repeating: "n", count: 2001)
        XCTAssertThrowsError(try AndroidScheduleImportPlan.fromNative(courses: [invalid], semesterStart: start))
    }

    func testTaskVersionOneMapsLegacyDeadlineReminderWithoutInventingPlan() throws {
        let plan = try parsedTasks(version: 1), item = try XCTUnwrap(plan.tasks.first)
        XCTAssertNil(item.plannedAt); XCTAssertNil(item.plannedDay)
        XCTAssertEqual(item.deadline, try BackupValue.localDate("2026-11-12T18:30"))
        XCTAssertEqual(item.reminders.count, 1); XCTAssertEqual(item.reminders[0].anchor, .deadline)
        XCTAssertEqual(item.reminders[0].minutes, 30); XCTAssertEqual(item.reminders[0].originalID, "legacy")
        XCTAssertFalse(item.legacyReminder)
        XCTAssertEqual(item.originalID, "synthetic-task")
        XCTAssertEqual(try parsedTasks().tasks[0].id, item.id)
    }

    func testRichTasksPreserveSubtasksAllRemindersRepeatAndIdentifiers() throws {
        var record = task("arbitrary/android/id")
        record["plannedDay"] = "2026-11-11"; record["prepared"] = true; record["durationMinutes"] = 90; record["priority"] = 3; record["pinned"] = true
        record["steps"] = [["id": "step-not-a-uuid", "title": "第一步", "completed": true]]
        record["repeat"] = ["kind": "days", "interval": 2, "weekdays": [1, 3, 5]] as [String: Any]
        record["reminders"] = [["id": "deadline-one", "anchor": "deadline", "minutes": 10], ["id": "absolute-one", "anchor": "absolute", "minutes": 0, "at": "2026-11-11T20:00"]] as [[String: Any]]
        record["completedAt"] = stamp; record["generatedFrom"] = "original-task"; record["seriesId"] = "series-original"
        record["snoozedUntil"] = "2026-11-11T21:00"
        let plan = try parsedTasks([record]), item = plan.tasks[0]
        XCTAssertTrue(item.prepared); XCTAssertEqual(item.durationMinutes, 90); XCTAssertEqual(item.priority, 3); XCTAssertTrue(item.pinned)
        XCTAssertEqual(item.steps[0].originalID, "step-not-a-uuid"); XCTAssertTrue(item.steps[0].completed)
        XCTAssertEqual(item.repeatRule?.kind, .days); XCTAssertEqual(item.repeatRule?.weekdays, [1, 3, 5])
        XCTAssertEqual(item.reminders.count, 2); XCTAssertEqual(item.generatedFromOriginalID, "original-task"); XCTAssertEqual(item.seriesOriginalID, "series-original")
        guard case .androidTasks(let roundTrip) = try PersonalBackupImport.parse(plan.exportData()) else { return XCTFail() }
        XCTAssertEqual(roundTrip.tasks, plan.tasks)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.exportData()) as? [String: Any])
        let exportedTasks = try XCTUnwrap(object["tasks"] as? [[String: Any]])
        XCTAssertEqual(exportedTasks[0]["id"] as? String, "arbitrary/android/id")
        XCTAssertEqual(exportedTasks[0]["seriesId"] as? String, "series-original")
    }

    func testExplicitEmptyRemindersDoNotRestoreLegacyReminder() throws {
        var record = task(); record["reminders"] = []
        XCTAssertEqual(try parsedTasks([record]).tasks[0].reminders, [])
        record["deadline"] = NSNull(); record["remindMinutes"] = NSNull()
        let plan = try parsedTasks([record]); XCTAssertNil(plan.tasks[0].deadline)
        XCTAssertNoThrow(try plan.exportData())
    }

    func testTaskMergeIsRepeatableAndPreservesExistingEdits() throws {
        let plan = try parsedTasks()
        var existing = plan.tasks[0]; existing.notes = "保留本机修改"
        let preview = try plan.merge(into: [existing])
        XCTAssertEqual(preview.addedCount, 0); XCTAssertEqual(preview.duplicateCount, 1)
        XCTAssertEqual(preview.tasks, [existing]); XCTAssertEqual(preview.conflictingTitles.count, 1)
        let first = try plan.merge(into: [])
        XCTAssertEqual(first.addedCount, 1)
        XCTAssertEqual(try plan.merge(into: first.tasks).tasks.count, 1)
        XCTAssertTrue(try plan.merge(into: plan.tasks).conflictingTitles.isEmpty)
    }

    func testNativeTaskAndroidRoundTripKeepsUUIDAndDeduplicates() throws {
        var native = TaskRules.makeTask(title: "原生往返", now: try BackupValue.timestamp(stamp))
        native.plannedAt = try BackupValue.localDate("2026-11-11T09:00")
        native.steps = [TaskStep(title: "原生步骤")]
        native.reminders = [TaskReminder(anchor: .start, minutes: 10)]
        native = try TaskRules.validated(native)
        guard case .androidTasks(let imported) = try PersonalBackupImport.parse(AndroidTaskImportPlan.export(tasks: [native])) else { return XCTFail() }
        XCTAssertEqual(imported.tasks[0].id, native.id)
        XCTAssertEqual(imported.tasks[0].steps[0].id, native.steps[0].id)
        XCTAssertEqual(imported.tasks[0].reminders[0].id, native.reminders[0].id)
        let merged = try imported.merge(into: [native])
        XCTAssertEqual(merged.addedCount, 0); XCTAssertEqual(merged.duplicateCount, 1)
        XCTAssertEqual(merged.tasks, [native]); XCTAssertEqual(merged.conflictingTitles, [])
    }

    func testTaskMergeRemapsRepeatLinksToExistingOriginalIdentity() throws {
        let root = task("android-series-root")
        var child = task("android-series-child")
        child["generatedFrom"] = "android-series-root"; child["seriesId"] = "android-series-root"
        let incoming = try parsedTasks([root, child])
        var existing = incoming.tasks[0]; existing.id = UUID(); existing.notes = "保留本机根任务"
        let merged = try incoming.merge(into: [existing])
        XCTAssertEqual(merged.addedCount, 1); XCTAssertEqual(merged.duplicateCount, 1)
        let added = try XCTUnwrap(merged.tasks.first(where: { $0.originalID == "android-series-child" }))
        XCTAssertEqual(added.generatedFrom, existing.id); XCTAssertEqual(added.seriesID, existing.id)
        XCTAssertEqual(added.generatedFromOriginalID, "android-series-root")
        XCTAssertEqual(try incoming.merge(into: merged.tasks).tasks.count, 2)
        guard case .androidTasks(let exported) = try PersonalBackupImport.parse(AndroidTaskImportPlan.export(tasks: merged.tasks)) else { return XCTFail() }
        XCTAssertEqual(try exported.merge(into: merged.tasks).addedCount, 0)
    }

    func testTaskMergeRejectsAmbiguousNativeAndOriginalAliases() throws {
        var first = try parsedTasks().tasks[0]
        first.originalID = "another-original"
        var second = first; second.id = UUID(); second.originalID = "synthetic-task"
        XCTAssertThrowsError(try parsedTasks().merge(into: [first, second]))
    }

    func testBackupDocumentAcceptsBothAndroidFormatsAndRejectsForeignData() throws {
        XCTAssertNoThrow(try PersonalBackupDocument(data: bytes(schedule())))
        XCTAssertNoThrow(try PersonalBackupDocument(data: bytes(taskSnapshot())))
        XCTAssertThrowsError(try PersonalBackupDocument(data: bytes(["cookies": "synthetic"])))
    }

    func testTasksRejectOfficialLearningStatusAndUnknownNestedFields() throws {
        for key in ["source", "externalId", "platformStatus", "platformDescription", "timeText", "token", "cookies"] {
            var record = task(); record[key] = "synthetic"
            XCTAssertThrowsError(try parsedTasks([record]), key)
        }
        var root = taskSnapshot(); root["session"] = "synthetic"
        XCTAssertThrowsError(try PersonalBackupImport.parse(bytes(root)))
        var record = task(); record["steps"] = [["id": "step", "title": "步骤", "completed": false, "password": "synthetic"]] as [[String: Any]]
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["repeat"] = ["kind": "daily", "interval": 1, "weekdays": [], "token": "synthetic"] as [String: Any]
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["reminders"] = [["id": "r", "anchor": "deadline", "minutes": 0, "cookie": "synthetic"]] as [[String: Any]]
        XCTAssertThrowsError(try parsedTasks([record]))
    }

    func testInvalidTaskLimitsAndDuplicateIdentitiesAreRejected() throws {
        XCTAssertThrowsError(try parsedTasks([task(), task()]))
        XCTAssertThrowsError(try parsedTasks((0...500).map { task("task-\($0)") }))
        for field in ["deadline", "plannedAt", "snoozedUntil"] {
            var record = task(); record[field] = "2026-02-30T08:00"
            XCTAssertThrowsError(try parsedTasks([record]), field)
        }
        var record = task(); record["completed"] = 1
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["priority"] = true
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["steps"] = (0...50).map { ["id": "step\($0)", "title": "步骤", "completed": false] as [String: Any] }
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["reminders"] = (0...5).map { ["id": "r\($0)", "anchor": "deadline", "minutes": 0] as [String: Any] }
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["repeat"] = ["kind": "days", "interval": 1, "weekdays": []] as [String: Any]
        XCTAssertThrowsError(try parsedTasks([record]))
        record = task(); record["plannedAt"] = "2026-11-11T09:00"; record["plannedDay"] = "2026-11-11"
        XCTAssertThrowsError(try parsedTasks([record]))
    }

    func testNativeTaskExportRefusesLossyOrUnsupportedFields() throws {
        var item = try parsedTasks().tasks[0]
        item.notes = String(repeating: "a", count: 1001)
        XCTAssertThrowsError(try AndroidTaskImportPlan.export(tasks: [item]))
        item = try parsedTasks().tasks[0]; item.legacyReminder = true
        XCTAssertThrowsError(try AndroidTaskImportPlan.export(tasks: [item]))
        item = try parsedTasks().tasks[0]; item.plannedAt = Date(timeIntervalSince1970: 1794384001)
        XCTAssertThrowsError(try AndroidTaskImportPlan.export(tasks: [item]))
    }

    func testJSONBoundsDuplicateEscapedKeysAndCompressedInputAreRejected() throws {
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data(repeating: 32, count: PersonalBackupImport.maximumBytes + 1)))
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data([0x1f, 0x8b, 0x08, 0x00])))
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data("{\"version\":1,\"vers\\u0069on\":2}".utf8)))
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data((String(repeating: "[", count: 20) + "0" + String(repeating: "]", count: 20)).utf8)))
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data("{\"value\":NaN}".utf8)))
        XCTAssertThrowsError(try PersonalBackupImport.parse(Data("{} {}".utf8)))
    }

    func testBoundedFileReaderDoesNotDecompressOrAcceptNonJSONFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes(taskSnapshot()).write(to: url)
        guard case .androidTasks(let value) = try PersonalBackupImport.read(from: url) else { return XCTFail() }
        XCTAssertEqual(value.tasks.count, 1)
        XCTAssertThrowsError(try PersonalBackupImport.read(from: url.deletingPathExtension().appendingPathExtension("zip")))
        try Data(repeating: 32, count: PersonalBackupImport.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try PersonalBackupImport.read(from: url))
    }

    func testCourseIdentityUsesUnambiguousTupleAndRemainsStable() {
        XCTAssertEqual(AndroidScheduleImportPlan.nativeCourseID(course: "a", arrangement: "bc"), AndroidScheduleImportPlan.nativeCourseID(course: "a", arrangement: "bc"))
        XCTAssertNotEqual(AndroidScheduleImportPlan.nativeCourseID(course: "a", arrangement: "bc"), AndroidScheduleImportPlan.nativeCourseID(course: "ab", arrangement: "c"))
    }
}
