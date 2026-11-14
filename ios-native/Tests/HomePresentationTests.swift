import XCTest
@testable import Hanyuantong

final class HomePresentationTests: XCTestCase {
    private let monday = BackupValue.dayDate("2026-09-14")
    func testProgressAndRemainingMinutesUseActualTimeAndClampBoundaries() {
        let focus = HomeCourseFocus(course: Course(name: "合成课程", day: 1, start: "08:00", end: "09:00", weeks: [1]), start: monday, end: monday.addingTimeInterval(3600))
        XCTAssertEqual(focus.progress(at: monday.addingTimeInterval(-1)), 0)
        XCTAssertEqual(focus.progress(at: monday.addingTimeInterval(1800)), 0.5)
        XCTAssertEqual(focus.progress(at: monday.addingTimeInterval(7200)), 1)
        XCTAssertEqual(focus.remainingMinutes(at: monday.addingTimeInterval(3599)), 1)
        XCTAssertEqual(focus.remainingMinutes(at: monday.addingTimeInterval(3600)), 0)
    }
    func testCurrentCourseWinsAndEndsExactlyOnTime() {
        let courses = [Course(name: "正在上课", day: 1, start: "08:00", end: "09:00", weeks: [1]), Course(name: "下一节", day: 1, start: "10:00", end: "11:00", weeks: [1])]
        let now = monday.addingTimeInterval(8.5 * 3600)
        let focus = HomeCourseFocus.select(courses: courses, personalStart: monday, schoolStart: monday, now: now)
        XCTAssertEqual(focus?.course.name, "正在上课"); XCTAssertTrue(focus?.isCurrent(at: now) == true)
        XCTAssertEqual(HomeCourseFocus.select(courses: courses, personalStart: monday, schoolStart: monday, now: monday.addingTimeInterval(9 * 3600))?.course.name, "下一节")
    }
    func testSparseFutureWeeksAndNoFutureCourse() {
        let course = Course(name: "第三周", day: 1, start: "08:00", end: "09:00", weeks: [3])
        XCTAssertEqual(HomeCourseFocus.select(courses: [course], personalStart: monday, schoolStart: monday, now: monday)?.start, monday.addingTimeInterval(14 * 86400 + 8 * 3600))
        XCTAssertNil(HomeCourseFocus.select(courses: [course], personalStart: monday, schoolStart: monday, now: monday.addingTimeInterval(15 * 86400)))
    }
    func testSchoolAndPersonalCalendarsRemainIndependent() {
        let later = monday.addingTimeInterval(14 * 86400)
        let school = Course(name: "学校第三周", day: 1, start: "08:00", end: "09:00", weeks: [3], source: "school")
        let personal = Course(name: "个人第一周", day: 1, start: "10:00", end: "11:00", weeks: [1])
        XCTAssertEqual(HomeCourseFocus.select(courses: [personal, school], personalStart: later, schoolStart: monday, now: later)?.course.name, "学校第三周")
    }
    func testMalformedCourseIsNotPresentedAsUpcoming() {
        let courses = [Course(name: "错误时间", day: 1, start: "8:00", end: "09:00", weeks: [1]), Course(name: "错误星期", day: 8, start: "08:00", end: "09:00", weeks: [1])]
        XCTAssertNil(HomeCourseFocus.select(courses: courses, personalStart: monday, schoolStart: monday, now: monday))
    }
}
