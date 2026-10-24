import BlazerCore
import Foundation
import Testing
@testable import LightningDesk

private let deskNow = Date(timeIntervalSince1970: 1_800_000_000)

private func deskCandles(
    identity: ShadowMarketIdentity,
    base: Double,
    endingAt: Date,
    count: Int = 30
) -> [ShadowCandle] {
    var bars: [ShadowCandle] = []
    var price = base
    let firstStart = endingAt.addingTimeInterval(-Double(count) * 60)
    for index in 0..<count {
        let start = firstStart.addingTimeInterval(Double(index) * 60)
        let open = price
        let compressed = index >= count - 5
        let close = open + (compressed ? 0.00005 : 0.0002)
        let wick = compressed ? 0.00002 : 0.00015
        bars.append(ShadowCandle(
            identity: identity, intervalSeconds: 60,
            providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: start.timeIntervalSince1970),
            open: open, high: max(open, close) + wick,
            low: min(open, close) - wick, close: close, complete: true))
        price = close
    }
    let lastStart = endingAt.addingTimeInterval(-60)
    let open = bars[count - 2].close
    let close = open + 0.0004
    bars[count - 1] = ShadowCandle(
        identity: identity, intervalSeconds: 60,
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: lastStart.timeIntervalSince1970),
        open: open, high: max(open, close) + 0.00003,
        low: min(open, close) - 0.00003, close: close, complete: true)
    return bars
}

private struct FakeOTCProvider: ShadowMarketObservationProvider {
    let sourceIdentity = ShadowDataSourceIdentity(
        providerID: "test.otc.v1", displayName: "Test OTC", venueID: "otc",
        directBrokerConnection: false)
    let availabilities: [ShadowInstrumentAvailability]
    let series: [String: [ShadowCandle]]
    let failing: Bool

    init(availabilities: [ShadowInstrumentAvailability],
         series: [String: [ShadowCandle]], failing: Bool = false) {
        self.availabilities = availabilities
        self.series = series
        self.failing = failing
    }

    func instruments() async throws -> [ShadowInstrumentAvailability] {
        if failing { throw ShadowMarketDataError.disabled }
        return availabilities
    }

    func candles(for identity: ShadowMarketIdentity, intervalSeconds: Int,
                 limit: Int) async throws -> [ShadowCandle] {
        if failing { throw ShadowMarketDataError.disabled }
        return Array((series[identity.venueSymbol] ?? []).suffix(limit))
    }

    func updates(for identities: [ShadowMarketIdentity]) async throws
        -> AsyncThrowingStream<ShadowProviderUpdate, any Error> {
        if failing { throw ShadowMarketDataError.disabled }
        guard let identity = identities.first,
              let candles = series[identity.venueSymbol],
              let last = candles.last else {
            throw ShadowMarketDataError.invalidPoint
        }
        let observation = ShadowMarketObservation(
            source: sourceIdentity,
            identity: identity,
            quote: ShadowQuote(price: last.close, bid: last.close - 0.0001,
                               ask: last.close + 0.0001),
            providerTimestamp: ShadowProviderTimestamp(
                rawUnixSeconds: deskNow.timeIntervalSince1970),
            receivedAt: deskNow,
            payoutPercent: 88,
            marketOpen: true,
            connectionState: .live,
            verification: .syntheticTestFixture,
            provenance: "Synthetic deterministic desk integration fixture")
        return AsyncThrowingStream { continuation in
            continuation.yield(.connection(.live, reason: nil))
            continuation.yield(.observation(observation))
            continuation.finish()
        }
    }
}

@MainActor
private func makeDeskModel(provider: FakeOTCProvider) -> LightningDeskModel {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("otc-desk-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    model.otcCredentialVault = InMemoryKeychainVault()
    model.saveOTChartsAPIKey("otc_test_key")
    model.otcSignalProviderFactory = { _ in provider }
    model.otcSignalClock = { deskNow }
    return model
}

private func availability(
    symbol: String, name: String, payout: Double = 88
) -> ShadowInstrumentAvailability {
    ShadowInstrumentAvailability(
        identity: ShadowMarketIdentity(
            marketKind: .otc, venue: "Pocket Option", venueSymbol: symbol,
            displaySymbol: name, session: .weekendSession,
            settlementBasis: .venueDisplayed),
        isOpen: true, payoutPercent: payout)
}

@MainActor
@Test func otcModeProducesResearchSignalWithoutExecutionState() async {
    let eur = availability(symbol: "EURUSD_otc", name: "EUR/USD OTC")
    let provider = FakeOTCProvider(
        availabilities: [eur],
        series: ["EURUSD_otc": deskCandles(
            identity: eur.identity, base: 1.1000, endingAt: deskNow)])
    let model = makeDeskModel(provider: provider)

    model.marketMode = .otc
    await model.scan()

    let signal = model.otcSignal
    #expect(signal?.decision == .high)
    #expect(signal?.instrument == OTCInstrumentCatalog.pocketOptionEURUSDOTC)
    #expect(signal?.researchOnly == true)
    #expect(signal?.mayAuthorizeEntry == false)
    #expect(model.frame == nil)
    #expect(model.activeTrade == nil)
    #expect(model.candles.count == 30)
    #expect(model.pairs == ["EUR/USD OTC"])
    #expect(model.side(for: model.pair) == "HIGH")
    #expect(model.score(for: model.pair) == signal?.score)
    #expect(model.currentPrice == signal?.quotePrice)
    #expect(model.otcLastPayoutPercent == 88)
    #expect(model.otcSignalHistory.count == 1)
    #expect(model.otcSignalConnectionState == .live)

    await model.lockInTrade()
    #expect(model.entryIssue == "OTC research signals cannot authorize entries")
    #expect(model.activeTrade == nil)
    #expect(model.frame == nil)

    await model.refreshOTCReplayReport()
    #expect(model.otcReplayReport?.accepted == 1)
    #expect(model.otcReplayReport?.containsSyntheticData == true)
    #expect(model.otcReplayReport?.promotionEligible == false)
}

@MainActor
@Test func otcDeskDropsTheFormingCandleBeforeEvaluation() async {
    let eur = availability(symbol: "EURUSD_otc", name: "EUR/USD OTC")
    let closed = deskCandles(identity: eur.identity, base: 1.1000, endingAt: deskNow)
    let last = closed.last!
    let forming = ShadowCandle(
        identity: eur.identity, intervalSeconds: 60,
        providerTimestamp: ShadowProviderTimestamp(
            rawUnixSeconds: deskNow.timeIntervalSince1970),
        open: last.close, high: last.close + 0.00002,
        low: last.close - 0.00002, close: last.close, complete: false)
    let provider = FakeOTCProvider(
        availabilities: [eur],
        series: ["EURUSD_otc": closed + [forming]])
    let model = makeDeskModel(provider: provider)

    model.marketMode = .otc
    await model.scan()

    #expect(model.candles.count == 30)
    #expect(model.otcSignal?.decision == .high)
    #expect(model.frame == nil)
    #expect(model.activeTrade == nil)
}

@MainActor
@Test func otcModeNeverFabricatesASignalWhenTheProviderFails() async {
    let provider = FakeOTCProvider(availabilities: [], series: [:], failing: true)
    let model = makeDeskModel(provider: provider)

    model.marketMode = .otc
    await model.scan()

    #expect(model.otcSignal == nil)
    #expect(model.otcSignalIssue != nil)
    #expect(model.frame == nil)
    #expect(model.activeTrade == nil)
    #expect(model.candles.isEmpty)
    #expect(model.otcSignalConnectionState == .degraded)
}

@MainActor
@Test func otcWatchlistExpandsAndSwitchesInstrumentsWithoutAliasing() async {
    let eur = availability(symbol: "EURUSD_otc", name: "EUR/USD OTC")
    let gbp = availability(symbol: "GBPUSD_otc", name: "GBP/USD OTC", payout: 79)
    let provider = FakeOTCProvider(
        availabilities: [eur, gbp],
        series: [
            "EURUSD_otc": deskCandles(
                identity: eur.identity, base: 1.1000, endingAt: deskNow),
            "GBPUSD_otc": deskCandles(
                identity: gbp.identity, base: 1.2500, endingAt: deskNow),
        ])
    let model = makeDeskModel(provider: provider)
    model.marketMode = .otc
    await model.scan()

    #expect(model.otcAvailableInstruments.map(\.venueSymbol) == ["EURUSD_otc", "GBPUSD_otc"])
    #expect(model.otcSelectedInstrumentID == "pocketoption:EURUSD_otc")

    await model.selectOTCInstrument("pocketoption:GBPUSD_otc")
    #expect(model.otcSelectedInstrumentID == "pocketoption:GBPUSD_otc")
    #expect(model.otcSignal?.instrument.venueSymbol == "GBPUSD_otc")
    #expect(model.pair == "GBP/USD OTC")
    #expect(model.otcLastPayoutPercent == 79)
    #expect(model.frame == nil)
    #expect(model.activeTrade == nil)
}

@Test func entryGateRejectsResearchOnlyContextUnconditionally() {
    let context = DeskEntryGate.Context(
        commit: nil, frame: nil, signal: nil, quote: nil,
        lastFreshPollAt: nil, activeTrade: nil, awaitingOutcome: false,
        settlementInFlight: false, scanning: false, historical: false,
        armedAt: nil, armID: nil, researchOnly: true)
    #expect(DeskEntryGate.veto(context) == .researchOnly)
}
