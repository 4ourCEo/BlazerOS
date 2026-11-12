import Foundation
import Testing
@testable import BlazerCore

struct V3StructuralOutcomeTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func plan(instrument: String = "EUR/USD") -> V3TradePlan {
        V3TradePlan(id: "orb-plan", instrument: instrument, strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1", engineVersion: "V3_ORB_ENGINE_1",
            sourceObservationID: "confirm", state: .validated, side: .long,
            entryPrice: 1.1002, stopPrice: 1.099, targetPrice: 1.102,
            units: 10_000, maxSpread: 0.0003, riskFraction: 0.01, createdAt: now)
    }

    private func quote(_ id: String, bid: Double, ask: Double,
                       instrument: String = "EUR/USD", at: Date) -> V3MarketObservation {
        V3MarketObservation(id: id, instrument: instrument, provider: "OANDA",
            environment: .oandaPractice, bid: bid, ask: ask, sourceTime: at, receivedAt: at)
    }

    private func entry(_ plan: V3TradePlan, at: Date? = nil) -> V3PlanEntryEvidence {
        let time = at ?? now
        return V3PlanEntryEvidence(id: "entry-\(plan.id)", planID: plan.id,
            observation: quote("entry-quote", bid: 1.1, ask: 1.1002, at: time), recordedAt: time)
    }

    @Test func targetUsesLongAskToBidAndRecordsSpreadAdjustedPnl() {
        let plan = plan()
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("target", bid: 1.1021, ask: 1.1023, at: now.addingTimeInterval(2))],
            asOf: now.addingTimeInterval(3))
        #expect(result.status == .winner)
        #expect(result.exitReason == .takeProfit)
        #expect(result.entryPrice == 1.1002)
        #expect(result.exitPrice == 1.1021)
        #expect(abs((result.netPnl ?? 0) - 19) < 0.000001)
        #expect(abs((result.spreadCost ?? 0) - 4) < 0.000001)
    }

    @Test func stopUsesLongBidAndRecordsLoser() {
        let plan = plan()
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("stop", bid: 1.0989, ask: 1.0991, at: now.addingTimeInterval(2))],
            asOf: now.addingTimeInterval(3))
        #expect(result.status == .loser)
        #expect(result.exitReason == .stopLoss)
        #expect(abs((result.netPnl ?? 0) + 13) < 0.000001)
    }

    @Test func noTriggerRemainsUntriggeredWithoutForcedExpiration() {
        let plan = plan()
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("quiet", bid: 1.101, ask: 1.1012, at: now.addingTimeInterval(2))],
            asOf: now.addingTimeInterval(3))
        #expect(result.status == .untriggered)
        #expect(result.exitReason == .noTrigger)
        #expect(result.netPnl == nil)
    }

    @Test func sameTimestampConflictingTriggersAreAmbiguous() {
        let plan = plan()
        let time = now.addingTimeInterval(2)
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("a-stop", bid: 1.0989, ask: 1.0991, at: time),
                         quote("z-target", bid: 1.1021, ask: 1.1023, at: time)],
            asOf: now.addingTimeInterval(3))
        #expect(result.status == .ambiguous)
        #expect(result.exitReason == .ambiguousTiming)
    }

    @Test func missingQuoteIsUnresolved() {
        let plan = plan()
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [], asOf: now.addingTimeInterval(3))
        #expect(result.status == .unresolved)
        #expect(result.exitReason == .missingQuote)
    }

    @Test func staleEntryIsNotUsedAsExecutableEvidence() {
        let plan = plan()
        let stale = entry(plan, at: now.addingTimeInterval(-30))
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: stale,
            exitQuotes: [quote("target", bid: 1.1021, ask: 1.1023, at: now)],
            asOf: now)
        #expect(result.status == .unresolved)
        #expect(result.exitReason == .staleEvidence)
    }

    @Test func crossInstrumentEntryCannotContaminatePlan() {
        let plan = plan()
        let foreign = V3PlanEntryEvidence(id: "foreign", planID: plan.id,
            observation: quote("foreign-quote", bid: 1.1, ask: 1.1002,
                               instrument: "GBP/USD", at: now), recordedAt: now)
        let result = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: foreign,
            exitQuotes: [], asOf: now.addingTimeInterval(1))
        #expect(result.status == .unresolved)
        #expect(result.exitReason == .instrumentMismatch)
    }

    @Test func structuralOutcomeReplayIsIdempotentAndConflictsAreRejected() async throws {
        let plan = plan()
        let outcome = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("target", bid: 1.1021, ask: 1.1023, at: now.addingTimeInterval(2))],
            asOf: now.addingTimeInterval(3))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-structural-\(UUID().uuidString)")
        let store = ResearchStore(root: root)
        try await store.record(outcome)
        try await store.record(outcome)
        #expect(try await store.v3StructuralOutcomes() == [outcome])
        let conflict = V3StructuralOutcome(id: outcome.id, planID: outcome.planID,
            instrument: outcome.instrument, strategyVersion: outcome.strategyVersion,
            engineVersion: outcome.engineVersion, quality: .manual,
            status: outcome.status, exitReason: outcome.exitReason,
            entryObservation: outcome.entryObservation, exitObservation: outcome.exitObservation,
            entryPrice: outcome.entryPrice, exitPrice: outcome.exitPrice,
            netPnl: outcome.netPnl, spreadCost: outcome.spreadCost,
            additionalCosts: outcome.additionalCosts, recordedAt: outcome.recordedAt)
        await #expect(throws: ScanError.self) { try await store.record(conflict) }
    }
}
