import XCTest

/// Opens a seeded recording, reads its transcript, and searches within it.
final class TranscriptTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTranscriptShowsParagraphsAndSearches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--use-fake-services", "--seed-sample-data"]
        app.launch()

        let row = app.staticTexts["Kitchen remodel walk-through"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // The sample recording has a summary, so the detail opens on the Summary tab.
        let transcriptTab = app.buttons["Transcript"]
        XCTAssertTrue(transcriptTab.waitForExistence(timeout: 5))
        transcriptTab.tap()

        let paragraph = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "permit")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player.playPause"].exists)

        let search = app.textFields["transcript.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("county")
        XCTAssertTrue(app.staticTexts["1 match"].waitForExistence(timeout: 5))

        // Edit mode swaps the paragraphs for text fields and back.
        let edit = app.buttons["transcript.edit"]
        edit.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
    }
}
