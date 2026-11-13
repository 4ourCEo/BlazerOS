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

@Test @MainActor func manualPracticeReportPersistsAsUserReportedWithoutBrokerEvidence() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BlazerOS-Manual-Report-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let plan = V3TradePlan(id: "manual-report-plan", instrument: "EUR/USD",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "1", engineVersion: "test",
        sourceObservationID: "manual-report-observation", state: .validated, side: .long,
        entryPrice: 1.1002, stopPrice: 1.0992, targetPrice: 1.1022, units: 1,
        maxSpread: 0.0003, riskFraction: 0.01, sourceEnvironment: .oandaPractice, createdAt: now)
    let event = SpotFXPracticeLifecycleEvent(id: "manual-report-lifecycle", planID: plan.id,
        instrument: plan.instrument, environment: .oandaPractice, state: .forming,
        reason: "fixture_actionable", recordedAt: now, riskAccepted: nil, riskUnits: nil)
    let store = ResearchStore(root: root)
    try await store.record(plan)
    try await store.record(event)

    let model = LightningDeskModel(storageRoot: root, researchRoot: root)
    await model.restoreSpotFXPracticeLifecycle()
    #expect(await model.reportManualSpotFXTrade(for: "EUR/USD", units: 12_000, now: now.addingTimeInterval(1)))

    let positions = try await store.v3PositionRecords()
    let report = try #require(positions.first)
    #expect(report.state == .userReported)
    #expect(report.provenance == .manualTradeReport)
    #expect(report.units == 12_000)
    #expect(report.entryPrice == nil)
    #expect(report.exitPrice == nil)
    #expect(try await store.v3SpotOutcomes().isEmpty)
}

/// Optional one-shot writer for a disposable installed-app acceptance run. The explicit absolute
/// root is supplied by the harness; without it, the test does not create persistent fixture data.
@Test func writeOfflineIntegrationFixtureForInstalledAppWhenRequested() async throws {
    guard let raw = ProcessInfo.processInfo.environment["BLAZER_WRITE_OFFLINE_FIXTURE_ROOT"],
          raw.hasPrefix("/") else { return }
    let root = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        .appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("oanda-proxy", isDirectory: true)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let session = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9, minute: 30))!
    func bar(_ id: String, _ offset: Int, _ open: Double, _ high: Double, _ low: Double, _ close: Double) -> ORBBar {
        let start = session.addingTimeInterval(Double(offset * 60))
        return ORBBar(id: "OFFLINE_\(id)", instrument: "EUR/USD", sourceTime: start,
            endTime: start.addingTimeInterval(60), open: open, high: high, low: low, close: close)
    }
    let bars = (0..<5).map { bar("range-\($0)", $0, 1.102, 1.105, 1.100, 1.102) } + [
        bar("break", 5, 1.104, 1.107, 1.103, 1.106),
        bar("retest", 6, 1.1055, 1.106, 1.1049, 1.1052),
        bar("confirm", 7, 1.1052, 1.107, 1.105, 1.106),
    ]
    let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
        asOf: session.addingTimeInterval(8 * 60))
    #expect(decision.stage == .setupConfirmed)
    let plan = try #require(decision.candidate?.plan)
    let simulatedPlan = plan.withSourceEnvironment(.simulated)
    let created = plan.createdAt
    let event = SpotFXPracticeLifecycleEvent(id: "offline-integration-\(plan.id)-risk-missing",
        planID: simulatedPlan.id, instrument: simulatedPlan.instrument, environment: .simulated,
        state: .unresolved, reason: "OFFLINE_INTEGRATION · deterministic ORB fixture · risk_missing",
        recordedAt: created, riskAccepted: nil, riskUnits: nil)
    let store = ResearchStore(root: root)
    try await store.record(simulatedPlan)
    try await store.record(event)
    #expect(try await store.v3TradePlans().contains(where: { $0.id == simulatedPlan.id && $0.sourceEnvironment == .simulated }))
    #expect(try await store.spotFXPracticeLifecycleEvents().contains(where: { $0.id == event.id }))
}

@Test @MainActor func offlineIntegrationScanUsesORBAndPersistsSimulatedPlanWithoutOrders() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BlazerOS-Offline-Scan-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = LightningDeskModel(offlineIntegrationRoot: root)

    await model.scan()

    let decision = try #require(model.orbDecision(for: "EUR/USD"))
    let plan = try #require(model.orbPlan(for: "EUR/USD"))
    #expect(decision.stage == .setupConfirmed)
    #expect(decision.candidate?.plan.id == plan.id)
    #expect(plan.strategyID == "ORB_BREAK_RETEST_V1")
    #expect(plan.sourceEnvironment == .simulated)
    let research = ResearchStore(root: root.appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("oanda-proxy", isDirectory: true))
    let storedPlans = try await research.v3TradePlans()
    #expect(storedPlans.contains(where: { $0.id == plan.id }))
    let events = try await research.spotFXPracticeLifecycleEvents()
    let scanEvent = try #require(events.first(where: { $0.planID == plan.id && $0.environment == .simulated }))
    #expect(scanEvent.reason.hasPrefix("OFFLINE_INTEGRATION"))
    #expect(scanEvent.riskAccepted == nil)
    #expect(scanEvent.riskUnits == nil)
    #expect(try await research.v3SpotOutcomes().isEmpty)
    #expect(try await research.v3PositionRecords().isEmpty)
}
