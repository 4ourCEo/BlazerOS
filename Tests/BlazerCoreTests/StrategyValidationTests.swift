import Foundation
import Testing
@testable import BlazerCore

private let validationSignalTime = Date(timeIntervalSince1970: 2_000_000_000)

private struct HistoricalEvaluatorReached: Error, LocalizedError {
    var errorDescription: String? { "historical evaluator was called" }
}

private func validationInput(signalTime: Date = validationSignalTime) -> StrategyEngine.MarketInput {
    func bars(interval: Int, count: Int) -> [StrategyEngine.CandlePayload] {
        (0..<count).map { index in
            let remaining = count - index
            let openTime = signalTime.addingTimeInterval(-Double(remaining * interval)).timeIntervalSince1970 * 1_000
            let open = 1.10 + Double(index) * 0.00001
            let close = open + 0.00002
            return StrategyEngine.CandlePayload(
                time: openTime, open: open, high: close + 0.00001,
                low: open - 0.00001, close: close)
        }
    }
    return StrategyEngine.MarketInput(
        asset: "EUR/USD", source: "historical-fixture",
        candles1m: bars(interval: 60, count: 30),
        candles5m: bars(interval: 300, count: 30),
        lastPrice: 1.101, bid: 1.1009, ask: 1.1011, spread: 0.0002,
        expirySeconds: 60,
        quoteAsOfMs: signalTime.timeIntervalSince1970 * 1_000,
        evaluatedAtMs: signalTime.timeIntervalSince1970 * 1_000,
        policy: .baseline)
}

private func validationCase(
    id: String = "case",
    stage: ValidationStage = .historicalReplay,
    authority: ValidationPriceAuthority = .independentProvider,
    entryDelay: TimeInterval = 3,
    entryPrice: Double = 1.1000,
    expiryPrice: Double = 1.1010,
    payout: Double? = 0.80,
    maximumSignalQuoteAgeSeconds: TimeInterval? = 5,
    recorded: RecordedValidationExecution? = nil,
    input: StrategyEngine.MarketInput? = nil,
    observationVenue: String = "OANDA",
    signalPriceAuthority: ValidationPriceAuthority? = nil
) -> StrategyValidationCase {
    let entry = validationSignalTime.addingTimeInterval(entryDelay)
    return StrategyValidationCase(
        id: id, stage: stage,
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, signalTimestamp: validationSignalTime,
        engineSHA: EngineIdentity.pinnedSHA1, input: input ?? validationInput(),
        maximumSignalQuoteAgeSeconds: maximumSignalQuoteAgeSeconds,
        signalPriceAuthority: signalPriceAuthority,
        observations: [
            ValidationPriceObservation(
                instrumentID: "oanda:EUR/USD", venueID: observationVenue,
                observedAt: entry, price: entryPrice, source: "fixture", authority: authority),
            ValidationPriceObservation(
                instrumentID: "oanda:EUR/USD", venueID: observationVenue,
                observedAt: entry.addingTimeInterval(60), price: expiryPrice,
                source: "fixture", authority: authority)
        ],
        recordedExecution: recorded, payoutRatio: payout,
        signalCategory: "continuation", marketRegime: "trend",
        provenance: authority == .syntheticFixture ? "synthetic fixture" : "test provider")
}

private let highEvaluator: StrategyValidationEngine.Evaluator = { input in
    EngineSignal(asset: input.asset, cabinetSide: "HIGH", call: "CALL", why: "fixture",
                 price: input.lastPrice, confidence: 0.8, asOfMs: input.evaluatedAtMs,
                 source: input.source, policy: "baseline")
}

@Test func replayPreservesSignalTimeAndSimulatesExactSixtySecondExpiry() async throws {
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase()],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    let record = try #require(records.first)

    #expect(record.signalTimestamp == validationSignalTime)
    #expect(record.entryTimestamp == validationSignalTime.addingTimeInterval(3))
    #expect(record.expiryTimestamp == validationSignalTime.addingTimeInterval(63))
    #expect(record.executionKind == .simulated)
    #expect(record.resolution == .win)
    #expect(record.payoutRatio == 0.80)
    #expect(record.isVenueOutcome == false)
}

@Test func futureOrIncompleteCandleIsRejectedBeforeEvaluation() async throws {
    var input = validationInput()
    input.candles1m[input.candles1m.count - 1].time = validationSignalTime.timeIntervalSince1970 * 1_000
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase(input: input)], configuration: .sixtySecond,
        evaluator: highEvaluator)
    let record = try #require(records.first)
    #expect(record.resolution == .unresolved)
    #expect(record.rejectionReason?.contains("future candle") == true)
}

@Test func timestampMutationAndWrongVenueCannotBecomeHistoricalOutcome() async throws {
    var mutated = validationInput()
    mutated.evaluatedAtMs = validationSignalTime.addingTimeInterval(1).timeIntervalSince1970 * 1_000
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "mutated", input: mutated),
                validationCase(id: "venue", observationVenue: "Pocket Option")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    #expect(records[0].rejectionReason == "Signal timestamp is missing or changed")
    #expect(records[1].rejectionReason == "Entry observation missing")
    #expect(records.allSatisfy { $0.resolution == .unresolved })
}

@Test func liveObservationRequiresManualExecutionAndVenueConfirmation() async throws {
    let entry = validationSignalTime.addingTimeInterval(4)
    let execution = RecordedValidationExecution(
        enteredAt: entry, entryPrice: 1.10,
        expiryObservedAt: entry.addingTimeInterval(60), expiryPrice: 1.11,
        confirmedResolution: .win, venueEventID: "venue-1")
    let live = validationCase(stage: .liveObservation, entryDelay: 4, recorded: execution)
    let missing = validationCase(id: "missing", stage: .liveObservation)
    let records = try await StrategyValidationEngine.replay(
        cases: [live, missing], configuration: .sixtySecond, evaluator: highEvaluator)
    let confirmed = try #require(records.first { $0.caseID == "case" })
    #expect(confirmed.executionKind == .recordedManual)
    #expect(confirmed.isVenueOutcome)
    #expect(confirmed.resolution == .win)
    #expect(records.first { $0.caseID == "missing" }?.resolution == .unresolved)

    let report = StrategyValidationEngine.report(records: records, stage: .liveObservation)
    #expect(report.performanceEligible == 1)
    #expect(report.overall.wins == 1)
    #expect(report.status == "INSUFFICIENT EVIDENCE")
}

@Test func reportUsesMixedPayoutExpectancyAndSeparatesSyntheticEvidence() async throws {
    let cases = [
        validationCase(id: "win", payout: 0.80),
        validationCase(id: "loss", entryPrice: 1.10, expiryPrice: 1.09, payout: 0.90),
        validationCase(id: "synthetic", authority: .syntheticFixture, payout: 0.99)
    ]
    let records = try await StrategyValidationEngine.replay(
        cases: cases, configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    let report = StrategyValidationEngine.report(records: records, stage: .historicalReplay)

    #expect(report.total == 3)
    #expect(report.syntheticRecords == 1)
    #expect(report.performanceEligible == 2)
    #expect(report.overall.wins == 1)
    #expect(report.overall.losses == 1)
    #expect(abs((report.overall.payoutAdjustedExpectancy ?? 99) - (-0.10)) < 1e-12)
    #expect(abs((report.overall.breakEvenWinRate ?? 0) - (1 / 1.8)) < 1e-12)
    #expect(report.overall.maximumConsecutiveLosses == 1)
    #expect(report.overall.effectiveSampleSize == 1)
    #expect(report.overall.candidateBlocks == 1)
    #expect(report.sampleWarning != nil)
    #expect(report.byRegime.map(\.key) == ["trend"])
    #expect(report.bySignalCategory.map(\.key) == ["continuation"])
    #expect(report.byExecutionDelay.map(\.key) == ["3-5s"])
}

@Test func replayRefusesMixedEntryAndExpiryProvenance() async throws {
    let entry = validationSignalTime.addingTimeInterval(3)
    let base = validationCase()
    let item = StrategyValidationCase(
        id: "mixed-source", stage: .historicalReplay,
        instrumentID: base.instrumentID, engineAsset: base.engineAsset, venueID: base.venueID,
        marketKind: base.marketKind, signalTimestamp: base.signalTimestamp,
        engineSHA: base.engineSHA, input: base.input,
        maximumSignalQuoteAgeSeconds: base.maximumSignalQuoteAgeSeconds,
        observations: [
            ValidationPriceObservation(
                instrumentID: base.instrumentID, venueID: base.venueID, observedAt: entry,
                price: 1.10, source: "provider-a", authority: .independentProvider),
            ValidationPriceObservation(
                instrumentID: base.instrumentID, venueID: base.venueID,
                observedAt: entry.addingTimeInterval(60), price: 1.11,
                source: "provider-b", authority: .independentProvider)
        ], payoutRatio: 0.8, provenance: "mixed fixture")
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [item], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    #expect(record.resolution == .unresolved)
    #expect(record.rejectionReason == "Entry and expiry price provenance changed")
}

@Test func payoutCoverageFailureWithholdsExpectancyAndDrawdown() async throws {
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase(payout: nil)],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    let report = StrategyValidationEngine.report(records: records, stage: .historicalReplay)
    #expect(report.overall.resolved == 1)
    #expect(report.overall.payoutAdjustedExpectancy == nil)
    #expect(report.overall.breakEvenWinRate == nil)
    #expect(report.overall.maximumUnitDrawdown == nil)
}

@Test func invalidConfigurationAndManualPricesFailClosedWithoutTrapping() async throws {
    let invalidDelay = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "invalid-delay")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: .nan),
        evaluator: highEvaluator)
    #expect(invalidDelay.first?.resolution == .unresolved)
    #expect(invalidDelay.first?.rejectionReason == "Invalid 60-second replay configuration")

    let entry = validationSignalTime.addingTimeInterval(1)
    let invalidExecution = RecordedValidationExecution(
        enteredAt: entry, entryPrice: .nan,
        expiryObservedAt: entry.addingTimeInterval(60), expiryPrice: -1,
        confirmedResolution: .win, venueEventID: "venue")
    let live = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "bad-live", stage: .liveObservation,
                               recorded: invalidExecution)],
        configuration: .sixtySecond, evaluator: highEvaluator)
    #expect(live.first?.resolution == .unresolved)
    #expect(live.first?.isVenueOutcome == false)
    #expect(live.first?.rejectionReason == "Invalid recorded manual entry")
}

@Test func duplicateCasesAndForgedOANDAOTCPricesCannotInflateEvidence() async throws {
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "duplicate")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    let duplicated = StrategyValidationEngine.report(
        records: [record, record], stage: .historicalReplay)
    #expect(duplicated.excludedDuplicateCases == 2)
    #expect(duplicated.performanceEligible == 0)

    let entry = validationSignalTime.addingTimeInterval(3)
    let otc = StrategyValidationCase(
        id: "forged-oanda", stage: .historicalReplay,
        instrumentID: "pocketoption:EURUSD_otc", engineAsset: "EUR/USD",
        venueID: "Pocket Option", marketKind: .otc,
        signalTimestamp: validationSignalTime, engineSHA: EngineIdentity.pinnedSHA1,
        input: validationInput(), maximumSignalQuoteAgeSeconds: 5, observations: [
            ValidationPriceObservation(
                instrumentID: "pocketoption:EURUSD_otc", venueID: "Pocket Option",
                observedAt: entry, price: 1.10, source: "oanda", authority: .oandaReference),
            ValidationPriceObservation(
                instrumentID: "pocketoption:EURUSD_otc", venueID: "Pocket Option",
                observedAt: entry.addingTimeInterval(60), price: 1.11,
                source: "oanda", authority: .oandaReference)
        ], payoutRatio: 0.8, provenance: "OANDA cross-check")
    let otcRecord = try #require(try await StrategyValidationEngine.replay(
        cases: [otc], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    #expect(otcRecord.resolution == .unresolved)
    #expect(StrategyValidationEngine.report(
        records: [otcRecord], stage: .historicalReplay).performanceEligible == 0)
}

@Test func unknownTiePolicyWithholdsExpectancyAndRefundPolicyCountsStake() async throws {
    let tie = validationCase(id: "tie", entryPrice: 1.10, expiryPrice: 1.10)
    let unknown = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "win"), tie],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    #expect(StrategyValidationEngine.report(
        records: unknown, stage: .historicalReplay).overall.payoutAdjustedExpectancy == nil)

    let refunded = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "win"), tie],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3, tiePolicy: .refund),
        evaluator: highEvaluator)
    let expectancy = StrategyValidationEngine.report(
        records: refunded, stage: .historicalReplay).overall.payoutAdjustedExpectancy
    #expect(expectancy == 0.4)
}

@Test func tieSettledAsLossCountsInLossRateAndConfidenceSample() async throws {
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "win"),
                validationCase(id: "flat-loss", entryPrice: 1.10, expiryPrice: 1.10)],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3, tiePolicy: .loss),
        evaluator: highEvaluator)
    let cohort = StrategyValidationEngine.report(
        records: records, stage: .historicalReplay).overall
    #expect(cohort.resolved == 2)
    #expect(cohort.wins == 1)
    #expect(cohort.losses == 1)
    #expect(cohort.winRate == 0.5)
}

@Test func unresolvedEnteredTradeWithholdsPathStatisticsAndEqualTimesAreDeterministic() async throws {
    let resolved = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "a-loss", entryPrice: 1.10, expiryPrice: 1.09),
                validationCase(id: "b-win")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    let forward = StrategyValidationEngine.report(records: resolved, stage: .historicalReplay)
    let reversed = StrategyValidationEngine.report(
        records: Array(resolved.reversed()), stage: .historicalReplay)
    #expect(forward.overall.maximumUnitDrawdown == reversed.overall.maximumUnitDrawdown)
    #expect(forward.overall.maximumConsecutiveLosses == reversed.overall.maximumConsecutiveLosses)

    let base = validationCase(id: "missing-expiry")
    let entryOnly = StrategyValidationCase(
        id: base.id, stage: base.stage, instrumentID: base.instrumentID,
        engineAsset: base.engineAsset, venueID: base.venueID, marketKind: base.marketKind,
        signalTimestamp: base.signalTimestamp, engineSHA: base.engineSHA, input: base.input,
        maximumSignalQuoteAgeSeconds: base.maximumSignalQuoteAgeSeconds,
        observations: Array(base.observations.prefix(1)), payoutRatio: base.payoutRatio,
        provenance: base.provenance)
    let unresolved = try await StrategyValidationEngine.replay(
        cases: [entryOnly], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator)
    let incomplete = StrategyValidationEngine.report(
        records: resolved + unresolved, stage: .historicalReplay)
    #expect(incomplete.overall.maximumUnitDrawdown == nil)
    #expect(incomplete.overall.maximumConsecutiveLosses == nil)
}

@Test func duplicateVenueSettlementCannotCountUnderDifferentCaseIDs() async throws {
    let entry = validationSignalTime.addingTimeInterval(2)
    let execution = RecordedValidationExecution(
        enteredAt: entry, entryPrice: 1.10,
        expiryObservedAt: entry.addingTimeInterval(60), expiryPrice: 1.11,
        confirmedResolution: .win, venueEventID: "same-venue-event")
    let records = try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "live-a", stage: .liveObservation, recorded: execution),
                validationCase(id: "live-b", stage: .liveObservation, recorded: execution)],
        configuration: .sixtySecond, evaluator: highEvaluator)
    let report = StrategyValidationEngine.report(records: records, stage: .liveObservation)
    #expect(report.performanceEligible == 0)
    #expect(report.excludedDuplicateCases == 2)
}

@Test func historicalBuilderCreatesOnlyPastCompletedSnapshots() throws {
    let input = validationInput()
    let quote = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime.addingTimeInterval(-1), price: 1.101,
        bid: 1.1009, ask: 1.1011, source: "oanda-history", authority: .oandaReference)
    let future = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime.addingTimeInterval(3), price: 1.102,
        bid: 1.1019, ask: 1.1021, source: "oanda-history", authority: .oandaReference)
    let built = HistoricalValidationCaseBuilder.build(
        series: HistoricalValidationSeries(
            instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
            marketKind: .standard, source: "oanda-history", authority: .oandaReference,
            candles1m: input.candles1m, candles5m: input.candles5m,
            prices: [quote, future], evaluationTimes: [validationSignalTime],
            maximumSignalQuoteAgeSeconds: 5,
            payoutRatio: 0.88, provenance: "historical fixture"),
        minimumM1: 2, minimumM5: 2)
    let item = try #require(built.cases.first)
    #expect(built.rejections.isEmpty)
    #expect(item.input.quoteAsOfMs == quote.observedAt.timeIntervalSince1970 * 1_000)
    #expect(item.input.lastPrice == quote.price)
    #expect(item.observations.contains(future))
    #expect(item.input.candles1m.allSatisfy {
        $0.time + 60_000 <= validationSignalTime.timeIntervalSince1970 * 1_000 + 1
    })
}

@Test func historicalBuilderRejectsQuoteOlderThanSourceFreshnessContract() throws {
    let input = validationInput()
    let stale = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime.addingTimeInterval(-10), price: 1.101,
        bid: 1.1009, ask: 1.1011, source: "oanda-history", authority: .oandaReference)
    let built = HistoricalValidationCaseBuilder.build(series: .init(
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, source: "oanda-history", authority: .oandaReference,
        candles1m: input.candles1m, candles5m: input.candles5m,
        prices: [stale], evaluationTimes: [validationSignalTime],
        maximumSignalQuoteAgeSeconds: 5, provenance: "historical fixture"),
        minimumM1: 2, minimumM5: 2)

    #expect(built.cases.isEmpty)
    #expect(built.rejections.map(\.reason)
        == ["Historical signal quote exceeds source freshness contract"])
    #expect(stale.observedAt == validationSignalTime.addingTimeInterval(-10))
}

@Test func historicalBuilderRequiresSourceSpecificFreshnessContract() throws {
    let input = validationInput()
    let quote = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime, price: 1.101,
        bid: 1.1009, ask: 1.1011, source: "oanda-history", authority: .oandaReference)
    let built = HistoricalValidationCaseBuilder.build(series: .init(
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, source: "oanda-history", authority: .oandaReference,
        candles1m: input.candles1m, candles5m: input.candles5m,
        prices: [quote], evaluationTimes: [validationSignalTime],
        provenance: "historical fixture"), minimumM1: 2, minimumM5: 2)

    #expect(built.cases.isEmpty)
    #expect(built.rejections.map(\.reason)
        == ["Source-specific signal quote freshness contract unavailable"])
}

@Test func replayRejectsStaleHistoricalQuoteBeforeCallingStrategy() async throws {
    var input = validationInput()
    input.quoteAsOfMs = validationSignalTime.addingTimeInterval(-10).timeIntervalSince1970 * 1_000
    let item = validationCase(id: "stale-signal-quote", maximumSignalQuoteAgeSeconds: 5,
                              input: input)
    let records = try await StrategyValidationEngine.replay(
        cases: [item], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: { _ in throw HistoricalEvaluatorReached() })

    #expect(records.first?.rejectionReason
        == "Historical signal quote exceeds source freshness contract")
    #expect(records.first?.resolution == .unresolved)
}

@Test func replayRejectsFutureHistoricalSignalQuote() async throws {
    var input = validationInput()
    input.quoteAsOfMs = validationSignalTime.addingTimeInterval(1).timeIntervalSince1970 * 1_000
    let item = validationCase(id: "future-signal-quote", maximumSignalQuoteAgeSeconds: 5,
                              input: input)
    let records = try await StrategyValidationEngine.replay(
        cases: [item], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: { _ in throw HistoricalEvaluatorReached() })

    #expect(records.first?.rejectionReason == "Future quote leaked into the signal")
    #expect(records.first?.resolution == .unresolved)
}

@Test func legacyHistoricalCaseWithoutFreshnessContractDecodesButStaysUnresolved() async throws {
    let encoded = try JSONEncoder().encode(validationCase(id: "legacy-missing-freshness"))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "maximumSignalQuoteAgeSeconds")
    let legacy = try JSONDecoder().decode(
        StrategyValidationCase.self, from: JSONSerialization.data(withJSONObject: object))
    let records = try await StrategyValidationEngine.replay(
        cases: [legacy], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: { _ in throw HistoricalEvaluatorReached() })

    #expect(records.first?.resolution == .unresolved)
    #expect(records.first?.rejectionReason
        == "Source-specific signal quote freshness contract unavailable")
}

@Test func syntheticSignalInputRemainsSyntheticWithIndependentSettlementPrices() async throws {
    let input = validationInput()
    let signalQuote = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime, price: 1.101, bid: 1.1009, ask: 1.1011,
        source: "synthetic-history", authority: .syntheticFixture)
    let entry = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime.addingTimeInterval(3), price: 1.101,
        source: "independent", authority: .independentProvider)
    let expiry = ValidationPriceObservation(
        instrumentID: "oanda:EUR/USD", venueID: "OANDA",
        observedAt: validationSignalTime.addingTimeInterval(63), price: 1.102,
        source: "independent", authority: .independentProvider)
    let built = HistoricalValidationCaseBuilder.build(series: .init(
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, source: "synthetic-history", authority: .syntheticFixture,
        candles1m: input.candles1m, candles5m: input.candles5m,
        prices: [signalQuote, entry, expiry], evaluationTimes: [validationSignalTime],
        maximumSignalQuoteAgeSeconds: 5,
        payoutRatio: 0.8, provenance: "test history"), minimumM1: 2, minimumM5: 2)
    let item = try #require(built.cases.first)
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [item], configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    #expect(record.resolution == .win)
    #expect(record.signalPriceAuthority == .syntheticFixture)
    #expect(record.isSynthetic)
    #expect(StrategyValidationEngine.report(
        records: [record], stage: .historicalReplay).performanceEligible == 0)
}

@Test func replayPropagatesCancellation() async {
    let task = Task {
        try await StrategyValidationEngine.replay(
            cases: [validationCase()], configuration: .sixtySecond,
            evaluator: { _ in
                try await Task.sleep(for: .seconds(5))
                return try await highEvaluator(validationInput())
            })
    }
    task.cancel()
    var cancelled = false
    do { _ = try await task.value }
    catch is CancellationError { cancelled = true }
    catch { }
    #expect(cancelled)
}

@Test func pinnedHistoricalReplayIsDeterministic() async throws {
    var input = GoldenFixture.market()
    let lastOpen = try #require(input.candles5m.last?.time)
    let signalTime = Date(timeIntervalSince1970: lastOpen / 1_000 + 300)
    input.evaluatedAtMs = signalTime.timeIntervalSince1970 * 1_000
    input.quoteAsOfMs = input.evaluatedAtMs
    let entry = signalTime.addingTimeInterval(1)
    let item = StrategyValidationCase(
        id: "pinned", stage: .historicalReplay,
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, signalTimestamp: signalTime,
        engineSHA: EngineIdentity.pinnedSHA1, input: input,
        maximumSignalQuoteAgeSeconds: 5,
        observations: [
            ValidationPriceObservation(
                instrumentID: "oanda:EUR/USD", venueID: "OANDA", observedAt: entry,
                price: input.lastPrice, source: "fixture", authority: .syntheticFixture),
            ValidationPriceObservation(
                instrumentID: "oanda:EUR/USD", venueID: "OANDA",
                observedAt: entry.addingTimeInterval(60), price: input.lastPrice + 0.0001,
                source: "fixture", authority: .syntheticFixture)
        ], payoutRatio: 0.88, provenance: "synthetic deterministic fixture")
    let configuration = StrategyValidationConfiguration(entryDelaySeconds: 1)
    let first = try await StrategyValidationEngine.replay(cases: [item], configuration: configuration)
    let second = try await StrategyValidationEngine.replay(cases: [item], configuration: configuration)
    #expect(first == second)
    #expect(first.first?.engineSHA == EngineIdentity.pinnedSHA1)
}

@Test func strategyValidationRecordsUseExistingImmutableResearchStore() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("strategy-validation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "persist")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    let store = ResearchStore(root: root)
    let item = validationCase(id: "persist")
    try await store.record(item)
    try await store.record(record)
    try await store.record(record)
    let loaded = try await store.strategyValidationRecords()
    #expect(loaded == [record])
    #expect(loaded.first?.configuration
        == StrategyValidationConfiguration(entryDelaySeconds: 3))
    #expect(try await store.strategyValidationCases().count == 1)
}

@Test func researchStoreRejectsDecodableCaseWhoseContentDoesNotMatchFilename() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("strategy-validation-tamper-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let item = validationCase(id: "original")
    let store = ResearchStore(root: root)
    try await store.record(item)
    let digest = StrategyValidationEngine.digest(of: item)
    let url = root.appendingPathComponent("strategy-validation-cases")
        .appendingPathComponent(digest + ".json")
    var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    object["id"] = "modified-but-decodable"
    try JSONSerialization.data(withJSONObject: object).write(to: url)
    await #expect(throws: (any Error).self) { try await store.strategyValidationCases() }
}

@Test func researchStoreLinksRecordByCaseDigestWhenHumanCaseIDIsReused() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("strategy-validation-reused-id-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = validationCase(id: "same-human-id")
    let extended = StrategyValidationCase(
        id: original.id, stage: original.stage, instrumentID: original.instrumentID,
        engineAsset: original.engineAsset, venueID: original.venueID, marketKind: original.marketKind,
        signalTimestamp: original.signalTimestamp, engineSHA: original.engineSHA, input: original.input,
        observations: original.observations + [ValidationPriceObservation(
            instrumentID: original.instrumentID, venueID: original.venueID,
            observedAt: validationSignalTime.addingTimeInterval(180), price: 1.2,
            source: "fixture", authority: .independentProvider)],
        payoutRatio: original.payoutRatio, provenance: original.provenance)
    let configuration = StrategyValidationConfiguration(entryDelaySeconds: 3)
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [original], configuration: configuration, evaluator: highEvaluator).first)
    let store = ResearchStore(root: root)
    try await store.record(original)
    try await store.record(extended)
    try await store.record(record)
    #expect(try await store.strategyValidationCases().count == 2)
    #expect(try await store.strategyValidationRecords() == [record])
}

@Test func validationRecordDecodesArchivesWrittenBeforeTiePolicy() async throws {
    let record = try #require(try await StrategyValidationEngine.replay(
        cases: [validationCase(id: "legacy")],
        configuration: StrategyValidationConfiguration(entryDelaySeconds: 3),
        evaluator: highEvaluator).first)
    let encoded = try JSONEncoder().encode(record)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "tiePolicy")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(StrategyValidationRecord.self, from: legacy)
    #expect(decoded.tiePolicy == nil)
    let report = StrategyValidationEngine.report(records: [decoded], stage: .historicalReplay)
    #expect(report.performanceEligible == 1)
}

@Test func boundedAssistantDiagnosticsReportOmittedJournalNotes() {
    let context = AssistantContext(
        generatedAt: validationSignalTime, scans: [], confirmedEntries: [], gaps: [],
        notes: [JournalNoteContext(id: "n", pair: "EUR/USD", note: "review",
                                   createdAt: validationSignalTime)])
    let bounded = context.bounded(maxScans: 0, maxEntries: 0, maxGaps: 0, maxNotes: 0)
    #expect(context.selectionNotes(after: bounded).contains("notes 0/1"))
}

@Test func assistantValidationSummariesAreBoundedToOnePerStage() {
    let empty = StrategyValidationEngine.report(records: [], stage: .historicalReplay)
    let paper = StrategyValidationEngine.report(records: [], stage: .paperTrading)
    let summaries = [StrategyValidationSummary(empty), StrategyValidationSummary(empty),
                     StrategyValidationSummary(paper)]
    let context = AssistantContext(strategyValidation: summaries)
    #expect(context.strategyValidation?.count == 2)
    #expect(context.bounded(maxScans: 0, maxEntries: 0, maxGaps: 0, maxNotes: 0)
        .strategyValidation?.count == 2)
}
