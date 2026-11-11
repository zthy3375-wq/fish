import XCTest

/// Simulator-only smoke coverage. No school credentials or live-device claims.
final class NativeSmokeTests: XCTestCase {
    func testTabsAndInterruptedEditors() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts["提示"].exists, "Fresh launch must not report a storage failure")
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
    func testPersonalTaskPersistsAndCompletes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["待办"].tap()
        app.buttons["添加待办"].tap()
        let title = "本机持久化验证"
        let field = app.textFields["待办内容"].exists ? app.textFields["待办内容"] : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(title)
        app.buttons["保存"].tap()
        let savedRow = taskRow(title, in: app)
        let persistedIdentity = savedRow.identifier
        XCTAssertTrue(persistedIdentity.hasPrefix("task-edit-"))
        XCTAssertTrue((savedRow.value as? String)?.hasPrefix("未完成") == true)
        XCTAssertFalse(app.alerts["提示"].exists, "Saving must succeed before relaunch")
        app.terminate(); app.launch()
        app.tabBars.buttons["待办"].tap()
        let restoredRow = taskRow(title, identifier: persistedIdentity, in: app)
        XCTAssertTrue((restoredRow.value as? String)?.hasPrefix("未完成") == true)
        app.buttons["完成：" + title].tap()
        app.buttons["已完成"].tap()
        let completedRow = taskRow(title, identifier: persistedIdentity, in: app)
        XCTAssertTrue((completedRow.value as? String)?.hasPrefix("已完成") == true)
        screenshot("05-personal-task", app)
    }
    func testNativeServiceScreensWithoutCredentials() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        for (identifier, title, shot) in [("open-quzhi", "趣智校园", "06-quzhi"), ("open-pangguai", "胖乖生活", "07-pangguai"), ("open-learning", "学习通", "08-learning")] {
            let entry = app.buttons[identifier]
            for _ in 0..<5 { if entry.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            screenshot(shot, app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        }
    }
    func testPersonalTaskEditSaveDiscardAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let title = "TaskEdit-" + String(UUID().uuidString.prefix(8))
        let savedCourse = "Synthetic Course"
        let savedNotes = "Saved edit notes"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["待办"].waitForExistence(timeout: 10))
        app.tabBars.buttons["待办"].tap()
        app.buttons["添加待办"].tap()
        XCTAssertTrue(app.navigationBars["添加待办"].waitForExistence(timeout: 5))
        let titleField = taskEditorField("task-title-editor", in: app)
        titleField.tap(); titleField.typeText(title)
        app.buttons["保存"].tap()
        let persistedIdentity = openTask(title, in: app)

        let course = taskEditorField("task-course-editor", in: app)
        course.tap(); course.typeText(savedCourse)
        let notes = taskEditorField("task-notes-editor", in: app)
        notes.tap(); notes.typeText(savedNotes)
        app.buttons["保存"].tap()
        XCTAssertFalse(app.alerts["提示"].exists)
        openTask(title, in: app)
        XCTAssertEqual(taskEditorField("task-course-editor", in: app).value as? String, savedCourse)
        let savedField = taskEditorField("task-notes-editor", in: app)
        XCTAssertEqual(savedField.value as? String, savedNotes)

        savedField.tap(); savedField.typeText("-unsaved")
        let unsavedValue = try XCTUnwrap(savedField.value as? String)
        XCTAssertNotEqual(unsavedValue, savedNotes)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 5))
        app.buttons["继续编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑待办"].waitForExistence(timeout: 5))
        XCTAssertEqual(taskEditorField("task-notes-editor", in: app).value as? String, unsavedValue)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 5))
        app.buttons["放弃修改"].tap()
        openTask(title, in: app)
        XCTAssertEqual(taskEditorField("task-notes-editor", in: app).value as? String, savedNotes)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["我的待办"].waitForExistence(timeout: 5))

        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["待办"].waitForExistence(timeout: 10))
        app.tabBars.buttons["待办"].tap()
        openTask(title, identifier: persistedIdentity, in: app)
        XCTAssertEqual(taskEditorField("task-course-editor", in: app).value as? String, savedCourse)
        XCTAssertEqual(taskEditorField("task-notes-editor", in: app).value as? String, savedNotes)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["我的待办"].waitForExistence(timeout: 5))
        screenshot("09-task-edit-persistence", app)
    }
    private func taskEditorField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields[identifier]
        if field.waitForExistence(timeout: 1) { return field }
        let multiline = app.textViews[identifier]
        XCTAssertTrue(multiline.waitForExistence(timeout: 5), "Missing task editor field: " + identifier)
        return multiline
    }
    /// SwiftUI can put semantic metadata on the Button or on an enclosing Other element.
    /// Match exact metadata across element types; the UUID still identifies the same record after relaunch.
    private func taskRow(_ title: String, identifier: String? = nil, in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.navigationBars["我的待办"].waitForExistence(timeout: 5), "Task save/dismiss must finish before reopening")
        let expectedLabel = "编辑待办：" + title
        let matches: XCUIElementQuery
        if let identifier {
            matches = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@", identifier, expectedLabel))
        } else {
            matches = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "task-edit-", expectedLabel))
        }
        let row = matches.firstMatch
        for _ in 0..<5 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        let exists = row.waitForExistence(timeout: 5)
        if !exists || !row.isHittable {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "task-row-accessibility"; tree.lifetime = .keepAlways; add(tree)
            screenshot("task-row-missing", app)
        }
        XCTAssertTrue(exists, "Saved task semantic element must exist")
        XCTAssertEqual(matches.count, 1, "Saved task metadata must identify exactly one record")
        XCTAssertTrue(row.isHittable, "Saved task must be visible")
        XCTAssertEqual(row.label, expectedLabel, "Persisted title must be unchanged")
        XCTAssertTrue(row.identifier.hasPrefix("task-edit-"))
        XCTAssertNotNil(UUID(uuidString: String(row.identifier.dropFirst("task-edit-".count))))
        let state = row.value as? String
        XCTAssertTrue(state?.hasPrefix("未完成") == true || state?.hasPrefix("已完成") == true, "Task completion state must remain accessible")
        return row
    }
    @discardableResult
    private func openTask(_ title: String, identifier: String? = nil, in app: XCUIApplication) -> String {
        let row = taskRow(title, identifier: identifier, in: app)
        let persistedIdentity = row.identifier
        let editButton: XCUIElement
        if row.elementType == .button {
            editButton = row
        } else {
            // Observed CI hierarchy: semantic Other → one Button carrying the exact task title.
            let controls = row.descendants(matching: .button).matching(NSPredicate(format: "label == %@", title))
            XCTAssertEqual(controls.count, 1, "Task metadata must contain exactly one matching edit button")
            editButton = controls.firstMatch
        }
        XCTAssertEqual(editButton.elementType, .button)
        XCTAssertTrue(editButton.isHittable, "The real task edit button must be tappable")
        editButton.tap()
        XCTAssertTrue(app.navigationBars["编辑待办"].waitForExistence(timeout: 5))
        return persistedIdentity
    }
    func testSemesterBackupAndDisplayScreens() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["我的"].tap()
        let semesters = app.buttons["open-personal-schedule"]
        for _ in 0..<6 { if semesters.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(semesters.waitForExistence(timeout: 5)); semesters.tap()
        XCTAssertTrue(app.navigationBars["个人课表管理"].waitForExistence(timeout: 5))
        screenshot("09-personal-semesters", app)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        semesters.tap(); app.buttons["完成"].tap()
        let display = app.buttons["open-display-preferences"]
        for _ in 0..<6 { if display.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(display.waitForExistence(timeout: 5)); display.tap()
        XCTAssertTrue(app.navigationBars["显示与本机资料"].waitForExistence(timeout: 5))
        app.buttons["深色"].tap(); screenshot("10-dark-preferences", app)
        app.buttons["浅色"].tap(); screenshot("11-light-preferences", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let backup = app.buttons["备份与恢复"]
        for _ in 0..<6 { if backup.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); backup.tap()
        XCTAssertTrue(app.buttons["exportNativePersonalBackup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exportAndroidScheduleBackup"].exists)
        XCTAssertTrue(app.buttons["exportAndroidTaskBackup"].exists)
        screenshot("12-backup-options", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
