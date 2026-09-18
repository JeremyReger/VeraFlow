import XCTest

/// Walks the four onboarding pages and lands on the Library.
final class OnboardingTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingLeadsToLibrary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--use-fake-services", "--show-onboarding"]
        app.launch()

        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your meetings, turned into a to-do list."].exists)
        button.tap()
        XCTAssertTrue(app.staticTexts["Everything stays on your iPhone."].waitForExistence(timeout: 5))
        button.tap()
        let microphone = app.buttons["onboarding.microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        microphone.tap()
        XCTAssertTrue(app.staticTexts["Microphone access allowed"].waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.staticTexts["What this iPhone can do"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 5))
        app.buttons["Get started"].tap()

        XCTAssertTrue(app.otherElements["library"].waitForExistence(timeout: 5) || app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }
}
