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

    private func livePlan(createdAt: Date) -> V3TradePlan {
        V3TradePlan(id: "orb-live-plan", instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1", engineVersion: "V3_ORB_ENGINE_1",
            sourceObservationID: "confirm", state: .validated, side: .long,
            entryPrice: 1.1002, stopPrice: 1.099, targetPrice: 1.102,
            units: 10_000, maxSpread: 0.0003, riskFraction: 0.01,
            maxEntryDeviation: 0.0003, createdAt: createdAt)
    }

    private func liveEntryObservation(at time: Date) -> V3MarketObservation {
        V3MarketObservation(id: "live-entry-quote", instrument: "EUR/USD", provider: "OANDA",
            environment: .oandaLive, bid: 1.1001, ask: 1.1003,
            sourceTime: time, receivedAt: time.addingTimeInterval(0.1))
    }

    private func liveExitObservation(_ id: String, bid: Double, ask: Double,
                                     sourceTime: Date, receivedAt: Date? = nil) -> V3MarketObservation {
        V3MarketObservation(id: id, instrument: "EUR/USD", provider: "OANDA",
            environment: .oandaLive, bid: bid, ask: ask,
            sourceTime: sourceTime, receivedAt: receivedAt ?? sourceTime.addingTimeInterval(0.1))
    }

    private func persistLiveEntry(plan: V3TradePlan, store: ResearchStore,
                                  observation: V3MarketObservation) async throws {
        try await store.record(plan)
        let result = try await store.recordLivePlanEntryObservation(planID: plan.id,
            observation: observation, recordedAt: observation.receivedAt, shouldAppend: { true })
        guard case .appended = result else { throw ScanError.failed("Live entry fixture did not append") }
    }

    private func writeEntryFixture(_ entry: V3PlanEntryEvidence, root: URL) throws {
        let directory = root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entry).write(to: directory.appendingPathComponent("\(entry.id).json"))
    }

    private func terminalLifecycleEvents(planID: String, confirmedAt: Date,
                                         terminalAt: Date) -> [V3SetupLifecycleEvent] {
        let digest = String(repeating: "a", count: 64)
        func event(_ id: String, previous: V3SetupState?, state: V3SetupState,
                   sourceTime: Date, planID: String? = nil, sequence: UInt64) -> V3SetupLifecycleEvent {
            V3SetupLifecycleEvent(id: id, setupID: "setup-shadow",
                instrument: "EUR/USD", strategyID: "SHADOW_TEST_STRATEGY",
                strategyVersion: "ORB_BREAK_RETEST_V1", provider: "OANDA", environment: .oandaLive,
                previousState: previous, state: state, sourceObservationID: "bar-\(id)",
                sourceTime: sourceTime, receivedAt: sourceTime.addingTimeInterval(0.1),
                recordedAt: sourceTime.addingTimeInterval(0.2), planID: planID,
                reason: "observed", configurationDigest: digest, inputDigest: digest,
                engineVersion: "V3_ORB_ENGINE_1", sourceBarIDs: ["bar-\(id)"],
                quoteSequence: sequence, reasonCodes: ["observed"], structureID: "structure-shadow",
                timeframeSeconds: 60, evidenceSchemaVersion: 1)
        }
        return [event("confirm", previous: nil, state: .confirmed,
                      sourceTime: confirmedAt, planID: planID, sequence: 1),
                event("terminal", previous: .confirmed, state: .invalidated,
                      sourceTime: terminalAt, sequence: 2)]
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

    @Test func genericEvaluatorKeepsEvaluationTimeFreshnessWhileLiveOptionUsesEntryReceipt() {
        let plan = plan()
        let stale = entry(plan, at: now.addingTimeInterval(-30))
        let generic = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: stale,
            exitQuotes: [quote("target", bid: 1.1021, ask: 1.1023, at: now)],
            asOf: now)
        #expect(generic.status == .unresolved)
        #expect(generic.exitReason == .staleEvidence)

        let livePath = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: stale,
            exitQuotes: [quote("target-live", bid: 1.1021, ask: 1.1023, at: now)],
            asOf: now, maximumEvidenceAge: 5, entryFreshnessAtReceipt: true)
        #expect(livePath.status == .winner)
        #expect(livePath.exitReason == .takeProfit)
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

    @Test func liveShadowOutcomeBindsObservedEntryAndStoresOneSimulatedTerminalResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-5))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-2))
        try await persistLiveEntry(plan: plan, store: store, observation: entryObservation)
        let exit = liveExitObservation("target-live", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-1))
        let appended = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        guard case let .appended(outcome) = appended else {
            Issue.record("Expected a terminal simulated outcome")
            return
        }
        #expect(outcome.status == .winner)
        #expect(outcome.exitReason == .takeProfit)
        #expect(outcome.quality == .simulated)
        #expect(outcome.entryObservation == (try await store.v3PlanEntryEvidence().first?.observation))
        #expect(outcome.exitObservation == exit)
        #expect(outcome.id.hasPrefix("shadow-structural-"))
        let retry = try await ResearchStore(root: root).recordLiveShadowStructuralOutcome(
            planID: plan.id, exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { false })
        guard case let .alreadyRecorded(replayed) = retry else {
            Issue.record("Expected exact retry to return the durable terminal result")
            return
        }
        #expect(replayed.id == outcome.id)
        #expect(replayed.quality == .simulated)
        #expect(try await store.v3StructuralOutcomes().map(\.id) == [outcome.id])
        #expect(try await store.v3PositionRecords().isEmpty)
        #expect(try await store.v3SetupLifecycleEvents().isEmpty)

        let conflict = liveExitObservation("other-target-live", bid: 1.1022, ask: 1.1024,
            sourceTime: now.addingTimeInterval(-0.5))
        await #expect(throws: ScanError.self) {
            try await ResearchStore(root: root).recordLiveShadowStructuralOutcome(
                planID: plan.id, exitObservation: conflict, recordedAt: conflict.receivedAt,
                shouldAppend: { true })
        }
        #expect(try await store.v3StructuralOutcomes().map(\.id) == [outcome.id])
    }

    @Test func liveShadowOutcomeRequiresStrictSourceAndReceiptChronology() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-time-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-5))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-2))
        try await persistLiveEntry(plan: plan, store: store, observation: entryObservation)
        let persistedEntry = try #require(await store.v3PlanEntryEvidence().first)

        let equalSource = liveExitObservation("equal-source", bid: 1.1021, ask: 1.1023,
            sourceTime: persistedEntry.observation.sourceTime,
            receivedAt: persistedEntry.observation.receivedAt.addingTimeInterval(0.1))
        let sourceRejected = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: equalSource, recordedAt: equalSource.receivedAt, shouldAppend: { true })
        #expect(sourceRejected == .noTerminalTrigger)

        let equalReceipt = liveExitObservation("equal-receipt", bid: 1.1021, ask: 1.1023,
            sourceTime: persistedEntry.observation.sourceTime.addingTimeInterval(0.1),
            receivedAt: persistedEntry.observation.receivedAt)
        let receiptRejected = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: equalReceipt, recordedAt: equalReceipt.receivedAt, shouldAppend: { true })
        #expect(receiptRejected == .noTerminalTrigger)
        #expect(try await store.v3StructuralOutcomes().isEmpty)

        let quiet = liveExitObservation("quiet", bid: 1.101, ask: 1.1012,
            sourceTime: now.addingTimeInterval(-1))
        let noTrigger = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: quiet, recordedAt: quiet.receivedAt, shouldAppend: { true })
        #expect(noTrigger == .noTerminalTrigger)
        #expect(try await store.v3StructuralOutcomes().isEmpty)
    }

    @Test func liveShadowOutcomeCanRecordDelayedTriggerAfterEntryIsNoLongerFresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-delayed-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-60))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-20))
        try await persistLiveEntry(plan: plan, store: store, observation: entryObservation)
        let exit = liveExitObservation("delayed-target", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-0.5))
        #expect(exit.sourceTime.timeIntervalSince(entryObservation.sourceTime) > 10)
        let result = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        guard case let .appended(outcome) = result else {
            Issue.record("Expected a delayed terminal market trigger to remain evaluable")
            return
        }
        #expect(outcome.status == .winner)
        #expect(outcome.quality == .simulated)
        #expect(try await store.v3StructuralOutcomes().count == 1)
    }

    @Test func genericStructuralOutcomeWriterCannotBypassLivePlanBinding() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-generic-bypass-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let plan = plan()
        let candidate = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry(plan),
            exitQuotes: [quote("generic-target", bid: 1.1021, ask: 1.1023,
                at: now.addingTimeInterval(2))], asOf: now.addingTimeInterval(3))
        let store = ResearchStore(root: root)
        await #expect(throws: ScanError.self) { try await store.record(candidate) }
        #expect(try await store.v3StructuralOutcomes().isEmpty)
        #expect(!FileManager.default.fileExists(atPath:
            root.appendingPathComponent("v3-structural-outcomes", isDirectory: true).path))
    }

    @Test func liveShadowOutcomeRejectsMissingOrMismatchedObservedEntry() async throws {
        let plan = livePlan(createdAt: now.addingTimeInterval(-5))
        let exit = liveExitObservation("target", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-1))

        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-missing-entry-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let missingStore = ResearchStore(root: missingRoot)
        try await missingStore.record(plan)
        await #expect(throws: ScanError.self) {
            try await missingStore.recordLiveShadowStructuralOutcome(planID: plan.id,
                exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        }
        #expect(try await missingStore.v3StructuralOutcomes().isEmpty)

        let mismatchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-mismatch-entry-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let mismatchStore = ResearchStore(root: mismatchRoot)
        try await mismatchStore.record(plan)
        let badObservation = V3MarketObservation(id: "wrong-provider", instrument: plan.instrument,
            provider: "PROXY", environment: .oandaLive, bid: 1.1001, ask: 1.1003,
            sourceTime: now.addingTimeInterval(-2), receivedAt: now.addingTimeInterval(-1.9))
        try writeEntryFixture(V3PlanEntryEvidence(id: "wrong-entry",
            planID: plan.id, observation: badObservation, quality: .observed,
            recordedAt: badObservation.receivedAt), root: mismatchRoot)
        await #expect(throws: ScanError.self) {
            try await mismatchStore.recordLiveShadowStructuralOutcome(planID: plan.id,
                exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        }
        #expect(try await mismatchStore.v3StructuralOutcomes().isEmpty)
    }

    @Test func genericLiveEntryWriterCannotBypassExactPlanObservationPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-entry-generic-bypass-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let observation = liveEntryObservation(at: now.addingTimeInterval(-1))
        let entry = V3PlanEntryEvidence(id: "generic-live-entry", planID: "plan-id",
            observation: observation, quality: .observed, recordedAt: observation.receivedAt)
        await #expect(throws: ScanError.self) { try await store.record(entry) }
        #expect(try await store.v3PlanEntryEvidence().isEmpty)
        #expect(!FileManager.default.fileExists(atPath:
            root.appendingPathComponent("v3-plan-entry-evidence", isDirectory: true).path))
    }

    @Test func dedicatedWriterRejectsEntryOutsideDeviationOrBeforePlanCreation() async throws {
        let exit = liveExitObservation("target-entry-gates", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-0.5))

        let bandRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-entry-band-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let bandStore = ResearchStore(root: bandRoot)
        let bandPlan = livePlan(createdAt: now.addingTimeInterval(-5))
        try await bandStore.record(bandPlan)
        let outsideBand = V3MarketObservation(id: "entry-outside-band", instrument: bandPlan.instrument,
            provider: "OANDA", environment: .oandaLive, bid: 1.1006, ask: 1.1008,
            sourceTime: now.addingTimeInterval(-2), receivedAt: now.addingTimeInterval(-1.9))
        try writeEntryFixture(V3PlanEntryEvidence(id: "outside-band-entry", planID: bandPlan.id,
            observation: outsideBand, quality: .observed, recordedAt: outsideBand.receivedAt), root: bandRoot)
        await #expect(throws: ScanError.self) {
            try await bandStore.recordLiveShadowStructuralOutcome(planID: bandPlan.id,
                exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        }
        #expect(try await bandStore.v3StructuralOutcomes().isEmpty)

        let chronologyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-entry-chronology-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let chronologyStore = ResearchStore(root: chronologyRoot)
        let chronologyPlan = livePlan(createdAt: now.addingTimeInterval(-1))
        try await chronologyStore.record(chronologyPlan)
        let prePlanEntry = V3MarketObservation(id: "entry-before-plan", instrument: chronologyPlan.instrument,
            provider: "OANDA", environment: .oandaLive, bid: 1.1001, ask: 1.1003,
            sourceTime: now.addingTimeInterval(-2), receivedAt: now.addingTimeInterval(-1.9))
        try writeEntryFixture(V3PlanEntryEvidence(id: "before-plan-entry", planID: chronologyPlan.id,
            observation: prePlanEntry, quality: .observed, recordedAt: prePlanEntry.receivedAt), root: chronologyRoot)
        await #expect(throws: ScanError.self) {
            try await chronologyStore.recordLiveShadowStructuralOutcome(planID: chronologyPlan.id,
                exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        }
        #expect(try await chronologyStore.v3StructuralOutcomes().isEmpty)
    }

    @Test func liveShadowOutcomeTerminalLifecycleCutsOffAtAndAfterInvalidation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-terminal-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-8))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-2))
        try await persistLiveEntry(plan: plan, store: store, observation: entryObservation)
        for event in terminalLifecycleEvents(planID: plan.id,
            confirmedAt: now.addingTimeInterval(-3), terminalAt: now.addingTimeInterval(-1)) {
            try await store.record(event)
        }
        let atCutoff = liveExitObservation("at-terminal", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-1))
        let result = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: atCutoff, recordedAt: atCutoff.receivedAt, shouldAppend: { true })
        #expect(result == .noTerminalTrigger)
        #expect(try await store.v3StructuralOutcomes().isEmpty)

        let afterCutoff = liveExitObservation("after-terminal", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-0.5))
        let after = try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
            exitObservation: afterCutoff, recordedAt: afterCutoff.receivedAt, shouldAppend: { true })
        #expect(after == .noTerminalTrigger)
        #expect(try await store.v3StructuralOutcomes().isEmpty)
    }

    @Test func competingLiveShadowOutcomeStoresKeepOnlyOneTerminalResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-race-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let firstStore = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-5))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-2))
        try await persistLiveEntry(plan: plan, store: firstStore, observation: entryObservation)
        let exits = [
            liveExitObservation("race-target-a", bid: 1.1021, ask: 1.1023,
                sourceTime: now.addingTimeInterval(-1)),
            liveExitObservation("race-target-b", bid: 1.1022, ask: 1.1024,
                sourceTime: now.addingTimeInterval(-0.5))
        ]
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for (index, exit) in exits.enumerated() {
                let store = index == 0 ? firstStore : ResearchStore(root: root)
                group.addTask {
                    do {
                        let result = try await store.recordLiveShadowStructuralOutcome(
                            planID: plan.id, exitObservation: exit, recordedAt: exit.receivedAt,
                            shouldAppend: { true })
                        if case .appended = result { return true }
                        return false
                    } catch { return false }
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(results.filter { $0 }.count == 1)
        #expect(try await firstStore.v3StructuralOutcomes().count == 1)
        #expect(try await firstStore.v3PositionRecords().isEmpty)
    }

    @Test func failedShadowOutcomeArchiveReadLeavesPlanEntryAndPositionsUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v3-live-shadow-failure-\(UUID().uuidString)")
            .appendingPathComponent("live-oanda", isDirectory: true)
        let store = ResearchStore(root: root)
        let plan = livePlan(createdAt: now.addingTimeInterval(-5))
        let entryObservation = liveEntryObservation(at: now.addingTimeInterval(-2))
        try await persistLiveEntry(plan: plan, store: store, observation: entryObservation)
        let outcomePath = root.appendingPathComponent("v3-structural-outcomes")
        try Data("corrupt archive path".utf8).write(to: outcomePath)
        let exit = liveExitObservation("archive-failure-target", bid: 1.1021, ask: 1.1023,
            sourceTime: now.addingTimeInterval(-1))
        await #expect(throws: (any Error).self) {
            try await store.recordLiveShadowStructuralOutcome(planID: plan.id,
                exitObservation: exit, recordedAt: exit.receivedAt, shouldAppend: { true })
        }
        #expect(try await store.v3TradePlans() == [plan])
        #expect(try await store.v3PlanEntryEvidence().count == 1)
        #expect(try await store.v3PositionRecords().isEmpty)
        #expect(try await store.v3SetupLifecycleEvents().isEmpty)
    }
}
