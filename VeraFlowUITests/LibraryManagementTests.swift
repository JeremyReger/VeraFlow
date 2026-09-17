import XCTest

/// Rename via the context menu and search by title, against seeded sample data.
final class LibraryManagementTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRenameAndSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--use-fake-services", "--seed-sample-data"]
        app.launch()

        let row = app.staticTexts["Kitchen remodel walk-through"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        row.press(forDuration: 1.2)
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()

        // Alert text fields don't surface their accessibility identifier to XCUITest.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" edited")
        alert.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Kitchen remodel walk-through edited"].waitForExistence(timeout: 5))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Lecture")
        XCTAssertTrue(app.staticTexts["Lecture · Materials science"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Weekly client check-in"].exists)
    }
}
