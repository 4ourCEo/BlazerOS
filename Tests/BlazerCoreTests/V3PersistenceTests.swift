import Foundation
import Testing
@testable import BlazerCore

private func v3TemporaryRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("blazer-v3-\(name)-\(UUID().uuidString)")
}

private func v3Observation(_ id: String, instrument: String = "EUR/USD", time: Date) -> V3MarketObservation {
    V3MarketObservation(id: id, instrument: instrument, provider: "OANDA",
        environment: .oandaPractice, bid: 1.1000, ask: 1.1002,
        sourceTime: time, receivedAt: time)
}

private func v3Outcome(id: String = "outcome-1", instrument: String = "EUR/USD") -> V3DurableSpotOutcome {
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = v3Observation("entry", instrument: instrument, time: time)
    let exit = v3Observation("exit", instrument: instrument, time: time.addingTimeInterval(60))
    let evaluation = V3SpotOutcomeEvaluator.evaluate(side: .long, units: 10_000,
        entry: entry, exit: exit, expectedExitAt: time.addingTimeInterval(60))
    return V3DurableSpotOutcome(id: id, planID: "plan-1", instrument: instrument,
        provider: "OANDA", environment: .oandaPractice, entryObservation: entry,
        exitObservation: exit, evaluation: evaluation, strategyVersion: "v3.0.0",
        engineVersion: "engine-test", recordedAt: time.addingTimeInterval(61))
}

private func v3Plan() -> V3TradePlan {
    V3TradePlan(id: "plan-forward", instrument: "EUR/USD", strategyID: "acceptance",
        strategyVersion: "v3.0.0", engineVersion: "engine-test", sourceObservationID: "entry",
        state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
        targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003, riskFraction: 0.005,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000))
}

private func v3LivePositionRoot(_ name: String) -> URL {
    v3TemporaryRoot(name).appendingPathComponent("live-oanda", isDirectory: true)
}

private func v3LivePositionPlan(id: String = "user-plan", createdAt: Date = Date().addingTimeInterval(-120)) -> V3TradePlan {
    V3TradePlan(id: id, instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: "ORB_BREAK_RETEST_V1", engineVersion: "V3_ORB_ENGINE_1",
        sourceObservationID: "EUR/USD-confirm-1", state: .validated, side: .long,
        entryPrice: 1.1002, stopPrice: 1.0992, targetPrice: 1.1022,
        units: 10_000, maxSpread: 0.0003, riskFraction: 0.005, createdAt: createdAt)
}

private func writeV3PositionFixture(_ position: V3PositionRecord, root: URL) throws {
    let directory = root.appendingPathComponent("v3-position-events", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(position).write(to: directory.appendingPathComponent("\(position.id).json"))
}

private func v3LifecycleEvent(_ id: String, previous: V3SetupState?, state: V3SetupState,
                              time: Date) -> V3SetupLifecycleEvent {
    V3SetupLifecycleEvent(id: id, setupID: "setup-persist", instrument: "EUR/USD",
        strategyID: "orb-break-retest", strategyVersion: "1.0.0", provider: "OANDA",
        environment: .oandaLive, previousState: previous, state: state,
        sourceObservationID: "quote-\(id)", sourceTime: time, receivedAt: time,
        recordedAt: time, reason: "persisted fixture")
}

private func v3EntryEvidence(id: String = "entry-1", planID: String = "plan-1",
                            time: Date) -> V3PlanEntryEvidence {
    V3PlanEntryEvidence(id: id, planID: planID,
        observation: v3Observation("quote-entry", time: time), recordedAt: time)
}

private func v3EvidenceEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

@Test func v3PersistenceSeparatesAndReloadsExecutableOutcomes() async throws {
    let root = v3TemporaryRoot("reload")
    let store = ResearchStore(root: root)
    let outcome = v3Outcome()
    try await store.record(outcome)
    try await store.record(outcome)
    let reloaded = try await ResearchStore(root: root).v3SpotOutcomes()
    #expect(reloaded == [outcome])
    #expect(try await ResearchStore(root: root).outcomes().isEmpty)
}

@Test func v3PersistenceRejectsConflictingReplay() async throws {
    let root = v3TemporaryRoot("conflict")
    let store = ResearchStore(root: root)
    try await store.record(v3Outcome())
    var changed = v3Outcome()
    changed = V3DurableSpotOutcome(id: changed.id, planID: changed.planID, instrument: changed.instrument,
        provider: changed.provider, environment: changed.environment,
        entryObservation: changed.entryObservation, exitObservation: changed.exitObservation,
        evaluation: V3SpotEvaluation(status: .unresolved, side: .long, units: 10_000, reason: "replay"),
        strategyVersion: changed.strategyVersion, engineVersion: changed.engineVersion,
        recordedAt: changed.recordedAt)
    await #expect(throws: ScanError.self) { try await store.record(changed) }
}

@Test func livePlanEntryObservationIsBoundedIdempotentAndPathSafe() async throws {
    let root = v3LivePositionRoot("entry-observation")
    let store = ResearchStore(root: root)
    let plan = v3LivePositionPlan(id: "entry-plan-safe", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    let boundedPlan = V3TradePlan(id: plan.id, instrument: plan.instrument, strategyID: plan.strategyID,
        strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
        sourceObservationID: plan.sourceObservationID, state: plan.state, side: plan.side,
        entryPrice: plan.entryPrice, stopPrice: plan.stopPrice, targetPrice: plan.targetPrice,
        units: plan.units, maxSpread: plan.maxSpread, riskFraction: plan.riskFraction,
        maxEntryDeviation: 0.0003, createdAt: plan.createdAt)
    try await store.record(boundedPlan)
    let source = plan.createdAt.addingTimeInterval(1)
    let observation = V3MarketObservation(id: "quote-live-entry", instrument: plan.instrument,
        provider: "OANDA", environment: .oandaLive, bid: 1.1001, ask: 1.1003,
        sourceTime: source, receivedAt: source.addingTimeInterval(0.2))
    let stale = try await store.recordLivePlanEntryObservation(planID: plan.id,
        observation: observation, recordedAt: observation.receivedAt, shouldAppend: { false })
    #expect(stale == .generationSuperseded)
    #expect(try await store.v3PlanEntryEvidence().isEmpty)
    let first = try await store.recordLivePlanEntryObservation(planID: plan.id,
        observation: observation, recordedAt: observation.receivedAt, shouldAppend: { true })
    let replay = try await ResearchStore(root: root).recordLivePlanEntryObservation(planID: plan.id,
        observation: observation, recordedAt: observation.receivedAt.addingTimeInterval(2), shouldAppend: { true })
    guard case let .appended(entry) = first, case let .alreadyRecorded(replayed) = replay else {
        Issue.record("Expected first append then immutable replay")
        return
    }
    #expect(entry == replayed)
    #expect(entry.quality == .observed)
    #expect(entry.id.hasPrefix("live-entry-"))
    #expect(entry.id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    #expect(try await ResearchStore(root: root).v3PlanEntryEvidence() == [entry])

    let outside = V3MarketObservation(id: "quote-outside-entry", instrument: plan.instrument,
        provider: "OANDA", environment: .oandaLive, bid: 1.1006, ask: 1.1008,
        sourceTime: source, receivedAt: source.addingTimeInterval(0.2))
    await #expect(throws: ScanError.self) {
        try await ResearchStore(root: root).recordLivePlanEntryObservation(
            planID: plan.id, observation: outside, recordedAt: outside.receivedAt, shouldAppend: { true })
    }
}

@Test func v3PersistenceRejectsValidOutcomeWithoutExitAndCrossInstrumentEvidence() async throws {
    let root = v3TemporaryRoot("validation")
    let store = ResearchStore(root: root)
    let valid = v3Outcome()
    let missingExit = V3DurableSpotOutcome(id: "missing-exit", planID: valid.planID,
        instrument: valid.instrument, provider: valid.provider, environment: valid.environment,
        entryObservation: valid.entryObservation, exitObservation: nil, evaluation: valid.evaluation,
        strategyVersion: valid.strategyVersion, engineVersion: valid.engineVersion, recordedAt: valid.recordedAt)
    await #expect(throws: ScanError.self) { try await store.record(missingExit) }

    let mismatch = V3DurableSpotOutcome(id: "mismatch", planID: valid.planID,
        instrument: valid.instrument, provider: valid.provider, environment: valid.environment,
        entryObservation: valid.entryObservation, exitObservation: v3Observation("other", instrument: "GBP/USD", time: valid.recordedAt),
        evaluation: valid.evaluation, strategyVersion: valid.strategyVersion,
        engineVersion: valid.engineVersion, recordedAt: valid.recordedAt)
    await #expect(throws: ScanError.self) { try await store.record(mismatch) }
}

@Test func v3PersistenceKeepsMissingExitExplicitlyUnresolved() async throws {
    let root = v3TemporaryRoot("unresolved")
    let time = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = v3Observation("entry", time: time)
    let unresolved = V3DurableSpotOutcome(id: "unresolved-1", planID: "plan-1",
        instrument: "EUR/USD", provider: "OANDA", environment: .oandaPractice,
        entryObservation: entry, exitObservation: nil,
        evaluation: V3SpotEvaluation(status: .unresolved, side: .long, units: 10_000,
            reason: "missing_observation"), strategyVersion: "v3.0.0",
        engineVersion: "engine-test", recordedAt: time.addingTimeInterval(6))
    try await ResearchStore(root: root).record(unresolved)
    let records = try await ResearchStore(root: root).v3SpotOutcomes()
    #expect(records.first?.evaluation.status == .unresolved)
    #expect(records.first?.evaluation.notionalPnl == nil)
}

@Test func v3ForwardPathEvaluatesThenPersistsExecutableOutcome() async throws {
    let root = v3TemporaryRoot("forward-path")
    let store = ResearchStore(root: root)
    let plan = v3Plan()
    let entry = v3Observation("entry", time: plan.createdAt)
    let exit = v3Observation("exit", time: plan.createdAt.addingTimeInterval(60))
    let persisted = try await store.recordV3SpotOutcome(plan: plan, entry: entry,
        exit: exit, recordedAt: plan.createdAt.addingTimeInterval(60))
    #expect(persisted.evaluation.status == .valid)
    #expect(persisted.evaluation.entryPrice == entry.ask)
    #expect(try await store.v3SpotOutcomes().count == 1)
}

@Test func v3PlansAreImmutableAndReloadable() async throws {
    let root = v3TemporaryRoot("plans")
    let store = ResearchStore(root: root)
    let plan = v3Plan()
    try await store.record(plan)
    try await store.record(plan)
    #expect(try await ResearchStore(root: root).v3TradePlans() == [plan])

    let changedState = V3TradePlan(id: plan.id, instrument: plan.instrument,
        strategyID: plan.strategyID, strategyVersion: plan.strategyVersion,
        engineVersion: plan.engineVersion, sourceObservationID: plan.sourceObservationID,
        state: .offered, side: plan.side, entryPrice: plan.entryPrice,
        stopPrice: plan.stopPrice, targetPrice: plan.targetPrice, units: plan.units,
        maxSpread: plan.maxSpread, riskFraction: plan.riskFraction,
        evidenceIDs: plan.evidenceIDs, createdAt: plan.createdAt)
    await #expect(throws: ScanError.self) { try await store.record(changedState) }
}

@Test func userReportedPositionRequiresLiveRootAndExactPersistedPlan() async throws {
    let liveRoot = v3LivePositionRoot("user-plan-binding")
    let liveStore = ResearchStore(root: liveRoot)
    let plan = v3LivePositionPlan()
    try await liveStore.record(plan)

    let reportTime = Date()
    let saved = try await liveStore.recordUserReportedPosition(planID: plan.id, units: 12_500,
        entryPrice: 1.1007, userReportedEnteredAt: reportTime.addingTimeInterval(-20),
        updatedAt: reportTime)
    #expect(saved.state == .userReported)
    #expect(saved.provenance == .manualTradeReport)
    #expect(saved.instrument == plan.instrument)
    #expect(saved.side == plan.side)
    #expect(saved.planID == plan.id)
    #expect(saved.broker == nil && saved.brokerPositionID == nil)
    #expect(saved.id.hasPrefix("userposrev-"))

    let proxyStore = ResearchStore(root: v3TemporaryRoot("user-plan-proxy"))
    await #expect(throws: V3UserPositionReportError.self) {
        try await proxyStore.recordUserReportedPosition(planID: plan.id, units: 1, updatedAt: reportTime)
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: "missing-plan", units: 1, updatedAt: reportTime)
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: plan.id, units: -1, updatedAt: reportTime)
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: plan.id, units: 1,
            entryPrice: 0, updatedAt: reportTime)
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: plan.id, units: 1,
            updatedAt: Date().addingTimeInterval(6))
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: plan.id, units: 1,
            userReportedEnteredAt: plan.createdAt.addingTimeInterval(-1), updatedAt: reportTime)
    }
    await #expect(throws: V3UserPositionReportError.self) {
        try await liveStore.recordUserReportedPosition(planID: plan.id, units: 1,
            userReportedEnteredAt: reportTime.addingTimeInterval(10), updatedAt: reportTime)
    }
}

@Test func userReportedPositionExactRetryRetainsFirstTimeAndCorrectionsAreLinear() async throws {
    let store = ResearchStore(root: v3LivePositionRoot("user-position-corrections"))
    let plan = v3LivePositionPlan()
    try await store.record(plan)
    let recordedAt = Date()
    let entryTime = recordedAt.addingTimeInterval(-30)
    let first = try await store.recordUserReportedPosition(planID: plan.id, units: 10_000,
        entryPrice: 1.1003, userReportedEnteredAt: entryTime, updatedAt: recordedAt)
    let retry = try await store.recordUserReportedPosition(planID: plan.id, units: 10_000,
        entryPrice: 1.1003, userReportedEnteredAt: entryTime,
        updatedAt: recordedAt.addingTimeInterval(1))
    #expect(retry.id == first.id)
    #expect(retry.updatedAt == first.updatedAt)
    #expect(try await store.v3PositionRecords().first == first)

    let correctedAt = recordedAt.addingTimeInterval(2)
    let correction = try await store.recordUserReportedPosition(planID: plan.id, units: 9_500,
        entryPrice: 1.1004, userReportedEnteredAt: entryTime,
        updatedAt: correctedAt, supersedesRecordID: first.id)
    #expect(correction.id != first.id)
    #expect(correction.positionID == first.positionID)
    #expect(correction.supersedesRecordID == first.id)
    let correctionRetry = try await store.recordUserReportedPosition(planID: plan.id, units: 9_500,
        entryPrice: 1.1004, userReportedEnteredAt: entryTime,
        updatedAt: correctedAt.addingTimeInterval(1), supersedesRecordID: first.id)
    #expect(correctionRetry.id == correction.id)
    #expect(correctionRetry.updatedAt == correction.updatedAt)
    #expect(try await store.v3PositionRecords().first == correction)
    await #expect(throws: V3UserPositionReportError.self) {
        try await store.recordUserReportedPosition(planID: plan.id, units: 8_000,
            entryPrice: 1.1001, userReportedEnteredAt: entryTime,
            updatedAt: correctedAt.addingTimeInterval(2), supersedesRecordID: first.id)
    }
    #expect(try await store.v3PositionRecords().count == 2)
}

@Test func concurrentUserReportedPositionRootsAllowOnlyOneDifferentPayload() async throws {
    let root = v3LivePositionRoot("user-position-root-race")
    let writerA = ResearchStore(root: root)
    let writerB = ResearchStore(root: root)
    let plan = v3LivePositionPlan()
    try await writerA.record(plan)
    let reportTime = Date()
    let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
        group.addTask {
            do {
                _ = try await writerA.recordUserReportedPosition(planID: plan.id, units: 10_000,
                    entryPrice: 1.1003, updatedAt: reportTime)
                return true
            } catch { return false }
        }
        group.addTask {
            do {
                _ = try await writerB.recordUserReportedPosition(planID: plan.id, units: 12_000,
                    entryPrice: 1.1005, updatedAt: reportTime)
                return true
            } catch { return false }
        }
        var successes = 0
        for await result in group where result { successes += 1 }
        return successes
    }
    #expect(successes == 1)
    #expect(try await ResearchStore(root: root).v3PositionRecords().count == 1)
}

@Test func legacyUserReportedPositionBlocksSecondAggregate() async throws {
    let store = ResearchStore(root: v3LivePositionRoot("legacy-user-position"))
    let plan = v3LivePositionPlan()
    try await store.record(plan)
    let legacy = V3PositionRecord(id: "legacy-user-position", planID: plan.id,
        instrument: plan.instrument, state: .userReported, side: plan.side,
        units: 10_000, provenance: .manualTradeReport, updatedAt: Date())
    try await store.record(legacy)
    await #expect(throws: V3UserPositionReportError.self) {
        try await store.recordUserReportedPosition(planID: plan.id, units: 10_000, updatedAt: Date())
    }
    #expect(try await store.v3PositionRecords().map(\.id) == [legacy.id])
}

@Test func positionArchiveRejectsCorrectionBranchesAndCycles() async throws {
    let branchRoot = v3LivePositionRoot("user-position-branch-corrupt")
    let branchStore = ResearchStore(root: branchRoot)
    let plan = v3LivePositionPlan()
    try await branchStore.record(plan)
    let rootReport = try await branchStore.recordUserReportedPosition(planID: plan.id,
        units: 10_000, updatedAt: Date())
    for suffix in ["one", "two"] {
        try writeV3PositionFixture(V3PositionRecord(id: "branch-\(suffix)",
            positionID: rootReport.positionID, planID: plan.id, supersedesRecordID: rootReport.id,
            instrument: plan.instrument, state: .userReported, side: plan.side,
            units: suffix == "one" ? 9_000 : 8_000, provenance: .manualTradeReport,
            updatedAt: rootReport.updatedAt.addingTimeInterval(1)), root: branchRoot)
    }
    await #expect(throws: ScanError.self) { _ = try await branchStore.v3PositionRecords() }

    let cycleRoot = v3LivePositionRoot("user-position-cycle-corrupt")
    let cycleStore = ResearchStore(root: cycleRoot)
    try await cycleStore.record(plan)
    let cycleRootReport = try await cycleStore.recordUserReportedPosition(planID: plan.id,
        units: 10_000, updatedAt: Date())
    let time = cycleRootReport.updatedAt.addingTimeInterval(2)
    let a = V3PositionRecord(id: "cycle-a", positionID: cycleRootReport.positionID,
        planID: plan.id, supersedesRecordID: "cycle-b", instrument: plan.instrument,
        state: .userReported, side: plan.side, units: 9_000,
        provenance: .manualTradeReport, updatedAt: time)
    let b = V3PositionRecord(id: "cycle-b", positionID: cycleRootReport.positionID,
        planID: plan.id, supersedesRecordID: "cycle-a", instrument: plan.instrument,
        state: .userReported, side: plan.side, units: 8_000,
        provenance: .manualTradeReport, updatedAt: time.addingTimeInterval(1))
    try writeV3PositionFixture(a, root: cycleRoot)
    try writeV3PositionFixture(b, root: cycleRoot)
    await #expect(throws: ScanError.self) { _ = try await cycleStore.v3PositionRecords() }
}

@Test func userReportedPositionWriteFailureLeavesPlanAndLifecycleUntouched() async throws {
    let root = v3LivePositionRoot("user-position-write-failure")
    let store = ResearchStore(root: root)
    let plan = v3LivePositionPlan()
    try await store.record(plan)
    let lifecycle = v3LifecycleEvent("user-position-lifecycle", previous: nil,
        state: .watching, time: plan.createdAt)
    try await store.record(lifecycle)
    let positionsPath = root.appendingPathComponent("v3-position-events")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: positionsPath, withIntermediateDirectories: true)
    try Data("blocked".utf8).write(to: positionsPath.appendingPathComponent("userposrev-blocked.json"))
    await #expect(throws: Error.self) {
        try await store.recordUserReportedPosition(planID: plan.id, units: 10_000, updatedAt: Date())
    }
    #expect(try await store.v3TradePlans().map(\.id) == [plan.id])
    #expect(try await store.v3SetupLifecycleEvents().map(\.id) == [lifecycle.id])
}

@Test func v3SetupLifecycleEventsPersistReplayAndRejectInvalidTransitions() async throws {
    let root = v3TemporaryRoot("setup-lifecycle")
    let store = ResearchStore(root: root)
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let watching = v3LifecycleEvent("watching-1", previous: nil, state: .watching, time: t0)
    let forming = v3LifecycleEvent("forming-1", previous: .watching, state: .forming,
        time: t0.addingTimeInterval(1))
    try await store.record(watching)
    try await store.record(forming)
    try await store.record(forming)
    #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents() == [watching, forming])

    let invalid = v3LifecycleEvent("bad-1", previous: .watching, state: .confirmed,
        time: t0.addingTimeInterval(2))
    await #expect(throws: ScanError.self) { try await store.record(invalid) }
    #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents() == [watching, forming])
}

@Test func v3PlanEntryEvidenceRejectsMalformedDecodedRecord() async throws {
    let root = v3TemporaryRoot("entry-malformed")
    let directory = root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let malformed = v3EntryEvidence(id: "unsafe/id", time: date)
    let data = try v3EvidenceEncoder().encode(malformed)
    try data.write(to: directory.appendingPathComponent("entry-record.json"))

    await #expect(throws: ScanError.self) {
        _ = try await ResearchStore(root: root).v3PlanEntryEvidence()
    }
}

@Test func v3PlanEntryEvidenceRejectsFileNameIdentityMismatch() async throws {
    let root = v3TemporaryRoot("entry-filename")
    let store = ResearchStore(root: root)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let entry = v3EntryEvidence(time: date)
    try await store.record(entry)
    let directory = root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true)
    let original = directory.appendingPathComponent("\(entry.id).json")
    let mismatched = directory.appendingPathComponent("different-entry-id.json")
    try FileManager.default.moveItem(at: original, to: mismatched)

    await #expect(throws: ScanError.self) {
        _ = try await ResearchStore(root: root).v3PlanEntryEvidence()
    }
}

@Test func v3PlanEntryEvidenceRejectsInvalidObservation() async throws {
    let root = v3TemporaryRoot("entry-observation")
    let directory = root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let observation = V3MarketObservation(id: "quote-entry", instrument: "EUR/USD",
        provider: "OANDA", environment: .oandaPractice, bid: 1.2, ask: 1.1,
        sourceTime: date, receivedAt: date)
    let malformed = V3PlanEntryEvidence(id: "entry-1", planID: "plan-1",
        observation: observation, recordedAt: date)
    let data = try v3EvidenceEncoder().encode(malformed)
    try data.write(to: directory.appendingPathComponent("entry-1.json"))

    await #expect(throws: ScanError.self) {
        _ = try await ResearchStore(root: root).v3PlanEntryEvidence()
    }
}

@Test func v3PlanEntryEvidenceRejectsUnsafePlanIdentity() async throws {
    let root = v3TemporaryRoot("entry-plan-identity")
    let directory = root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let malformed = v3EntryEvidence(planID: "unsafe/plan", time: date)
    let data = try v3EvidenceEncoder().encode(malformed)
    try data.write(to: directory.appendingPathComponent("entry-1.json"))

    await #expect(throws: ScanError.self) {
        _ = try await ResearchStore(root: root).v3PlanEntryEvidence()
    }
}

@Test func everyV3CollectionRejectsFilenameIdentityMismatch() async throws {
    let root = v3TemporaryRoot("all-filename-identities")
    let store = ResearchStore(root: root)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = v3Plan()
    let lifecycle = v3LifecycleEvent("setup-id", previous: nil, state: .watching, time: date)
    let entry = v3EntryEvidence(id: "entry-id", planID: plan.id, time: date)
    let position = V3PositionRecord(id: "position-id", planID: plan.id, instrument: plan.instrument,
        state: .userReported, side: .long, units: 1, provenance: .manualTradeReport, updatedAt: date)
    let spot = v3Outcome(id: "spot-id")
    let structural = V3StructuralOutcome(id: "structural-id", planID: plan.id,
        instrument: plan.instrument, strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
        quality: .simulated, status: .unresolved, exitReason: .missingQuote,
        entryObservation: nil, exitObservation: nil, entryPrice: nil, exitPrice: nil,
        netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: date)
    try await store.record(plan)
    try await store.record(lifecycle)
    try await store.record(entry)
    try await store.record(position)
    try await store.record(spot)
    try await store.record(structural)

    func move(_ directory: String, from: String, to: String) throws {
        let folder = root.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("\(from).json"),
                                         to: folder.appendingPathComponent("\(to).json"))
    }
    try move("v3-trade-plans", from: plan.id, to: "wrong-plan")
    try move("v3-setup-lifecycle-events", from: lifecycle.id, to: "wrong-setup")
    try move("v3-plan-entry-evidence", from: entry.id, to: "wrong-entry")
    try move("v3-position-events", from: position.id, to: "wrong-position")
    try move("v3-spot-outcomes", from: spot.id, to: "wrong-spot")
    try move("v3-structural-outcomes", from: structural.id, to: "wrong-structural")

    await #expect(throws: ScanError.self) { _ = try await store.v3TradePlans() }
    await #expect(throws: ScanError.self) { _ = try await store.v3SetupLifecycleEvents() }
    await #expect(throws: ScanError.self) { _ = try await store.v3PlanEntryEvidence() }
    await #expect(throws: ScanError.self) { _ = try await store.v3PositionRecords() }
    await #expect(throws: ScanError.self) { _ = try await store.v3SpotOutcomes() }
    await #expect(throws: ScanError.self) { _ = try await store.v3StructuralOutcomes() }
}

@Test func v3CollectionsRejectUnsafeIDsAndPlanReferencesButKeepOptionalNil() async throws {
    let root = v3TemporaryRoot("safe-identities")
    let store = ResearchStore(root: root)
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let plan = v3Plan()
    let unsafePlan = V3TradePlan(id: "unsafe/plan", instrument: plan.instrument,
        strategyID: plan.strategyID, strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
        sourceObservationID: plan.sourceObservationID, state: plan.state, side: plan.side,
        entryPrice: plan.entryPrice, stopPrice: plan.stopPrice, targetPrice: plan.targetPrice,
        units: plan.units, maxSpread: plan.maxSpread, riskFraction: plan.riskFraction,
        createdAt: plan.createdAt)
    await #expect(throws: ScanError.self) { try await store.record(unsafePlan) }

    let unsafePosition = V3PositionRecord(id: "position-safe", planID: "unsafe/plan",
        instrument: "EUR/USD", state: .userReported, side: .long, units: 1,
        provenance: .manualTradeReport, updatedAt: date)
    await #expect(throws: ScanError.self) { try await store.record(unsafePosition) }
    let unlinkedPosition = V3PositionRecord(id: "position-unlinked", planID: nil,
        instrument: "EUR/USD", state: .userReported, side: .long, units: 1,
        provenance: .manualTradeReport, updatedAt: date)
    try await store.record(unlinkedPosition)
    #expect(try await store.v3PositionRecords() == [unlinkedPosition])

    let unsafeSpot = V3DurableSpotOutcome(id: "spot-safe", planID: "unsafe/plan",
        instrument: "EUR/USD", provider: "OANDA", environment: .oandaPractice,
        entryObservation: nil, exitObservation: nil,
        evaluation: V3SpotEvaluation(status: .unresolved, side: .long, units: 1),
        strategyVersion: "1", engineVersion: "engine", recordedAt: date)
    await #expect(throws: ScanError.self) { try await store.record(unsafeSpot) }
    let unsafeStructural = V3StructuralOutcome(id: "structural-safe", planID: "unsafe/plan",
        instrument: "EUR/USD", strategyVersion: "1", engineVersion: "engine", quality: .simulated,
        status: .unresolved, exitReason: .missingQuote, entryObservation: nil, exitObservation: nil,
        entryPrice: nil, exitPrice: nil, netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: date)
    await #expect(throws: ScanError.self) { try await store.record(unsafeStructural) }
}

@Test func v3PlanAllowsSafeSlashDelimitedObservationReferencesButRejectsTraversal() async throws {
    let root = v3TemporaryRoot("slash-safe-references")
    let store = ResearchStore(root: root)
    let base = v3Plan()
    let valid = V3TradePlan(id: "slash-safe-plan", instrument: base.instrument,
        strategyID: base.strategyID, strategyVersion: base.strategyVersion,
        engineVersion: base.engineVersion, sourceObservationID: "EUR/USD-confirm-123",
        state: base.state, side: base.side, entryPrice: base.entryPrice,
        stopPrice: base.stopPrice, targetPrice: base.targetPrice, units: base.units,
        maxSpread: base.maxSpread, riskFraction: base.riskFraction,
        evidenceIDs: ["EUR/USD-range-1,EUR/USD-range-2", "EUR/USD-confirm-123"],
        createdAt: base.createdAt)
    try await store.record(valid)
    #expect(try await store.v3TradePlans() == [valid])

    let unsafe = V3TradePlan(id: "traversal-plan", instrument: base.instrument,
        strategyID: base.strategyID, strategyVersion: base.strategyVersion,
        engineVersion: base.engineVersion, sourceObservationID: "EUR/USD/../../secret",
        state: base.state, side: base.side, entryPrice: base.entryPrice,
        stopPrice: base.stopPrice, targetPrice: base.targetPrice, units: base.units,
        maxSpread: base.maxSpread, riskFraction: base.riskFraction,
        evidenceIDs: base.evidenceIDs, createdAt: base.createdAt)
    await #expect(throws: ScanError.self) { try await store.record(unsafe) }
}
