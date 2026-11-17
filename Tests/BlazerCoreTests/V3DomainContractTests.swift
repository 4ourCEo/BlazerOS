import Foundation
import Testing
@testable import BlazerCore

@Test func userReportedPositionCloseRequiresManualProvenanceAndAllowsUnavailableExitFacts() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let close = V3UserReportedPositionClose(id: "close-1", positionID: "position-1",
        planID: "plan-1", openingRecordID: "opening-1", recordedAt: now)
    #expect(close.validation().isEmpty)
    #expect(close.closedAt == nil && close.exitPrice == nil)
    let brokerClaim = V3UserReportedPositionClose(id: "close-2", positionID: "position-1",
        planID: "plan-1", openingRecordID: "opening-1", provenance: .brokerExecution,
        recordedAt: now)
    #expect(brokerClaim.validation().contains("user_close_provenance_mismatch"))
    let invalidPrice = V3UserReportedPositionClose(id: "close-3", positionID: "position-1",
        planID: "plan-1", openingRecordID: "opening-1", exitPrice: .infinity, recordedAt: now)
    #expect(invalidPrice.validation().contains("invalid_user_reported_exit_price"))
    let toleranceBoundary = V3UserReportedPositionClose(id: "close-4", positionID: "position-1",
        planID: "plan-1", openingRecordID: "opening-1",
        closedAt: now.addingTimeInterval(1), recordedAt: now)
    #expect(!toleranceBoundary.validation().contains("close_time_after_report"))
    let futureClose = V3UserReportedPositionClose(id: "close-5", positionID: "position-1",
        planID: "plan-1", openingRecordID: "opening-1",
        closedAt: now.addingTimeInterval(1.001), recordedAt: now)
    #expect(futureClose.validation().contains("close_time_after_report"))
}

@Test func v3SetupLifecycleRejectsResurrection() {
    #expect(V3SetupState.confirmed.canTransition(to: .triggered))
    #expect(V3SetupState.confirmed.canTransition(to: .invalidated))
    #expect(!V3SetupState.invalidated.canTransition(to: .confirmed))
    #expect(!V3SetupState.setupExpired.canTransition(to: .approaching))
    #expect(V3SetupState.watching.canTransition(to: .setupExpired))
    #expect(V3SetupState.confirmed.canTransition(to: .setupExpired))
}

private func setupEvent(_ id: String, previous: V3SetupState?, state: V3SetupState,
                        at time: Date, setupID: String = "setup-1") -> V3SetupLifecycleEvent {
    V3SetupLifecycleEvent(id: id, setupID: setupID, instrument: "EUR/USD",
        strategyID: "orb-break-retest", strategyVersion: "1.0.0", provider: "OANDA",
        environment: .oandaLive, previousState: previous, state: state,
        sourceObservationID: "quote-\(id)", sourceTime: time,
        receivedAt: time, recordedAt: time, reason: "fixture")
}

@Test func v3SetupLifecycleValidatesReplayIdentityOrderingAndProvenance() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let first = setupEvent("event-1", previous: nil, state: .watching, at: t0)
    let next = setupEvent("event-2", previous: .watching, state: .forming, at: t0.addingTimeInterval(1))
    #expect(first.validation().isEmpty)
    #expect(V3SetupLifecycle.validationIssues(for: [next, first]).isEmpty)
    #expect(V3SetupLifecycle.validationIssues(for: [first, first]).isEmpty)

    let sameTime = setupEvent("event-2", previous: .watching, state: .forming, at: t0)
    #expect(V3SetupLifecycle.validationIssues(for: [first, sameTime]).contains("ambiguous_recorded_time"))

    let changedIdentity = setupEvent("event-3", previous: .forming, state: .approaching,
        at: t0.addingTimeInterval(2), setupID: "other-setup")
    #expect(V3SetupLifecycle.validationIssues(for: [first, changedIdentity]).contains("setup_identity_changed"))

    let incomplete = V3SetupLifecycleEvent(id: "event-4", setupID: "setup-1", instrument: "EUR/USD",
        strategyID: "orb-break-retest", strategyVersion: "1.0.0", provider: "OANDA",
        environment: .oandaLive, previousState: .forming, state: .approaching,
        sourceObservationID: "quote-4", sourceTime: nil, receivedAt: t0, recordedAt: t0,
        reason: "fixture")
    #expect(incomplete.validation().contains("observation_provenance_incomplete"))
}

@Test func v3MarketObservationValidatesBidAskAndFreshness() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let observation = V3MarketObservation(
        id: "quote-1", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1000, ask: 1.1002,
        sourceTime: now.addingTimeInterval(-1), receivedAt: now.addingTimeInterval(-0.5), sequence: 7)
    #expect(observation.validation(now: now).isEmpty)
    #expect(abs(observation.spread - 0.0002) < 0.0000001)

    let stale = V3MarketObservation(
        id: "quote-2", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1002, ask: 1.1000,
        sourceTime: now.addingTimeInterval(-8), receivedAt: now.addingTimeInterval(-7))
    #expect(stale.validation(now: now).contains("invalid_bid_ask"))
    #expect(stale.validation(now: now).contains("stale_source"))
}

@Test func v3ProxyAndUnresolvedOutcomesDoNotBecomeVerifiedPerformance() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let proxy = V3OutcomeRecord(id: "outcome-1", planID: "plan-1", quality: .proxy, reason: "midpoint reference", recordedAt: date)
    let unresolved = V3OutcomeRecord(id: "outcome-2", planID: "plan-1", quality: .unresolved, reason: "missing exit evidence", recordedAt: date)
    let observed = V3OutcomeRecord(id: "outcome-3", planID: "plan-1", quality: .observed, recordedAt: date)
    #expect(!proxy.canAffectVerifiedPerformance)
    #expect(!unresolved.canAffectVerifiedPerformance)
    #expect(observed.canAffectVerifiedPerformance)
}

@Test func v3SpotEvaluationUsesExecutableBidAskSides() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = V3MarketObservation(id: "entry", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1000, ask: 1.1002,
        sourceTime: t0, receivedAt: t0)
    let exit = V3MarketObservation(id: "exit", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1005, ask: 1.1007,
        sourceTime: t0.addingTimeInterval(60), receivedAt: t0.addingTimeInterval(60))
    let long = V3SpotOutcomeEvaluator.evaluate(side: .long, units: 10_000,
        entry: entry, exit: exit, expectedExitAt: t0.addingTimeInterval(60))
    let short = V3SpotOutcomeEvaluator.evaluate(side: .short, units: 10_000,
        entry: entry, exit: exit, expectedExitAt: t0.addingTimeInterval(60))
    #expect(long.status == .valid)
    #expect(abs(long.notionalPnl! - 3.0) < 0.0000001)
    #expect(short.status == .valid)
    #expect(abs(short.notionalPnl! + 7.0) < 0.0000001)
}

@Test func v3SpotEvaluationDoesNotInventLateResults() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = V3MarketObservation(id: "entry", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1000, ask: 1.1002,
        sourceTime: t0, receivedAt: t0)
    let late = V3MarketObservation(id: "late", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1005, ask: 1.1007,
        sourceTime: t0.addingTimeInterval(70), receivedAt: t0.addingTimeInterval(70))
    let result = V3SpotOutcomeEvaluator.evaluate(side: .long, units: 1,
        entry: entry, exit: late, expectedExitAt: t0.addingTimeInterval(60))
    #expect(result.status == .unresolved)
    #expect(result.notionalPnl == nil)
}

@Test func v3TradePlanRequiresStructuralLevelsAndVersionedEvidence() {
    let plan = V3TradePlan(id: "plan-1", instrument: "EUR/USD", strategyID: "breakout-acceptance",
        strategyVersion: "v3.0.0", engineVersion: "swift-v3-test", sourceObservationID: "quote-1",
        state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
        targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003, riskFraction: 0.005,
        evidenceIDs: ["quote-1", "bars-1"], createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(plan.validation().isEmpty)
    let bounded = V3TradePlan(id: "plan-bounded", instrument: "EUR/USD", strategyID: "breakout-acceptance",
        strategyVersion: "v3.0.0", engineVersion: "swift-v3-test", sourceObservationID: "quote-1",
        state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
        targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003, riskFraction: 0.005,
        maxEntryDeviation: 0.0003, createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(bounded.maxEntryDeviation == 0.0003)
    #expect(bounded.validation().isEmpty)
    #expect(abs(plan.rewardRisk! - 2) < 0.0000001)
    let encoded = try! JSONEncoder().encode(bounded)
    var legacy = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacy.removeValue(forKey: "maxEntryDeviation")
    let decodedLegacy = try! JSONDecoder().decode(V3TradePlan.self,
        from: JSONSerialization.data(withJSONObject: legacy))
    #expect(decodedLegacy.maxEntryDeviation == nil)

    let invalid = V3TradePlan(id: "plan-2", instrument: "EUR/USD", strategyID: "breakout-acceptance",
        strategyVersion: "v3.0.0", engineVersion: "swift-v3-test", sourceObservationID: "quote-1",
        state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.1012,
        targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003, riskFraction: 0.005,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(invalid.validation().contains("invalid_long_structure"))
}

@Test func v3MarketObservationRejectsFutureAndReceiptInversions() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let future = V3MarketObservation(id: "future", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1, ask: 1.1002,
        sourceTime: now.addingTimeInterval(2), receivedAt: now)
    #expect(future.validation(now: now).contains("future_source_time"))
    #expect(future.validation(now: now).contains("source_after_receipt"))
}

@Test func v3SpotEvaluationRejectsIdentityAndSourceOrderMismatches() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = V3MarketObservation(id: "entry", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1, ask: 1.1002, sourceTime: t0, receivedAt: t0)
    let wrongInstrument = V3MarketObservation(id: "exit", instrument: "GBP/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.2, ask: 1.2002,
        sourceTime: t0.addingTimeInterval(1), receivedAt: t0.addingTimeInterval(1))
    #expect(V3SpotOutcomeEvaluator.evaluate(side: .long, units: 1, entry: entry, exit: wrongInstrument).reason == "observation_identity_mismatch")

    let earlier = V3MarketObservation(id: "earlier", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.099, ask: 1.0992,
        sourceTime: t0.addingTimeInterval(-1), receivedAt: t0)
    #expect(V3SpotOutcomeEvaluator.evaluate(side: .long, units: 1, entry: entry, exit: earlier).reason == "out_of_order_source_time")
}

@Test func v3PlanLifecycleDoesNotResurrectTerminalPlans() {
    #expect(V3TradePlanState.draft.canTransition(to: .validated))
    #expect(V3TradePlanState.validated.canTransition(to: .offered))
    #expect(V3TradePlanState.offered.canTransition(to: .triggered))
    #expect(V3TradePlanState.offered.canTransition(to: .expired))
    #expect(!V3TradePlanState.expired.canTransition(to: .offered))
    #expect(!V3TradePlanState.triggered.canTransition(to: .validated))
}

@Test func v3PositionLifecycleSeparatesUserReportsFromBrokerConfirmation() {
    #expect(V3PositionState.notOpen.canTransition(to: .userReported))
    #expect(V3PositionState.userReported.canTransition(to: .unconfirmed))
    #expect(V3PositionState.unconfirmed.canTransition(to: .brokerOpen))
    #expect(V3PositionState.brokerOpen.canTransition(to: .exitRequested))
    #expect(V3PositionState.exitRequested.canTransition(to: .brokerClosed))
    #expect(!V3PositionState.brokerClosed.canTransition(to: .brokerOpen))

    let userReport = V3PositionRecord(id: "position-1", planID: "plan-1", instrument: "EUR/USD",
        state: .userReported, side: .long, units: 10_000,
        provenance: .manualTradeReport, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(userReport.validation().isEmpty)

    let incompleteBrokerClose = V3PositionRecord(id: "position-2", instrument: "EUR/USD",
        state: .brokerClosed, side: .long, units: 10_000, broker: "OANDA",
        brokerPositionID: "broker-1", provenance: .brokerExecution,
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    #expect(incompleteBrokerClose.validation().contains("closed_exit_missing"))
}

@Test func v3UserReportedPositionRequiresManualProvenanceAndOldRecordsDecode() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let report = V3PositionRecord(id: "userposrev-report", positionID: "userpos-plan",
        planID: "plan", instrument: "EUR/USD", state: .userReported,
        side: .long, units: 12_000, entryPrice: 1.1005,
        userReportedEnteredAt: now.addingTimeInterval(-10),
        provenance: .manualTradeReport, updatedAt: now)
    #expect(report.validation().isEmpty)

    let mislabeled = V3PositionRecord(id: "userposrev-broker", positionID: "userpos-plan",
        planID: "plan", instrument: "EUR/USD", state: .userReported,
        side: .long, units: 12_000, broker: "OANDA", brokerPositionID: "broker-id",
        provenance: .brokerExecution, updatedAt: now)
    #expect(mislabeled.validation().contains("user_report_provenance_mismatch"))
    #expect(mislabeled.validation().contains("user_report_contains_broker_identity"))
    #expect(mislabeled.validation().contains("invalid_user_report_identity"))

    let legacyJSON = """
    {"id":"legacy-position","planID":"plan","instrument":"EUR/USD","state":"USER_REPORTED","side":"LONG","units":1000,"broker":null,"brokerPositionID":null,"entryPrice":null,"exitPrice":null,"provenance":"MANUAL_TRADE_REPORT","updatedAt":1800000000000}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let legacy = try decoder.decode(V3PositionRecord.self, from: Data(legacyJSON.utf8))
    #expect(legacy.positionID == nil)
    #expect(legacy.supersedesRecordID == nil)
    #expect(legacy.userReportedEnteredAt == nil)
    #expect(legacy.validation().isEmpty)
}

@Test func v3RiskSizerRespectsRiskBudgetAndMargin() {
    let request = V3RiskSizingRequest(accountBalanceUSD: 500, riskFraction: 0.01,
        entryPrice: 1.1000, stopPrice: 1.0990, accountRiskPerPriceUnit: 1,
        estimatedCostPerUnit: 0.00025, minimumUnits: 1_000,
        availableMarginUSD: 100, marginPerUnitUSD: 0.001)
    let result = V3RiskSizer.size(request)
    #expect(result.accepted)
    #expect(result.units == 3_000)
    #expect(result.riskBudgetUSD == 5)
    #expect(result.estimatedWorstCaseLossUSD! <= result.riskBudgetUSD)
}

@Test func v3RiskSizerRejectsInsufficientMarginAndMalformedInputs() {
    let marginLimited = V3RiskSizingRequest(accountBalanceUSD: 500, riskFraction: 0.01,
        entryPrice: 1.1, stopPrice: 1.099, accountRiskPerPriceUnit: 1,
        estimatedCostPerUnit: 0, minimumUnits: 1_000,
        availableMarginUSD: 1, marginPerUnitUSD: 0.001)
    #expect(V3RiskSizer.size(marginLimited).rejectionReason == "insufficient_margin")

    let malformed = V3RiskSizingRequest(accountBalanceUSD: 500, riskFraction: 0,
        entryPrice: 1.1, stopPrice: 1.099, accountRiskPerPriceUnit: 1,
        estimatedCostPerUnit: 0, minimumUnits: 1_000,
        availableMarginUSD: 100, marginPerUnitUSD: 0)
    #expect(V3RiskSizer.size(malformed).rejectionReason == "invalid_sizing_input")
}
