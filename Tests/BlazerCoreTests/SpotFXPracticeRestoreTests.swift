import BlazerCore
import Foundation
import Testing
@testable import LightningDesk

@Test @MainActor func practicePlanAndLifecycleRestoreFromIsolatedResearchRoot() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BlazerOS-Practice-Restore-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let created = Date(timeIntervalSince1970: 1_900_000_000)
    let plan = V3TradePlan(id: "restore-plan-fixture", instrument: "EUR/USD",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "1", engineVersion: "test",
        sourceObservationID: "restore-observation", state: .validated, side: .long,
        entryPrice: 1.1002, stopPrice: 1.0992, targetPrice: 1.1022, units: 10_000,
        maxSpread: 0.0003, riskFraction: 0.01, createdAt: created)
    let event = SpotFXPracticeLifecycleEvent(id: "restore-event-fixture", planID: plan.id,
        instrument: plan.instrument, environment: .oandaPractice, state: .forming,
        reason: "fixture_actionable", recordedAt: created, spreadPips: 2,
        pipScale: 0.0001, riskAccepted: nil, riskUnits: nil)
    let store = ResearchStore(root: root)
    try await store.record(plan)
    try await store.record(event)

    // A new model instance simulates a fresh process projection without touching app-support data.
    let relaunchedModel = LightningDeskModel(storageRoot: root, researchRoot: root)
    await relaunchedModel.restoreSpotFXPracticeLifecycle()

    #expect(relaunchedModel.spotFXPracticeRestoreIssue == nil)
    #expect(relaunchedModel.orbPlan(for: "EUR/USD")?.id == "restore-plan-fixture")
    #expect(relaunchedModel.spotFXPracticeState(for: "EUR/USD")?.planID == "restore-plan-fixture")
    #expect(relaunchedModel.spotFXPracticeState(for: "EUR/USD")?.state == .forming)
    #expect(relaunchedModel.spotFXPracticeState(for: "EUR/USD")?.reason.contains("restored") == true)
}
