import XCTest
@testable import Hanyuantong

final class PersonalBackupTests: XCTestCase {
    private func sample() -> PersonalBackup {
        PersonalBackup(courses: [Course(name: "个人课程", day: 1, start: "08:00", end: "09:30", weeks: [1, 2])],
                       tasks: [CampusTask(title: "完成作业", date: Date(timeIntervalSince1970: 1800000000))],
                       semesterStart: Date(timeIntervalSince1970: 1790000000))
    }
    func testRoundTripKeepsPersonalFields() throws {
        var value = sample()
        value.courses[0].notes = "带好教材"
        value.tasks[0].completed = true
        let decoded = try PersonalBackup.decode(value.encode())
        XCTAssertEqual(decoded.courses, value.courses)
        XCTAssertEqual(decoded.tasks, value.tasks)
        XCTAssertEqual(decoded.semesterStart, value.semesterStart)
    }
    func testRejectsSchoolSourcesAndExternalIDs() {
        var value = sample()
        value.courses[0].source = "school"
        XCTAssertThrowsError(try value.encode())
        value.courses[0].source = "personal"
        value.courses[0].externalID = "school-page-example"
        XCTAssertThrowsError(try value.encode())
    }
    func testRejectsMalformedTimesAndRanges() {
        for time in ["8:00", "24:00", "08:60", "aa:bb", "０８:００", "09:30", "10:00"] {
            var value = sample(); value.courses[0].start = time
            XCTAssertThrowsError(try value.validate(), time)
        }
        for weeks in [[], [0], [61], [1, 1]] {
            var value = sample(); value.courses[0].weeks = weeks
            XCTAssertThrowsError(try value.validate())
        }
        var value = sample(); value.courses[0].day = 8
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses[0].startPeriod = 4; value.courses[0].endPeriod = 2
        XCTAssertThrowsError(try value.validate())
    }
    func testDuplicateIDsAreRejectedAcrossAndWithinCollections() {
        var value = sample(); value.courses.append(value.courses[0])
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.tasks.append(value.tasks[0])
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.tasks[0].id = value.courses[0].id
        XCTAssertThrowsError(try value.validate())
    }
    func testUnknownVersionAndForeignFieldsRejected() throws {
        var value = sample(); value.version = 99
        XCTAssertThrowsError(try value.validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample().encode()) as? [String: Any])
        object["cookies"] = "synthetic-not-a-real-cookie"
        XCTAssertThrowsError(try PersonalBackup.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "cookies")
        var courses = try XCTUnwrap(object["courses"] as? [[String: Any]])
        courses[0]["token"] = "synthetic"
        object["courses"] = courses
        XCTAssertThrowsError(try PersonalBackup.decode(JSONSerialization.data(withJSONObject: object)))
        XCTAssertThrowsError(try PersonalBackup.decode(Data("{\"version\":1}".utf8)))
    }
    func testSizeAndContentLimits() {
        XCTAssertThrowsError(try PersonalBackup.decode(Data(repeating: 32, count: PersonalBackup.maximumBytes + 1)))
        var value = sample(); value.tasks[0].title = " \n "
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses[0].notes = String(repeating: "a", count: 4001)
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.semesterStart = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try value.validate())
        value = sample(); value.courses = (0..<2001).map { _ in Course(name: "课程", day: 1, start: "08:00", end: "09:00", weeks: [1]) }
        XCTAssertThrowsError(try value.validate())
    }
    func testEmptyPersonalBackupIsValidForExplicitReplacement() throws {
        let value = PersonalBackup(courses: [], tasks: [], semesterStart: sample().semesterStart)
        XCTAssertNoThrow(try PersonalBackup.decode(value.encode()))
    }
    func testFileReadUsesSameStrictValidation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try sample().encode().write(to: url)
        XCTAssertEqual(try PersonalBackup.read(from: url).courses.count, 1)
        try Data(repeating: 32, count: PersonalBackup.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try PersonalBackup.read(from: url))
    }
    func testReadsOriginalNativeVersionOne() throws {
        let object: [String: Any] = ["version": 1, "courses": [], "tasks": [["id": UUID().uuidString, "title": "旧待办", "date": "2026-11-11T01:00:00Z", "completed": false, "notes": ""]], "semesterStart": "2026-09-13T16:00:00Z"]
        let backup = try PersonalBackup.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(backup.tasks[0].legacyReminder)
        XCTAssertNotNil(backup.tasks[0].plannedAt)
    }
    func testRejectsCredentialsInsideRichTaskFields() throws {
        var value = sample(); value.tasks[0].steps = [TaskStep(title: "小步骤")]
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: value.encode()) as? [String: Any])
        var tasks = try XCTUnwrap(root["tasks"] as? [[String: Any]])
        var steps = try XCTUnwrap(tasks[0]["steps"] as? [[String: Any]])
        steps[0]["token"] = "synthetic"; tasks[0]["steps"] = steps; root["tasks"] = tasks
        XCTAssertThrowsError(try PersonalBackup.decode(JSONSerialization.data(withJSONObject: root)))
    }

    func testNativeBackupRetainsAllFractionalDateFieldsExactly() throws {
        let instant = Date(timeIntervalSinceReferenceDate: 816091200.1234567)
        var task = TaskRules.makeTask(title: "保留精度", now: instant)
        task.plannedAt = instant.addingTimeInterval(60.0000004)
        task.deadline = instant.addingTimeInterval(3600.0000008)
        task.completed = true; task.completedAt = instant.addingTimeInterval(0.0003)
        task.updatedAt = instant.addingTimeInterval(0.0007)
        task.snoozedUntil = instant.addingTimeInterval(600.000001)
        task.reminders = [TaskReminder(anchor: .absolute, at: instant.addingTimeInterval(120.000002))]
        task = try TaskRules.validated(task)
        let backup = PersonalBackup(courses: [], tasks: [task], semesterStart: instant)
        let data = try backup.encode()
        let restored = try PersonalBackup.decode(data)
        XCTAssertEqual(restored.tasks, [task])
        XCTAssertEqual(restored.semesterStart, instant)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["semesterStart"] as? String, "Keep the existing ISO-string schema, not numeric/object dates")
        XCTAssertEqual(restored.tasks[0].createdAt, task.createdAt)
        XCTAssertNotEqual(restored.tasks[0].createdAt, restored.tasks[0].updatedAt)
    }

    func testTimestampCodecPreservesImportedMillisSubmillisAndReferenceEpoch() throws {
        for stamp in ["2026-11-11T08:00:00.123Z", "2026-11-11T16:00:00.123+08:00", "2026-11-11T08:00:00.123456789Z"] {
            let date = try BackupValue.timestamp(stamp)
            XCTAssertEqual(try BackupValue.timestamp(BackupValue.timestampString(date)), date)
        }
        XCTAssertEqual(try BackupValue.timestamp("2026-11-11T08:00:00.123Z"), try BackupValue.timestamp("2026-11-11T16:00:00.123+08:00"))
        let instants = [
            Date(timeIntervalSinceReferenceDate: 0.12345678901234567),
            Date(timeIntervalSinceReferenceDate: -0.12345678901234567),
            Date(timeIntervalSinceReferenceDate: 816091200.1234567),
            // Existing versions may already hold the representable result of a Unix-epoch conversion.
            Date(timeIntervalSince1970: 1794384000.1234567),
            Date(timeIntervalSince1970: -2208988800), Date(timeIntervalSince1970: 7289654400)
        ]
        for instant in instants {
            let restored = try PersonalBackup.decode(PersonalBackup(courses: [], tasks: [], semesterStart: instant).encode())
            XCTAssertEqual(restored.semesterStart, instant)
        }
        for invalid in ["2026-02-30T08:00:00.123Z", "2026-11-11T08:00:00.123Ztail", "2026-11-11T08:00:00.123e2Z", "2026-11-11T08:00:00." + String(repeating: "1", count: 26) + "Z"] {
            XCTAssertThrowsError(try BackupValue.timestamp(invalid))
        }
    }

    private func fractionalRepeatPair() throws -> [CampusTask] {
        let now = try BackupValue.timestamp("2026-11-11T08:00:00.1234567Z")
        var parent = TaskRules.makeTask(title: "精确重复任务", now: now.addingTimeInterval(-3600))
        parent.plannedAt = try BackupValue.localDate("2026-11-11T09:00")
        parent.deadline = try BackupValue.localDate("2026-11-11T18:00")
        parent.repeatRule = TaskRepeatRule(kind: .daily)
        parent.steps = [TaskStep(title: "保留步骤")]
        parent.reminders = [TaskReminder(anchor: .deadline, minutes: 10)]
        return try TaskRules.settingCompleted([parent], id: parent.id, completed: true, now: now)
    }

    private func nativeRoundTrip(_ tasks: [CampusTask]) throws -> [CampusTask] {
        try PersonalBackup.decode(PersonalBackup(courses: [], tasks: tasks, semesterStart: sample().semesterStart).encode()).tasks
    }
    private func androidRoundTrip(_ tasks: [CampusTask]) throws -> [CampusTask] {
        guard case .androidTasks(let imported) = try PersonalBackupImport.parse(AndroidTaskImportPlan.export(tasks: tasks)) else {
            throw BackupCompatibilityFailure("测试格式无效")
        }
        return imported.tasks
    }

    func testUntouchedRepeatUndoSurvivesNativeAndAndroidRoundTrips() throws {
        let pair = try fractionalRepeatPair()
        let routes = [try nativeRoundTrip(pair), try androidRoundTrip(pair), try nativeRoundTrip(androidRoundTrip(pair))]
        for restored in routes {
            XCTAssertEqual(restored[0].completedAt, pair[0].completedAt)
            XCTAssertEqual(restored[1].createdAt, pair[1].createdAt)
            XCTAssertEqual(restored[1].updatedAt, pair[1].updatedAt)
            let undone = try TaskRules.settingCompleted(restored, id: pair[0].id, completed: false, now: pair[1].createdAt.addingTimeInterval(60))
            XCTAssertEqual(undone.count, 1); XCTAssertFalse(undone[0].completed)
        }
    }

    func testSubmillisecondEditCannotBecomeUntouchedAfterEitherRoundTrip() throws {
        var pair = try fractionalRepeatPair()
        pair[1].updatedAt = pair[1].createdAt.addingTimeInterval(0.0003)
        XCTAssertNotEqual(pair[1].updatedAt, pair[1].createdAt)
        XCTAssertThrowsError(try TaskRules.settingCompleted(pair, id: pair[0].id, completed: false))
        let routes = [try nativeRoundTrip(pair), try androidRoundTrip(pair), try nativeRoundTrip(androidRoundTrip(pair))]
        for restored in routes {
            XCTAssertEqual(restored[1].createdAt, pair[1].createdAt)
            XCTAssertEqual(restored[1].updatedAt, pair[1].updatedAt)
            XCTAssertNotEqual(restored[1].updatedAt, restored[1].createdAt)
            XCTAssertThrowsError(try TaskRules.settingCompleted(restored, id: pair[0].id, completed: false))
        }
    }

}
