import XCTest
@testable import Hanyuantong

final class AcademicSessionTests: XCTestCase {
    func testOriginRejectsLookalikesCredentialsAndPorts() {
        XCTAssertTrue(AcademicSession.allowed(URL(string: "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html")))
        XCTAssertTrue(AcademicSession.allowed(URL(string: "https://jwgl.hdc.edu.cn:443/kbcx/query")))
        for url in ["http://jwgl.hdc.edu.cn/", "https://jwgl.hdc.edu.cn.evil.test/", "https://user@jwgl.hdc.edu.cn/", "https://jwgl.hdc.edu.cn:8443/", "file:///tmp/page", "javascript:alert(1)"] {
            XCTAssertFalse(AcademicSession.allowed(URL(string: url)), url)
        }
        XCTAssertFalse(AcademicSession.allowed(nil))
    }
    func testTermValidation() {
        XCTAssertTrue(AcademicTerm(xnm: "2026", xqm: "3").isValid)
        XCTAssertFalse(AcademicTerm(xnm: "2026", xqm: "1").isValid)
        XCTAssertFalse(AcademicTerm(xnm: "2026'", xqm: "12").isValid)
    }
    func testPeriodsRejectZeroReversedAndOutOfRange() {
        XCTAssertTrue(AcademicCourse.validPeriods("1-2"))
        XCTAssertTrue(AcademicCourse.validPeriods("13"))
        for value in ["0", "0-2", "5-2", "25", "1-25", "1-x"] {
            XCTAssertFalse(AcademicCourse.validPeriods(value), value)
        }
    }
    func testVerifiedGradeAndExamSchemaDecodes() throws {
        let grade: [String: Any] = ["name": "测试课程", "scoreText": "优秀", "credit": 2,
            "gpa": NSNull(), "term": "2026 秋", "kind": "必修", "courseCode": "TEST",
            "recordId": "fixture", "year": "2026", "termCode": "3", "examType": "正常考试"]
        let exam = ["name": "测试课程", "date": "2026-12-01", "time": "09:00-11:00", "room": "测试教室", "seat": "1"]
        let result = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope,
            "modules": ["grades": ["status": "ok", "data": [grade], "scope": "all"],
                        "exams": ["status": "ok", "data": [exam]]]])
        XCTAssertEqual(result.grades?.first?.scoreText, "优秀")
        XCTAssertEqual(result.grades?.first?.credit, 2)
        XCTAssertNil(result.grades?.first?.gpa)
        XCTAssertEqual(result.exams?.first?.seat, "1")
        XCTAssertEqual(result.gradeScope, "all")
        XCTAssertTrue(result.moduleErrors.isEmpty)
    }
    private let scope = "71B083B2-F34C-4A65-AE47-DAAA9574D812"
    private var term: AcademicTerm { AcademicTerm(xnm: "2026", xqm: "3") }
    private func previous() -> AcademicSnapshot {
        AcademicSnapshot(scope: scope, term: term,
            courses: [AcademicCourse(name: "测试课程", teacher: "", room: "", weekday: 1, periods: "1-2", weeks: "1-16周")],
            practice: [], grades: [], exams: [AcademicExam(name: "测试考试", date: "2026-12-01", time: "09:00", room: "", seat: "")],
            semesters: [term], moduleErrors: [:], updatedAt: Date(timeIntervalSince1970: 1))
    }
    func testFailedModulePreservesSuccessAndExplicitEmptyExamReplaces() throws {
        let payload: [String: Any] = ["session": "valid", "sessionScope": scope,
            "modules": ["timetable": ["status": "error", "code": "NETWORK"], "exams": ["status": "ok", "data": []]]]
        let next = try AcademicSnapshot.decode(payload).merging(previous: previous())
        XCTAssertEqual(next.courses, previous().courses)
        XCTAssertEqual(next.exams, [])
        XCTAssertEqual(next.moduleErrors["timetable"], "NETWORK")
    }
    func testAccountOrTermSwitchNeverInheritsOldData() throws {
        let changedAccount = try AcademicSnapshot.decode(["session": "valid", "sessionScope": UUID().uuidString, "modules": [:]])
        XCTAssertNil(changedAccount.merging(previous: previous()).courses)
        let changedTerm = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope,
            "requestedTerm": ["xnm": "2026", "xqm": "12"], "modules": [:]])
        XCTAssertNil(changedTerm.merging(previous: previous()).courses)
    }
    func testMalformedSuccessCannotEraseTimetable() throws {
        let result = try AcademicSnapshot.decode(["session": "valid", "sessionScope": scope,
            "modules": ["timetable": ["status": "ok", "data": ["term": ["xnm": "2026", "xqm": "3"], "kbList": [], "practice": []]]]])
        XCTAssertNil(result.courses)
        XCTAssertEqual(result.moduleErrors["timetable"], "SCHEMA")
        XCTAssertEqual(result.merging(previous: previous()).courses, previous().courses)
    }
    func testExpiryAndUnscopedPayloadCannotBecomeSnapshot() {
        XCTAssertThrowsError(try AcademicSnapshot.decode(["session": "expired"])) { error in
            XCTAssertEqual(error as? AcademicError, AcademicError(code: "EXPIRED"))
        }
        XCTAssertThrowsError(try AcademicSnapshot.decode(["session": "valid", "modules": [:]]))
    }
    func testCodableRoundTrip() throws {
        let value = previous()
        XCTAssertEqual(try JSONDecoder().decode(AcademicSnapshot.self, from: JSONEncoder().encode(value)), value)
    }
    func testResolvedTermSurvivesTimetableFailure() throws {
        let scope = UUID().uuidString
        let payload: [String: Any] = ["session": "valid", "sessionScope": scope,
            "resolvedTerm": ["xnm": "2026", "xqm": "3"],
            "modules": ["timetable": ["status": "error", "code": "NETWORK"],
                        "grades": ["status": "ok", "data": [], "scope": "all"],
                        "exams": ["status": "ok", "data": []]]]
        let result = try AcademicSnapshot.decode(payload)
        XCTAssertEqual(result.term, AcademicTerm(xnm: "2026", xqm: "3"))
        XCTAssertNil(result.courses)
        XCTAssertEqual(result.grades, [])
        XCTAssertEqual(result.exams, [])
        XCTAssertEqual(result.gradeScope, "all")
    }

}
