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

    private func archiveCandle(_ start: Date, instrument: String = "EUR/USD",
                               bid: (Double, Double, Double, Double),
                               ask: (Double, Double, Double, Double)) -> OandaBidAskCandle {
        OandaBidAskCandle(instrument: instrument, granularity: "M1", sourceTime: start,
            complete: true, bidOpen: bid.0, bidHigh: bid.1, bidLow: bid.2, bidClose: bid.3,
            askOpen: ask.0, askHigh: ask.1, askLow: ask.2, askClose: ask.3)
    }

    private func archivePlan(side: V3SpotSide = .long) -> V3TradePlan {
        V3TradePlan(id: "archive-plan", instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1", engineVersion: "V3_ORB_ENGINE_1",
            sourceObservationID: "confirm-source", state: .validated, side: side,
            entryPrice: 1.100, stopPrice: side == .long ? 1.099 : 1.101,
            targetPrice: side == .long ? 1.102 : 1.098, units: 1,
            maxSpread: 0.0003, riskFraction: 0.01, createdAt: now)
    }

    private func archiveEntryCandle(_ plan: V3TradePlan, spread: Double = 0.0002) -> OandaBidAskCandle {
        archiveCandle(plan.createdAt.addingTimeInterval(-60),
            bid: (1.0999, 1.1000, 1.0998, 1.0999),
            ask: (1.1001, max(1.1002, 1.0999 + spread), 1.1000, 1.0999 + spread))
    }

    @Test func archiveStructuralReplayHandlesFirstTouchesAndUnresolvedSeries() {
        let plan = archivePlan()
        let stop = archiveCandle(now, bid: (1.100, 1.1001, 1.0989, 1.0995),
            ask: (1.1002, 1.1003, 1.0991, 1.0997))
        let laterTarget = archiveCandle(now.addingTimeInterval(60),
            bid: (1.100, 1.1021, 1.0999, 1.101), ask: (1.1002, 1.1023, 1.1001, 1.1012))
        let first = ORBArchiveStructuralReplay.evaluate(plan: plan, candles: [archiveEntryCandle(plan), laterTarget, stop])
        #expect(first.status == .stopTouched)
        #expect(first.firstTouchCandleStart == now)
        #expect(first.firstTouchCandleEnd == now.addingTimeInterval(60))
        #expect(abs((first.spreadToRiskRatio ?? 0) - 0.2) < 1e-12)
        #expect(first.entryQuoteCandleStart == now.addingTimeInterval(-60))
        #expect(first.entryQuoteCandleEnd == now)
        #expect(first.entryBidClose == 1.0999)
        #expect(first.entryAskClose == 1.1001)
        #expect(first.entrySpread == first.entryAskClose! - first.entryBidClose!)
        #expect(first.entryIndicativeSideClose == first.entryAskClose)
        let quiet = archiveCandle(now, bid: (1.100, 1.101, 1.0995, 1.100),
            ask: (1.1002, 1.1012, 1.0997, 1.1002))
        let unresolved = ORBArchiveStructuralReplay.evaluate(plan: plan, candles: [archiveEntryCandle(plan), quiet])
        #expect(unresolved.status == .unresolved)
        #expect(unresolved.firstTouchCandleEnd == nil)
        #expect(unresolved.entryQuoteWithinPlanMaxSpread == true)
    }

    @Test func archiveStructuralReplayMarksAFirstTouchAfterCoverageGapUnresolved() {
        let plan = archivePlan()
        let quietAtEntry = archiveCandle(now, bid: (1.100, 1.101, 1.0995, 1.100),
            ask: (1.1002, 1.1012, 1.0997, 1.1002))
        let touchAfterTwoMissingMinutes = archiveCandle(now.addingTimeInterval(180),
            bid: (1.100, 1.1001, 1.0989, 1.0995), ask: (1.1002, 1.1003, 1.0991, 1.0997))
        let result = ORBArchiveStructuralReplay.evaluate(plan: plan,
            candles: [archiveEntryCandle(plan), quietAtEntry, touchAfterTwoMissingMinutes])
        #expect(result.status == .unresolvedCoverageGap)
        #expect(result.coverageGapFrom == now.addingTimeInterval(60))
        #expect(result.coverageGapTo == now.addingTimeInterval(180))
        #expect(result.firstTouchCandleStart == nil)
        #expect(result.entryQuoteWithinPlanMaxSpread == true)
    }

    private func archiveBatch(filename: String? = nil,
                              candles: [OandaBidAskCandle], transport: OandaTransport = .ok,
                              httpStatus: Int? = 200, rejected: Bool = false,
                              from: Date? = nil, to: Date? = nil) -> ORBArchiveBatchSource {
        let requestedFrom = from ?? now.addingTimeInterval(-60)
        let requestedTo = to ?? now.addingTimeInterval(180)
        let name = filename ?? "oanda-practice-EUR_USD-M1-\(Int(requestedFrom.timeIntervalSince1970))-\(Int(requestedTo.timeIntervalSince1970)).json"
        return ORBArchiveBatchSource(filename: name, batch: OandaHistoricalBidAskBatch(
            instrument: "EUR_USD", granularity: "M1", requestedFrom: requestedFrom,
            requestedTo: requestedTo, candles: candles, transport: transport,
            practiceOnlyRejected: rejected, httpStatus: httpStatus))
    }

    @Test func archiveBatchValidatorRejectsBadProvenanceAndCandleIdentity() {
        let mismatched = OandaBidAskCandle(instrument: "GBP_JPY", granularity: "M1",
            sourceTime: now, complete: true, bidOpen: 1.1, bidHigh: 1.1, bidLow: 1.1,
            bidClose: 1.1, askOpen: 1.1002, askHigh: 1.1002, askLow: 1.1002, askClose: 1.1002)
        let source = archiveBatch(candles: [mismatched], transport: .network,
            httpStatus: 503, rejected: true)
        let reasons = Set(ORBArchiveBatchValidator.validate([source]).map(\.reason))
        #expect(reasons.contains("transport_not_ok"))
        #expect(reasons.contains("http_status_not_200"))
        #expect(reasons.contains("practice_only_rejected"))
        #expect(reasons.contains("candle_batch_identity_mismatch"))
    }

    @Test func archiveBatchValidatorRejectsFilenameEpochsThatDisagreeWithMetadata() {
        let valid = archiveCandle(now, instrument: "EUR_USD", bid: (1.1, 1.1, 1.1, 1.1),
            ask: (1.1002, 1.1002, 1.1002, 1.1002))
        let source = archiveBatch(filename: "oanda-practice-EUR_USD-M1-100-200.json", candles: [valid])
        #expect(ORBArchiveBatchValidator.validate([source]).contains {
            $0.reason == "filename_requested_range_mismatch"
        })
    }

    @Test func archiveSessionCoverageSeparatesOpeningRangeFromCensoredSetupWindow() {
        let start = now
        func bars(count: Int) -> [ORBBar] {
            (0..<count).map { minute in
                let time = start.addingTimeInterval(Double(minute * 60))
                return ORBBar(id: "coverage-\(minute)", instrument: "EUR/USD",
                    sourceTime: time, endTime: time.addingTimeInterval(60),
                    open: 1.1, high: 1.101, low: 1.099, close: 1.1)
            }
        }
        let defaults = ORBArchiveSessionCoverageEvaluator.evaluate(sessionStart: start, bars: bars(count: 125))
        #expect(defaults.openingRangeEligible)
        #expect(defaults.fullSetupWindowCovered)
        let censored = ORBArchiveSessionCoverageEvaluator.evaluate(sessionStart: start, bars: bars(count: 124))
        #expect(censored.openingRangeEligible)
        #expect(!censored.fullSetupWindowCovered)
        let insufficient = ORBArchiveSessionCoverageEvaluator.evaluate(sessionStart: start, bars: bars(count: 4))
        #expect(!insufficient.openingRangeEligible)
        #expect(!insufficient.fullSetupWindowCovered)
    }

    @Test func archiveOutputGuardResolvesSymlinksAndRejectsOutputInsideInput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orb-archive-guard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("historical-bid-ask", isDirectory: true)
        let output = root.appendingPathComponent("structural-replay", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        #expect(ORBArchiveFilesystemGuard.outputIsOutsideInputArchive(inputArchive: input, outputDirectory: output))
        let link = root.appendingPathComponent("linked-output", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        #expect(!ORBArchiveFilesystemGuard.outputIsOutsideInputArchive(inputArchive: input, outputDirectory: link))
    }

    @Test func archiveBatchValidatorRejectsConflictingOverlaps() {
        let one = archiveCandle(now, instrument: "EUR_USD", bid: (1.1, 1.1, 1.1, 1.1),
            ask: (1.1002, 1.1002, 1.1002, 1.1002))
        let other = archiveCandle(now, instrument: "EUR_USD", bid: (1.1001, 1.1001, 1.1001, 1.1001),
            ask: (1.1003, 1.1003, 1.1003, 1.1003))
        let a = archiveBatch(candles: [one])
        let b = archiveBatch(filename: "oanda-practice-EUR_USD-M1-1899999940-1900000180.json", candles: [other])
        let issues = ORBArchiveBatchValidator.validate([b, a])
        #expect(issues.filter { $0.reason == "conflicting_duplicate_candle" }.count == 2)
    }

    @Test func archiveStructuralReplayUsesShortAskAndAmbiguousSameCandleTouches() {
        let short = archivePlan(side: .short)
        let target = archiveCandle(now, bid: (1.0997, 1.0998, 1.0978, 1.0996),
            ask: (1.0999, 1.1000, 1.0979, 1.0998))
        #expect(ORBArchiveStructuralReplay.evaluate(plan: short,
            candles: [archiveEntryCandle(short), target]).status == .targetTouched)
        let shortEntry = ORBArchiveStructuralReplay.evaluate(plan: short, candles: [archiveEntryCandle(short)])
        #expect(shortEntry.entryIndicativeSideClose == shortEntry.entryBidClose)
        #expect(shortEntry.entrySpread == shortEntry.entryAskClose! - shortEntry.entryBidClose!)
        let long = archivePlan()
        let both = archiveCandle(now, bid: (1.100, 1.1021, 1.0989, 1.100),
            ask: (1.1002, 1.1023, 1.0991, 1.1002))
        #expect(ORBArchiveStructuralReplay.evaluate(plan: long,
            candles: [archiveEntryCandle(long), both]).status == .ambiguous)
    }

    @Test func archiveStructuralReplaySeparatesMissingEntryAndSpreadFailure() {
        let plan = archivePlan()
        let missing = ORBArchiveStructuralReplay.evaluate(plan: plan, candles: [])
        #expect(missing.status == .entryMissingQuote)
        #expect(missing.entryQuoteCandleStart == nil)
        #expect(missing.entryQuoteCandleEnd == nil)
        #expect(missing.entryBidClose == nil)
        #expect(missing.entryAskClose == nil)
        #expect(missing.entryIndicativeSideClose == nil)
        let wrongMinute = archiveCandle(now.addingTimeInterval(-120),
            bid: (1.0999, 1.1000, 1.0998, 1.0999),
            ask: (1.1001, 1.1002, 1.1000, 1.1001))
        let noFallback = ORBArchiveStructuralReplay.evaluate(plan: plan, candles: [wrongMinute])
        #expect(noFallback.status == .entryMissingQuote)
        #expect(noFallback.entryQuoteCandleStart == nil)
        let wide = archiveEntryCandle(plan, spread: 0.0004)
        #expect(ORBArchiveStructuralReplay.evaluate(plan: plan, candles: [wide]).status == .entrySpreadExceeded)
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
