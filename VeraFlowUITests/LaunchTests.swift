import XCTest

final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsLibrary() throws {
        let app = XCUIApplication()
        // Live services (so their setup is exercised), but past onboarding.
        app.launchArguments = ["--skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Record"].firstMatch.exists)
    }
}
