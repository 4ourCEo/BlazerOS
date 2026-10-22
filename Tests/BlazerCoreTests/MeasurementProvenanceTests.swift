import Foundation
import Testing
import BlazerCore

private func featureSet(atr: Double) -> ScanFeatures {
    ScanFeatures(
        atr1m: atr, atr5m: atr, efficiency: 0, slopeATR: 0, spreadATR: 0,
        rangeATR: 0, bodyATR: 0, upperWickShare: 0, lowerWickShare: 0,
        twoSidedSweep: false, sweep: nil, structureBreak: nil, regime: "test"
    )
}

@Test func lowSignalIsNotExcludedFromResearchMeasurement() throws {
    let now = Date()
    let nowMs = now.timeIntervalSince1970 * 1000
    let input = StrategyEngine.MarketInput(
        asset: "EUR/USD",
        source: "test",
        candles1m: [],
        candles5m: [],
        lastPrice: 1.1,
        bid: 1.0999,
        ask: 1.1001,
        spread: 0.0002,
        expirySeconds: 60,
        quoteAsOfMs: nowMs,
        evaluatedAtMs: nowMs
    )
    let low = EngineSignal(
        asset: "EUR/USD", cabinetSide: "LOW", call: "PUT", why: "down",
        price: 1.1, entryPrice: 1.1, confidence: 76,
        asOfMs: nowMs, features: featureSet(atr: 0.0005)
    )
    let quote = LiveQuote(
        asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
        asOfMs: nowMs, source: "test"
    )

    let event = try ResearchEvent(
        input: input, signal: low, sourceKind: "synthetic",
        capturedAt: now, entryQuote: quote
    )
    #expect(event.entryVeto == nil)
    #expect(event.entryTime != nil)
    #expect(event.entryPrice == 1.1)
}

@Test func lowSignalGetsTheSameTelemetryTiersAsHigh() {
    let low = StalkingTelemetry.evaluate(
        asset: "EUR/USD", score: 80, side: "LOW", evidence: "Downside sweep", veto: nil
    )
    let high = StalkingTelemetry.evaluate(
        asset: "EUR/USD", score: 80, side: "HIGH", evidence: "Upside sweep", veto: nil
    )
    #expect(low.isActionable == high.isActionable)
    #expect(low.tier == high.tier)
}

@Test func syntheticResearchRootIsIsolatedFromTheDeskRoot() {
    let desk = ResearchStore.defaultRoot(synthetic: false)
    let synthetic = ResearchStore.defaultRoot(synthetic: true)
    #expect(desk != synthetic)
    #expect(desk.lastPathComponent == "oanda-proxy")
    #expect(synthetic.lastPathComponent == "synthetic")
    #expect(desk.deletingLastPathComponent() == synthetic.deletingLastPathComponent())
}

@Test func confirmedStatsExcludeReferenceAndSyntheticRows() {
    func row(_ outcome: String, _ label: String) -> LedgerRow {
        LedgerRow(
            timestamp: Date(), pair: "EUR/USD", hash: UUID().uuidString, score: 70,
            side: "HIGH", veto: false, drift: 0, outcome: outcome,
            outcomeEventID: UUID().uuidString, labelSource: label
        )
    }
    let rows = [
        row("HIT", "venue-confirmed"),
        row("MISS", "venue-confirmed"),
        row("HIT", "oanda-midpoint-proxy"),
        row("HIT", "synthetic"),
        row("MISS", "manual-unverified"),
    ]
    #expect(OutcomeStats.tally(rows) == OutcomeStats(hits: 3, misses: 2))
    #expect(OutcomeStats.confirmedTally(rows) == OutcomeStats(hits: 1, misses: 1))
}
