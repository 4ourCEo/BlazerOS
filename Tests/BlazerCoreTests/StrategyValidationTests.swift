import Foundation
import Testing
@testable import BlazerCore

private let validationSignalTime = Date(timeIntervalSince1970: 2_000_000_000)

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
    recorded: RecordedValidationExecution? = nil,
    input: StrategyEngine.MarketInput? = nil,
    observationVenue: String = "OANDA"
) -> StrategyValidationCase {
    let entry = validationSignalTime.addingTimeInterval(entryDelay)
    return StrategyValidationCase(
        id: id, stage: stage,
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, signalTimestamp: validationSignalTime,
        engineSHA: EngineIdentity.pinnedSHA1, input: input ?? validationInput(),
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
    try await store.record(record)
    try await store.record(record)
    let loaded = try await store.strategyValidationRecords()
    #expect(loaded == [record])
}

@Test func boundedAssistantDiagnosticsReportOmittedJournalNotes() {
    let context = AssistantContext(
        generatedAt: validationSignalTime, scans: [], confirmedEntries: [], gaps: [],
        notes: [JournalNoteContext(id: "n", pair: "EUR/USD", note: "review",
                                   createdAt: validationSignalTime)])
    let bounded = context.bounded(maxScans: 0, maxEntries: 0, maxGaps: 0, maxNotes: 0)
    #expect(context.selectionNotes(after: bounded).contains("notes 0/1"))
}
