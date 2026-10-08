import XCTest

@MainActor final class NavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private func launchFreshApp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh in-memory SwiftData and no automatic Health reads. Never touches personal logs.
        app.launchArguments = ["--uitesting"]
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
}
