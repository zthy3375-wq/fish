import XCTest

/// Simulator-only smoke coverage. No school credentials or live-device claims.
final class NativeSmokeTests: XCTestCase {
    func testTabsAndInterruptedEditors() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        screenshot("01-home", app)
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.buttons["添加课程"].waitForExistence(timeout: 5))
        screenshot("02-schedule", app)
        app.buttons["添加课程"].tap()
        app.buttons["取消"].tap()
        XCTAssertTrue(app.tabBars.buttons["待办"].exists)
        app.tabBars.buttons["待办"].tap()
        app.buttons["添加待办"].tap()
        XCTAssertTrue(app.buttons["保存"].exists)
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        app.buttons["取消"].tap()
        screenshot("03-tasks", app)
        app.buttons["添加待办"].tap()
        app.buttons["取消"].tap()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["连接邯郸学院"].waitForExistence(timeout: 5))
        screenshot("04-profile", app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
