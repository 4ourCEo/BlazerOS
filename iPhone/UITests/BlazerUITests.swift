import XCTest

@MainActor
final class BlazerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        setUpApplication()
    }

    private func setUpApplication() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.blazer.os")
        let reportFixtureTest = name.contains("testUserPositionReportStaysSeparateFromBinaryEntry")
        let closeCorrectionFixtureTest = name.contains("testCloseCorrectionKeepsReferencedOpeningRevision")
        let insightBriefFixtureTest = name.contains("testReviewInsightOpensDeterministicCoachBrief")
        app.launchArguments = insightBriefFixtureTest
            ? ["-ui-testing", "--ui-testing-review-insight"]
            : closeCorrectionFixtureTest
            ? ["-ui-testing", "--ui-testing-user-report", "--ui-testing-user-close-correction"]
            : (reportFixtureTest || insightBriefFixtureTest)
            ? ["-ui-testing", "--ui-testing-user-report"]
            : ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let demo = app.buttons["Explore Demo Desk (Simulated)"]
        if !reportFixtureTest && !closeCorrectionFixtureTest && !insightBriefFixtureTest,
           demo.waitForExistence(timeout: 10) {
            demo.tap()
        }
    }

    func testPrimaryDestinationsAreTradeMarketsReview() {
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ORB BREAK · RETEST"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["orb.lifecycle.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["STRATEGY OPPORTUNITY"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["v3.review.insights.title.live-oanda"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["v3.review.insights.status.live-oanda"].exists)
    }

    func testUserPositionReportStaysSeparateFromBinaryEntry() {
        let reportAction = app.buttons["orb.user-reported-position"]
        XCTAssertTrue(reportAction.waitForExistence(timeout: 15))
        XCTAssertEqual(reportAction.identifier, "orb.user-reported-position")
        reportAction.tap()

        XCTAssertTrue(app.staticTexts["v3.position.report-copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "ui-test-user-report-plan"
        )).firstMatch.exists)
        XCTAssertTrue(app.switches["v3.position.already-opened-confirmation"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "does not place an order", "verify a broker fill"
        )).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Record Position"].exists)
        XCTAssertFalse(app.buttons["Record"].isEnabled)
        app.buttons["Cancel"].tap()
        reportAction.tap()
        XCTAssertTrue(app.staticTexts["Record Position"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Correct Report"].exists)
        app.buttons["Cancel"].tap()

        let closeAction = app.buttons["orb.user-reported-position-close"]
        XCTAssertTrue(closeAction.waitForExistence(timeout: 5))
        closeAction.tap()
        XCTAssertTrue(app.staticTexts["v3.position-close.report-copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["v3.position-close.confirmation"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "does not verify", "broker"
        )).firstMatch.exists)
        app.buttons["Cancel"].tap()

        app.buttons["Review"].tap()
        let planDetail = app.descendants(matching: .any)
            .matching(identifier: "v3.review.plan-detail.ui-test-user-report-plan").firstMatch
        XCTAssertTrue(planDetail.waitForExistence(timeout: 10))
        XCTAssertTrue((planDetail.value as? String)?.contains(
            "No position evidence is linked for plan ui-test-user-report-plan") == true)
    }

    func testCloseCorrectionKeepsReferencedOpeningRevisionAfterEntryTimeCorrection() {
        let action = app.buttons["orb.user-reported-position-close"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        action.tap()
        XCTAssertTrue(app.staticTexts["v3.position-close.report-copy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Opening revision userposrev-"
        )).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["v3.position-close.opening-superseded"].exists)
        let confirmation = app.switches["v3.position-close.confirmation"]
        XCTAssertTrue(confirmation.exists)
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(confirmation.value as? String, "1", "The close confirmation must be enabled before saving.")
        // The reported close time is after the opening time on the referenced
        // immutable revision but before the later corrected entry time.
        XCTAssertTrue(app.buttons["Save Correction"].isEnabled)
    }

    func testReviewInsightOpensDeterministicCoachBrief() {
        XCTAssertTrue(app.staticTexts["ORB BREAK · RETEST"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["orb.user-reported-position"].waitForExistence(timeout: 5))
        let reviewTab = app.buttons["Review"]
        let reviewIsHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: reviewTab
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reviewIsHittable], timeout: 10), .completed)
        reviewTab.tap()
        XCTAssertTrue(reviewTab.isSelected)
        XCTAssertTrue(app.staticTexts["v3.review.insights.status.live-oanda"].waitForExistence(timeout: 10))
        let planDetail = app.descendants(matching: .any)
            .matching(identifier: "v3.review.plan-detail.ui-test-review-insight-plan-v1").firstMatch
        XCTAssertTrue(planDetail.waitForExistence(timeout: 10))
        let insight = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                "v3.review.insight.live-oanda|user-close|"))
            .firstMatch
        XCTAssertTrue(insight.waitForExistence(timeout: 10))
        insight.tap()
        let explain = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "v3.review.insight.explain.live-oanda"
        )).firstMatch
        XCTAssertTrue(explain.waitForExistence(timeout: 5))
        explain.tap()

        XCTAssertTrue(app.staticTexts["Insight explanation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Deterministic record brief · local archive snapshot"].exists)
        XCTAssertTrue(app.staticTexts["Source archive: Live OANDA decision archive"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "close record userclose-")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "remain unavailable")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "not broker-confirmed")).firstMatch.exists)
        XCTAssertFalse(app.textFields["Ask Coach"].exists)

        let missingQuestion = app.buttons["v3.coach.insight.intent.what-is-missing"]
        XCTAssertTrue(missingQuestion.waitForExistence(timeout: 5))
        missingQuestion.tap()
        let answer = app.staticTexts["v3.coach.insight.intent.answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertTrue(answer.label.contains("close time and exit price"))
        XCTAssertTrue(answer.label.contains("remain unavailable"))
        let citations = app.staticTexts["v3.coach.insight.intent.citations"]
        XCTAssertTrue(citations.exists)
        XCTAssertTrue(citations.label.contains("v3:live-oanda:user-close:"))

        let brokerQuestion = app.buttons["v3.coach.insight.intent.is-this-broker-confirmed"]
        XCTAssertTrue(brokerQuestion.exists)
        brokerQuestion.tap()
        XCTAssertTrue(answer.label.contains("not broker-confirmed"))
        XCTAssertFalse(app.textFields["Ask Coach"].exists)
        app.buttons["v3.coach.insight.return"].tap()
        XCTAssertTrue(explain.waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["STRATEGY OPPORTUNITY"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["STRATEGY OPPORTUNITY"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let demo = app.buttons["Explore Demo Desk (Simulated)"]
        if demo.waitForExistence(timeout: 10) { demo.tap() }
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["STRATEGY OPPORTUNITY"].waitForExistence(timeout: 5))
    }
}
