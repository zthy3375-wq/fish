import XCTest

final class HonorParityUITests:XCTestCase {
    func test01FiveTabsAndCollectionAcrossLaunches() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launch()
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label),["首页","课表","社区","待办","我的"])
        capture("home",app)
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.buttons["添加课程"].waitForExistence(timeout:6))
        capture("schedule",app)
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "添加", "第1节课程")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.navigationBars["添加课程"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["跳转教学周"].exists)
        XCTAssertTrue(app.staticTexts["教学周不对？校准本周"].exists || app.buttons["教学周不对？校准本周"].exists)
        app.buttons["整周总览"].tap()
        XCTAssertTrue(app.buttons["舒适阅读"].waitForExistence(timeout: 5))
        app.buttons["舒适阅读"].tap()
        app.tabBars.buttons["社区"].tap()
        let connectedOrFailed = NSPredicate { _, _ in
            app.buttons["重试连接"].exists || app.secureTextFields.firstMatch.exists || app.buttons["发帖"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: connectedOrFailed, object: app)], timeout: 70), .completed)
        capture("community",app)
        app.tabBars.buttons["待办"].tap()
        XCTAssertTrue(app.buttons["添加待办"].waitForExistence(timeout:6))
        capture("tasks",app)
        app.tabBars.buttons["我的"].tap()
        let shelf=app.buttons["open-achievement-hall"]
        XCTAssertTrue(shelf.waitForExistence(timeout:6))
        let shortcuts = ["成绩与学业", "考试安排", "学期校历", "桌面课表"].map { app.buttons[$0] }
        for button in shortcuts { XCTAssertTrue(button.isHittable, button.label) }
        let bounds = shortcuts.map(\.frame)
        XCTAssertLessThan((bounds.map(\.midY).max() ?? 0) - (bounds.map(\.midY).min() ?? 0), 8)
        XCTAssertEqual(bounds.map(\.minX), bounds.map(\.minX).sorted())
        capture("profile",app)
        app.buttons["profile-settings"].tap()
        XCTAssertTrue(app.navigationBars["设置与帮助"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
        capture("settings",app)
        app.navigationBars.buttons.firstMatch.tap()
        shelf.tap()
        let hidden=app.buttons["隐藏"]
        XCTAssertTrue(app.navigationBars["荣誉殿堂"].waitForExistence(timeout:6))
        XCTAssertTrue(app.staticTexts["成就收藏馆"].exists)
        XCTAssertFalse(app.navigationBars["成就详情"].exists)
        XCTAssertTrue(hidden.waitForExistence(timeout:6))
        capture("gallery",app)
        XCTAssertTrue(hidden.isHittable)
        hidden.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format:"label CONTAINS %@", "隐藏成就")).firstMatch.exists)
        app.terminate(); app.launch(); app.tabBars.buttons["我的"].tap(); app.buttons["open-achievement-hall"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format:"label CONTAINS %@", "你好，邯院")).firstMatch.waitForExistence(timeout:5))
    }
    func testAndroidQuickEntryAndDayAgenda() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["待办"].tap()
        app.buttons["未安排"].tap()
        let title = "Quick-" + String(UUID().uuidString.prefix(6))
        let field = app.textFields["quick-task-title"]
        field.tap()
        field.typeText(title + "\n")
        XCTAssertTrue(app.buttons["完成：" + title].waitForExistence(timeout: 6))
        app.segmentedControls.buttons["日程"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["后一天日程"].tap()
        let weekRange = app.segmentedControls.buttons["未来7天"]
        weekRange.tap()
        XCTAssertTrue(weekRange.isSelected)
        app.buttons["添加待办"].tap()
        XCTAssertTrue(app.navigationBars["添加待办"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["task-plan-date"].firstMatch.exists,
                      "A task started from the agenda inherits a plan date")
        app.buttons["取消"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["待办"].tap()
        app.buttons["未安排"].tap()
        XCTAssertTrue(app.buttons["完成：" + title].waitForExistence(timeout: 5))
    }

    func testCommunityQuickReplyKeepsDraftAndRetriesInPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HYT_REPLY_UI_FIXTURE"] = try replyFixture()
        app.launch()
        app.tabBars.buttons["社区"].tap()
        let title = app.buttons["快捷回复测试帖"]
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        title.tap()
        let entry = app.buttons["community-quick-reply"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertEqual(entry.label, "说点什么吧…")
        capture("quick-reply-entry", app)
        entry.tap()

        let input = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label == %@", "community-reply-input", "你的回复")).matching(NSPredicate(format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.textView.rawValue, XCUIElement.ElementType.textField.rawValue)).firstMatch
        let submit = app.buttons["发布回复"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(submit.isHittable)
        XCTAssertTrue(app.buttons["添加评论图片"].isHittable)
        let anonymous = app.buttons["匿名回复"]
        XCTAssertEqual(anonymous.value as? String, "已关闭")
        anonymous.tap()
        XCTAssertEqual(anonymous.value as? String, "已开启")

        input.typeText("Quick reply")
        XCTAssertTrue(submit.isEnabled)
        capture("quick-reply-editor", app)
        app.buttons["收起回复编辑器"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.label, "继续编辑回复…")
        entry.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Quick reply")
        XCTAssertEqual(anonymous.value as? String, "已开启")
        submit.tap()

        let retry = app.buttons["重试回复"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertEqual(input.value as? String, "Quick reply")
        capture("quick-reply-retry", app)
        retry.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertEqual(entry.label, "说点什么吧…")
        app.buttons["查看评论"].tap()
        XCTAssertTrue(app.staticTexts["Quick reply"].waitForExistence(timeout: 5))
    }

    private func replyFixture() throws -> String {
        func response(_ payload: [String: Any], status: Int = 200) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return ["status": status, "json": String(decoding: data, as: UTF8.self)]
        }
        let postID = "57932B87-002B-4ECC-A874-072227D3DA2D"
        let author: [String: Any] = ["name": "测试同学", "anonymous": false, "mine": false]
        let post: [String: Any] = [
            "id": postID, "title": "快捷回复测试帖", "body": "", "createdAt": "2026-11-21T05:00:00Z",
            "anonymous": false, "locked": false, "liked": false, "saved": false,
            "author": author, "commentCount": 0, "likeCount": 0, "category": "daily"
        ]
        var updated = post
        updated["commentCount"] = 1
        let comment: [String: Any] = [
            "id": "4D45E3F4-1DCD-4822-965E-B17E9CA0DD41", "postId": postID, "body": "Quick reply",
            "createdAt": "2026-11-21T05:10:00Z", "author": ["name": "匿名同学", "anonymous": true, "mine": true],
            "deleted": false, "isOriginalPoster": false
        ]
        let member: [String: Any] = ["id": "D815C068-2752-4B3B-A6C9-EEB1B7A245CF", "username": "fixture", "nickname": "测试用户", "role": "member"]
        let configuration = try response([
            "user": member, "config": ["engagementEnabled": true, "commentImagesEnabled": true],
            "posts": [post]
        ])
        let fixture = [
            "me": [configuration],
            "posts.get": [try response(["post": post, "comments": []]), try response(["post": updated, "comments": [comment]])],
            "comments.create": [try response(["error": "network_unavailable"], status: 503), try response(["comment": comment])]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }

    private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:app.screenshot()); image.name="parity-"+name; image.lifetime = .keepAlways; add(image)
    }
}
