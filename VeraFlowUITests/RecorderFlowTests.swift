import XCTest

/// Drives the recording screen against the fake recorder (no microphone needed).
final class RecorderFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRecordPauseStopSaveShowsRowInLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--use-fake-services"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.buttons["Record"].firstMatch.tap()

        let start = app.buttons["recorder.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let stop = app.buttons["recorder.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recorder.status"].exists)

        app.buttons["recorder.bookmark"].tap()
        app.buttons["recorder.pause"].tap()
        XCTAssertTrue(app.buttons["recorder.resume"].waitForExistence(timeout: 5))
        app.buttons["recorder.resume"].tap()
        XCTAssertTrue(app.buttons["recorder.pause"].waitForExistence(timeout: 5))

        stop.tap()
        let save = app.buttons["recorder.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Meeting'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
}
