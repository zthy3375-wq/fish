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
}
