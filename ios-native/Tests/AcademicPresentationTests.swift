import XCTest
@testable import Hanyuantong

final class AcademicPresentationTests: XCTestCase {
    private func row(_ name: String = "测试课程", score: String = "80", credit: String = "2", gpa: Double? = nil, code: String = "TEST", term: String = "3", year: String = "2026", record: String = "") -> GradeRecord {
        GradeRecord(name: name, score: score, credit: credit, term: year + " " + term, schoolGPA: gpa, courseCode: code, recordId: record, year: year, termCode: term)
    }
    func testSchoolGPAIsNeverInferredFromScore() {
        let report = NativeGradeReport([row(score: "100")])
        XCTAssertEqual(report.summary().mean, 100)
        XCTAssertNil(report.summary().gpa)
        XCTAssertEqual(report.summary().gpaCount, 0)
    }
    func testWeightedGradeAndSchoolGPAUseIndependentCoverage() {
        let report = NativeGradeReport([row(score: "80", credit: "2", gpa: 3, code: "A"), row("等级课程", score: "优秀", credit: "1", gpa: 4, code: "B"), row("另一课程", score: "100", credit: "1", code: "C")])
        XCTAssertEqual(report.summary().numericCount, 2)
        XCTAssertEqual(report.summary().weightedMean!, 260.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(report.summary().gpa!, 10.0 / 3, accuracy: 0.00001)
        XCTAssertEqual(report.summary().earnedCredits, 4)
    }
    func testRetakesDoNotPickBestOrLastAndCreditsCountOnce() {
        let report = NativeGradeReport([row(score: "50", term: "3"), row(score: "90", term: "12")])
        XCTAssertNil(report.summary().mean)
        XCTAssertEqual(report.summary().earnedCredits, 2)
        XCTAssertEqual(report.summary(term: "2026–2027 秋季").earnedCredits, 0)
        XCTAssertEqual(report.summary(term: "2026–2027 春季").earnedCredits, 2)
        XCTAssertEqual(report.groups.first?.resolved, true)
    }
    func testMissingCourseCodeMakesSharedNameAmbiguous() {
        let report = NativeGradeReport([row(score: "50", code: ""), row(score: "90", code: "A")])
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups.first?.ambiguous, true)
        XCTAssertEqual(report.groups.first?.state, .unknown)
        XCTAssertEqual(report.summary().earnedCredits, 0)
        XCTAssertNil(report.summary().mean)
    }
    func testConflictingPassedCreditsAreExcludedAndDuplicateCollapsed() {
        let a = row(score: "80", credit: "2")
        let report = NativeGradeReport([a, a, row(score: "90", credit: "3")])
        XCTAssertEqual(report.duplicates, 1)
        XCTAssertEqual(report.summary().earnedCredits, 0)
        XCTAssertNil(report.summary().mean)
    }
    func testPendingAttemptDoesNotReplaceOnePublishedResult() {
        let report = NativeGradeReport([row(score: "80"), row(score: "缓考", term: "12")])
        XCTAssertEqual(report.summary().mean, 80)
        XCTAssertEqual(report.summary().earnedCredits, 2)
    }
    func testNumericAndLevelSemanticsAndTermFilter() {
        XCTAssertEqual(NativeGradeReport.value("５９分").0, .failed)
        XCTAssertEqual(NativeGradeReport.value("101").0, .unknown)
        XCTAssertEqual(NativeGradeReport.value("合格").0, .passed)
        XCTAssertNil(NativeGradeReport.value("优秀").1)
        XCTAssertEqual(NativeGradeReport.value("缓考").0, .pending)
        let report = NativeGradeReport([row(term: "3"), row("另一门", code: "B", term: "12")])
        XCTAssertEqual(report.filtered(term: "2026–2027 秋季", query: " 测试 ", kind: "all", state: "passed", band: "80–89", sort: "score-desc").count, 1)
    }
    func testInvalidCreditAndGPAExcluded() {
        let report = NativeGradeReport([row(credit: "-1", gpa: .infinity)])
        XCTAssertNil(report.summary().gpa)
        XCTAssertNil(report.summary().weightedMean)
        XCTAssertEqual(report.summary().earnedCredits, 0)
    }
    func testSchoolProfileIsBoundedPreservedOnlyWithinAccountAndCodable() throws {
        let scope = UUID().uuidString
        let profile = ["name": "测试姓名", "major": "测试专业", "className": "测试班", "year": "2026"]
        let initial = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope, "modules": ["profile": ["status": "ok", "data": profile]]])
        XCTAssertEqual(initial.profile?.major, "测试专业")
        let roundTrip = try JSONDecoder().decode(AcademicSnapshot.self, from: JSONEncoder().encode(initial))
        XCTAssertEqual(roundTrip.profile, initial.profile)
        let failed = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope, "modules": ["profile": ["status": "error", "code": "NETWORK"]]])
        XCTAssertEqual(failed.merging(previous: initial).profile, initial.profile)
        let changed = try AcademicSnapshot.decode(["session": "valid", "sessionScope": UUID().uuidString, "modules": [:]])
        XCTAssertNil(changed.merging(previous: initial).profile)
        let empty = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope, "modules": ["profile": ["status": "ok", "data": ["name": "", "major": "", "className": "", "year": ""]]]])
        XCTAssertNil(empty.profile)
        XCTAssertEqual(empty.merging(previous: initial).profile, initial.profile)
        XCTAssertFalse(AcademicProfile(name: String(repeating: "a", count: 61), major: "", className: "", year: "").isValid)
    }
    func testExamUpcomingUsesCampusDayAndRetainsUnknownSeparately() {
        let today = ExamRecord(name: "今天", date: "2026-11-12", time: "08:00")
        let tomorrow = ExamRecord(name: "明天", date: "2026/11/13")
        let past = ExamRecord(name: "昨天", date: "2026-11-11")
        let unknown = ExamRecord(name: "待定", date: "待定")
        let impossible = ExamRecord(name: "异常", date: "2026-02-30")
        let now = ISO8601DateFormatter().date(from: "2026-11-11T18:00:00Z")!
        XCTAssertEqual(NativeExamPresentation.upcoming([past, unknown, tomorrow, today, impossible], now: now).map(\.name), ["今天", "明天"])
        XCTAssertEqual(NativeExamPresentation.unknownDates([unknown, impossible]).count, 2)
        XCTAssertEqual(NativeExamPresentation.dayLabel(today, now: now), "今天")
        XCTAssertEqual(NativeExamPresentation.dayLabel(tomorrow, now: now), "1 天后")
    }
}
