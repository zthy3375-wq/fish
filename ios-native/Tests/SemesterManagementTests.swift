import XCTest
@testable import Hanyuantong

final class SemesterManagementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var monday: Date { BackupValue.dayDate("2026-09-14") }

    private func state() throws -> AndroidScheduleState {
        var value = try PersonalSemesterRules.migrateLegacy(courses: [], semesterStart: monday, now: now)
        let first = try PersonalSemesterRules.activeSemester(in: value)
        let second = AndroidSemester(id: "term-spring", academicYear: "2026–2027", season: "春季", startDate: "2027-02-22", weekStartDate: "2027-02-22", weekCount: 18, timeTableId: first.timeTableId)
        value.semesters.append(second)
        let arrangements = [
            AndroidArrangement(id: "arrangement-one", day: 1, startPeriod: 1, endPeriod: 2, start: "08:00", end: "09:35", room: "A101", startWeek: 1, endWeek: 17, rule: "odd", customWeeks: [], timeMode: "period"),
            AndroidArrangement(id: "arrangement-two", day: 3, startPeriod: 3, endPeriod: 4, start: "10:10", end: "11:20", room: "B202", startWeek: 2, endWeek: 18, rule: "even", customWeeks: [], timeMode: "custom")
        ]
        value.courses = [
            AndroidManagedCourse(id: "course-one", semesterId: first.id, name: "合成数学", teacher: "示例教师", color: "blue", notes: "合成备注", arrangements: arrangements),
            AndroidManagedCourse(id: "course-spring", semesterId: second.id, name: "合成英语", teacher: "", color: "green", notes: "保留其他学期", arrangements: [arrangements[0]])
        ]
        return try value.validated()
    }

    func testStableProjectionIdentityAcrossReorderRenameAndRoundTrip() throws {
        let original = try state()
        let ids = try original.projectedCourses(semesterID: original.activeSemesterId).map(\.id)
        var changed = original
        changed.courses.reverse(); changed.semesters.reverse()
        changed.courses[1].name = "修改名称，不换编号"
        let decoded = try JSONDecoder().decode(AndroidScheduleState.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(try decoded.projectedCourses(semesterID: original.activeSemesterId).map(\.id), ids)
        XCTAssertEqual(Set(ids).count, 2)
        XCTAssertNotEqual(AndroidScheduleImportPlan.nativeCourseID(course: "ab", arrangement: "c"), AndroidScheduleImportPlan.nativeCourseID(course: "a", arrangement: "bc"))
    }

    func testV1LegacyConversionKeepsClockTimesAndAddsIndependentTables() throws {
        let original = try state()
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        raw["version"] = 1; raw.removeValue(forKey: "timeTables")
        let plan = try AndroidScheduleImportPlan.parse(["format": "handan-campus-schedule", "exportedAt": BackupValue.timestampString(now), "data": raw])
        XCTAssertEqual(plan.sourceVersion, 1)
        XCTAssertEqual(plan.state.version, 2)
        XCTAssertEqual(plan.state.timeTables.count, 2)
        XCTAssertEqual(plan.state.semesters.map(\.timeTableId), ["legacy-times-1", "legacy-times-2"])
        XCTAssertTrue(plan.state.courses.flatMap(\.arrangements).allSatisfy { $0.timeMode == "custom" })
        XCTAssertEqual(plan.state.courses[0].arrangements[1].start, "10:10")
        XCTAssertEqual(plan.state.courses[0].arrangements[1].end, "11:20")
    }

    func testNativeFlatMigrationPreservesIrregularWeeksAndClockTimes() throws {
        let flat = Course(id: UUID(uuidString: "AB21F147-68E7-43A6-9A91-99AC2D2DF304")!, name: "合成课程", teacher: "教师", room: "教室", day: 7, start: "13:02", end: "14:03", weeks: [1, 3, 7], color: "orange", startPeriod: 8, endPeriod: 9, notes: "原备注")
        let migrated = try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday, now: now)
        let repeated = try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday, now: now)
        let projection = try XCTUnwrap(try PersonalSemesterRules.activeCourses(in: migrated).first)
        XCTAssertEqual(projection.id, try PersonalSemesterRules.activeCourses(in: repeated).first?.id)
        XCTAssertEqual(projection.weeks, [1, 3, 7]); XCTAssertEqual(projection.start, "13:02")
        XCTAssertEqual(projection.notes, "原备注"); XCTAssertEqual(projection.source, "personal")
        XCTAssertNil(projection.externalID)
        XCTAssertEqual(migrated.courses[0].arrangements[0].timeMode, "custom")
        XCTAssertEqual(migrated.semesters[0].weekCount, 19)
        XCTAssertEqual(migrated.timeTables[0].slots.count, 12)
    }

    func testMigrationRefusesSchoolAndIncompatibleLegacyDataWithoutTruncation() throws {
        var flat = Course(name: "课程", day: 1, start: "08:00", end: "09:00", weeks: [1])
        flat.source = "school"
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
        flat.source = "personal"; flat.externalID = "school-page-term/course"
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
        flat.externalID = nil; flat.weeks = [41]
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
        flat.weeks = [1]; flat.notes = String(repeating: "记", count: 2001)
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [], semesterStart: monday.addingTimeInterval(86400)))
    }

    func testTimeModePeriodRecomputesWhileCustomAndOtherSemesterStayUnchanged() throws {
        let original = try state()
        let other = original.courses[1]
        var table = PersonalSemesterRules.standardTimeTable(id: "new-copy")
        table.slots[0].start = "07:30"; table.slots[1].end = "09:45"
        let result = try PersonalSemesterRules.applyTimeTable(table, to: original.activeSemesterId, saveCopy: true, in: original, now: now)
        XCTAssertEqual(result.courses[0].arrangements[0].start, "07:30")
        XCTAssertEqual(result.courses[0].arrangements[0].end, "09:45")
        XCTAssertEqual(result.courses[0].arrangements[1], original.courses[0].arrangements[1])
        XCTAssertEqual(result.courses[1], other)
        XCTAssertEqual(result.semesters[1], original.semesters[1])
        XCTAssertEqual(result.timeTables[0], original.timeTables[0])
    }

    func testTimeTableCannotMutateSharedPlanAndInvalidPeriodReferencesFailAtomically() throws {
        let original = try state()
        var shared = original.timeTables[0]; shared.slots[0].start = "07:30"
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(shared, to: original.activeSemesterId, saveCopy: false, in: original))
        var short = original.timeTables[0]; short.id = "short"; short.slots = Array(short.slots.prefix(1))
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(short, to: original.activeSemesterId, saveCopy: true, in: original))
        XCTAssertEqual(original.courses[0].arrangements[0].end, "09:35")
        XCTAssertEqual(original.timeTables.count, 1)
    }

    func testCustomTimeTableOneThroughTwentyFourAndValidation() throws {
        let original = try PersonalSemesterRules.migrateLegacy(courses: [], semesterStart: monday)
        let slots = (0..<24).map { n in AndroidTimeSlot(number: n + 1, start: String(format: "%02d:00", n), end: String(format: "%02d:30", n)) }
        let full = AndroidTimeTable(id: "full-day", name: "24节测试", slots: slots)
        XCTAssertEqual(try PersonalSemesterRules.applyTimeTable(full, to: original.activeSemesterId, saveCopy: true, in: original).timeTables.last?.slots.count, 24)
        var bad = full; bad.slots.append(AndroidTimeSlot(number: 25, start: "23:31", end: "23:59"))
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(bad, to: original.activeSemesterId, saveCopy: true, in: original))
        bad = full; bad.slots[1].start = "00:10"
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(bad, to: original.activeSemesterId, saveCopy: true, in: original))
        bad = full; bad.slots[1].number = 3
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(bad, to: original.activeSemesterId, saveCopy: true, in: original))
        bad = full; bad.slots[0].end = "24:00"
        XCTAssertThrowsError(try PersonalSemesterRules.applyTimeTable(bad, to: original.activeSemesterId, saveCopy: true, in: original))
    }

    func testSemesterRemovalRequiresConfirmationAndPreservesOtherTermsAndReminders() throws {
        var original = try state(); original.reminders = AndroidScheduleReminders(enabled: true, minutes: 25)
        XCTAssertThrowsError(try PersonalSemesterRules.deleteSemester(id: original.activeSemesterId, confirmed: false, in: original))
        let result = try PersonalSemesterRules.deleteSemester(id: original.activeSemesterId, confirmed: true, in: original, now: now)
        XCTAssertEqual(result.semesters, [original.semesters[1]])
        XCTAssertEqual(result.courses, [original.courses[1]])
        XCTAssertEqual(result.activeSemesterId, original.semesters[1].id)
        XCTAssertEqual(result.timeTables, original.timeTables)
        XCTAssertEqual(result.reminders, original.reminders)
        XCTAssertThrowsError(try PersonalSemesterRules.deleteSemester(id: result.activeSemesterId, confirmed: true, in: result))
        XCTAssertEqual(original.semesters.count, 2)
    }

    func testRemovingInactiveSemesterKeepsCurrentSelection() throws {
        let original = try state()
        let result = try PersonalSemesterRules.deleteSemester(id: original.semesters[1].id, confirmed: true, in: original)
        XCTAssertEqual(result.activeSemesterId, original.activeSemesterId)
        XCTAssertEqual(result.courses, [original.courses[0]])
    }

    func testSelectAndEditSemesterPreserveUnselectedCourses() throws {
        let original = try state()
        let selected = try PersonalSemesterRules.selectSemester(id: "term-spring", in: original, now: now)
        XCTAssertEqual(try PersonalSemesterRules.activeCourses(in: selected).map(\.name), ["合成英语"])
        XCTAssertEqual(selected.courses, original.courses)
        var semester = try PersonalSemesterRules.activeSemester(in: selected)
        semester.academicYear = "调整学年"; semester.weekStartDate = "2027-03-01"; semester.weekCount = 20
        let edited = try PersonalSemesterRules.saveSemester(semester, in: selected, now: now)
        XCTAssertEqual(edited.semesters[0], original.semesters[0]); XCTAssertEqual(edited.courses, original.courses)
        semester.weekStartDate = "2027-03-02"
        XCTAssertThrowsError(try PersonalSemesterRules.saveSemester(semester, in: selected))
        semester.weekStartDate = "2027-03-01"; semester.weekCount = 2
        XCTAssertThrowsError(try PersonalSemesterRules.saveSemester(semester, in: selected))
    }

    func testFlatUpsertRetainsGroupOriginalIDsSiblingArrangementAndWeekRule() throws {
        let original = try state()
        var flat = try XCTUnwrap(try PersonalSemesterRules.activeCourses(in: original).first)
        flat.name = "修改共享名称"; flat.room = "新教室"
        let updated = try PersonalSemesterRules.upsertFlatCourse(flat, in: original, now: now)
        XCTAssertEqual(updated.courses[0].id, "course-one")
        XCTAssertEqual(updated.courses[0].arrangements[0].id, "arrangement-one")
        XCTAssertEqual(updated.courses[0].arrangements[0].rule, "odd")
        XCTAssertEqual(updated.courses[0].arrangements[0].timeMode, "period")
        XCTAssertEqual(updated.courses[0].arrangements[1], original.courses[0].arrangements[1])
        XCTAssertEqual(updated.courses[1], original.courses[1])
        XCTAssertEqual(try PersonalSemesterRules.activeCourses(in: updated).first?.id, flat.id)
        XCTAssertEqual(try PersonalSemesterRules.activeCourses(in: updated).last?.name, "修改共享名称")
    }

    func testFlatClockEditConvertsOnlyEditedArrangementToCustom() throws {
        let original = try state()
        var flat = try XCTUnwrap(try PersonalSemesterRules.activeCourses(in: original).first)
        flat.start = "07:45"
        let result = try PersonalSemesterRules.upsertFlatCourse(flat, in: original)
        XCTAssertEqual(result.courses[0].arrangements[0].timeMode, "custom")
        XCTAssertEqual(result.courses[0].arrangements[0].start, "07:45")
        XCTAssertEqual(result.courses[0].arrangements[1], original.courses[0].arrangements[1])
    }

    func testFlatDeletionRemovesOnlyMappedArrangementThenEmptyCourse() throws {
        let original = try state()
        let flat = try PersonalSemesterRules.activeCourses(in: original)
        let once = try PersonalSemesterRules.deleteFlatCourse(id: flat[0].id, in: original)
        XCTAssertEqual(once.courses[0].arrangements.map(\.id), ["arrangement-two"])
        let twice = try PersonalSemesterRules.deleteFlatCourse(id: flat[1].id, in: once)
        XCTAssertEqual(twice.courses, [original.courses[1]])
        XCTAssertThrowsError(try PersonalSemesterRules.deleteFlatCourse(id: flat[1].id, in: twice))
    }

    func testStaleFlatEditingCannotMoveCourseAcrossSemesters() throws {
        let original = try state()
        let flat = try XCTUnwrap(try PersonalSemesterRules.activeCourses(in: original).first)
        let other = try PersonalSemesterRules.selectSemester(id: "term-spring", in: original)
        XCTAssertThrowsError(try PersonalSemesterRules.upsertFlatCourse(flat, in: other))
        XCTAssertThrowsError(try PersonalSemesterRules.deleteFlatCourse(id: flat.id, in: other))
        var school = flat; school.source = "school"
        XCTAssertThrowsError(try PersonalSemesterRules.upsertFlatCourse(school, in: original))
    }

    func testRepeatedFlatUpsertKeepsOneCourseAndLegacyAliasCanBeDeleted() throws {
        let original = try PersonalSemesterRules.migrateLegacy(courses: [], semesterStart: monday)
        var flat = Course(name: "新课程", day: 1, start: "08:00", end: "09:00", weeks: [1, 3, 4])
        let first = try PersonalSemesterRules.upsertFlatCourse(flat, in: original)
        flat.name = "重试编辑"
        let second = try PersonalSemesterRules.upsertFlatCourse(flat, in: first)
        XCTAssertEqual(second.courses.count, 1)
        XCTAssertEqual(second.courses[0].name, "重试编辑")
        XCTAssertTrue(try PersonalSemesterRules.deleteFlatCourse(id: flat.id, in: second).courses.isEmpty)
    }

    func testReplaceActiveImportPreservesOtherSemesterAndRejectsDuplicateIDs() throws {
        let original = try state()
        let flat = Course(name: "新导入", day: 2, start: "08:00", end: "09:00", weeks: [1, 3, 4])
        let imported = try PersonalSemesterRules.importFlatCourses([flat], replacingActive: true, in: original)
        XCTAssertEqual(imported.courses.first, original.courses[1])
        XCTAssertEqual(imported.courses.count, 2)
        XCTAssertEqual(imported.semesters, original.semesters)
        XCTAssertThrowsError(try PersonalSemesterRules.importFlatCourses([flat, flat], replacingActive: true, in: original))
        let cleared = try PersonalSemesterRules.importFlatCourses([], replacingActive: true, in: original)
        XCTAssertEqual(cleared.courses, [original.courses[1]])
    }

    func testManagedCourseDeletionRequiresExplicitConfirmation() throws {
        let original = try state()
        XCTAssertThrowsError(try PersonalSemesterRules.deleteCourse(id: "course-one", confirmed: false, in: original))
        let result = try PersonalSemesterRules.deleteCourse(id: "course-one", confirmed: true, in: original)
        XCTAssertEqual(result.courses, [original.courses[1]])
        XCTAssertThrowsError(try PersonalSemesterRules.deleteCourse(id: "course-spring", confirmed: true, in: original))
    }

    func testCustomWeeksParserRejectsPartialInputInsteadOfSilentlyDroppingIt() throws {
        XCTAssertEqual(try PersonalSemesterRules.parseCustomWeeks("1-3，5、7–9, 3"), [1, 2, 3, 5, 7, 8, 9])
        for invalid in ["", "1,,3", "0", "41", "8-3", "1-x", "1,3oops", "1,", "-1"] {
            XCTAssertThrowsError(try PersonalSemesterRules.parseCustomWeeks(invalid), invalid)
        }
    }

    func testConflictDetectionIncludesSiblingArrangementsAndExcludesOtherTerms() throws {
        var original = try state()
        XCTAssertTrue(try PersonalSemesterRules.conflicts(in: original, semesterID: original.activeSemesterId).isEmpty)
        original.courses[0].arrangements[1].day = 1
        original.courses[0].arrangements[1].start = "08:30"; original.courses[0].arrangements[1].end = "09:10"
        original.courses[0].arrangements[1].rule = "all"
        XCTAssertEqual(try PersonalSemesterRules.conflicts(in: original, semesterID: original.activeSemesterId).count, 1)
    }

    func testDefaultsMatchAndroidCourseEditor() throws {
        let original = try state()
        let semester = try PersonalSemesterRules.activeSemester(in: original)
        let course = PersonalSemesterRules.newCourse(semester: semester, table: original.timeTables[0])
        XCTAssertEqual(course.color, "purple")
        XCTAssertEqual(course.arrangements[0].timeMode, "period")
        XCTAssertEqual(course.arrangements[0].startPeriod, 1)
        XCTAssertEqual(course.arrangements[0].endPeriod, 1)
        XCTAssertEqual(course.arrangements[0].end, "08:45")
    }

    func testLegacyFreeformPeriodLabelIsNotSilentlyDiscarded() throws {
        var flat = Course(name: "课程", day: 1, start: "08:00", end: "09:00", period: "轮转实验", weeks: [1])
        XCTAssertThrowsError(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
        flat.period = "1-2"; flat.startPeriod = 1; flat.endPeriod = 2
        XCTAssertNoThrow(try PersonalSemesterRules.migrateLegacy(courses: [flat], semesterStart: monday))
    }

    func testUserSuppliedHandanTablePreservesAndroidThirteenPeriodValues() {
        let table = PersonalSemesterRules.handanTimeTable()
        XCTAssertEqual(table.slots.count, 13)
        XCTAssertEqual(table.slots[5].start, "14:30")
        XCTAssertEqual(table.slots[12].end, "21:10")
        XCTAssertEqual(PersonalSemesterRules.standardTimeTable().slots[1].end, "09:35")
    }
}
