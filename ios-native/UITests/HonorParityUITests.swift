import XCTest
import Network

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
        let photoServer = try serveCampusPhoto()
        defer { photoServer.cancel() }
        let port = try XCTUnwrap(photoServer.port).rawValue
        app.launchEnvironment["HYT_REPLY_UI_FIXTURE"] = try replyFixture(photoURL: "http://127.0.0.1:\(port)/campus.jpg")
        app.launch()
        app.tabBars.buttons["社区"].tap()
        let title = app.buttons["快捷回复测试帖"]
        XCTAssertTrue(title.waitForExistence(timeout: 12))
        for label in ["广场", "关注", "继续聊", "全部", "校园", "学习", "兴趣", "搭子", "树洞", "帖子排序", "选择回应"] {
            XCTAssertTrue(app.buttons[label].exists, label)
        }
        let photo = app.buttons["查看配图 1，共 1 张"]
        XCTAssertTrue(photo.isHittable)
        XCTAssertGreaterThan(photo.frame.width, 140)
        XCTAssertEqual(photo.frame.width / photo.frame.height, 1.5, accuracy: 0.05)
        XCTAssertTrue(app.buttons["查看评论，共 0 条"].isHittable)
        XCTAssertTrue(app.buttons["点赞"].isHittable)
        photo.tap()
        let close = app.buttons["关闭图片"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["community-zoomed-photo"].firstMatch.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        capture("community-signed-in-feed", app)
        app.buttons["学习"].tap()
        XCTAssertTrue(app.buttons["考研"].waitForExistence(timeout: 5))
        app.buttons["继续聊"].tap()
        XCTAssertTrue(app.buttons["关注的讨论"].waitForExistence(timeout: 5))
        app.buttons["广场"].tap()
        XCTAssertTrue(app.buttons["学习"].waitForExistence(timeout: 5))
        title.tap()
        let entry = app.buttons["community-quick-reply"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertEqual(entry.label, "说点什么吧…")
        capture("quick-reply-entry", app)
        entry.tap()

        let replyInput = NSPredicate(format: "identifier == %@ OR label == %@", "community-reply-input", "你的回复")
        let textView = app.textViews.matching(replyInput).firstMatch
        let textField = app.textFields.matching(replyInput).firstMatch
        let inputReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in textView.exists || textField.exists }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [inputReady], timeout: 5), .completed)
        let input = textView.exists ? textView : textField
        let submit = app.buttons["发布回复"]
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
        app.buttons["返回社区"].tap()
        XCTAssertTrue(app.buttons["快捷回复测试帖"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["社区"].isSelected)
    }

    func testCommunityAchievementProgressAndOfflineReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let owner = UUID().uuidString
        func openHall(account: String, offline: Bool) throws {
            let member: [String: Any] = ["id": account, "username": "gallery", "nickname": "收藏测试", "role": "member"]
            let item: [String: Any] = ["id": "definition", "code": "campus-observer", "name": "今天的邯院",
                "category": "contribution", "rarity": "common", "displayKind": "achievement",
                "archived": false, "publicHidden": false, "awardId": "earned", "at": "2026-11-01T10:00:00Z"]
            let hall: [String: Any] = ["id": account, "nickname": "收藏测试", "badges": [:], "honors": [],
                "showcase": [], "total": 0, "awards": [:], "progress": ["posts": 2]]
            let collection: [String: Any] = ["id": account, "nickname": "收藏测试", "items": [item],
                "badges": [:], "identities": [], "useTitle": false, "total": 1, "rarities": ["common": 1], "unseen": []]
            func response(_ json: [String: Any], status: Int = 200) throws -> [[String: Any]] {
                [["status": status, "json": String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self)]]
            }
            let unavailable = try response(["error": "temporarily_unavailable"], status: 503)
            let fixture = [
                "me": try response(["user": member, "config": ["honorCollectionEnabled": true], "posts": []]),
                "honors.hall": offline ? unavailable : try response(["hall": hall]),
                "collection.profile": offline ? unavailable : try response(["collection": collection])
            ]
            app.launchEnvironment["HYT_REPLY_UI_FIXTURE"] = String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
            app.launch()
            app.tabBars.buttons["社区"].tap()
            XCTAssertTrue(app.buttons["发帖"].waitForExistence(timeout: 8))
            app.tabBars.buttons["我的"].tap()
            app.buttons["open-achievement-hall"].tap()
            app.scrollViews.buttons["社区"].firstMatch.tap()
        }
        try openHall(account: owner, offline: false)
        let badge = app.buttons["achievement-campus-observer"]
        let earned = NSPredicate(format: "label CONTAINS %@", "已解锁")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: earned, object: badge)], timeout: 8), .completed)
        app.buttons["achievement-sprout"].tap()
        let progress = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "2 / 5", "2 / 5")
        ).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        app.terminate()
        try openHall(account: owner, offline: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: earned, object: badge)], timeout: 8), .completed)
        app.terminate()
        try openHall(account: UUID().uuidString, offline: true)
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(badge.label.contains("待同步"))
    }

    func testHomeFishRespondsToRealTapsAndHoldAndKeepsAwards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let fish = app.buttons["home-mascot"]
        XCTAssertTrue(fish.waitForExistence(timeout: 6) && fish.isHittable)
        fish.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(fish.value as? String, "咕噜")
        fish.press(forDuration: 3.4)
        XCTAssertEqual(fish.value as? String, "呼……")
        fish.tap(withNumberOfTaps: 5, numberOfTouches: 1)
        XCTAssertEqual(fish.value as? String, "别戳啦！")
        app.terminate()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["open-achievement-hall"].tap()
        app.buttons["隐藏"].tap()
        for id in ["puff", "dream"] {
            let badge = app.buttons["achievement-" + id]
            XCTAssertTrue(badge.waitForExistence(timeout: 5))
            XCTAssertTrue(badge.label.contains("已解锁"), badge.label)
        }
    }

    func testMapWalletVersionAndReleaseDiscoveriesUseTheirVisibleControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        func reveal(_ button: XCUIElement, swipes: Int = 7) {
            for _ in 0..<swipes {
                if button.exists && button.isHittable { return }
                app.swipeUp()
            }
            XCTAssertTrue(button.isHittable, button.description)
        }
        for (id, title) in [("home-quzhi", "趣智校园"), ("home-pangguai", "胖乖生活"), ("home-campus-map", "校园平面图")] {
            let entry = app.buttons[id]
            reveal(entry); entry.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if id == "home-campus-map" { app.buttons["地图上的小金鱼"].tap() }
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.tabBars.buttons["我的"].tap()
        app.buttons["profile-settings"].tap()
        let about = app.buttons["版本与更新日志"]
        reveal(about); about.tap()
        app.buttons["版本号"].tap(withNumberOfTaps: 7, numberOfTouches: 1)
        app.buttons["更新日志"].tap()
        let colophon = app.buttons["release-history-colophon"]
        reveal(colophon, swipes: 16); colophon.tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["open-achievement-hall"].tap()
        for (group, ids) in [("生活", ["bath","laundry","map","life"]), ("隐藏", ["mapfish","goldfish","lastline"])] {
            app.buttons[group].tap()
            for id in ids {
                let badge = app.buttons["achievement-" + id]
                XCTAssertTrue(badge.waitForExistence(timeout: 5))
                XCTAssertTrue(badge.label.contains("已解锁"), badge.label)
            }
        }
    }

    func testScheduleJourneyFreeDayAndEmptyListUseVisibleControls() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HYT_DISCOVERY_UI_FIXTURE"] = "1"
        app.launch()
        app.tabBars.buttons["待办"].tap()
        let emptyFish = app.buttons["清单里的小金鱼"]
        XCTAssertTrue(emptyFish.waitForExistence(timeout: 5))
        emptyFish.tap()
        app.tabBars.buttons["课表"].tap()
        let weeks = app.buttons["跳转教学周"]
        XCTAssertEqual(weeks.value as? String, "第 3 周")
        weeks.tap()
        app.buttons["第 1 周"].tap()
        XCTAssertEqual(weeks.value as? String, "第 1 周")
        app.buttons["回到本周"].tap()
        XCTAssertEqual(weeks.value as? String, "第 3 周")
        app.segmentedControls.buttons["日视图"].tap()
        app.buttons["schedule-weekday-2"].tap()
        app.terminate()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["open-achievement-hall"].tap()
        app.buttons["隐藏"].tap()
        for id in ["timewalk","freeday","emptyfish"] {
            let badge = app.buttons["achievement-" + id]
            if !badge.exists { app.swipeUp() }
            XCTAssertTrue(badge.waitForExistence(timeout: 5) && badge.label.contains("已解锁"), id)
        }
    }

    private func serveCampusPhoto() throws -> NWListener {
        let resource = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "campus-autumn", withExtension: "jpg"))
        let jpeg = try Data(contentsOf: resource)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(jpeg)
        let bytes = response
        let queue = DispatchQueue(label: "community-photo-ui-test")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "Loopback photo server ready")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.fulfill()
            case .failed(let error): XCTFail(error.localizedDescription); ready.fulfill()
            default: break
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, error in
                guard error == nil else { connection.cancel(); return }
                connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        return listener
    }

    private func replyFixture(photoURL: String) throws -> String {
        func response(_ payload: [String: Any], status: Int = 200) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return ["status": status, "json": String(decoding: data, as: UTF8.self)]
        }
        let postID = "57932B87-002B-4ECC-A874-072227D3DA2D"
        let author: [String: Any] = ["name": "测试同学", "anonymous": false, "mine": false]
        let photoID = "6672CE47-236E-443C-BB52-AB83E12E9910"
        let media: [String: Any] = ["id": photoID, "width": 1200, "height": 800]
        let post: [String: Any] = [
            "id": postID, "title": "快捷回复测试帖", "body": "", "createdAt": "2026-11-21T05:00:00Z",
            "anonymous": false, "locked": false, "liked": false, "saved": false,
            "author": author, "commentCount": 0, "likeCount": 0, "category": "daily", "images": [media]
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
            "user": member, "config": ["engagementEnabled": true, "commentImagesEnabled": true, "followingEnabled": true, "discoveryEnabled": true, "boardsEnabled": true, "responsesEnabled": true, "responseKinds": ["useful", "joy", "hug"]],
            "posts": [post]
        ])
        let fixture = [
            "me": [configuration],
            "media.url": [try response(["image": media.merging(["url": photoURL]) { _, url in url }])],
            "posts.list": Array(repeating: try response(["posts": [post]]), count: 3),
            "posts.get": [try response(["post": post, "comments": []]), try response(["post": updated, "comments": [comment]])],
            "comments.create": [try response(["error": "network_unavailable"], status: 503), try response(["comment": comment])]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: fixture), as: UTF8.self)
    }

    private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:app.screenshot()); image.name="parity-"+name; image.lifetime = .keepAlways; add(image)
    }
}
