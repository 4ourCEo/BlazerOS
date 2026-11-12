import Foundation
import Testing
@testable import BlazerCore

@Test func v3SetupLifecycleRejectsResurrection() {
    #expect(V3SetupState.confirmed.canTransition(to: .triggered))
    #expect(V3SetupState.confirmed.canTransition(to: .invalidated))
    #expect(!V3SetupState.invalidated.canTransition(to: .confirmed))
    #expect(!V3SetupState.setupExpired.canTransition(to: .approaching))
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
    #expect(abs(plan.rewardRisk! - 2) < 0.0000001)

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
