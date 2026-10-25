import Foundation
import Testing
@testable import BlazerCore

private let otcInstrument = OTCInstrumentCatalog.pocketOptionEURUSDOTC
private let testSource = ShadowDataSourceIdentity(
    providerID: "test.otc.v1", displayName: "Test OTC", venueID: "otc",
    directBrokerConnection: false)
private let evaluationTime = Date(timeIntervalSince1970: 1_800_000_000)

private func makeCandle(
    start: Date,
    open: Double,
    close: Double,
    wick: Double,
    identity: ShadowMarketIdentity = otcInstrument.identity,
    complete: Bool = true
) -> ShadowCandle {
    ShadowCandle(
        identity: identity,
        intervalSeconds: 60,
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: start.timeIntervalSince1970),
        open: open,
        high: max(open, close) + wick,
        low: min(open, close) - wick,
        close: close,
        complete: complete)
}

/// Deterministic synthetic series: steady trend, compressed tail, final breakout. This is a test
/// fixture for the evaluator only; it never becomes outcome evidence.
private func trendingCandles(direction: Double, count: Int = 30, endingAt end: Date) -> [ShadowCandle] {
    var bars: [ShadowCandle] = []
    var price = 1.1000
    let firstStart = end.addingTimeInterval(-Double(count) * 60)
    for index in 0..<count {
        let start = firstStart.addingTimeInterval(Double(index) * 60)
        let open = price
        let compressed = index >= count - 5
        let close = open + direction * (compressed ? 0.00005 : 0.0002)
        let wick = compressed ? 0.00002 : 0.00015
        bars.append(makeCandle(start: start, open: open, close: close, wick: wick))
        price = close
    }
    if count >= 6 {
        let lastStart = firstStart.addingTimeInterval(Double(count - 1) * 60)
        let open = bars[count - 2].close
        let close = open + direction * 0.0004
        bars[count - 1] = makeCandle(start: lastStart, open: open, close: close, wick: 0.00003)
    }
    return bars
}

private func flatCandles(count: Int = 30, endingAt end: Date) -> [ShadowCandle] {
    let firstStart = end.addingTimeInterval(-Double(count) * 60)
    return (0..<count).map { index in
        makeCandle(
            start: firstStart.addingTimeInterval(Double(index) * 60),
            open: 1.1000, close: 1.1000, wick: 0.0001)
    }
}

private func makeInput(
    candles: [ShadowCandle],
    evaluatedAt: Date = evaluationTime,
    quotePrice: Double? = nil,
    quoteTimestamp: Date? = nil,
    connection: ShadowConnectionState = .live,
    marketOpen: Bool = true,
    instrument: OTCInstrumentIdentity = otcInstrument,
    payout: Double? = 82
) -> OTCResearchInput {
    let price = quotePrice ?? candles.last?.close ?? 1.1
    return OTCResearchInput(
        instrument: instrument,
        source: testSource,
        snapshotID: "snapshot-\(Int(evaluatedAt.timeIntervalSince1970))-\(candles.count)",
        quote: ShadowQuote(price: price, bid: price - 0.0001, ask: price + 0.0001),
        quoteTimestamp: quoteTimestamp ?? evaluatedAt,
        receivedAt: quoteTimestamp ?? evaluatedAt,
        candles: candles,
        payoutPercent: payout,
        marketOpen: marketOpen,
        connectionState: connection,
        verification: .syntheticTestFixture,
        provenance: "Synthetic deterministic engine fixture",
        evaluatedAt: evaluatedAt)
}

@Test func otcInstrumentsRemainDistinctAndAreNeverAliased() {
    let oanda = OTCInstrumentCatalog.oandaEURUSD
    let standard = OTCInstrumentCatalog.pocketOptionEURUSD
    let otc = OTCInstrumentCatalog.pocketOptionEURUSDOTC

    #expect(oanda.instrumentID != standard.instrumentID)
    #expect(standard.instrumentID != otc.instrumentID)
    #expect(oanda.identity != standard.identity)
    #expect(standard.identity != otc.identity)
    #expect(oanda.identity.displaySymbol == standard.identity.displaySymbol)
    #expect(!oanda.isOTC && !standard.isOTC && otc.isOTC)
    #expect(otc.isResearchOnly && !otc.mayAuthorizeEntry)
    #expect(otc.identity.venueSymbol == "EURUSD_otc")
    #expect(otc.identity.session == .weekendSession)
    #expect(standard.identity.session == .regularSession)
    #expect(OTCInstrumentCatalog.exact(venue: "Pocket Option", venueSymbol: "EURUSD_otc") == otc)
    #expect(OTCInstrumentCatalog.exact(venue: "Pocket Option", venueSymbol: "EURUSD") == standard)
    #expect(OTCInstrumentCatalog.exact(venue: "Pocket Option", venueSymbol: "eurusd_otc") == nil)
    #expect(OTCInstrumentCatalog.exact(instrumentID: standard.instrumentID) == standard)
    #expect(otc.isValid && standard.isValid && oanda.isValid)
}

@Test func providerCatalogueExpandsOnlyVerifiedOTCRows() {
    func availability(_ symbol: String, _ name: String, kind: ShadowMarketKind,
                      venue: String = "Pocket Option") -> ShadowInstrumentAvailability {
        ShadowInstrumentAvailability(
            identity: ShadowMarketIdentity(
                marketKind: kind, venue: venue, venueSymbol: symbol,
                displaySymbol: name,
                session: kind == .otc ? .weekendSession : .regularSession,
                settlementBasis: .venueDisplayed),
            isOpen: true, payoutPercent: 88)
    }
    let rows = [
        availability("EURUSD_otc", "EUR/USD OTC", kind: .otc),
        availability("GBPUSD_otc", "GBP/USD OTC", kind: .otc),
        availability("EURUSD", "EUR/USD", kind: .standard),
        availability("USDJPY_otc", "USD/JPY OTC", kind: .otc),
        availability("AUDUSD_otc", "AUD/USD OTC", kind: .standard),
        availability("EURUSD_otc", "EUR/USD OTC", kind: .otc, venue: "OtherVenue"),
    ]
    let watchlist = OTCInstrumentCatalog.otcWatchlist(from: rows)
    #expect(watchlist.map(\.venueSymbol) == ["EURUSD_otc", "GBPUSD_otc", "USDJPY_otc"])
    #expect(Set(watchlist.map(\.instrumentID)).count == watchlist.count)
    #expect(watchlist.allSatisfy { $0.isResearchOnly && !$0.mayAuthorizeEntry })
    #expect(OTCInstrumentCatalog.otcIdentity(from: rows[2]) == nil)
    #expect(OTCInstrumentCatalog.otcIdentity(from: rows[4]) == nil)
}

@Test func otcChallengerProducesDeterministicHighAndLow() {
    let up = makeInput(candles: trendingCandles(direction: 1, endingAt: evaluationTime))
    let upSignal = OTCResearchEvaluator.evaluate(up)
    #expect(upSignal.decision == .high)
    #expect(upSignal.direction == "HIGH")
    #expect(upSignal.score >= 60)
    #expect(upSignal.vetoes.isEmpty)
    #expect(upSignal.horizonSeconds == 60)
    #expect(upSignal.instrument == otcInstrument)
    #expect(upSignal.source == testSource)
    #expect(upSignal.sourceSnapshotID == up.snapshotID)
    #expect(upSignal.engineVersion == "otc-research-engine-v1")
    #expect(upSignal.strategyVersion == "otc-momentum-structure-v1")
    #expect(upSignal.evaluatedAt == evaluationTime)
    #expect(upSignal.freshness == .fresh)
    #expect(upSignal.feedQuality == .live)
    #expect(upSignal.payoutPercent == 82)
    #expect(upSignal.researchOnly)
    #expect(!upSignal.mayAuthorizeEntry)
    #expect(!upSignal.scoreIsCalibratedWinProbability)
    #expect(upSignal.isActionableResearch)
    #expect(OTCResearchEvaluator.evaluate(up) == upSignal)

    let down = makeInput(candles: trendingCandles(direction: -1, endingAt: evaluationTime))
    let downSignal = OTCResearchEvaluator.evaluate(down)
    #expect(downSignal.decision == .low)
    #expect(downSignal.direction == "LOW")
    #expect(downSignal.score >= 60)
    #expect(downSignal.isActionableResearch)
}

@Test func otcChallengerWaitsWhenThereIsNoConfluence() {
    let signal = OTCResearchEvaluator.evaluate(
        makeInput(candles: flatCandles(endingAt: evaluationTime)))
    #expect(signal.decision == .wait)
    #expect(signal.direction == nil)
    #expect(signal.vetoes.contains(.insufficientConfluence))
    #expect(!signal.isActionableResearch)
}

@Test func otcChallengerRefusesStaleAndIncompleteData() {
    let candles = trendingCandles(direction: 1, endingAt: evaluationTime)

    let stale = makeInput(
        candles: candles,
        quoteTimestamp: evaluationTime.addingTimeInterval(-6))
    let staleSignal = OTCResearchEvaluator.evaluate(stale)
    #expect(staleSignal.decision == .wait)
    #expect(staleSignal.vetoes.contains(.staleQuote))

    var incomplete = candles
    incomplete[incomplete.count - 1] = makeCandle(
        start: evaluationTime.addingTimeInterval(-60),
        open: incomplete[incomplete.count - 1].open,
        close: incomplete[incomplete.count - 1].close,
        wick: 0.00003, complete: false)
    #expect(OTCResearchEvaluator.evaluate(
        makeInput(candles: incomplete)).vetoes.contains(.incompleteCandles))

    var misaligned = candles
    misaligned.remove(at: 10)
    #expect(OTCResearchEvaluator.evaluate(
        makeInput(candles: misaligned)).vetoes.contains(.misalignedCandles))

    let future = makeInput(
        candles: trendingCandles(direction: 1, endingAt: evaluationTime.addingTimeInterval(60)))
    let futureSignal = OTCResearchEvaluator.evaluate(future)
    #expect(futureSignal.decision == .wait)
    #expect(futureSignal.vetoes.contains(.futureCandles))

    let short = makeInput(candles: trendingCandles(direction: 1, count: 10, endingAt: evaluationTime))
    #expect(OTCResearchEvaluator.evaluate(short).vetoes.contains(.insufficientHistory))

    let old = makeInput(
        candles: trendingCandles(direction: 1, endingAt: evaluationTime.addingTimeInterval(-120)))
    let oldSignal = OTCResearchEvaluator.evaluate(old)
    #expect(oldSignal.decision == .wait)
    #expect(oldSignal.vetoes.contains(.staleCandles))
}

@Test func otcChallengerRefusesBadEnvelopeFeedAndWrongInstrument() {
    let candles = trendingCandles(direction: 1, endingAt: evaluationTime)
    let price = candles.last!.close

    let envelope = makeInput(candles: candles, quotePrice: price + 0.01)
    #expect(OTCResearchEvaluator.evaluate(envelope).vetoes.contains(.priceEnvelopeViolation))

    let degraded = makeInput(candles: candles, connection: .degraded)
    let degradedSignal = OTCResearchEvaluator.evaluate(degraded)
    #expect(degradedSignal.decision == .wait)
    #expect(degradedSignal.vetoes.contains(.feedNotLive))

    let closed = makeInput(candles: candles, marketOpen: false)
    #expect(OTCResearchEvaluator.evaluate(closed).vetoes.contains(.sessionClosed))

    let wrong = makeInput(
        candles: trendingCandles(direction: 1, endingAt: evaluationTime),
        instrument: OTCInstrumentCatalog.oandaEURUSD)
    let wrongSignal = OTCResearchEvaluator.evaluate(wrong)
    #expect(wrongSignal.decision == .wait)
    #expect(wrongSignal.vetoes == [.wrongInstrument])
    #expect(wrongSignal.score == 0)
}

@Test func otcChallengerRejectsFutureQuotesAndInvalidPayout() {
    let candles = trendingCandles(direction: 1, endingAt: evaluationTime)
    let futureQuote = makeInput(
        candles: candles,
        quoteTimestamp: evaluationTime.addingTimeInterval(30))
    #expect(OTCResearchEvaluator.evaluate(futureQuote).vetoes.contains(.futureQuote))

    let badPayout = makeInput(candles: candles, payout: 101)
    #expect(OTCResearchEvaluator.evaluate(badPayout).vetoes.contains(.invalidQuote))
}
