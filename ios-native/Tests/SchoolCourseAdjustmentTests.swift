import XCTest
import SwiftUI
@testable import Hanyuantong

final class SchoolCourseAdjustmentTests: XCTestCase {
    private let scope = "C171040F-EC43-4656-AFE7-F9981A355CB8"
    private let term = AcademicTerm(xnm: "2026", xqm: "3")
    private func snapshot(room: String = "原教室") -> AcademicSnapshot {
        AcademicSnapshot(scope: scope, term: term,
            courses: [AcademicCourse(name: "合成调课测试", teacher: "教师", room: room, weekday: 2, periods: "1-2", weeks: "1-11周(单)")],
            practice: [], grades: [], exams: [], semesters: [term], moduleErrors: [:], updatedAt: Date())
    }
    private func change(_ course: Course) -> SchoolCourseTimeChange {
        var value = SchoolCourseTimeChange(course: course)
        value.day = 4; value.room = "新教室"; value.startPeriod = 6; value.endPeriod = 7
        return value
    }
    func testOneWeekMovesAndOtherWeeksKeepOriginalSource() throws {
        let snapshot = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(snapshot).first)
        let records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: change(source), periods: SchoolCourseAdjustments.periods(snapshot))
        let projected = SchoolCourseAdjustments.project([source], term: term, records: records, periods: SchoolCourseAdjustments.periods(snapshot))
        XCTAssertEqual(source.weeks, [1,3,5,7,9,11]); XCTAssertEqual(projected.count, 2)
        XCTAssertEqual(projected[0].weeks, [1,3,7,9,11]); XCTAssertEqual(projected[0].day, 2)
        XCTAssertEqual(projected[1].weeks, [5]); XCTAssertEqual(projected[1].day, 4)
        XCTAssertEqual(projected[1].start, "14:30"); XCTAssertEqual(projected[1].end, "15:55")
        XCTAssertEqual(projected[1].locallyAdjusted, true)
    }
    func testFutureOddWeeksAndRestoringOnlySelectedWeek() throws {
        let snapshot = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(snapshot).first), periods = SchoolCourseAdjustments.periods(snapshot)
        var records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: source.weeks.filter { $0 >= 7 }, change: change(source), periods: periods)
        XCTAssertEqual(records.map(\.week), [7,9,11])
        records = try SchoolCourseAdjustments.updating(records, term: term, source: source, weeks: [9], change: SchoolCourseTimeChange(course: source), periods: periods)
        let projected = SchoolCourseAdjustments.project([source], term: term, records: records, periods: periods)
        XCTAssertEqual(projected[0].weeks, [1,3,5,9]); XCTAssertEqual(projected[1].weeks, [7,11])
    }
    func testChangedOfficialRoomPausesOverrideAndOtherTermDoesNotUseIt() throws {
        let first = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(first).first), periods = SchoolCourseAdjustments.periods(first)
        let records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: change(source), periods: periods)
        let changed = SchoolCourseAdjustments.originals(snapshot(room: "老师最新教室"))
        XCTAssertEqual(SchoolCourseAdjustments.inactiveCount(changed, term: term, records: records, periods: periods), 1)
        XCTAssertFalse(SchoolCourseAdjustments.project(changed, term: term, records: records, periods: periods).contains { $0.locallyAdjusted == true })
        XCTAssertFalse(SchoolCourseAdjustments.project([source], term: AcademicTerm(xnm: "2025", xqm: "12"), records: records, periods: periods).contains { $0.locallyAdjusted == true })
    }
    func testMergeRefreshTermSwitchAndAccountSwitch() throws {
        var previous = snapshot(); let source = try XCTUnwrap(SchoolCourseAdjustments.originals(previous).first)
        previous.courseAdjustments = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: change(source), periods: SchoolCourseAdjustments.periods(previous))
        XCTAssertEqual(snapshot().merging(previous: previous).courseAdjustments, previous.courseAdjustments)
        let anotherTerm = AcademicSnapshot(scope: scope, term: AcademicTerm(xnm: "2025", xqm: "12"), courses: [], practice: [], grades: [], exams: [], semesters: [], moduleErrors: [:], updatedAt: Date())
        XCTAssertEqual(anotherTerm.merging(previous: previous).courseAdjustments, previous.courseAdjustments)
        let anotherAccount = AcademicSnapshot(scope: UUID().uuidString, term: term, courses: previous.courses, practice: [], grades: [], exams: [], semesters: [], moduleErrors: [:], updatedAt: Date())
        XCTAssertNil(anotherAccount.merging(previous: previous).courseAdjustments)
    }
    func testInvalidWeeksTimeAndDuplicateRecordsAreRejected() throws {
        let snapshot = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(snapshot).first), periods = SchoolCourseAdjustments.periods(snapshot)
        for weeks in [[], [5,5], [2]] { XCTAssertThrowsError(try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: weeks, change: change(source), periods: periods)) }
        var invalid = change(source); invalid.usesPeriods = false; invalid.start = "11:00"; invalid.end = "10:00"
        XCTAssertThrowsError(try invalid.validated())
        let records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: change(source), periods: periods)
        XCTAssertThrowsError(try SchoolCourseAdjustments.validated(records + records))
    }
    func testConflictRequiresSameWeekAndOverlappingTime() throws {
        let snapshot = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(snapshot).first), periods = SchoolCourseAdjustments.periods(snapshot)
        let records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: change(source), periods: periods)
        let projected = SchoolCourseAdjustments.project([source], term: term, records: records, periods: periods)
        var other = Course(name: "另一门课", day: 4, start: "15:00", end: "16:00", weeks: [5])
        XCTAssertEqual(SchoolCourseAdjustments.conflicts(projected + [other], sourceKey: SchoolCourseAdjustments.key(source), weeks: [5]), ["另一门课"])
        other.weeks = [7]; XCTAssertTrue(SchoolCourseAdjustments.conflicts(projected + [other], sourceKey: SchoolCourseAdjustments.key(source), weeks: [5]).isEmpty)
        other.weeks = [5]; other.start = "15:55"; XCTAssertTrue(SchoolCourseAdjustments.conflicts(projected + [other], sourceKey: SchoolCourseAdjustments.key(source), weeks: [5]).isEmpty)
    }
    func testStableIDsAndCustomTimePersistence() throws {
        let snapshot = snapshot(), source = try XCTUnwrap(SchoolCourseAdjustments.originals(snapshot).first), periods = SchoolCourseAdjustments.periods(snapshot)
        XCTAssertEqual(SchoolCourseAdjustments.originals(snapshot).first?.id, source.id)
        var custom = change(source); custom.usesPeriods = false; custom.start = "13:12"; custom.end = "14:13"
        let records = try SchoolCourseAdjustments.updating([], term: term, source: source, weeks: [5], change: custom, periods: periods)
        let reopened = try JSONDecoder().decode([SchoolCourseAdjustment].self, from: JSONEncoder().encode(records))
        XCTAssertEqual(reopened, records)
        let projected = SchoolCourseAdjustments.project([source], term: term, records: reopened, periods: periods)
        XCTAssertEqual(projected[1].start, "13:12"); XCTAssertNil(projected[1].startPeriod)
    }
    @MainActor private func withSchoolStore(_ body: (CampusStore, ProtectedStorage, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        try storage.write(snapshot(), name: "academic")
        let store = CampusStore(storage: storage); try store.restoreAcademicCache(scope: scope)
        try body(store, storage, directory)
    }
    @MainActor func testStoreSavesReopensRestoresAndRejectsLoggedOutEditor() throws {
        try withSchoolStore { store, storage, _ in
            let source = try XCTUnwrap(store.courses.first)
            let context = try XCTUnwrap(store.schoolAdjustmentContext(for: source, date: store.schoolSemesterStart))
            try store.saveSchoolAdjustment(context, weeks: [5], change: change(source))
            let reopened = CampusStore(storage: storage); try reopened.restoreAcademicCache(scope: scope)
            XCTAssertEqual(reopened.courses.filter { $0.locallyAdjusted == true }.count, 1)
            let changed = try XCTUnwrap(reopened.courses.first { $0.locallyAdjusted == true })
            let restore = try XCTUnwrap(reopened.schoolAdjustmentContext(for: changed, date: reopened.schoolSemesterStart))
            try reopened.restoreSchoolAdjustment(restore)
            XCTAssertEqual(reopened.courses.count, 1); XCTAssertEqual(reopened.courses[0].weeks, [1,3,5,7,9,11])
            reopened.disconnectSchool()
            XCTAssertThrowsError(try reopened.saveSchoolAdjustment(restore, weeks: [5], change: change(source)))
            XCTAssertTrue(reopened.courses.isEmpty)
        }
    }
    @MainActor func testStorageFailureDoesNotPublishAdjustment() throws {
        try withSchoolStore { store, _, directory in
            let before = store.courses, source = try XCTUnwrap(store.courses.first)
            let context = try XCTUnwrap(store.schoolAdjustmentContext(for: source, date: store.schoolSemesterStart))
            try FileManager.default.removeItem(at: directory)
            XCTAssertThrowsError(try store.saveSchoolAdjustment(context, weeks: [5], change: change(source)))
            XCTAssertEqual(store.courses, before)
        }
    }
    @MainActor func testSchoolAdjustmentEditorRenders() throws {
        try withSchoolStore { store, _, _ in
            let context = try XCTUnwrap(store.schoolAdjustmentContext(for: try XCTUnwrap(store.courses.first), date: store.schoolSemesterStart))
            let controller = UIHostingController(rootView: SchoolCourseAdjustmentView(context: context).environmentObject(store))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)); window.rootViewController = controller; window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "school-course-adjustment-editor"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertGreaterThan(controller.view.bounds.width, 0)
            window.isHidden = true
        }
    }
}
