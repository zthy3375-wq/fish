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
        app.buttons["放大查看"].tap()
        XCTAssertTrue(app.buttons["显示整周"].waitForExistence(timeout: 5))
        app.buttons["显示整周"].tap()
        app.tabBars.buttons["社区"].tap()
        capture("community",app)
        app.tabBars.buttons["待办"].tap()
        XCTAssertTrue(app.buttons["添加待办"].waitForExistence(timeout:6))
        capture("tasks",app)
        app.tabBars.buttons["我的"].tap()
        let shelf=app.buttons["open-honor-shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout:6))
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
        XCTAssertTrue(app.buttons.containing(NSPredicate(format:"label CONTAINS %@", "???")).firstMatch.exists)
        app.terminate(); app.launch(); app.tabBars.buttons["我的"].tap(); app.buttons["open-honor-shelf"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format:"label CONTAINS %@", "你好，邯院")).firstMatch.waitForExistence(timeout:5))
    }
    private func capture(_ name:String,_ app:XCUIApplication) {
        let image=XCTAttachment(screenshot:app.screenshot()); image.name="parity-"+name; image.lifetime = .keepAlways; add(image)
    }
}
