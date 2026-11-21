import XCTest

final class HonorParityUITests:XCTestCase {
    func testFiveTabsAndCollectionAcrossLaunches() throws {
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
        app.buttons["放大查看"].tap()
        XCTAssertTrue(app.buttons["显示整周"].waitForExistence(timeout: 5))
        app.buttons["显示整周"].tap()
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

    private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:app.screenshot()); image.name="parity-"+name; image.lifetime = .keepAlways; add(image)
    }
}
