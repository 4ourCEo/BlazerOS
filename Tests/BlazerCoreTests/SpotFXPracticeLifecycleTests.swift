import Foundation
import Testing
@testable import BlazerCore

private let lifecycleDate = Date(timeIntervalSince1970: 1_900_000_000)

private func lifecyclePlan(_ instrument: String = "EUR/USD", maxSpread: Double = 0.0003) -> V3TradePlan {
    V3TradePlan(id: "lifecycle-plan", instrument: instrument, strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "orb-source", state: .validated,
        side: .long, entryPrice: instrument == "GBP/JPY" ? 190.02 : 1.1002,
        stopPrice: instrument == "GBP/JPY" ? 189.92 : 1.0992,
        targetPrice: instrument == "GBP/JPY" ? 190.22 : 1.1022, units: 10_000,
        maxSpread: maxSpread, riskFraction: 0.01, createdAt: lifecycleDate)
}

private func lifecycleDecision(plan: V3TradePlan? = lifecyclePlan(), state: V3SetupState = .confirmed,
                              stage: ORBStage = .setupConfirmed) -> ORBDecision {
    let candidate = plan.map { ORBTradePlanCandidate(direction: $0.side == .long ? .long : .short,
        breakoutBarID: "break", retestBarID: "retest", confirmationBarID: "confirm",
        rangeHigh: 1.101, rangeLow: 1.099, plan: $0) }
    return ORBDecision(stage: stage, setupState: state, sessionStart: lifecycleDate,
        direction: plan.map { $0.side == .long ? .long : .short }, reason: "test", candidate: candidate)
}

private func lifecycleObservation(_ instrument: String = "EUR/USD", bid: Double = 1.1000,
                                  ask: Double = 1.1002, source: Date = lifecycleDate,
                                  received: Date = lifecycleDate) -> V3MarketObservation {
    V3MarketObservation(id: "quote", instrument: instrument, provider: "OANDA",
        environment: .oandaPractice, bid: bid, ask: ask, sourceTime: source, receivedAt: received)
}

private func lifecycleRisk(accepted: Bool = true, loss: Double? = 10) -> V3RiskSizingResult {
    V3RiskSizingResult(accepted: accepted, riskBudgetUSD: 100, units: accepted ? 10_000 : 0,
        estimatedWorstCaseLossUSD: loss, estimatedMarginUSD: 10, rejectionReason: accepted ? nil : "rejected")
}

private func lifecycleInput(plan: V3TradePlan? = lifecyclePlan(), observation: V3MarketObservation? = lifecycleObservation(),
                            risk: V3RiskSizingResult? = lifecycleRisk(), environment: V3ProviderEnvironment? = .oandaPractice,
                            now: Date = lifecycleDate, expiresAt: Date = lifecycleDate.addingTimeInterval(60),
                            pipScale: Double? = 0.0001, evidence: SpotFXBrokerExecutionEvidence? = nil) -> SpotFXPracticeLifecycleInput {
    SpotFXPracticeLifecycleInput(decision: lifecycleDecision(plan: plan), plan: plan, observation: observation, risk: risk,
        hardRiskCapUSD: 20, environment: environment, expiresAt: expiresAt, now: now,
        pipScale: pipScale, brokerEvidence: evidence)
}

@Test func m1SetupMappingAndPracticeEligibility() {
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput()).state == .actionable)
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(environment: .oandaLive)).state == .rejected)
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(environment: nil)).state == .unresolved)
    let forming = SpotFXPracticeLifecycleInput(decision: lifecycleDecision(state: .forming, stage: .rangeForming),
        plan: nil, observation: nil, risk: nil, hardRiskCapUSD: 20, environment: .oandaPractice,
        expiresAt: lifecycleDate.addingTimeInterval(60), now: lifecycleDate)
    #expect(SpotFXPracticeLifecycle.evaluate(forming).state == .forming)
    let mismatch = lifecycleInput(plan: lifecyclePlan(), observation: lifecycleObservation())
    let otherDecision = lifecycleDecision(plan: V3TradePlan(id: "other", instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "orb-source", state: .validated,
        side: .long, entryPrice: 1.1002, stopPrice: 1.0992, targetPrice: 1.1022, units: 10_000,
        maxSpread: 0.0003, riskFraction: 0.01, createdAt: lifecycleDate))
    let badCandidate = SpotFXPracticeLifecycleInput(decision: otherDecision, plan: mismatch.plan,
        observation: mismatch.observation, risk: mismatch.risk, hardRiskCapUSD: 20, environment: .oandaPractice,
        expiresAt: lifecycleDate.addingTimeInterval(60), now: lifecycleDate, pipScale: 0.0001)
    #expect(SpotFXPracticeLifecycle.evaluate(badCandidate).reason == "candidate_plan_mismatch")
}

@Test func quoteFreshnessCrossingSpreadBoundaryAndPipScales() {
    let stale = lifecycleInput(observation: lifecycleObservation(source: lifecycleDate.addingTimeInterval(-6), received: lifecycleDate.addingTimeInterval(-6)))
    #expect(SpotFXPracticeLifecycle.evaluate(stale).reason == "stale_source")
    let future = lifecycleInput(observation: lifecycleObservation(source: lifecycleDate.addingTimeInterval(2), received: lifecycleDate.addingTimeInterval(2)))
    #expect(SpotFXPracticeLifecycle.evaluate(future).state == .unresolved)
    let crossed = lifecycleInput(observation: lifecycleObservation(ask: 1.0999))
    #expect(SpotFXPracticeLifecycle.evaluate(crossed).reason == "invalid_bid_ask")
    let boundary = lifecycleInput(plan: lifecyclePlan(maxSpread: 0.0002), observation: lifecycleObservation())
    #expect(SpotFXPracticeLifecycle.evaluate(boundary).state == .actionable)
    let jpy = lifecycleInput(plan: lifecyclePlan("GBP/JPY", maxSpread: 0.03),
        observation: lifecycleObservation("GBP/JPY", bid: 190, ask: 190.02), pipScale: 0.01)
    #expect(abs((SpotFXPracticeLifecycle.evaluate(jpy).spreadPips ?? 0) - 2) < 0.000001)
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(plan: lifecyclePlan("GBP/JPY"),
        observation: lifecycleObservation("GBP/JPY", bid: 190, ask: 190.02), pipScale: 0.0001)).reason == "pip_scale_mismatch")
}

@Test func riskExpiryAndDeterministicUnresolvedStates() {
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(risk: lifecycleRisk(accepted: false))).reason == "risk_rejected")
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(risk: lifecycleRisk(loss: 21))).reason == "risk_exceeds_hard_cap")
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(risk: V3RiskSizingResult(accepted: true,
        riskBudgetUSD: 100, units: 1_000, estimatedWorstCaseLossUSD: 10, estimatedMarginUSD: 10,
        rejectionReason: nil))).reason == "risk_rejected")
    let expired = lifecycleInput(now: lifecycleDate.addingTimeInterval(60))
    #expect(SpotFXPracticeLifecycle.evaluate(expired).state == .expired)
    let missing = lifecycleInput(observation: nil, risk: nil)
    #expect(SpotFXPracticeLifecycle.evaluate(missing) == SpotFXPracticeLifecycle.evaluate(missing))
}

@Test func manualAcknowledgmentIsNotFillAndBrokerNeedsExplicitEvidence() {
    let manual = SpotFXPracticeLifecycleEvent(id: "manual-1", planID: "lifecycle-plan", instrument: "EUR/USD",
        state: .manuallyConfirmed, reason: "user_acknowledged_manual_action", recordedAt: lifecycleDate,
        manualAcknowledged: true)
    #expect(manual.validation().isEmpty)
    let noEvidence = lifecycleInput(evidence: nil)
    #expect(SpotFXPracticeLifecycle.evaluate(noEvidence).state == .actionable)
    let evidence = SpotFXBrokerExecutionEvidence(evidenceID: "broker-evidence", planID: "lifecycle-plan",
        instrument: "EUR/USD", broker: "OANDA", transactionID: "tx-1", environment: .oandaPractice,
        executedAt: lifecycleDate)
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(evidence: evidence)).state == .brokerVerified)
    let bad = SpotFXBrokerExecutionEvidence(evidenceID: "bad", planID: "lifecycle-plan", instrument: "EUR/USD",
        broker: "OANDA", transactionID: "tx-1", environment: .oandaPractice, executedAt: lifecycleDate,
        evidenceKind: .manualTradeReport)
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(evidence: bad)).state == .unresolved)
    let late = SpotFXBrokerExecutionEvidence(evidenceID: "late", planID: "lifecycle-plan", instrument: "EUR/USD",
        broker: "OANDA", transactionID: "tx-2", environment: .oandaPractice, executedAt: lifecycleDate.addingTimeInterval(1))
    #expect(SpotFXPracticeLifecycle.evaluate(lifecycleInput(evidence: late)).state == .unresolved)
}

@Test func lifecycleEventsRoundTripIdempotencyAndConflict() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("lifecycle-\(UUID().uuidString)")
    let store = ResearchStore(root: root)
    let event = SpotFXPracticeLifecycleEvent(id: "event-1", planID: "lifecycle-plan", instrument: "EUR/USD",
        state: .actionable, reason: "all_evidence_valid", recordedAt: lifecycleDate, observationID: "quote",
        sourceTime: lifecycleDate, receivedAt: lifecycleDate, spread: 0.0002, spreadPips: 2,
        pipScale: 0.0001, expiresAt: lifecycleDate.addingTimeInterval(60), riskAccepted: true,
        riskUnits: 10_000, estimatedWorstCaseLossUSD: 10)
    try await store.record(event)
    try await store.record(event)
    let later = SpotFXPracticeLifecycleEvent(id: "event-2", planID: event.planID, instrument: event.instrument,
        state: .unresolved, reason: "quote_missing", recordedAt: lifecycleDate.addingTimeInterval(1))
    try await store.record(later)
    try await store.record(event)
    #expect(try await store.spotFXPracticeLifecycleEvents() == [event, later])
    let conflict = SpotFXPracticeLifecycleEvent(id: event.id, planID: event.planID, instrument: event.instrument,
        state: .rejected, reason: "different", recordedAt: event.recordedAt)
    await #expect(throws: ScanError.self) { try await store.record(conflict) }
    let old = SpotFXPracticeLifecycleEvent(id: "event-0", planID: event.planID, instrument: event.instrument,
        state: .forming, reason: "old", recordedAt: lifecycleDate.addingTimeInterval(-1))
    await #expect(throws: ScanError.self) { try await store.record(old) }
    let reopen = SpotFXPracticeLifecycleEvent(id: "event-3", planID: event.planID, instrument: event.instrument,
        state: .actionable, reason: "reopen", recordedAt: lifecycleDate.addingTimeInterval(2))
    await #expect(throws: ScanError.self) { try await store.record(reopen) }
}
