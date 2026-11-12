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
