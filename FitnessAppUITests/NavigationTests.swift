import XCTest

@MainActor final class NavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private func launchFreshApp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh in-memory SwiftData and no automatic Health reads. Never touches personal logs.
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }
    private func tap(_ title: String) {
        let button = app.buttons[title].firstMatch
        for _ in 0..<6 {
            if button.exists && button.isHittable { button.tap(); return }
            app.swipeUp()
        }
        XCTFail("Button not reachable: \(title)")
    }
    private func enter(_ text: String, in fieldName: String) {
        let field = app.textFields[fieldName].firstMatch
        for _ in 0..<5 {
            if field.exists && field.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(field.isHittable, "Field not reachable: \(fieldName)")
        field.tap()
        let existing = (field.value as? String) ?? ""
        let count = existing == field.placeholderValue ? 0 : existing.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
    }
    func testAllFiveTabsAndReturnNavigation() {
        launchFreshApp()
        for (tab, title) in [("Nutrition", "Nutrition"), ("Training", "Training"),
                              ("Progress", "Progress"), ("Settings", "Settings"), ("Home", "Today")] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.exists)
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
    }
    func testHomeLoggingAndRecommendationSheetsCanBeOpenedAndCancelled() {
        launchFreshApp()
        for (button, title, close) in [("Log food", "Log food", "Cancel"),
                                      ("What should I eat now?", "Eat now", "Close"),
                                      ("Log gym workout", "Log workout", "Cancel"),
                                      ("Log weight", "Log weight", "Cancel"),
                                      ("Log badminton", "Badminton", "Cancel")] {
            tap(button)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            app.navigationBars.buttons[close].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        }
    }
    func testFoodSaveUpdatesDashboardAndEmptyNumericFieldBlocksSave() {
        launchFreshApp()
        tap("Log food")
        enter("Lunch", in: "Food / meal name")
        enter("700", in: "Calories (kcal)")
        enter("40", in: "Protein (g)")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["700 / 2700 kcal"].exists)
        XCTAssertTrue(app.staticTexts["40 / 130 g"].exists)
        tap("Log food")
        enter("Dinner", in: "Food / meal name")
        enter("", in: "Calories (kcal)")
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.navigationBars.buttons["Cancel"].tap()
    }
    func testSettingsSubpagesHaveBackNavigation() {
        launchFreshApp()
        app.tabBars.buttons["Settings"].tap()
        for (button, title) in [("Profile, targets & breakfast", "Profile & targets"),
                                ("Food inventory (0)", "Inventory"),
                                ("Health permissions & data", "Apple Health"),
                                ("Provider & API credentials", "Food photo analysis")] {
            tap(button)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        }
    }
    func testSimplifiedChineseTabsFormsAndSettings() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.navigationBars["今日"].waitForExistence(timeout: 10))
        for (tab, title) in [("营养", "营养"), ("训练", "训练"), ("进展", "进展"), ("设置", "设置"), ("首页", "今日")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
        tap("记录饮食")
        XCTAssertTrue(app.navigationBars["记录饮食"].waitForExistence(timeout: 3))
        for label in ["食物 / 餐食名称", "热量（千卡）", "蛋白质（克）"] {
            let field = app.textFields[label].firstMatch
            if !field.isHittable { app.swipeUp() }
            XCTAssertTrue(field.isHittable, label)
            XCTAssertGreaterThanOrEqual(field.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX)
        }
        attachScreenshot("zh-Hans meal form")
        app.navigationBars.buttons["取消"].tap()
        app.tabBars.buttons["设置"].tap()
        tap("资料、目标与早餐")
        XCTAssertTrue(app.navigationBars["资料与目标"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["身高（厘米）"].exists)
        attachScreenshot("zh-Hans profile form")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("服务与 API 凭据")
        XCTAssertTrue(app.navigationBars["食物照片分析"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["保存"].exists)
        attachScreenshot("zh-Hans food analysis settings")
    }

    func testProgressArchiveNavigationAndManualMilestone() {
        launchFreshApp()
        app.tabBars.buttons["Progress"].tap()
        for (link, title) in [("Overview", "Overview"), ("Growth Timeline", "Growth Timeline"),
                               ("Milestones", "Milestones"), ("Progress Photos", "Progress Photos")] {
            tap(link)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        tap("Milestones"); tap("Add milestone")
        enter("First tournament", in: "Milestone title")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["First tournament"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap("Growth Timeline")
        for _ in 0..<6 {
            if app.staticTexts["First tournament"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["First tournament"].exists)
    }
    func testChineseGrowthTimelineAndExportNavigation() {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["进展"].waitForExistence(timeout: 10))
        app.tabBars.buttons["进展"].tap()
        for label in ["概览", "成长时间线", "里程碑", "成长照片"] { XCTAssertTrue(app.buttons[label].firstMatch.exists) }
        tap("成长时间线")
        XCTAssertTrue(app.navigationBars["成长时间线"].waitForExistence(timeout: 3))
        tap("导出成长档案")
        XCTAssertTrue(app.navigationBars["导出成长档案"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["全部历史"].exists)
        app.navigationBars.buttons["关闭"].tap()
    }
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
