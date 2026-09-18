import XCTest

/// Captures the App Store screenshot set from sample data. Run on each device size you need
/// (iPhone 17 Pro Max for 6.9", iPhone 16 Plus for 6.5"); the PNGs land in the test result
/// bundle as attachments named `01-library` … `06-paywall`. Light and dark: run twice with
/// the simulator appearance switched. Not part of the regular test plan's failure gate:
/// every assertion here is only there so a missing screen is noticed.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--use-fake-services", "--seed-sample-data"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))
        snap(app, "01-library")

        // Recorder mid-recording (fake recorder: no microphone needed).
        app.buttons["Record"].firstMatch.tap()
        let start = app.buttons["recorder.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["recorder.stop"].waitForExistence(timeout: 5))
        app.buttons["recorder.bookmark"].tap()
        snap(app, "02-recorder")
        app.buttons["recorder.stop"].tap()
        // Stop leads to the naming step; Save keeps the fake recording out of the way below.
        let save = app.buttons["recorder.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Detail: the seeded recording opens on Summary.
        let row = app.staticTexts["Kitchen remodel walk-through"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        // The detail draws its own serif title; the tabs are the sign it opened.
        if !app.buttons["Transcript"].waitForExistence(timeout: 3) {
            app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Kitchen remodel")).firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Transcript"].waitForExistence(timeout: 5))
        snap(app, "04-summary")

        app.buttons["Transcript"].tap()
        let search = app.textFields["transcript.search"]
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("permit")
        }
        snap(app, "03-transcript")

        // Share menu (exports), then a locked export opens the paywall (fake purchases start locked).
        let share = app.buttons["detail.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let pdf = app.buttons["PDF"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 5))
        snap(app, "05-share")
        pdf.tap()
        XCTAssertTrue(app.buttons["paywall.unlock"].waitForExistence(timeout: 5))
        snap(app, "06-paywall")
        app.buttons["paywall.dismiss"].tap()
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
