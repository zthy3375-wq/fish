import XCTest

/// Simulator-only smoke coverage. No school credentials or live-device claims.
final class NativeSmokeTests: XCTestCase {
    func testTabsAndInterruptedEditors() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["首页", "课表", "社区", "待办", "我的"])
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
        reveal(app.buttons["连接邯郸学院"], in: app)
        XCTAssertTrue(app.buttons["连接邯郸学院"].waitForExistence(timeout: 5))
        screenshot("04-profile", app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
    }
    func testGlobalAchievementHallShowsLockedAndUnlocked() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        let entry = app.buttons["open-achievement-hall"]
        for _ in 0..<5 { if entry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.navigationBars["荣誉殿堂"].waitForExistence(timeout: 5))
        let welcome = app.buttons["achievement-welcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        XCTAssertTrue(welcome.label.contains("已解锁"))
        let locked = app.buttons["achievement-arrival"]
        XCTAssertTrue(locked.exists)
        XCTAssertTrue(locked.label.contains("待同步") || locked.label.contains("未解锁"))
        XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
        screenshot("10-global-achievements", app)
        welcome.tap()
        XCTAssertTrue(app.navigationBars["成就详情"].waitForExistence(timeout: 5))
        app.buttons["展示到我的页面"].tap()
        app.buttons["完成"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["查看成就，你好，邯院"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["我的"].isHittable)
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
        selectTaskScope("已完成", in: app)
        let completedRow = taskRow(title, identifier: persistedIdentity, in: app)
        XCTAssertTrue((completedRow.value as? String)?.hasPrefix("已完成") == true)
        screenshot("05-personal-task", app)
    }
    func testHomeScheduleAndAnnouncementRoutes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.buttons["home-open-schedule"].tap()
        XCTAssertTrue(app.tabBars.buttons["课表"].isSelected)
        app.tabBars.buttons["首页"].tap()
        let bell = app.buttons["通知设置"]
        bell.tap()
        let toggle = app.switches["应用内提醒"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.tap() }
        let mark = app.buttons["全部标为已读"]
        if mark.exists { mark.tap() }
        XCTAssertTrue(app.staticTexts["已读"].exists)
        app.buttons["设置课程提醒与系统权限"].tap()
        XCTAssertTrue(app.navigationBars["系统提醒"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "Tapping the middle of the row must disable announcements")
        XCTAssertFalse(app.staticTexts["欢迎使用邯院通"].exists)
        app.terminate()
        app.launch()
        bell.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "Tapping the switch itself must toggle exactly once")
        XCTAssertTrue(app.staticTexts["已读"].exists)
    }

    func testNativeServiceScreensWithoutCredentials() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        for (identifier, title, shot) in [("open-quzhi", "趣智校园", "06-quzhi"), ("open-pangguai", "胖乖生活", "07-pangguai"), ("open-learning", "学习通", "08-learning")] {
            let isWallet = identifier != "open-learning"
            if isWallet { app.buttons["profile-settings"].tap(); app.buttons["more-settings"].tap() }
            let entry = app.buttons[identifier]
            for _ in 0..<5 { if entry.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            screenshot(shot, app)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            if isWallet { app.navigationBars["设置与帮助"].buttons.element(boundBy: 0).tap() }
            XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        }
    }
    func testPersonalTaskEditSaveDiscardAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let title = "T-" + String(UUID().uuidString.prefix(8))
        let savedCourse = "Math"
        let savedNotes = "Read"
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

        let insertion = "-x"
        savedField.tap()
        savedField.typeText(insertion)
        let completedInput = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", insertion), object: savedField)
        XCTAssertEqual(XCTWaiter.wait(for: [completedInput], timeout: 8), .completed,
                       "The keyboard must commit the new text before opening the confirmation.")
        let unsavedValue = try XCTUnwrap(savedField.value as? String)
        XCTAssertEqual(unsavedValue.count, savedNotes.count + insertion.count)
        XCTAssertEqual(unsavedValue.replacingOccurrences(of: insertion, with: ""), savedNotes,
                       "The insertion must preserve the saved text wherever the caret was placed.")
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
    private func selectTaskScope(_ scope: String, in app: XCUIApplication) {
        app.buttons["筛选"].tap()
        let menu = app.buttons["task-scope-picker"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons[scope].firstMatch.tap()
        app.buttons["筛选"].tap()
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
        if !row.exists { selectTaskScope("全部", in: app) }
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
        app.buttons["profile-settings"].tap()
        let semesters = app.buttons["open-personal-schedule"]
        for _ in 0..<6 { if semesters.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(semesters.waitForExistence(timeout: 5)); semesters.tap()
        XCTAssertTrue(app.navigationBars["个人课表管理"].waitForExistence(timeout: 5))
        screenshot("09-personal-semesters", app)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["设置与帮助"].waitForExistence(timeout: 5))
        semesters.tap(); app.buttons["完成"].tap()
        app.buttons["more-settings"].tap()
        let display = app.buttons["open-display-preferences"]
        for _ in 0..<6 { if display.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(display.waitForExistence(timeout: 5)); display.tap()
        XCTAssertTrue(app.navigationBars["显示与本机资料"].waitForExistence(timeout: 5))
        app.buttons["深色"].tap(); screenshot("10-dark-preferences", app)
        app.buttons["浅色"].tap(); screenshot("11-light-preferences", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let backup = app.buttons["备份与恢复"]
        for _ in 0..<6 { if backup.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(backup.waitForExistence(timeout: 5)); backup.tap()
        XCTAssertTrue(app.buttons["exportNativePersonalBackup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["exportAndroidScheduleBackup"].exists)
        XCTAssertTrue(app.buttons["exportAndroidTaskBackup"].exists)
        screenshot("12-backup-options", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["设置与帮助"].waitForExistence(timeout: 5))
    }
    func testProfileAcademicShortcutsAndSchoolDisclosure() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["我的"].tap()
        for (label, title) in [("成绩与学业", "成绩与考试"), ("考试安排", "成绩与考试"),
                               ("学期校历", "学期校历"), ("桌面课表", "课表小组件")] {
            let link = app.buttons[label]
            reveal(link, in: app)
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if title == "成绩与考试" {
                XCTAssertTrue(app.segmentedControls.buttons[label == "考试安排" ? "考试" : "成绩"].isSelected)
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
        let school = app.buttons["school-details"]
        reveal(school, in: app)
        school.tap()
        XCTAssertEqual(school.value as? String, "已展开")
        school.tap()
        XCTAssertEqual(school.value as? String, "已收起")
        let copy = app.buttons["复制群号"]
        reveal(copy, in: app)
        copy.tap()
        XCTAssertTrue(app.staticTexts["群号已复制"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["加入 QQ 交流群"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
