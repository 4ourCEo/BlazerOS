import Foundation
import Testing
@testable import BlazerCore

private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: - Ledger helpers

private func ledgerRow(
    outcome: String,
    payout: Double?,
    index: Int,
    prefix: String = "arm",
    label: String = "venue-confirmed"
) -> LedgerRow {
    LedgerRow(
        timestamp: baseDate.addingTimeInterval(Double(index) * 60),
        pair: "EUR/USD",
        hash: "\(index)",
        score: 80,
        side: "HIGH",
        veto: false,
        drift: 0,
        outcome: outcome,
        outcomeEventID: "\(prefix)-\(index)",
        payout: payout,
        labelSource: label
    )
}

private func confirmedBook(
    wins: Int,
    losses: Int,
    payout: Double?,
    prefix: String = "arm"
) -> [LedgerRow] {
    var rows: [LedgerRow] = []
    for index in 0..<wins {
        rows.append(ledgerRow(outcome: "HIT", payout: payout, index: index, prefix: prefix))
    }
    for index in 0..<losses {
        rows.append(ledgerRow(outcome: "MISS", payout: payout, index: wins + index, prefix: prefix))
    }
    return rows
}

// MARK: - Break-even

@Test func breakEvenMatchesCommonVenuePayouts() {
    #expect(abs(ExpectancyMath.breakEvenWinRate(payoutRatio: 0.80) - 0.555556) < 1e-5)
    #expect(abs(ExpectancyMath.breakEvenWinRate(payoutRatio: 0.88) - 0.531915) < 1e-5)
    #expect(abs(ExpectancyMath.breakEvenWinRate(payoutRatio: 0.90) - 0.526316) < 1e-5)
}

@Test func recordedPayoutReplacesTheAssumedRate() {
    let eighty = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 60, losses: 40, payout: 0.80)
    )
    #expect(eighty.payoutSource == "recorded")
    #expect(abs(eighty.payoutRatio - 0.80) < 1e-9)
    #expect(abs(eighty.expectancy - 0.08) < 1e-9)
    #expect(abs(eighty.breakEvenRate - 0.555556) < 1e-5)

    let eightyEight = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 60, losses: 40, payout: 0.88)
    )
    #expect(eightyEight.payoutSource == "recorded")
    #expect(abs(eightyEight.payoutRatio - 0.88) < 1e-9)
    #expect(abs(eightyEight.expectancy - 0.128) < 1e-9)

    // Same win rate, different venue terms: the lower payout is worth less.
    #expect(eightyEight.expectancy > eighty.expectancy)
    #expect(eightyEight.breakEvenRate < eighty.breakEvenRate)
}

@Test func mixedPayoutBookUsesEveryRecordedRate() {
    var rows = confirmedBook(wins: 60, losses: 40, payout: 0.80, prefix: "low")
    rows += confirmedBook(wins: 60, losses: 40, payout: 0.88, prefix: "high")

    let stats = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(stats.sampleSize == 200)
    #expect(stats.wins == 120)
    // Different rates, but every row still carries a recorded payout.
    #expect(stats.payoutSource == "recorded")
    #expect(abs(stats.payoutRatio - 0.84) < 1e-9)
    #expect(abs(stats.minimumPayoutRatio - 0.80) < 1e-9)
    #expect(abs(stats.expectancy - 0.104) < 1e-9)
    // Promotion is judged against the worst payout in the book, not the average.
    #expect(abs(stats.breakEvenRateAtMinimumPayout - 0.555556) < 1e-5)
}

@Test func partiallyLabelledBookIsMarkedMixed() {
    var rows = confirmedBook(wins: 60, losses: 40, payout: 0.80, prefix: "recorded")
    rows += confirmedBook(wins: 40, losses: 60, payout: nil, prefix: "assumed")

    let stats = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(stats.sampleSize == 200)
    #expect(stats.payoutSource == "mixed")
    // 100 recorded at 80%, 100 falling back to 88%.
    #expect(abs(stats.payoutRatio - 0.84) < 1e-9)
    #expect(abs(stats.minimumPayoutRatio - 0.80) < 1e-9)
}

@Test func unlabelledPayoutFallsBackToTheAssumedRate() {
    let rows = confirmedBook(wins: 60, losses: 40, payout: nil)
    let stats = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(stats.payoutSource == "assumed")
    #expect(abs(stats.payoutRatio - 0.88) < 1e-9)
    #expect(abs(stats.expectancy - 0.128) < 1e-9)
}

// MARK: - Promotion gating

@Test func promotionRequiresTheLowerBoundAboveBreakEven() {
    let strong = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 160, losses: 100, payout: 0.88)
    )
    #expect(strong.sampleSize == 260)
    #expect(!strong.meetsPromotionCriteria)
    #expect(!strong.isProvenEdge)

    // Win rate clears break-even, but the interval still straddles it.
    let borderline = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 140, losses: 120, payout: 0.88)
    )
    #expect(borderline.winRate > borderline.breakEvenRate)
    #expect(!borderline.meetsPromotionCriteria)

    // Sample size alone is not enough.
    let smallPerfect = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 100, losses: 0, payout: 0.88)
    )
    #expect(smallPerfect.winRate == 1.0)
    #expect(!smallPerfect.meetsPromotionCriteria)
}

@Test func highWinRateAtLowPayoutIsNotPromoted() {
    // 57.7% wins against a 55.6% break-even at 80% payout. Positive expectancy,
    // but the lower bound sits below break-even.
    let stats = LedgerStatsEngine.evaluate(
        pair: "EUR/USD", rows: confirmedBook(wins: 150, losses: 110, payout: 0.80)
    )
    #expect(stats.winRate > stats.breakEvenRate)
    #expect(stats.expectancy > 0)
    #expect(!stats.meetsPromotionCriteria)
    #expect(stats.statusBadge.contains("INSUFFICIENT EVIDENCE"))
}

// MARK: - Clustering

@Test func concurrentCorrelatedPairsCollapseIntoOneBlock() {
    let pairs = ["EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "USD/CAD", "XAU/USD"]
    let observations = pairs.enumerated().map { index, pair in
        ClusteredObservation(pair: pair, capturedAtMs: 1_000_000, won: index < 3)
    }
    let sample = EvidenceClustering.adjust(observations)
    #expect(sample.nominalSize == 6)
    #expect(sample.blocks == 1)
    #expect(sample.isClustered)
    #expect(sample.effectiveSize < Double(sample.nominalSize))
    #expect(sample.effectiveSize > 0)
}

@Test func separatedObservationsRemainIndependent() {
    let observations = (0..<6).map { index in
        ClusteredObservation(
            pair: "EUR/USD",
            capturedAtMs: 1_000_000 + Double(index) * EvidenceClustering.defaultBucketMs,
            won: index.isMultiple(of: 2)
        )
    }
    let sample = EvidenceClustering.adjust(observations)
    #expect(sample.blocks == 6)
    #expect(abs(sample.effectiveSize - 6) < 1e-9)
    #expect(!sample.isClustered)
}

@Test func differentCorrelationGroupsStaySeparateInTheSameMinute() {
    let observations = [
        ClusteredObservation(pair: "EUR/USD", capturedAtMs: 1_000_000, won: true),
        ClusteredObservation(pair: "BTC/USD", capturedAtMs: 1_000_000, won: false),
        ClusteredObservation(pair: "EUR/GBP", capturedAtMs: 1_000_000, won: true),
    ]
    let sample = EvidenceClustering.adjust(observations)
    #expect(sample.blocks == 3)
    #expect(EvidenceClustering.group(for: "BTC/USD") == .crypto)
    #expect(EvidenceClustering.group(for: "EUR/GBP") == .cross)
    #expect(EvidenceClustering.group(for: "XAU/USD") == .usd)
}

// MARK: - Research helpers

private func researchInput(asset: String = "EUR/USD") -> StrategyEngine.MarketInput {
    StrategyEngine.MarketInput(
        asset: asset, source: "test", candles1m: [], candles5m: [],
        lastPrice: 1.1, bid: 1.0999, ask: 1.1001, spread: 0.0002,
        expirySeconds: 60
    )
}

private func researchEvent(
    index: Int,
    capturedAt: Date,
    payout: Double = EntryQuality.assumedPayout,
    asset: String = "EUR/USD"
) throws -> ResearchEvent {
    let asOfMs = capturedAt.timeIntervalSince1970 * 1000
    let signal = EngineSignal(
        asset: asset,
        cabinetSide: index.isMultiple(of: 2) ? "HIGH" : "LOW",
        call: index.isMultiple(of: 2) ? "CALL" : "PUT",
        why: "test",
        price: 1.1,
        entryPrice: 1.1,
        confidence: 76,
        asOfMs: asOfMs,
        policy: ScanPolicy.baseline.rawValue,
        features: ScanFeatures(
            atr1m: 0.0005, atr5m: 0.0005, efficiency: 0, slopeATR: 0,
            spreadATR: 0, rangeATR: 0, bodyATR: 0, upperWickShare: 0,
            lowerWickShare: 0, twoSidedSweep: false, sweep: nil,
            structureBreak: nil, regime: "test"
        )
    )
    let quote = LiveQuote(
        asset: asset, bid: 1.0999, ask: 1.1001, mid: 1.1,
        asOfMs: asOfMs, source: "test"
    )
    return try ResearchEvent(
        input: researchInput(asset: asset),
        signal: signal,
        sourceKind: "synthetic",
        capturedAt: capturedAt,
        entryQuote: quote,
        assumedPayout: payout,
        engineSHA: EngineIdentity.pinnedSHA1
    )
}

private func researchOutcome(for event: ResearchEvent, win: Bool) -> ResearchOutcome {
    ResearchOutcome(
        eventID: event.id,
        horizon: 60,
        targetExpiry: event.capturedAt.addingTimeInterval(60),
        observedAt: event.capturedAt.addingTimeInterval(61),
        quoteTimeMs: event.capturedAt.addingTimeInterval(61).timeIntervalSince1970 * 1000,
        exitPrice: win ? 1.1005 : 1.0995,
        resolution: win ? .hit : .miss,
        reason: nil,
        labelSource: "synthetic"
    )
}

private func frozenExperiment(splitAt: Date?) -> ResearchExperiment {
    ResearchExperiment(
        name: "holdout test",
        policy: ScanPolicy.baseline.rawValue,
        engineSHA: EngineIdentity.pinnedSHA1,
        splitFraction: 0.7,
        splitAt: splitAt,
        payoutRatio: EntryQuality.assumedPayout,
        acceptanceCriteria: "break-even",
        rejectionCriteria: "below break-even"
    )
}

// MARK: - Frozen holdout

@Test func frozenHoldoutDoesNotMoveWhenTheArchiveGrows() throws {
    var events: [ResearchEvent] = []
    var outcomes: [ResearchOutcome] = []
    for index in 0..<10 {
        let captured = baseDate.addingTimeInterval(Double(index) * 60)
        let event = try researchEvent(index: index, capturedAt: captured)
        events.append(event)
        outcomes.append(researchOutcome(for: event, win: index < 7))
    }

    let experiment = frozenExperiment(splitAt: events[7].capturedAt)
    let first = ResearchEvaluator.evaluate(experiment: experiment, events: events, outcomes: outcomes)
    #expect(first.isHoldoutFrozen)
    #expect(first.train.candidates == 6)
    #expect(first.test.candidates == 3)

    // Five later events arrive. A frozen boundary must not absorb them into training.
    for index in 10..<15 {
        let captured = baseDate.addingTimeInterval(Double(index) * 60)
        let event = try researchEvent(index: index, capturedAt: captured)
        events.append(event)
        outcomes.append(researchOutcome(for: event, win: true))
    }

    let second = ResearchEvaluator.evaluate(experiment: experiment, events: events, outcomes: outcomes)
    #expect(second.train.candidates == 6)
    #expect(second.test.candidates == 8)
}

@Test func legacyExperimentRecomputesAndSaysSo() throws {
    var events: [ResearchEvent] = []
    var outcomes: [ResearchOutcome] = []
    for index in 0..<10 {
        let captured = baseDate.addingTimeInterval(Double(index) * 60)
        let event = try researchEvent(index: index, capturedAt: captured)
        events.append(event)
        outcomes.append(researchOutcome(for: event, win: index < 7))
    }
    let legacy = frozenExperiment(splitAt: nil)
    let first = ResearchEvaluator.evaluate(experiment: legacy, events: events, outcomes: outcomes)
    #expect(!first.isHoldoutFrozen)
    #expect(first.train.candidates == 6)

    for index in 10..<15 {
        let captured = baseDate.addingTimeInterval(Double(index) * 60)
        let event = try researchEvent(index: index, capturedAt: captured)
        events.append(event)
        outcomes.append(researchOutcome(for: event, win: true))
    }
    let second = ResearchEvaluator.evaluate(experiment: legacy, events: events, outcomes: outcomes)
    #expect(!second.isHoldoutFrozen)
    // The boundary moved: the training cohort now contains events that were held out.
    #expect(second.train.candidates == 9)
    #expect(second.train.candidates != first.train.candidates)
}

// MARK: - Acceptance threshold

private func holdoutReport(
    wins: Int,
    losses: Int,
    payout: Double
) throws -> ResearchExperimentReport {
    let total = wins + losses
    var events: [ResearchEvent] = []
    var outcomes: [ResearchOutcome] = []
    for index in 0..<total {
        let captured = baseDate.addingTimeInterval(Double(index) * 60)
        let event = try researchEvent(index: index, capturedAt: captured, payout: payout)
        events.append(event)
        outcomes.append(researchOutcome(for: event, win: index < wins))
    }
    let experiment = frozenExperiment(splitAt: baseDate.addingTimeInterval(-1))
    return ResearchEvaluator.evaluate(experiment: experiment, events: events, outcomes: outcomes)
}

@Test func acceptanceUsesBreakEvenNotFiftyPercent() throws {
    // 155/260 = 59.6% wins. At 80% payout break-even is 55.6%, but the lower bound is
    // 53.6%, so the identical signal record must not be accepted.
    let eighty = try holdoutReport(wins: 155, losses: 105, payout: 0.80)
    #expect(eighty.test.resolved == 260)
    #expect(eighty.test.winRate! > (eighty.test.breakEvenWinRate ?? 1))
    #expect(!eighty.acceptanceSatisfied)

    // Same outcomes at 88% payout: break-even falls to 53.2% and the lower bound clears it.
    let eightyEight = try holdoutReport(wins: 155, losses: 105, payout: 0.88)
    #expect(eightyEight.test.resolved == 260)
    #expect(!eightyEight.acceptanceSatisfied)
    #expect((eightyEight.breakEvenWinRate ?? 1) < (eighty.breakEvenWinRate ?? 0))
}

@Test func acceptanceRejectsSmallSyntheticCohorts() throws {
    // A perfect but tiny held-out cohort is descriptive only.
    let tiny = try holdoutReport(wins: 29, losses: 0, payout: 0.88)
    #expect(tiny.test.resolved == 29)
    #expect(!tiny.acceptanceSatisfied)
}
