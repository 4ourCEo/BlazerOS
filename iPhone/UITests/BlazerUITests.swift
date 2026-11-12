import XCTest

@MainActor
final class BlazerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.blazer.os")
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let demo = app.buttons["Explore Demo Desk (Simulated)"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
        }
    }

    func testPrimaryDestinationsAreTradeMarketsReview() {
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ORB BREAK · RETEST"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ADAPTIVE RESEARCH"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "blazer-trade-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.buttons["Markets"].exists)
        XCTAssertTrue(app.buttons["Review"].exists)
        app.buttons["Markets"].tap()
        XCTAssertTrue(app.staticTexts["Radar"].waitForExistence(timeout: 5))
        app.buttons["Review"].tap()
        XCTAssertTrue(app.staticTexts["Review"].waitForExistence(timeout: 5))
    }

    func testReviewSubsectionsRemainReachable() {
        app.buttons["Review"].tap()
        XCTAssertTrue(app.buttons["Trades"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Research"].exists)
        app.buttons["Research"].tap()
        XCTAssertTrue(app.buttons["Research"].isSelected)
        app.buttons["Trades"].tap()
        XCTAssertTrue(app.staticTexts["Journal"].waitForExistence(timeout: 5))
    }

    func testContextualCoachPresentsAndDismisses() {
        app.buttons["Review"].tap()
        let coach = app.buttons["Open contextual Coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        coach.tap()
        XCTAssertTrue(app.staticTexts["Coach"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
    }

    func testForegroundRecoveryAfterBackgroundAndTermination() {
        XCTAssertTrue(app.staticTexts["ADAPTIVE RESEARCH"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["ADAPTIVE RESEARCH"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let demo = app.buttons["Explore Demo Desk (Simulated)"]
        if demo.waitForExistence(timeout: 10) { demo.tap() }
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ADAPTIVE RESEARCH"].waitForExistence(timeout: 5))
    }
}
