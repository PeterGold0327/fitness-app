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
        if ["Log food", "What should I eat now?", "Log gym workout", "Log weight", "Log badminton", "记录饮食"].contains(title), app.buttons["home.moreLogging"].isHittable {
            app.buttons["home.moreLogging"].tap()
        }
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
        for (tab, title) in [("营养", "营养"), ("运动", "运动"), ("进展", "进展"), ("设置", "设置"), ("首页", "今日")] {
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
        let routes = [("progress.timeline", "Growth Timeline"), ("progress.milestones", "Milestones"),
                      ("progress.photos", "Progress Photos"), ("progress.onThisDay", "On This Day"),
                      ("progress.export", "Export Archive")]
        // Check visibility before scrolling: these must be first-screen entry points.
        for (identifier, _) in routes {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons[identifier].isHittable, identifier)
        }
        attachScreenshot("Progress archive entry points")
        for (identifier, title) in routes {
            app.buttons[identifier].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
            if identifier == "progress.onThisDay" {
                XCTAssertTrue(app.staticTexts["No earlier anniversary records yet."].exists)
            }
            if identifier == "progress.export" {
                XCTAssertTrue(app.switches["Entire history"].exists)
                XCTAssertTrue(app.switches["Include photos"].exists)
                XCTAssertTrue(app.buttons["Export Archive"].exists)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
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
        for (identifier, label) in [("progress.timeline", "成长时间线"), ("progress.milestones", "里程碑"),
                                     ("progress.photos", "成长照片"), ("progress.onThisDay", "那年今日"),
                                     ("progress.export", "导出成长档案")] {
            XCTAssertTrue(app.buttons[identifier].isHittable)
            XCTAssertTrue(app.buttons[identifier].label.contains(label))
        }
        tap("成长时间线")
        XCTAssertTrue(app.navigationBars["成长时间线"].waitForExistence(timeout: 3))
        tap("导出成长档案")
        XCTAssertTrue(app.navigationBars["导出成长档案"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["全部历史"].exists)
        app.navigationBars.buttons["关闭"].tap()
    }
    func testActualTabRootKeepsArchiveNavigationVisibleWhileAnalyticsScroll() {
        launchFreshApp()
        app.tabBars.buttons["Progress"].tap()
        let archive = app.descendants(matching: .any)["progress.archive.navigation"].firstMatch
        let analytics = app.descendants(matching: .any)["progress.analytics"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 3))
        XCTAssertTrue(analytics.waitForExistence(timeout: 3))
        for _ in 0..<5 { analytics.swipeUp() }
        for identifier in ["progress.timeline", "progress.milestones", "progress.photos", "progress.onThisDay", "progress.export"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, identifier)
        }
        app.buttons["progress.timeline"].tap()
        XCTAssertTrue(app.navigationBars["Growth Timeline"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(archive.waitForExistence(timeout: 3))
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["progress.timeline"].isHittable)
    }

    func testOriginalProgressSectionsRemainBelowArchiveLinks() {
        launchFreshApp()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons["progress.timeline"].isHittable)
        for title in ["Body weight · last 4 weeks", "Nutrition adherence · last 7 days",
                      "Gym progress", "Weekly summary", "Weight history"] {
            let header = app.staticTexts[title].firstMatch
            for _ in 0..<10 {
                if header.exists && header.isHittable { break }
                app.descendants(matching: .any)["progress.analytics"].firstMatch.swipeUp()
            }
            XCTAssertTrue(header.isHittable, title)
        }
    }


    func testAgentHomeAndTrainingTemplateUseRealNavigation() {
        launchFreshApp()
        XCTAssertTrue(app.descendants(matching: .any)["coach.recommendation"].firstMatch.exists)
        tap("View today's advice")
        XCTAssertTrue(app.navigationBars["Today's Recommendation"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["Close"].tap()
        app.tabBars.buttons["Training"].tap()
        tap("Chest")
        XCTAssertTrue(app.navigationBars["Chest"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Exercise name"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled, "Previous reps are not silently logged as today's work")
        app.navigationBars.buttons["Cancel"].tap()
        tap("Edit workout templates")
        XCTAssertTrue(app.navigationBars["Workout templates"].waitForExistence(timeout: 3))
        tap("Chest")
        XCTAssertTrue(app.textFields["Exercise name"].firstMatch.exists)
    }
    func testCommonMealsAndArchiveRemainReachableInRedesignedTabs() {
        launchFreshApp()
        app.tabBars.buttons["Nutrition"].tap()
        tap("Common meals")
        XCTAssertTrue(app.navigationBars["Common meals"].waitForExistence(timeout: 3))
        tap("Log yogurt, oats & banana")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].exists)
        app.tabBars.buttons["Progress"].tap()
        app.buttons["progress.timeline"].tap()
        XCTAssertTrue(app.navigationBars["Growth Timeline"].waitForExistence(timeout: 3))
    }
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
