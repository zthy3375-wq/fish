import XCTest
@testable import Hanyuantong

final class ScheduleMathTests: XCTestCase {
    func testCompressedLunchAndCustomCoursesUseTheSameAxis() {
        let slots = [AndroidTimeSlot(number: 1, start: "11:00", end: "11:45"),
                     AndroidTimeSlot(number: 2, start: "14:00", end: "14:40")]
        let regular = SchedulePeriodAxis(slots: slots, events: [])
        XCTAssertEqual(regular.position(840), 1.35, accuracy: 0.001)
        XCTAssertEqual(regular.units, 2.35, accuracy: 0.001)
        let extended = SchedulePeriodAxis(slots: slots, events: [630..<665, 720..<735, 890..<920])
        XCTAssertEqual(extended.position(660), 30.0 / 45, accuracy: 0.001)
        XCTAssertEqual(extended.position(735) - extended.position(720), 15.0 / 45, accuracy: 0.001)
        XCTAssertEqual(extended.position(920) - extended.position(880), 40.0 / 45, accuracy: 0.001)
    }

    func testChineseWeekRangesAndParity() {
        XCTAssertEqual(ScheduleMath.parseRange("1-8周(单),10-14周(双),17周", limit: 30), [1,3,5,7,10,12,14,17])
        XCTAssertEqual(ScheduleMath.parseRange("1－3，5、7", limit: 13), [1,2,3,5,7])
        XCTAssertEqual(ScheduleMath.parseRange("0,99,8-2", limit: 30), [])
    }
    func testCampusWeekAndWeekday() {
        let calendar = ScheduleMath.calendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        XCTAssertEqual(ScheduleMath.week(on: start, start: start), 1)
        XCTAssertEqual(ScheduleMath.weekday(on: start), 1)
        XCTAssertEqual(ScheduleMath.week(on: calendar.date(byAdding: .day, value: -1, to: start)!, start: start), 0)
        XCTAssertEqual(ScheduleMath.week(on: calendar.date(byAdding: .day, value: 7, to: start)!, start: start), 2)
    }
    func testOfficialPeriodMappingPreservesThirteenPeriods() {
        XCTAssertEqual(ScheduleMath.starts.count, 13)
        XCTAssertEqual(ScheduleMath.ends.count, 13)
        XCTAssertEqual(ScheduleMath.starts[5], "14:30")
        XCTAssertEqual(ScheduleMath.ends[12], "21:10")
    }
}
