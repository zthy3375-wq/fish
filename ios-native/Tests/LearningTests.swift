import XCTest
import WebKit
@testable import Hanyuantong

final class LearningTests: XCTestCase {
    private func course(_ id: String = "12", clazz: String = "34") -> LearningCourse {
        LearningCourse(courseId: id, classId: clazz, cpi: "56", name: "合成课程", teacher: "测试教师", url: LearningPolicy.params("https://mooc1.chaoxing.com/visit/stucoursemiddle", ["courseid": id, "clazzid": clazz, "cpi": "56"]))
    }
    private func item(_ id: String = "78", status: String = "pending", deadline: String? = "2026-11-12T18:00") -> LearningItem {
        LearningItem(id: "12/34/homework/\(id)", courseId: "12", classId: "34", workId: id, kind: "homework", title: "合成作业", course: "合成课程", status: status, statusText: status == "submitted" ? "已提交" : "未提交", deadline: deadline)
    }
    func testOfficialHTTPSOriginBoundary() {
        for value in ["https://chaoxing.com/", "https://mooc1.chaoxing.com/mooc2/work/list", "https://passport2.chaoxing.com:443/login"] { XCTAssertTrue(LearningPolicy.allowed(value), value) }
        for value in ["http://mooc1.chaoxing.com/", "https://chaoxing.com.evil.test/", "https://notchaoxing.com/", "https://user@chaoxing.com/", "https://user:pass@chaoxing.com/", "https://chaoxing.com:8443/", "file:///tmp/x", "javascript:alert(1)", "https://chaoxing.com\\@evil.test/", "https://chaoxing.com./"] { XCTAssertFalse(LearningPolicy.allowed(value), value) }
    }
    func testReadPolicyDoesNotAuthorizeSubmission() {
        XCTAssertTrue(LearningPolicy.safeRead("https://mooc1.chaoxing.com/mooc2/work/task?workId=78"))
        XCTAssertFalse(LearningPolicy.safeRead("https://mooc1.chaoxing.com/work/submit"))
        XCTAssertFalse(LearningPolicy.safeRead("https://mooc1.chaoxing.com/mooc2/work/list/../submit"))
        XCTAssertFalse(LearningPolicy.sameCourse("https://mooc1.chaoxing.com/mooc2/work/list?courseId=99&classId=34", course: course()))
        XCTAssertFalse(LearningPolicy.sameCourse("https://mooc1.chaoxing.com/mooc2/work/list?courseId=12&clazzId=99", course: course()))
    }
    func testIDsAreASCIIBounded() {
        XCTAssertTrue(LearningPolicy.numeric("123456"))
        XCTAssertFalse(LearningPolicy.numeric("１２３"))
        XCTAssertFalse(LearningPolicy.numeric(String(repeating: "1", count: 25)))
        XCTAssertFalse(LearningPolicy.numeric(""))
    }
    func testParameterEncodingPreservesSigns() {
        let url = LearningPolicy.params("https://mooc1.chaoxing.com/mooc2/work/list", ["enc": "test+value/part=", "courseId": "12"])
        XCTAssertEqual(LearningPolicy.query(url)["enc"], "test+value/part=")
        XCTAssertTrue(url.contains("%2B"))
    }
    func testJSONCourseAccountAssociationAndDuplicateHandling() throws {
        let json = #"{"result":true,"channelList":[{"content":{"id":34,"cpi":"56","course":{"data":[{"id":"12","name":"合成课程","teacherfactor":"测试教师"}]}}},{"content":{"id":"34","cpi":"56","course":{"data":[{"id":"12","name":"更新名称"}]}}}]}"#
        let parsed = try XCTUnwrap(LearningHTML.coursesJSON(json))
        XCTAssertTrue(parsed.complete)
        XCTAssertEqual(parsed.courses.count, 1)
        XCTAssertEqual(parsed.courses.first?.key, "12/34")
        XCTAssertEqual(parsed.courses.first?.name, "更新名称")
    }
    func testUnknownAndRejectedCoursesAreNotSuccessfulEmpty() throws {
        XCTAssertNil(try LearningHTML.coursesJSON("<p>加载中</p>"))
        XCTAssertThrowsError(try LearningHTML.coursesJSON(#"{"result":false,"message":"请先登录"}"#))
        XCTAssertThrowsError(try LearningHTML.coursesJSON(#"{"result":true,"channelList":[{"content":{"id":"34","cpi":"56","course":{"data":[{"id":"invalid","name":"无效"}]}}}]}"#))
        let validEmpty = try XCTUnwrap(LearningHTML.coursesJSON(#"{"result":true,"channelList":[]}"#))
        XCTAssertTrue(validEmpty.complete); XCTAssertTrue(validEmpty.courses.isEmpty)
    }
    func testJSONPartialCoursesAreExplicit() throws {
        let parsed = try XCTUnwrap(LearningHTML.coursesJSON(#"{"result":true,"channelList":[{"content":{"id":"34","cpi":"56","course":{"data":[{"id":"12","name":"有效课程"},{"id":"BAD","name":"无效课程"}]}}}]}"#))
        XCTAssertFalse(parsed.complete); XCTAssertEqual(parsed.courses.count, 1)
    }
    func testNotificationContentIsTextOnly() throws {
        let list = try LearningHTML.noticesJSON(#"{"status":true,"notices":{"list":[{"id":"1","title":"合成通知","content":"<script>BAD</script><p>内容 &amp; &#20013;</p>","sendName":"老师"}]}}"#)
        XCTAssertEqual(list.first?.content, "内容 & 中")
        XCTAssertFalse(list.first?.content.contains("BAD") ?? true)
        XCTAssertThrowsError(try LearningHTML.noticesJSON(#"{"status":true,"notices":{"list":[{"id":"1"}]}}"#))
    }
    func testStatusAndDatesDoNotInferSubmissionOrYear() {
        XCTAssertEqual(LearningHTML.status("未提交，已截止"), "pending")
        XCTAssertEqual(LearningHTML.status("已提交后退回"), "pending")
        XCTAssertEqual(LearningHTML.status("待批阅"), "submitted")
        XCTAssertEqual(LearningHTML.status("已结束"), "closed")
        XCTAssertEqual(LearningHTML.dates("2026-02-30 12:00"), [])
        XCTAssertEqual(LearningHTML.dates("2028-02-29 12:00"), ["2028-02-29T12:00"])
        XCTAssertNil(LearningHTML.deadline("截止时间：11-12 18:00"))
        XCTAssertNil(LearningHTML.deadline("提交时间：2026-11-12 18:00"))
        XCTAssertEqual(LearningHTML.deadline("作答时间：2026-11-11 08:00 至 2026-11-12 18:00"), "2026-11-12T18:00")
    }
    func testUnknownObservationRetainsKnownStatusAndDeadline() throws {
        var cache = LearningCache(); cache.items = [item(status: "submitted")]
        var incoming = item(status: "unknown", deadline: nil); incoming.statusText = "未知"
        try cache.merge([incoming])
        XCTAssertEqual(cache.items.first?.status, "submitted")
        XCTAssertEqual(cache.items.first?.deadline, "2026-11-12T18:00")
        XCTAssertTrue(cache.items.first?.stale == true)
    }
    func testCompleteEmptyMarksStaleButNeverDeletesOrSubmits() throws {
        var cache = LearningCache(); cache.items = [item()]
        try cache.merge([], completeCourse: "12/34")
        XCTAssertEqual(cache.items.count, 1)
        XCTAssertEqual(cache.items[0].status, "pending")
        XCTAssertTrue(cache.items[0].stale)
    }
    func testPartialEmptyDoesNotModifySuccessfulItems() throws {
        var cache = LearningCache(); let old = item(); cache.items = [old]
        try cache.merge([])
        XCTAssertEqual(cache.items, [old])
    }
    func testForeignCourseCompletionDoesNotMarkAnotherCourseStale() throws {
        var cache = LearningCache(); cache.items = [item()]
        try cache.merge([], completeCourse: "99/34")
        XCTAssertFalse(cache.items[0].stale)
    }
    func testMalformedItemFailsRatherThanInventingAssociation() throws {
        var cache = LearningCache(); cache.items = [item()]
        var bad = item(); bad.classId = "99"
        XCTAssertThrowsError(try cache.merge([bad]))
        XCTAssertEqual(cache.items, [item()])
    }
    func testEncryptedCacheScopeValidationAndResumeMode() throws {
        var cache = LearningCache(); cache.account = String(repeating: "a", count: 24); cache.session = "valid"
        cache.courses = [course()]; cache.items = [item()]; cache.activeCourses = ["12/34"]; cache.activeExtras = false; cache.cursor = 0
        let restored = try JSONDecoder().decode(LearningCache.self, from: JSONEncoder().encode(cache))
        XCTAssertFalse(try restored.validated(account: cache.account).activeExtras)
        XCTAssertEqual(restored.activeCourses, ["12/34"])
        XCTAssertThrowsError(try restored.validated(account: String(repeating: "b", count: 24)))
        cache.cursor = 2
        XCTAssertThrowsError(try cache.validated(account: cache.account))
    }
    func testDuplicateCacheIdentitiesRejectedBeforeMerge() {
        var cache = LearningCache(); cache.account = String(repeating: "a", count: 24); cache.courses = [course(), course()]
        XCTAssertThrowsError(try cache.validated(account: cache.account))
    }
    func testOverduePendingIsNotSubmitted() throws {
        let now = try XCTUnwrap(LearningDisplay.date("2026-11-13T12:00"))
        XCTAssertEqual(LearningDisplay.state(item(), now: now).key, "closed")
        XCTAssertEqual(LearningDisplay.state(item(status: "submitted"), now: now).key, "submitted")
        XCTAssertEqual(LearningDisplay.state(item(status: "unknown"), now: now).key, "unknown")
    }
    func testPayloadBoundedBeforeParsing() {
        XCTAssertThrowsError(try LearningHTML.coursesJSON(String(repeating: "中", count: 500_001)))
    }

    func testLearningCacheUsesAccountScopedSealedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try ProtectedStorage(directory: directory)
        var cache = LearningCache(); cache.account = String(repeating: "a", count: 24); cache.items = [item()]
        let name = "learning-" + cache.account
        try storage.write(cache, name: name)
        let raw = try Data(contentsOf: directory.appendingPathComponent(name + ".sealed"))
        XCTAssertNil(String(data: raw, encoding: .utf8))
        XCTAssertNil(try storage.read("learning-" + String(repeating: "b", count: 24), as: LearningCache.self))
        let loaded = try XCTUnwrap(storage.read(name, as: LearningCache.self))
        XCTAssertEqual(loaded.items.first?.title, "合成作业")
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    @MainActor
    private func html<T: Decodable>(_ operation: String, _ source: String, as: T.Type) async throws -> T {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let rules = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "learning-test-inert-v1", encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#)
        config.userContentController.add(try XCTUnwrap(rules))
        let web = WKWebView(frame: .zero, configuration: config)
        let c = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course()))
        let raw = try await web.callAsyncJavaScript(LearningHTML.script, arguments: ["operation": operation, "html": source, "baseURL": "https://mooc1.chaoxing.com/mooc2/work/list", "course": c, "item": NSNull()], in: nil, contentWorld: .defaultClient)
        let value = try XCTUnwrap(raw as? String)
        return try JSONDecoder().decode(T.self, from: Data(value.utf8))
    }
    @MainActor
    func testActualWebKitInertWorkParser() async throws {
        let source = #"<li onclick="goTask(this)" data="https://mooc1.chaoxing.com/mooc2/work/task?courseId=12&amp;classId=34&amp;workId=78&amp;enc=TEST_ONLY"><p class="title">合成作业</p><p class="status">待做</p><span class="time">截止时间：2026-11-12 18:00</span></li>"#
        let parsed = try await html("work", source, as: LearningParsedWork.self)
        XCTAssertTrue(parsed.complete); XCTAssertEqual(parsed.records.first?.id, "12/34/homework/78")
        XCTAssertEqual(parsed.records.first?.deadline, "2026-11-12T18:00")
    }
    @MainActor
    func testUnknownHiddenAndChallengeHTMLCannotClearWork() async throws {
        for source in ["<p>加载中</p>", "<script>const a='暂无作业';</script>", "<div hidden>暂无作业</div>", "<p>请输入验证码</p><p>暂无作业</p>", "<p>没有此页面访问权限</p><p>暂无作业</p>"] {
            let parsed = try await html("work", source, as: LearningParsedWork.self)
            XCTAssertFalse(parsed.recognized, source); XCTAssertFalse(parsed.complete, source)
        }
        let empty = try await html("work", "<p>老师尚未发布作业</p>", as: LearningParsedWork.self)
        XCTAssertTrue(empty.complete); XCTAssertTrue(empty.records.isEmpty)
    }
    @MainActor
    func testOnlySuppliedSameCourseFramesAreReturned() async throws {
        let source = #"<iframe src="/mooc2/work/list?courseId=99&amp;classId=34"></iframe><a href="/mooc2/work/list?courseId=12&amp;classId=34">作业</a><input name="workEnc" value="WORK_TEST"><input name="enc" value="STUDENT_TEST">"#
        let nav = try await html("navigation", source, as: LearningNavigation.self)
        XCTAssertNil(nav.workFrame); XCTAssertNotNil(nav.menu)
        XCTAssertEqual(nav.workEnc, "WORK_TEST"); XCTAssertEqual(nav.stuenc, "STUDENT_TEST")
    }
    @MainActor
    func testWorkParserRejectsCrossCourseAndWriteLinks() async throws {
        for target in ["https://mooc1.chaoxing.com/work/submit?courseId=12&classId=34&workId=78", "https://mooc1.chaoxing.com/mooc2/work/task?courseId=99&classId=34&workId=78"] {
            let parsed = try await html("work", "<li onclick='goTask(this)' data='\(target)'><p class='title'>合成作业</p></li>", as: LearningParsedWork.self)
            XCTAssertEqual(parsed.rejected, 1); XCTAssertFalse(parsed.complete)
        }
    }
}
