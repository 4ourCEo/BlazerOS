import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

private func v3ReviewRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-v3-review-\(UUID().uuidString)", isDirectory: true)
}

private func v3ReviewSetupEvent(at date: Date, id: String = "setup-event-1",
                                planID: String? = nil,
                                engineVersion: String? = nil) -> V3SetupLifecycleEvent {
    V3SetupLifecycleEvent(id: id, setupID: "setup-1",
        instrument: "EUR/USD", strategyID: "fixture-strategy", strategyVersion: "1",
        provider: "OANDA", environment: .oandaPractice, previousState: nil,
        state: .watching, receivedAt: date, recordedAt: date, planID: planID,
        reason: "fixture", engineVersion: engineVersion)
}

private func v3ReviewEntryEvidence(at date: Date, planID: String = "plan-1") -> V3PlanEntryEvidence {
    let observation = V3MarketObservation(id: "quote-1", instrument: "EUR/USD",
        provider: "OANDA", environment: .oandaPractice, bid: 1.1, ask: 1.1002,
        sourceTime: date, receivedAt: date)
    return V3PlanEntryEvidence(id: "entry-1", planID: planID,
        observation: observation, recordedAt: date)
}

private func reviewInsightPlan(_ id: String, at date: Date) -> V3TradePlan {
    V3TradePlan(id: id, instrument: "EUR/USD", strategyID: "orb", strategyVersion: "1",
        engineVersion: "engine", sourceObservationID: "quote-\(id)", state: .validated,
        side: .long, entryPrice: 1.1, stopPrice: 1.09, targetPrice: 1.12,
        units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: date)
}

private func reviewInsightOpening(_ id: String, positionID: String, planID: String,
                                 at date: Date, supersedes: String? = nil) -> V3PositionRecord {
    V3PositionRecord(id: id, positionID: positionID, planID: planID,
        supersedesRecordID: supersedes, instrument: "EUR/USD", state: .userReported,
        side: .long, units: 1, userReportedEnteredAt: date.addingTimeInterval(-30),
        provenance: .manualTradeReport, updatedAt: date)
}

private func reviewInsightClose(_ id: String, positionID: String, planID: String,
                               openingID: String, at date: Date, closedAt: Date? = nil,
                               exitPrice: Double? = nil, supersedes: String? = nil)
    -> V3UserReportedPositionClose {
    V3UserReportedPositionClose(id: id, positionID: positionID, planID: planID,
        openingRecordID: openingID, supersedesCloseID: supersedes, exitPrice: exitPrice,
        closedAt: closedAt, recordedAt: date)
}

@Test func reviewArchiveAbsentRootIsEmptyNotUnavailable() async {
    let state = await V3ReviewArchiveState.load(root: v3ReviewRoot())
    guard case .empty(let snapshot) = state else {
        Issue.record("An absent selected archive should be empty")
        return
    }
    #expect(snapshot.totalRecordCount == 0)
    #expect(snapshot.planCount == 0)
    #expect(snapshot.setupLifecycleEventCount == 0)
    #expect(snapshot.planEntryEvidenceEventCount == 0)
    #expect(snapshot.positionEventCount == 0)
    #expect(snapshot.spotOutcomeCount == 0)
    #expect(snapshot.structuralOutcomeCount == 0)
}

@Test func reviewArchivePopulatedCountsSetupAndEntryEvidenceEvents() async throws {
    let root = v3ReviewRoot()
    let store = ResearchStore(root: root)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    try await store.record(v3ReviewSetupEvent(at: date))
    try await store.record(v3ReviewEntryEvidence(at: date))

    let state = await V3ReviewArchiveState.load(root: root)
    guard case .populated(let snapshot) = state else {
        Issue.record("Valid records should produce a populated archive")
        return
    }
    #expect(snapshot.setupLifecycleEventCount == 1)
    #expect(snapshot.planEntryEvidenceEventCount == 1)
    #expect(snapshot.totalRecordCount == 2)
    #expect(state.snapshot?.setupLifecycleEvents == [v3ReviewSetupEvent(at: date)])
    #expect(state.snapshot?.planEntryEvidence == [v3ReviewEntryEvidence(at: date)])
}

@Test func reviewArchiveCorruptRecordIsUnavailableWithoutPartialCounts() async throws {
    let root = v3ReviewRoot()
    let store = ResearchStore(root: root)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    try await store.record(v3ReviewSetupEvent(at: date))
    let corruptDirectory = root.appendingPathComponent("v3-trade-plans", isDirectory: true)
    try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: corruptDirectory.appendingPathComponent("broken.json"))

    #expect(await V3ReviewArchiveState.load(root: root) == .unavailable)
}

@Test func reviewSourcesResolveToDistinctArchives() {
    let root = v3ReviewRoot()
    let live = V3ReviewArchiveSource.liveOanda.archiveRoot(under: root)
    let proxy = V3ReviewArchiveSource.proxyResearch.archiveRoot(under: root)
    #expect(live.lastPathComponent == "live-oanda")
    #expect(proxy.lastPathComponent == "oanda-proxy")
    #expect(live != proxy)
    #expect(V3ReviewArchiveSource.allCases.count == 2)
}

@Test func reviewSnapshotNamesEveryEvidenceCategory() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = V3TradePlan(id: "plan-1", instrument: "EUR/USD", strategyID: "strategy",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "quote",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.09,
        targetPrice: 1.12, units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: date)
    let setup = v3ReviewSetupEvent(at: date)
    let entry = v3ReviewEntryEvidence(at: date)
    let position = V3PositionRecord(id: "position-1", planID: "plan-1", instrument: "EUR/USD",
        state: .userReported, side: .long, units: 1, provenance: .manualTradeReport, updatedAt: date)
    let observation = V3MarketObservation(id: "spot-quote", instrument: "EUR/USD", provider: "OANDA",
        environment: .oandaPractice, bid: 1.1, ask: 1.1002, sourceTime: date, receivedAt: date)
    let spot = V3DurableSpotOutcome(id: "spot-1", planID: "plan-1", instrument: "EUR/USD",
        provider: "OANDA", environment: .oandaPractice, entryObservation: observation,
        exitObservation: nil, evaluation: V3SpotEvaluation(status: .unresolved, side: .long,
            units: 1, reason: "missing_exit"), strategyVersion: "1", engineVersion: "engine", recordedAt: date)
    let structural = V3StructuralOutcome(id: "structural-1", planID: "plan-1", instrument: "EUR/USD",
        strategyVersion: "1", engineVersion: "engine", quality: .simulated, status: .unresolved,
        exitReason: .missingQuote, entryObservation: nil, exitObservation: nil,
        entryPrice: nil, exitPrice: nil, netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: date)
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan], setupLifecycleEvents: [setup, setup],
        planEntryEvidence: [entry, entry, entry], positions: [position, position, position, position],
        spotOutcomes: [spot, spot, spot, spot, spot], structuralOutcomes: Array(repeating: structural, count: 6))
    #expect(snapshot.planCount == 1)
    #expect(snapshot.setupLifecycleEventCount == 2)
    #expect(snapshot.planEntryEvidenceEventCount == 3)
    #expect(snapshot.positionEventCount == 4)
    #expect(snapshot.spotOutcomeCount == 5)
    #expect(snapshot.structuralOutcomeCount == 6)
    #expect(snapshot.totalRecordCount == 21)
}

@Test func reviewPlanDetailUsesExactPlanIDSeparatesConflictsAndKeepsOrphans() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = V3TradePlan(id: "plan-a", instrument: "EUR/USD", strategyID: "strategy",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "quote",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.09,
        targetPrice: 1.12, units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: date)
    let goodEntry = v3ReviewEntryEvidence(at: date, planID: plan.id)
    let conflictingObservation = V3MarketObservation(id: "quote-conflict", instrument: "GBP/USD",
        provider: "OANDA", environment: .oandaPractice, bid: 1.2, ask: 1.2002,
        sourceTime: date, receivedAt: date)
    let conflict = V3PlanEntryEvidence(id: "entry-conflict", planID: plan.id,
        observation: conflictingObservation, recordedAt: date)
    let orphan = V3PlanEntryEvidence(id: "orphan-entry", planID: "missing-plan",
        observation: V3MarketObservation(id: "orphan-quote", instrument: "EUR/USD", provider: "OANDA",
            environment: .oandaPractice, bid: 1.1, ask: 1.1002, sourceTime: date, receivedAt: date),
        recordedAt: date)
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan], planEntryEvidence: [goodEntry, conflict, orphan])
    let detail = snapshot.detail(for: plan.id)
    #expect(detail?.timeline.contains(where: { $0.id == "entry|entry-1" }) == true)
    #expect(detail?.timeline.contains(where: { $0.id == "entry|entry-conflict" }) == false)
    #expect(detail?.integrity.map(\.id) == ["entry|entry-conflict"])
    #expect(snapshot.unlinkedEvidence.map(\.id) == ["entry|orphan-entry"])
}

@Test func reviewTimelineTreatsEngineVersionMismatchesAsIntegrityConflicts() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = V3TradePlan(id: "plan-engine", instrument: "EUR/USD", strategyID: "strategy",
        strategyVersion: "1", engineVersion: "engine-current", sourceObservationID: "EUR/USD-quote",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.09,
        targetPrice: 1.12, units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: date)
    let lifecycle = v3ReviewSetupEvent(at: date, id: "event-engine-conflict",
        planID: plan.id, engineVersion: "engine-old")
    let spot = V3DurableSpotOutcome(id: "spot-engine-conflict", planID: plan.id,
        instrument: plan.instrument, provider: "OANDA", environment: .oandaPractice,
        entryObservation: nil, exitObservation: nil,
        evaluation: V3SpotEvaluation(status: .unresolved, side: .long, units: 1),
        strategyVersion: plan.strategyVersion, engineVersion: "engine-old", recordedAt: date)
    let structural = V3StructuralOutcome(id: "structural-engine-conflict", planID: plan.id,
        instrument: plan.instrument, strategyVersion: plan.strategyVersion, engineVersion: "engine-old",
        quality: .simulated, status: .unresolved, exitReason: .missingQuote,
        entryObservation: nil, exitObservation: nil, entryPrice: nil, exitPrice: nil,
        netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: date)
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan], setupLifecycleEvents: [lifecycle],
        spotOutcomes: [spot], structuralOutcomes: [structural])
    let detail = snapshot.detail(for: plan.id)
    #expect(detail?.timeline.count == 1)
    #expect(Set(detail?.integrity.map(\.id) ?? []) == Set([
        "lifecycle|event-engine-conflict", "spot|spot-engine-conflict",
        "structural|structural-engine-conflict",
    ]))
}

@Test func reviewShowsUserReportCorrectionAndOutsidePlanWindowTiming() {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let terminalAt = createdAt.addingTimeInterval(120)
    let plan = V3TradePlan(id: "plan-user-position", instrument: "EUR/USD",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
        engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "EUR/USD-confirm-1",
        state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
        targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003,
        riskFraction: 0.005, createdAt: createdAt)
    let confirmed = V3SetupLifecycleEvent(id: "plan-confirmed", setupID: "setup-position",
        instrument: plan.instrument, strategyID: plan.strategyID, strategyVersion: plan.strategyVersion,
        provider: "OANDA", environment: .oandaLive, previousState: .approaching,
        state: .confirmed, sourceObservationID: "confirm-bar", sourceTime: createdAt,
        receivedAt: createdAt, recordedAt: createdAt, planID: plan.id, reason: "confirmed")
    let invalidated = V3SetupLifecycleEvent(id: "plan-invalidated", setupID: "setup-position",
        instrument: plan.instrument, strategyID: plan.strategyID, strategyVersion: plan.strategyVersion,
        provider: "OANDA", environment: .oandaLive, previousState: .confirmed,
        state: .invalidated, sourceObservationID: "failed-retest", sourceTime: terminalAt,
        receivedAt: terminalAt, recordedAt: terminalAt, planID: nil, reason: "retest failed")
    let original = V3PositionRecord(id: "position-original", positionID: "userpos-plan-user-position",
        planID: plan.id, instrument: plan.instrument, state: .userReported,
        side: plan.side, units: 12_000, entryPrice: 1.101,
        userReportedEnteredAt: terminalAt.addingTimeInterval(10),
        provenance: .manualTradeReport, updatedAt: terminalAt.addingTimeInterval(20))
    let correction = V3PositionRecord(id: "position-correction", positionID: original.positionID,
        planID: plan.id, supersedesRecordID: original.id, instrument: plan.instrument,
        state: .userReported, side: plan.side, units: 11_500, entryPrice: 1.1009,
        provenance: .manualTradeReport, updatedAt: terminalAt.addingTimeInterval(30))
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan],
        setupLifecycleEvents: [confirmed, invalidated], positions: [original, correction])

    let detail = snapshot.detail(for: plan.id)
    #expect(detail?.terminalSourceTime == terminalAt)
    #expect(detail?.currentUserReportedPosition?.id == correction.id)
    #expect(detail?.hasLegacyUserReportedPosition == false)
    #expect(detail?.timeline.contains(where: { $0.id == "lifecycle|plan-invalidated" }) == true)
    #expect(detail?.timeline.first(where: { $0.id == "position|position-original" })?.detail.contains("outside plan window") == true)
    #expect(detail?.timeline.first(where: { $0.id == "position|position-original" })?.detail.contains("superseded") == true)
    #expect(detail?.timeline.first(where: { $0.id == "position|position-correction" })?.detail.contains("User-reported; not independently verified") == true)
    #expect(detail?.timeline.first(where: { $0.id == "position|position-correction" })?.detail.contains("entry timing unavailable relative to terminal setup") == true)

    let legacy = V3PositionRecord(id: "legacy-manual-position", planID: plan.id,
        instrument: plan.instrument, state: .userReported, side: plan.side, units: 1,
        provenance: .manualTradeReport, updatedAt: terminalAt)
    #expect(V3ReviewArchiveSnapshot(plans: [plan], positions: [legacy])
        .detail(for: plan.id)?.hasLegacyUserReportedPosition == true)
}

@Test func reviewTimelineShowsSeparateEntryAndExitProvenance() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = V3TradePlan(id: "plan-provenance", instrument: "EUR/USD", strategyID: "strategy",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "EUR/USD-entry",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.09,
        targetPrice: 1.12, units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: date)
    let entry = V3MarketObservation(id: "EUR/USD-entry", instrument: "EUR/USD", provider: "entry-provider",
        environment: .oandaPractice, bid: 1.1, ask: 1.1002, sourceTime: date, receivedAt: date)
    let exit = V3MarketObservation(id: "EUR/USD-exit", instrument: "EUR/USD", provider: "exit-provider",
        environment: .oandaLive, bid: 1.101, ask: 1.1012,
        sourceTime: date.addingTimeInterval(10), receivedAt: date.addingTimeInterval(11))
    let spot = V3DurableSpotOutcome(id: "spot-provenance", planID: plan.id,
        instrument: plan.instrument, provider: "envelope-provider", environment: .unknown,
        entryObservation: entry, exitObservation: exit,
        evaluation: V3SpotEvaluation(status: .unresolved, side: .long, units: 1),
        strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion, recordedAt: date)
    let structural = V3StructuralOutcome(id: "structural-provenance", planID: plan.id,
        instrument: plan.instrument, strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
        quality: .simulated, status: .unresolved, exitReason: .missingQuote,
        entryObservation: entry, exitObservation: exit, entryPrice: nil, exitPrice: nil,
        netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: date)
    let detail = V3ReviewArchiveSnapshot(plans: [plan], spotOutcomes: [spot],
        structuralOutcomes: [structural]).detail(for: plan.id)
    let spotDetail = detail?.timeline.first(where: { $0.id == "spot|spot-provenance" })?.detail ?? ""
    let structuralDetail = detail?.timeline.first(where: { $0.id == "structural|structural-provenance" })?.detail ?? ""
    for text in [spotDetail, structuralDetail] {
        #expect(text.contains("entry-provider / OANDA_PRACTICE"))
        #expect(text.contains("exit-provider / OANDA_LIVE"))
        #expect(text.contains("EUR/USD-entry"))
        #expect(text.contains("EUR/USD-exit"))
    }
    #expect(spotDetail.contains("envelope-provider / UNKNOWN"))
}

@Test func reviewTimelineKeepsUserReportedCloseAndOpeningRevisionProvenance() {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = V3TradePlan(id: "close-plan", instrument: "EUR/USD", strategyID: "strategy",
        strategyVersion: "1", engineVersion: "engine", sourceObservationID: "entry",
        state: .validated, side: .long, entryPrice: 1.1, stopPrice: 1.09,
        targetPrice: 1.12, units: 1, maxSpread: 0.001, riskFraction: 0.01, createdAt: time)
    let opening = V3PositionRecord(id: "opening-revision", positionID: "userpos-close-plan",
        planID: plan.id, instrument: plan.instrument, state: .userReported, side: .long,
        units: 1, provenance: .manualTradeReport, updatedAt: time)
    let openingCorrection = V3PositionRecord(id: "opening-correction", positionID: opening.positionID,
        planID: plan.id, supersedesRecordID: opening.id, instrument: plan.instrument,
        state: .userReported, side: .long, units: 1, provenance: .manualTradeReport,
        updatedAt: time.addingTimeInterval(1))
    let close = V3UserReportedPositionClose(id: "close-revision", positionID: opening.positionID!,
        planID: plan.id, openingRecordID: opening.id, recordedAt: time.addingTimeInterval(2))
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan], positions: [opening, openingCorrection],
                                            positionCloses: [close])
    let item = snapshot.detail(for: plan.id)?.timeline.first { $0.id == "position-close|close-revision" }
    #expect(item?.detail.contains("close time unavailable") == true)
    #expect(item?.detail.contains("exit price unavailable") == true)
    #expect(item?.detail.contains("opening revision opening-revision") == true)
    #expect(item?.detail.contains("later superseded") == true)
    #expect(item?.detail.contains("User-reported/manual, unverified, not broker-confirmed") == true)
}

@Test func reviewInsightsSelectIncompleteCloseLeavesAndSuppressSupersededCorrections() {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let planA = reviewInsightPlan("plan-close-a", at: time)
    let planB = reviewInsightPlan("plan-close-b", at: time)
    let planC = reviewInsightPlan("plan-close-c", at: time)
    let openA = reviewInsightOpening("open-a", positionID: "position-a", planID: planA.id, at: time)
    let openB = reviewInsightOpening("open-b", positionID: "position-b", planID: planB.id, at: time)
    let openC = reviewInsightOpening("open-c", positionID: "position-c", planID: planC.id, at: time)
    let incompleteRoot = reviewInsightClose("close-a-root", positionID: "position-a", planID: planA.id,
        openingID: openA.id, at: time)
    let completedCorrection = reviewInsightClose("close-a-complete", positionID: "position-a", planID: planA.id,
        openingID: openA.id, at: time.addingTimeInterval(1), closedAt: time, exitPrice: 1.101,
        supersedes: incompleteRoot.id)
    let partialRoot = reviewInsightClose("close-b-root", positionID: "position-b", planID: planB.id,
        openingID: openB.id, at: time.addingTimeInterval(2), exitPrice: 1.101)
    let incompleteLeaf = reviewInsightClose("close-b-leaf", positionID: "position-b", planID: planB.id,
        openingID: openB.id, at: time.addingTimeInterval(3), supersedes: partialRoot.id)
    let complete = reviewInsightClose("close-c-complete", positionID: "position-c", planID: planC.id,
        openingID: openC.id, at: time.addingTimeInterval(4), closedAt: time, exitPrice: 1.102)
    let snapshot = V3ReviewArchiveSnapshot(plans: [planA, planB, planC],
        positions: [openA, openB, openC],
        positionCloses: [incompleteRoot, completedCorrection, partialRoot, incompleteLeaf, complete])

    let values = snapshot.closeCompletenessInsights(source: .liveOanda)
    #expect(values.count == 1)
    #expect(values[0].closeID == incompleteLeaf.id)
    #expect(values[0].missingFields == ["close time", "exit price"])
    #expect(values[0].visibleCitationText
        == "Plan plan-close-b · close record close-b-leaf · opening record open-b")
    #expect(values[0].evidenceRows.map(\.id) == ["position-close|close-b-leaf", "position|open-b"])
    #expect(values[0].accessibilityLabel.contains("manual close; unverified, not broker-confirmed"))
    #expect(!values.contains(where: { $0.closeID == completedCorrection.id || $0.closeID == complete.id }))
}

@Test func reviewInsightsRequireExactLinkedOpeningAndFlagSupersededRevision() {
    let date = Date(timeIntervalSince1970: 1_800_000_100)
    let plan = reviewInsightPlan("plan-linked", at: date)
    let opening = reviewInsightOpening("open-original", positionID: "position-linked", planID: plan.id, at: date)
    let openingCorrection = reviewInsightOpening("open-correction", positionID: "position-linked",
        planID: plan.id, at: date.addingTimeInterval(1), supersedes: opening.id)
    let close = reviewInsightClose("close-linked", positionID: "position-linked", planID: plan.id,
        openingID: opening.id, at: date.addingTimeInterval(2))
    let orphanClose = reviewInsightClose("close-orphan", positionID: "position-orphan", planID: plan.id,
        openingID: "missing-opening", at: date.addingTimeInterval(3))
    let mismatchedPlanClose = reviewInsightClose("close-wrong-plan", positionID: "position-other-plan",
        planID: "other-plan", openingID: opening.id, at: date.addingTimeInterval(4))
    let snapshot = V3ReviewArchiveSnapshot(plans: [plan], positions: [opening, openingCorrection],
        positionCloses: [close, orphanClose, mismatchedPlanClose])
    #expect(opening.validation().isEmpty)
    #expect(openingCorrection.validation().isEmpty)
    #expect(close.validation().isEmpty)
    let linkedTimeline = snapshot.detail(for: plan.id)?.timeline ?? []
    #expect(linkedTimeline.contains(where: { $0.id == "position-close|\(close.id)" }))
    #expect(linkedTimeline.contains(where: { $0.id == "position|\(opening.id)" }))
    let insights = snapshot.closeCompletenessInsights(source: .liveOanda)
    #expect(insights.map(\.closeID) == [close.id])
    guard let insight = insights.first else { return }
    #expect(insight.openingRecordID == opening.id)
    #expect(insight.openingWasSuperseded)
    #expect(insight.evidenceRows.last?.id == "position|open-original")
    #expect(insight.evidenceRows.last?.detail.contains("later user correction") == true)
    #expect(V3ReviewArchiveSnapshot(plans: [plan], positions: [opening], positionCloses: [orphanClose])
        .closeCompletenessInsights(source: .liveOanda).isEmpty)
    let wrongPositionOpening = reviewInsightOpening("open-other-position", positionID: "position-other",
        planID: plan.id, at: date)
    let mismatchedOpeningClose = reviewInsightClose("close-wrong-opening", positionID: "position-linked",
        planID: plan.id, openingID: wrongPositionOpening.id, at: date.addingTimeInterval(5))
    #expect(V3ReviewArchiveSnapshot(plans: [plan], positions: [opening, wrongPositionOpening],
        positionCloses: [mismatchedOpeningClose]).closeCompletenessInsights(source: .liveOanda).isEmpty)
    #expect(V3ReviewArchiveSnapshot(plans: [plan], positions: [opening], positionCloses: [mismatchedPlanClose])
        .closeCompletenessInsights(source: .liveOanda).isEmpty)
}

@Test func reviewInsightsHaveDeterministicReceiptOrderingAndSixItemCap() {
    let date = Date(timeIntervalSince1970: 1_800_000_200)
    var plans: [V3TradePlan] = []
    var positions: [V3PositionRecord] = []
    var closes: [V3UserReportedPositionClose] = []
    for index in 0..<8 {
        let planID = "cap-plan-\(index)"
        let positionID = "cap-position-\(index)"
        let plan = reviewInsightPlan(planID, at: date)
        let opening = reviewInsightOpening("cap-open-\(index)", positionID: positionID,
            planID: planID, at: date)
        let recordedAt = date.addingTimeInterval(Double(index / 2))
        let close = reviewInsightClose("cap-close-\(index)", positionID: positionID,
            planID: planID, openingID: opening.id, at: recordedAt)
        plans.append(plan)
        positions.append(opening)
        closes.append(close)
    }
    let snapshot = V3ReviewArchiveSnapshot(plans: plans, positions: positions,
                                            positionCloses: Array(closes.reversed()))
    let first = snapshot.closeCompletenessInsights(source: .proxyResearch)
    let second = snapshot.closeCompletenessInsights(source: .proxyResearch)
    #expect(first.count == 6)
    #expect(first == second)
    #expect(first.map(\.closeID) == ["cap-close-6", "cap-close-7", "cap-close-4",
                                     "cap-close-5", "cap-close-2", "cap-close-3"])
    #expect(first.allSatisfy { $0.id.hasPrefix("oanda-proxy|user-close|") })
}

@Test func reviewInsightsDistinguishArchiveLoadingUnavailableEmptyAndPopulatedNoMatch() {
    let emptySnapshot = V3ReviewArchiveSnapshot()
    #expect(V3ReviewInsightsState.project(archive: .loading, source: .liveOanda) == .loading)
    #expect(V3ReviewInsightsState.project(archive: .unavailable, source: .liveOanda) == .unavailable)
    #expect(V3ReviewInsightsState.project(archive: .empty(emptySnapshot), source: .liveOanda) == .emptyArchive)
    let date = Date(timeIntervalSince1970: 1_800_000_300)
    let plan = reviewInsightPlan("complete-plan", at: date)
    let opening = reviewInsightOpening("complete-open", positionID: "complete-position",
        planID: plan.id, at: date)
    let completeClose = reviewInsightClose("complete-close", positionID: "complete-position",
        planID: plan.id, openingID: opening.id, at: date, closedAt: date, exitPrice: 1.101)
    let populated = V3ReviewArchiveSnapshot(plans: [plan], positions: [opening],
                                             positionCloses: [completeClose])
    #expect(V3ReviewInsightsState.project(archive: .populated(populated), source: .liveOanda)
        == .noMatchingInsights)
}

private func selectedInsightSnapshot(_ suffix: String, at date: Date,
                                     closedAt: Date? = nil, exitPrice: Double? = nil,
                                     correction: Bool = false) -> V3ReviewArchiveSnapshot {
    let plan = reviewInsightPlan("selected-plan-\(suffix)", at: date)
    let positionID = "selected-position-\(suffix)"
    let opening = reviewInsightOpening("selected-opening-\(suffix)", positionID: positionID,
        planID: plan.id, at: date)
    let rootClose = reviewInsightClose("selected-close-\(suffix)", positionID: positionID,
        planID: plan.id, openingID: opening.id, at: date, closedAt: closedAt,
        exitPrice: exitPrice)
    var closes = [rootClose]
    if correction {
        closes.append(reviewInsightClose("selected-correction-\(suffix)",
            positionID: positionID, planID: plan.id, openingID: opening.id,
            at: date.addingTimeInterval(1), closedAt: date, exitPrice: 1.101,
            supersedes: rootClose.id))
    }
    return V3ReviewArchiveSnapshot(plans: [plan], positions: [opening], positionCloses: closes)
}

@Test func reviewInsightRouteValidationAcceptsSelectedLiveAndProxySources() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = selectedInsightSnapshot("source", at: date)
    for source in V3ReviewArchiveSource.allCases {
        guard let original = snapshot.closeCompletenessInsight(
            source: source, id: "\(source.directoryName)|user-close|selected-close-source") else {
            Issue.record("Expected a selected incomplete close for \(source.title)")
            continue
        }
        let state = V3ReviewInsightRouteValidation.project(selectedSource: source,
            original: original, archive: .populated(snapshot))
        #expect(state == .ready(original))
        #expect(state.insight == original)
    }
}

@Test func reviewInsightRouteValidationRejectsChangedPayloadAndCompleteCorrectionLeaf() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let originalSnapshot = selectedInsightSnapshot("changed", at: date)
    let originalID = "live-oanda|user-close|selected-close-changed"
    guard let original = originalSnapshot.closeCompletenessInsight(source: .liveOanda, id: originalID) else {
        Issue.record("Expected original selected insight")
        return
    }
    let changedPayload = selectedInsightSnapshot("changed", at: date, exitPrice: 1.101)
    let changedPayloadState = V3ReviewInsightRouteValidation.project(selectedSource: .liveOanda,
        original: original, archive: .populated(changedPayload))
    #expect(changedPayloadState == .stale)
    #expect(changedPayloadState.insight == nil)

    let changedLeaf = selectedInsightSnapshot("changed-leaf", at: date, correction: true)
    let rootInsightID = "live-oanda|user-close|selected-close-changed-leaf"
    guard let rootInsight = selectedInsightSnapshot("changed-leaf", at: date)
        .closeCompletenessInsight(source: .liveOanda, id: rootInsightID) else {
        Issue.record("Expected original close-chain leaf")
        return
    }
    let correctionState = V3ReviewInsightRouteValidation.project(selectedSource: .liveOanda,
        original: rootInsight, archive: .populated(changedLeaf))
    #expect(correctionState == .stale)
    #expect(correctionState.insight == nil)
}

@Test func reviewInsightRouteValidationUsesUncappedTargetedLookup() {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshots = (0..<7).map { index in
        selectedInsightSnapshot("cap-\(index)", at: baseDate.addingTimeInterval(Double(index)))
    }
    let selectedSnapshot = snapshots[0]
    let selectedID = "live-oanda|user-close|selected-close-cap-0"
    guard let original = selectedSnapshot.closeCompletenessInsight(source: .liveOanda, id: selectedID) else {
        Issue.record("Expected selected insight behind display cap")
        return
    }
    let combined = V3ReviewArchiveSnapshot(
        plans: snapshots.flatMap(\.plans), positions: snapshots.flatMap(\.positions),
        positionCloses: snapshots.flatMap(\.positionCloses))
    let displayed = combined.closeCompletenessInsights(source: .liveOanda)
    #expect(displayed.count == 6)
    #expect(!displayed.contains(where: { $0.id == selectedID }))
    let route = V3ReviewInsightRouteValidation.project(selectedSource: .liveOanda,
        original: original, archive: .populated(combined))
    #expect(route == .ready(original))
    #expect(route.insight == original)
}

@Test func reviewInsightRouteValidationHasNoFactsForSourceOrArchiveStateFailures() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = selectedInsightSnapshot("states", at: date)
    guard let original = snapshot.closeCompletenessInsight(source: .liveOanda,
        id: "live-oanda|user-close|selected-close-states") else {
        Issue.record("Expected selected insight")
        return
    }
    let mismatchedSource = V3ReviewInsightRouteValidation.project(selectedSource: .proxyResearch,
        original: original, archive: .populated(snapshot))
    #expect(mismatchedSource == .stale)
    #expect(mismatchedSource.insight == nil)

    let empty = V3ReviewArchiveSnapshot()
    let states: [(V3ReviewArchiveState, V3ReviewInsightRouteValidation)] = [
        (.loading, .loading),
        (.unavailable, .unavailable),
        (.empty(empty), .empty),
    ]
    for (archive, expected) in states {
        let projected = V3ReviewInsightRouteValidation.project(selectedSource: .liveOanda,
            original: original, archive: archive)
        #expect(projected == expected)
        #expect(projected.insight == nil)
    }
}

@Test func reviewInsightQuestionAnswersUseOnlySelectedEvidenceAndSourceQualifiedCitations() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = selectedInsightSnapshot("answers", at: date)
    guard let insight = snapshot.closeCompletenessInsight(source: .liveOanda,
        id: "live-oanda|user-close|selected-close-answers") else {
        Issue.record("Expected selected insight")
        return
    }
    let route = V3ReviewInsightRouteValidation.ready(insight)
    let closeCitation = "v3:live-oanda:user-close:\(insight.closeID)"
    let openingCitation = "v3:live-oanda:user-position:\(insight.openingRecordID)"

    let missing = V3ReviewInsightQuestionAnswer.make(question: .missingDetails, route: route)
    #expect(missing?.text.contains("close time and exit price") == true)
    #expect(missing?.text.contains("remain unavailable") == true)
    #expect(missing?.citations == [closeCitation])

    let establishes = V3ReviewInsightQuestionAnswer.make(question: .establishes, route: route)
    #expect(establishes?.text.contains("a manual close report was recorded") == true)
    #expect(establishes?.text.contains("does not establish an actual close, execution, or fill") == true)
    #expect(establishes?.citations == [closeCitation])

    let broker = V3ReviewInsightQuestionAnswer.make(question: .brokerConfirmation, route: route)
    #expect(broker?.text.contains("not broker-confirmed") == true)
    #expect(broker?.citations == [closeCitation])

    let linked = V3ReviewInsightQuestionAnswer.make(question: .linkedRecords, route: route)
    #expect(linked?.text.contains("Plan \(insight.planID) is a binding reference") == true)
    #expect(linked?.citations == [closeCitation, openingCitation])
    #expect(!linked!.citations.contains("v3:live-oanda:plan:\(insight.planID)"))

    let unsupported = V3ReviewInsightQuestionAnswer.make(question: .unsupported, route: route)
    #expect(unsupported?.text.contains("not supported by this record") == true)
    #expect(unsupported?.citations == [closeCitation])
}

@Test func reviewInsightQuestionAnswersPreserveEachMissingField() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let closeTimeOnlyMissing = selectedInsightSnapshot("time-only", at: date, exitPrice: 1.101)
    let closeTimeInsight = closeTimeOnlyMissing.closeCompletenessInsight(source: .proxyResearch,
        id: "oanda-proxy|user-close|selected-close-time-only")!
    let closeTimeAnswer = V3ReviewInsightQuestionAnswer.make(question: .missingDetails,
        route: .ready(closeTimeInsight))
    #expect(closeTimeAnswer?.text.contains("Missing: close time") == true)
    #expect(closeTimeAnswer?.text.contains("exit price") == false)
    #expect(closeTimeAnswer?.citations == ["v3:oanda-proxy:user-close:\(closeTimeInsight.closeID)"])

    let exitPriceOnlyMissing = selectedInsightSnapshot("price-only", at: date, closedAt: date)
    let exitPriceInsight = exitPriceOnlyMissing.closeCompletenessInsight(source: .liveOanda,
        id: "live-oanda|user-close|selected-close-price-only")!
    let exitPriceAnswer = V3ReviewInsightQuestionAnswer.make(question: .missingDetails,
        route: .ready(exitPriceInsight))
    #expect(exitPriceAnswer?.text.contains("Missing: exit price") == true)
    #expect(exitPriceAnswer?.text.contains("close time") == false)
}

@Test func reviewInsightQuestionAnswersRespectOpeningSupersessionAndNonReadyState() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let base = selectedInsightSnapshot("superseded", at: date)
    let original = base.positions[0]
    let laterOpening = reviewInsightOpening("selected-opening-superseded-later",
        positionID: original.positionID!, planID: original.planID!,
        at: date.addingTimeInterval(1), supersedes: original.id)
    let supersededSnapshot = V3ReviewArchiveSnapshot(plans: base.plans,
        positions: [original, laterOpening], positionCloses: base.positionCloses)
    let supersededInsight = supersededSnapshot.closeCompletenessInsight(source: .liveOanda,
        id: "live-oanda|user-close|selected-close-superseded")!
    #expect(supersededInsight.openingWasSuperseded)
    let supersededAnswer = V3ReviewInsightQuestionAnswer.make(question: .openingSupersession,
        route: .ready(supersededInsight))
    #expect(supersededAnswer?.text.contains("historical evidence, not the current opening") == true)
    #expect(supersededAnswer?.citations == [
        "v3:live-oanda:user-close:\(supersededInsight.closeID)",
        "v3:live-oanda:user-position:\(supersededInsight.openingRecordID)",
    ])

    let currentInsight = base.closeCompletenessInsight(source: .liveOanda,
        id: "live-oanda|user-close|selected-close-superseded")!
    let currentAnswer = V3ReviewInsightQuestionAnswer.make(question: .openingSupersession,
        route: .ready(currentInsight))
    #expect(currentAnswer?.text.contains("does not mark opening revision") == true)

    let nonReady: [V3ReviewInsightRouteValidation] = [.loading, .unavailable, .empty, .stale]
    for state in nonReady {
        for question in V3ReviewInsightQuestion.allCases {
            #expect(V3ReviewInsightQuestionAnswer.make(question: question, route: state) == nil)
        }
    }
}
