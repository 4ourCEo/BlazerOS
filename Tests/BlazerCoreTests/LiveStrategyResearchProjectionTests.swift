import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

private func shadowObservation(at date: Date) -> LiveStrategySelection {
    let candidate = AdaptiveOpportunityCandidate(
        id: "shadow-orb-1", strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: "ORB_BREAK_RETEST_V1", instrument: "EUR/USD",
        provider: "OANDA_LIVE", direction: .short, observedAt: date,
        evaluationStartedAt: date, evaluationCompletedAt: date,
        state: .eligible, entryReference: 1.08,
        provenance: "test-only-candidate", freshness: .fresh,
        spread: 0.0001, spreadState: .accepted,
        effectiveConfigurationSHA256: String(repeating: "a", count: 64),
        evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"],
        adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
        selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
    return LiveStrategySelector.evaluate(instrument: "EUR/USD", candidates: [candidate], now: date)
}

@MainActor
@Test func shadowProjectionIsSanitizedAndCannotPublishSignalNotification() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-shadow-projection-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let selection = shadowObservation(at: Date())

    #expect(selection.decision.action == .wait)
    #expect(selection.decision.plan == nil)
    #expect(selection.decision.reasons == ["no_strategy_passed_live_promotion_gate"])
    #expect(selection.researchObservations.count == 1)
    #expect(selection.researchObservations[0].status == .evaluated)
    #expect(selection.researchObservations[0].strategyID == "ORB_BREAK_RETEST_V1")
    #expect(selection.researchObservations[0].reasons == ["profile_shadow_only"])

    let encoded = try JSONEncoder().encode(selection.researchObservations[0])
    let observationJSON = try #require(String(data: encoded, encoding: .utf8))
    #expect(!observationJSON.contains("direction"))
    #expect(!observationJSON.contains("entryReference"))
    #expect(!observationJSON.contains("plan"))
    #expect(!observationJSON.contains("1.08"))

    let defaults = UserDefaults.standard
    let notificationKey = "blazer.strategy.deliveredNotificationIDs"
    let beforeNotificationIDs = defaults.stringArray(forKey: notificationKey)
    await model.publishLiveStrategySelectionForTesting(selection)

    #expect(model.strategyDecision(for: "EUR/USD")?.action == .wait)
    #expect(model.strategyDecision(for: "EUR/USD")?.plan == nil)
    #expect(model.strategyResearchObservations(for: "EUR/USD") == selection.researchObservations)
    #expect(defaults.stringArray(forKey: notificationKey) == beforeNotificationIDs)
    #expect(model.liveStrategyNotificationScheduleAttemptsForTesting == 0)
}

@MainActor
@Test func staleOrInvalidLiveRefreshClearsResearchProjection() async {
    let model = LightningDeskModel(storageRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-shadow-invalid-\(UUID().uuidString)"))
    model.installLiveStrategyResearchObservationsForTesting(
        shadowObservation(at: Date()).researchObservations)
    #expect(!model.strategyResearchObservations(for: "EUR/USD").isEmpty)

    await model.withdrawLiveStrategyDecisionForTesting("EUR/USD", reason: "fresh_live_quote_unavailable")

    #expect(model.strategyResearchObservations(for: "EUR/USD").isEmpty)
    #expect(model.strategyDecision(for: "EUR/USD")?.action == .wait)
    #expect(model.strategyDecision(for: "EUR/USD")?.plan == nil)
}

@MainActor
@Test func researchProjectionClearsOnPairModeAndBackgroundTransitions() async {
    let model = LightningDeskModel(storageRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-shadow-lifecycle-\(UUID().uuidString)"))
    let observations = shadowObservation(at: Date()).researchObservations

    model.installLiveStrategyResearchObservationsForTesting(observations)
    model.select(pair: "GBP/USD")
    #expect(model.liveStrategyResearchObservations.isEmpty)

    model.installLiveStrategyResearchObservationsForTesting(observations)
    model.marketMode = .crypto
    model.beginCryptoScanForTesting()
    #expect(model.liveStrategyResearchObservations.isEmpty)

    model.installLiveStrategyResearchObservationsForTesting(observations)
    model.handleAppBackgrounded()
    #expect(model.liveStrategyResearchObservations.isEmpty)
}

@MainActor
@Test func researchObservationsAreNotPersistedOrRestored() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-shadow-relaunch-\(UUID().uuidString)")
    let first = LightningDeskModel(storageRoot: root)
    let selection = shadowObservation(at: Date())
    await first.publishLiveStrategySelectionForTesting(selection)
    #expect(first.strategyResearchObservations(for: "EUR/USD").count == 1)

    let relaunched = LightningDeskModel(storageRoot: root)
    await relaunched.restoreLiveStrategyDecisionsForTesting()

    #expect(relaunched.strategyResearchObservations(for: "EUR/USD").isEmpty)
}

@MainActor
@Test func restoredActionableDecisionWithUnknownOrDemotedProfileBecomesWait() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-shadow-decision-restore-\(UUID().uuidString)")
    let store = ResearchStore(root: root.appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("live-oanda", isDirectory: true))
    let createdAt = Date().addingTimeInterval(-30)
    let plan = V3TradePlan(id: "previous-plan", instrument: "EUR/USD",
        strategyID: "UNKNOWN_STRATEGY", strategyVersion: "old-v0",
        engineVersion: "old-v0", sourceObservationID: "old-observation",
        state: .validated, side: .long, entryPrice: 1.08, stopPrice: 1.079,
        targetPrice: 1.082, units: 1, maxSpread: 0.0003,
        riskFraction: 0.01, createdAt: createdAt)
    let historical = LiveStrategyDecision(instrument: "EUR/USD", action: .buy,
        supportingStrategies: ["REMOVED_PROFILE"], plan: plan, reasons: [],
        observedAt: createdAt, selectedProfileID: "REMOVED_PROFILE",
        selectedProfileVersion: "old-v0", promotionRecordID: "revoked-promotion",
        selectorPolicyVersion: "old-policy", selectorPolicySHA256: String(repeating: "a", count: 64),
        selectorCodeSHA256: String(repeating: "b", count: 64))
    let actionableWithoutPlan = LiveStrategyDecision(instrument: "GBP/USD", action: .sell,
        supportingStrategies: ["REMOVED_PROFILE"], plan: nil, reasons: [], observedAt: createdAt,
        selectedProfileID: "REMOVED_PROFILE", selectedProfileVersion: "old-v0",
        promotionRecordID: "revoked-promotion")
    try await store.record(plan)
    try await store.record(historical)
    try await store.record(actionableWithoutPlan)

    let model = LightningDeskModel(storageRoot: root)
    await model.restoreLiveStrategyDecisionsForTesting()

    #expect(model.strategyDecision(for: "EUR/USD")?.action == .wait)
    #expect(model.strategyDecision(for: "EUR/USD")?.plan == nil)
    #expect(model.strategyDecision(for: "EUR/USD")?.reasons == ["restored_plan_requires_live_revalidation"])
    #expect(model.orbPlan(for: "EUR/USD") == nil)
    #expect(model.strategyDecision(for: "GBP/USD")?.action == .wait)
    #expect(model.strategyDecision(for: "GBP/USD")?.plan == nil)
    #expect(model.strategyDecision(for: "GBP/USD")?.reasons == [
        "restored_actionable_decision_without_plan_requires_live_revalidation"
    ])
    #expect(model.liveStrategyResearchObservations.isEmpty)
}
