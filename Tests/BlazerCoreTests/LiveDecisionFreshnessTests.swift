import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

@Test func liveDecisionRefreshGenerationRejectsOnlyOlderSameAssetWork() {
    var generations = LiveDecisionRefreshGeneration()
    let firstEUR = generations.begin(for: "EUR/USD")
    let firstGBP = generations.begin(for: "GBP/USD")
    let secondEUR = generations.begin(for: "EUR/USD")

    #expect(!generations.isCurrent(firstEUR, for: "EUR/USD"))
    #expect(generations.isCurrent(secondEUR, for: "EUR/USD"))
    #expect(generations.isCurrent(firstGBP, for: "GBP/USD"))
}

@MainActor
@Test func liveEntryGateRejectsTimestampOverflowAndRechecksLiveSession() {
    #expect(LightningDeskModel.safeQuoteTimestampMilliseconds(1_800_000_000_123) == 1_800_000_000_123)
    #expect(LightningDeskModel.safeQuoteTimestampMilliseconds(Double.greatestFiniteMagnitude) == nil)
    #expect(LightningDeskModel.safeQuoteTimestampMilliseconds(Double(Int64.max)) == nil)
    #expect(LightningDeskModel.safeQuoteTimestampMilliseconds(.infinity) == nil)

    #expect(LightningDeskModel.isLiveEntryAppendEligible(isCurrent: true,
        selectedPair: "EUR/USD", asset: "EUR/USD", marketMode: .fx,
        scanning: false, environment: .live))
    #expect(!LightningDeskModel.isLiveEntryAppendEligible(isCurrent: true,
        selectedPair: "EUR/USD", asset: "EUR/USD", marketMode: .fx,
        scanning: false, environment: .practice))
    #expect(!LightningDeskModel.isLiveEntryAppendEligible(isCurrent: true,
        selectedPair: "EUR/USD", asset: "EUR/USD", marketMode: .fx,
        scanning: false, environment: nil))
}

@Test func liveDecisionAgeLabelShowsEvaluationAgeWithoutExpiringSetup() {
    let evaluatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(LiveDecisionAgeLabel.text(observedAt: evaluatedAt,
                                     now: evaluatedAt.addingTimeInterval(3)) == "Evaluated just now")
    #expect(LiveDecisionAgeLabel.text(observedAt: evaluatedAt,
                                     now: evaluatedAt.addingTimeInterval(17)) == "Evaluated 17s ago")
    #expect(LiveDecisionAgeLabel.text(observedAt: evaluatedAt,
                                     now: evaluatedAt.addingTimeInterval(125)) == "Evaluated 2m ago")
    #expect(LiveDecisionAgeLabel.text(observedAt: evaluatedAt,
                                     now: evaluatedAt.addingTimeInterval(-3)) == "Evaluated just now")
}

@MainActor
@Test func liveDecisionWithdrawalPersistsWaitWithoutPlanAndLeavesOtherPairAlone() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-live-decision-withdrawal-\(UUID().uuidString)")
    let storeRoot = root.appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("live-oanda", isDirectory: true)
    let store = ResearchStore(root: storeRoot)
    let now = Date().addingTimeInterval(-20)
    let eurPlan = V3TradePlan(id: "eur-plan", instrument: "EUR/USD",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
        engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "eur-observation",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.099,
        targetPrice: 1.102, units: 1, maxSpread: 0.0003, riskFraction: 0.01,
        createdAt: now)
    let gbpPlan = V3TradePlan(id: "gbp-plan", instrument: "GBP/USD",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
        engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "gbp-observation",
        state: .validated, side: .short, entryPrice: 1.25, stopPrice: 1.251,
        targetPrice: 1.248, units: 1, maxSpread: 0.0003, riskFraction: 0.01,
        createdAt: now)
    let eurBuy = LiveStrategyDecision(instrument: "EUR/USD", action: .buy,
        supportingStrategies: ["ORB_BREAK_RETEST", "LEGACY_V1"], plan: eurPlan,
        reasons: [], observedAt: now)
    let gbpSell = LiveStrategyDecision(instrument: "GBP/USD", action: .sell,
        supportingStrategies: ["ORB_BREAK_RETEST", "LEGACY_V1"], plan: gbpPlan,
        reasons: [], observedAt: now)
    try await store.record(eurPlan)
    try await store.record(eurBuy)
    try await store.record(gbpPlan)
    try await store.record(gbpSell)

    let model = LightningDeskModel(storageRoot: root)
    model.installLiveStrategyDecisionForTesting(eurBuy)
    model.installLiveStrategyDecisionForTesting(gbpSell)
    await model.withdrawLiveStrategyDecisionForTesting("EUR/USD", reason: "live_m1_candles_unavailable")

    let eurCurrent = model.strategyDecision(for: "EUR/USD")
    #expect(eurCurrent?.action == .wait)
    #expect(eurCurrent?.plan == nil)
    #expect(model.orbPlan(for: "EUR/USD") == nil)
    #expect(model.orbDecision(for: "EUR/USD")?.stage == .unavailable)
    #expect(model.strategyDecision(for: "GBP/USD") == gbpSell)

    var stored = try await store.liveStrategyDecisions()
    #expect(stored.last(where: { $0.instrument == "EUR/USD" })?.id == eurCurrent?.id)
    #expect(stored.last(where: { $0.instrument == "EUR/USD" })?.action == .wait)
    #expect(stored.last(where: { $0.instrument == "EUR/USD" })?.plan == nil)
    #expect(stored.last(where: { $0.instrument == "GBP/USD" })?.id == gbpSell.id)
    #expect(stored.last(where: { $0.instrument == "GBP/USD" })?.action == .sell)
    #expect(stored.filter { $0.instrument == "EUR/USD" }.count == 2)

    await model.withdrawLiveStrategyDecisionForTesting("EUR/USD", reason: "live_m1_candles_unavailable")
    stored = try await store.liveStrategyDecisions()
    #expect(stored.filter { $0.instrument == "EUR/USD" }.count == 2)
}

@MainActor
@Test func postPickScanWithdrawsOnlyOtherActionableAssetsInAttemptedUniverse() async {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-live-scan-pick-withdrawal-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let now = Date().addingTimeInterval(-10)

    func decision(_ asset: String, side: V3SpotSide, action: LiveStrategyAction,
                  planID: String, reason: String? = nil) -> LiveStrategyDecision {
        let plan = V3TradePlan(id: planID, instrument: asset,
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "obs-\(planID)",
            state: .validated, side: side,
            entryPrice: 1.1, stopPrice: side == .long ? 1.099 : 1.101,
            targetPrice: side == .long ? 1.102 : 1.098,
            units: 1, maxSpread: 0.0003, riskFraction: 0.01, createdAt: now)
        return LiveStrategyDecision(instrument: asset, action: action,
            supportingStrategies: ["ORB_BREAK_RETEST", "LEGACY_V1"],
            plan: action == .wait ? nil : plan,
            reasons: reason.map { [$0] } ?? [], observedAt: now)
    }

    let picked = decision("EUR/USD", side: .long, action: .buy, planID: "picked-plan")
    let otherAttempted = decision("GBP/USD", side: .short, action: .sell, planID: "other-plan")
    let outsideScan = decision("USD/JPY", side: .short, action: .sell, planID: "outside-plan")
    let failedAttempt = decision("AUD/USD", side: .long, action: .wait,
        planID: "failed-plan", reason: "live_scan_failed")
    model.installLiveStrategyDecisionForTesting(picked)
    model.installLiveStrategyDecisionForTesting(otherAttempted)
    model.installLiveStrategyDecisionForTesting(outsideScan)
    model.installLiveStrategyDecisionForTesting(failedAttempt)

    await model.withdrawUnselectedLiveDecisionsForTesting(
        scanAssets: ["EUR/USD", "GBP/USD", "AUD/USD"], pickedAsset: "EUR/USD")

    #expect(model.strategyDecision(for: "EUR/USD") == picked)
    #expect(model.strategyDecision(for: "GBP/USD")?.action == .wait)
    #expect(model.strategyDecision(for: "GBP/USD")?.plan == nil)
    #expect(model.strategyDecision(for: "GBP/USD")?.reasons == ["live_instrument_not_currently_monitored"])
    #expect(model.strategyDecision(for: "USD/JPY") == outsideScan)
    #expect(model.strategyDecision(for: "AUD/USD") == failedAttempt)
}

private func liveORBPlanCandidate() -> ORBDecision {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6,
                                                   hour: 9, minute: 30))!
    func bar(_ id: String, _ minute: Int, open: Double, high: Double, low: Double,
             close: Double) -> ORBBar {
        let source = start.addingTimeInterval(Double(minute * 60))
        return ORBBar(id: "EUR/USD-\(id)", instrument: "EUR/USD", sourceTime: source,
                      endTime: source.addingTimeInterval(60), open: open, high: high,
                      low: low, close: close)
    }
    let opening = (0..<5).map {
        bar("range-\($0)", $0, open: 1.102, high: 1.105, low: 1.100, close: 1.102)
    }
    let bars = opening + [
        bar("break", 5, open: 1.104, high: 1.107, low: 1.103, close: 1.106),
        bar("retest", 6, open: 1.1055, high: 1.106, low: 1.1049, close: 1.1052),
        bar("confirm", 7, open: 1.1052, high: 1.107, low: 1.105, close: 1.106),
    ]
    return ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                      asOf: start.addingTimeInterval(8 * 60))
}

private func liveORBPlanBars() -> [ORBBar] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6,
                                                   hour: 9, minute: 30))!
    func bar(_ suffix: String, _ minute: Int, _ open: Double, _ high: Double,
             _ low: Double, _ close: Double) -> ORBBar {
        let source = start.addingTimeInterval(Double(minute * 60))
        return ORBBar(id: "EUR/USD-\(suffix)", instrument: "EUR/USD", sourceTime: source,
            endTime: source.addingTimeInterval(60), open: open, high: high, low: low, close: close)
    }
    return (0..<5).map { bar("range-\($0)", $0, 1.102, 1.105, 1.100, 1.102) } + [
        bar("break", 5, 1.104, 1.107, 1.103, 1.106),
        bar("retest", 6, 1.1055, 1.106, 1.1049, 1.1052),
        bar("confirm", 7, 1.1052, 1.107, 1.105, 1.106)
    ]
}

@MainActor
@Test func orbPlanPersistenceFailureClearsBothLiveProjections() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-write-failure-\(UUID().uuidString)")
    let decision = liveORBPlanCandidate()
    guard let plan = decision.candidate?.plan else {
        Issue.record("Fixture must produce an ORB plan")
        return
    }
    let changedPlan = V3TradePlan(id: plan.id, instrument: plan.instrument,
        strategyID: plan.strategyID, strategyVersion: plan.strategyVersion,
        engineVersion: plan.engineVersion, sourceObservationID: plan.sourceObservationID,
        state: .offered, side: plan.side, entryPrice: plan.entryPrice,
        stopPrice: plan.stopPrice, targetPrice: plan.targetPrice, units: plan.units,
        maxSpread: plan.maxSpread, riskFraction: plan.riskFraction,
        evidenceIDs: plan.evidenceIDs, createdAt: plan.createdAt)
    let storeRoot = root.appendingPathComponent("Research/live-oanda", isDirectory: true)
    let store = ResearchStore(root: storeRoot)
    try await store.record(changedPlan)

    let model = LightningDeskModel(storageRoot: root)
    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
        bars: liveORBPlanBars(), asOf: decision.candidate?.plan.createdAt ?? Date())
    #expect(model.orbPlan(for: "EUR/USD") == nil)
    #expect(model.orbDecision(for: "EUR/USD")?.stage == .unavailable)
    #expect(model.orbDecision(for: "EUR/USD")?.candidate == nil)
    #expect(model.orbDecision(for: "EUR/USD")?.reason == "live_orb_plan_persistence_failed")
    #expect(try await ResearchStore(root: storeRoot).v3SetupLifecycleEvents().isEmpty)
}

@MainActor
@Test func liveORBPublisherRecordsCandidateBeforeLifecycleAndReportsSeparateStatus() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-lifecycle-live-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let decision = liveORBPlanCandidate()
    let bars = liveORBPlanBars()
    let asOf = bars.last!.endTime
    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
                                              bars: bars, asOf: asOf)
    let store = ResearchStore(root: root.appendingPathComponent("Research/live-oanda", isDirectory: true))
    let events = try await store.v3SetupLifecycleEvents()
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .recorded)
    #expect(model.orbPlan(for: "EUR/USD")?.id == events.first?.planID)
    #expect(events.count == 1)
    #expect(events[0].state == .confirmed)
    #expect(try await store.v3PlanEntryEvidence().isEmpty)
    #expect(try await store.v3PositionRecords().isEmpty)
    #expect(try await store.v3SpotOutcomes().isEmpty)
    #expect(try await store.v3StructuralOutcomes().isEmpty)

    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
                                              bars: bars, asOf: asOf)
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .noTransition)
    #expect(try await store.v3SetupLifecycleEvents().count == 1)
}

@MainActor
@Test func lifecycleAppendFailureKeepsPersistedPlanAndDecisionPublished() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-lifecycle-append-failure-\(UUID().uuidString)")
    let storeRoot = root.appendingPathComponent("Research/live-oanda", isDirectory: true)
    let lifecyclePath = storeRoot.appendingPathComponent("v3-setup-lifecycle-events")
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    try Data("not a directory".utf8).write(to: lifecyclePath)

    let model = LightningDeskModel(storageRoot: root)
    let decision = liveORBPlanCandidate()
    let bars = liveORBPlanBars()
    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
        bars: bars, asOf: bars.last!.endTime)

    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .unavailable)
    #expect(model.orbPlan(for: "EUR/USD")?.id == decision.candidate?.plan.id)
    #expect(model.orbDecision(for: "EUR/USD") == decision)
    #expect(try await ResearchStore(root: storeRoot).v3TradePlans() == [decision.candidate!.plan])
}

@MainActor
@Test func terminalORBStructureSuppressionPreservesCurrentPlanAndDecision() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-structure-suppression-\(UUID().uuidString)")
    let bars = liveORBPlanBars()
    let asOf = bars.last!.endTime
    let decision = liveORBPlanCandidate()
    guard case let .projected(projection) = ORBBreakRetestLifecycleV1.project(
        decision: decision, bars: bars, asOf: asOf) else {
        Issue.record("Fixture must project complete ORB evidence")
        return
    }
    let historicalTerminal = V3SetupLifecycleEvent(id: "old-orb-terminal",
        setupID: "old-orb-config", instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: projection.strategyVersion, provider: "OANDA", environment: .oandaLive,
        previousState: nil, state: .invalidated,
        sourceObservationID: projection.sourceObservationID, sourceTime: projection.sourceTime,
        receivedAt: Date(), recordedAt: Date(), reason: "structural_failure",
        configurationDigest: projection.configurationDigest, inputDigest: projection.inputDigest,
        engineVersion: projection.engineVersion, sourceBarIDs: projection.sourceBarIDs,
        reasonCodes: ["structural_failure"], structureID: projection.structureID,
        timeframeSeconds: 60, evidenceSchemaVersion: 1)
    let storeRoot = root.appendingPathComponent("Research/live-oanda", isDirectory: true)
    try await ResearchStore(root: storeRoot).record(historicalTerminal)

    let model = LightningDeskModel(storageRoot: root)
    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
                                              bars: bars, asOf: asOf)
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .structureSuppressed)
    #expect(model.orbDecision(for: "EUR/USD")?.stage == .setupConfirmed)
    #expect(model.orbPlan(for: "EUR/USD")?.id == decision.candidate?.plan.id)
    do {
        let archived = try await ResearchStore(root: storeRoot).v3SetupLifecycleEvents()
        #expect(archived.count == 1)
        #expect(archived.first?.id == historicalTerminal.id)
    } catch {
        Issue.record("Suppressed ORB lifecycle archive became unreadable: \(error)")
    }
}

@MainActor
@Test func supersededORBGenerationCannotWriteOrPublishLifecycleStatus() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-lifecycle-stale-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let bars = liveORBPlanBars()
    let decision = liveORBPlanCandidate()
    await model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
        bars: bars, asOf: bars.last!.endTime, supersedeBeforePublish: true)
    let store = ResearchStore(root: root.appendingPathComponent("Research/live-oanda", isDirectory: true))
    #expect(try await store.v3SetupLifecycleEvents().isEmpty)
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .notAttempted)
    #expect(model.orbDecision(for: "EUR/USD") == nil)
}

@MainActor
@Test func concurrentORBRefreshesPersistOnlyCurrentGenerationProjection() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-lifecycle-race-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let bars = liveORBPlanBars()
    let decision = liveORBPlanCandidate()
    async let first = model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
        bars: bars, asOf: bars.last!.endTime)
    async let second = model.publishORBDecisionForTesting(decision, asset: "EUR/USD", live: true,
        bars: bars, asOf: bars.last!.endTime)
    _ = await (first, second)
    let store = ResearchStore(root: root.appendingPathComponent("Research/live-oanda", isDirectory: true))
    #expect(try await store.v3SetupLifecycleEvents().count == 1)
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .recorded
        || model.orbLifecycleStatus(for: "EUR/USD") == .noTransition)
}

@MainActor
@Test func actualSlashFormORBPlanPersistsAndReloads() async throws {
    let plan = liveORBPlanCandidate().candidate?.plan
    guard let plan else {
        Issue.record("Fixture must produce an ORB plan")
        return
    }
    #expect(plan.sourceObservationID.contains("/"))
    #expect(plan.evidenceIDs.contains(where: { $0.contains("/") && $0.contains(",") }))
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-slash-persistence-\(UUID().uuidString)")
    let store = ResearchStore(root: root)
    try await store.record(plan)
    #expect(try await ResearchStore(root: root).v3TradePlans() == [plan])
}

@MainActor
@Test func nonLiveORBDecisionNeverProjectsPracticeCandidateAsLive() async {
    let model = LightningDeskModel(storageRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-nonlive-\(UUID().uuidString)"))
    await model.publishORBDecisionForTesting(liveORBPlanCandidate(), asset: "EUR/USD", live: false)
    #expect(model.orbPlan(for: "EUR/USD") == nil)
    #expect(model.orbDecision(for: "EUR/USD")?.stage == .unavailable)
    #expect(model.orbDecision(for: "EUR/USD")?.candidate == nil)
    #expect(model.orbDecision(for: "EUR/USD")?.reason == "live_session_unavailable")
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .notApplicable)
}

@MainActor
@Test func nonFXORBDecisionNeverWritesLivePlanOrLifecycle() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-orb-nonfx-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    await model.publishORBDecisionForTesting(liveORBPlanCandidate(), asset: "EUR/USD",
        live: true, market: .crypto)
    #expect(model.orbPlan(for: "EUR/USD") == nil)
    #expect(model.orbLifecycleStatus(for: "EUR/USD") == .notApplicable)
    #expect(try await ResearchStore(root: root).v3TradePlans().isEmpty)
    #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents().isEmpty)
}
