import BlazerCore
import BlazerCrypto
import Foundation
import Testing
@testable import LightningDesk

private enum StubFailure: Error { case provider }

private struct FailingMarketTransport: MarketDataTransporting {
    func fetchFXScan(asset: String, session: OandaSession) async throws -> ScanEnvelope {
        throw StubFailure.provider
    }

    func fetchFXQuotes(assets: [String], session: OandaSession) async -> OandaQuoteBatch {
        OandaQuoteBatch(quotes: [], transport: .timeout)
    }

    func fetchFXCandles(asset: String, session: OandaSession, count: Int) async -> [Candle] { [] }
    func fetchCryptoBundle(asset: String) async throws -> CryptoCandleBatch? { throw StubFailure.provider }
    func fetchCryptoQuote(asset: String) async -> LiveQuote? { nil }
}

private actor ReorderedMarketTransport: MarketDataTransporting {
    private var continuations: [String: CheckedContinuation<ScanEnvelope, Error>] = [:]

    func fetchFXScan(asset: String, session: OandaSession) async throws -> ScanEnvelope {
        try await withCheckedThrowingContinuation { continuations[asset] = $0 }
    }

    func isWaiting(for asset: String) -> Bool { continuations[asset] != nil }
    func isWaiting(for assets: [String]) -> Bool { assets.allSatisfy { continuations[$0] != nil } }

    func finish(asset: String, price: Double) {
        let candle = Candle(time: 1_000, open: price, high: price, low: price, close: price)
        continuations.removeValue(forKey: asset)?.resume(returning: ScanEnvelope(
            signal: EngineSignal(
                asset: asset,
                cabinetSide: "WAIT",
                call: "WAIT",
                why: "test",
                price: price,
                asOfMs: 1_000,
                source: "test"
            ),
            error: nil,
            candles: [candle],
            source: "test",
            snapshotBars: [candle],
            bid: price - 0.0001,
            ask: price + 0.0001,
            spread: 0.0002,
            expirySeconds: 60,
            engineSHA: "test"
        ))
    }

    func fetchFXQuotes(assets: [String], session: OandaSession) async -> OandaQuoteBatch {
        OandaQuoteBatch(quotes: [], transport: .network)
    }

    func fetchFXCandles(asset: String, session: OandaSession, count: Int) async -> [Candle] { [] }
    func fetchCryptoBundle(asset: String) async throws -> CryptoCandleBatch? { nil }
    func fetchCryptoQuote(asset: String) async -> LiveQuote? { nil }
}

@Test func marketDataServiceMapsProviderFailuresWithoutFabricatingData() async {
    let service = LiveDeskMarketDataService(transport: FailingMarketTransport())
    let session = OandaSession(token: "test", accountId: "test")

    await #expect(throws: StubFailure.self) {
        _ = try await service.scan(market: .fx, asset: "EUR/USD", session: session)
    }
    let quotes = await service.quotes(market: .fx, assets: ["EUR/USD"], session: session)
    #expect(quotes.status == .timeout)
    #expect(quotes.quotes.isEmpty)
    #expect(await service.candles(market: .fx, asset: "EUR/USD", session: session, count: 80).isEmpty)
}

@Test func marketDataServiceKeepsOutOfOrderResponsesBoundToTheirAssets() async throws {
    let transport = ReorderedMarketTransport()
    let service = LiveDeskMarketDataService(transport: transport)
    let session = OandaSession(token: "test", accountId: "test")

    async let first = service.scan(market: .fx, asset: "EUR/USD", session: session)
    async let second = service.scan(market: .fx, asset: "GBP/USD", session: session)
    while await !transport.isWaiting(for: ["EUR/USD", "GBP/USD"]) {
        await Task.yield()
    }
    await transport.finish(asset: "GBP/USD", price: 1.25)
    await transport.finish(asset: "EUR/USD", price: 1.10)

    let results = try await [first, second]
    #expect(results[0].signal.asset == "EUR/USD")
    #expect(results[0].candles.last?.close == 1.10)
    #expect(results[1].signal.asset == "GBP/USD")
    #expect(results[1].candles.last?.close == 1.25)
}

@MainActor
@Test func candleCacheOwnsFreshnessAndDeduplicatesInFlightFetches() async {
    final class Clock { var now = Date(timeIntervalSince1970: 100) }
    let clock = Clock()
    let cache = CandleCache(ttl: 45, now: { clock.now })
    let key = CandleCache.Key(market: .fx, asset: "EUR/USD")
    let initial = [Candle(time: 1, open: 1, high: 1, low: 1, close: 1)]
    var fetchCount = 0

    let first = await cache.load(key) {
        fetchCount += 1
        return initial
    }
    let cached = await cache.load(key) {
        fetchCount += 1
        return []
    }
    #expect(first == initial)
    #expect(cached == initial)
    #expect(fetchCount == 1)
    #expect(cache.isFresh(key))

    clock.now = clock.now.addingTimeInterval(46)
    #expect(!cache.isFresh(key))
    _ = await cache.load(key) {
        fetchCount += 1
        return initial
    }
    #expect(fetchCount == 2)
}

@MainActor
@Test func candleCacheJoinsInFlightFetchesEvenWhenForced() async {
    let cache = CandleCache(ttl: 45)
    let key = CandleCache.Key(market: .fx, asset: "EUR/USD")
    let bars = [Candle(time: 1, open: 1, high: 1, low: 1, close: 1)]
    let gate = LifecycleGate()
    var fetchCount = 0

    let first = Task { @MainActor in
        await cache.load(key) {
            fetchCount += 1
            await gate.wait()
            return bars
        }
    }
    while await !gate.waiting { await Task.yield() }

    // A forced refresh must join the in-flight fetch instead of issuing a second one.
    let second = Task { @MainActor in
        await cache.load(key, force: true) {
            fetchCount += 1
            return []
        }
    }
    for _ in 0..<10 { await Task.yield() }
    #expect(fetchCount == 1)

    await gate.open()
    #expect(await first.value == bars)
    #expect(await second.value == bars)
    #expect(fetchCount == 1)
}

@MainActor
@Test func candleCacheDoesNotCacheEmptyFetches() async {
    let cache = CandleCache()
    let key = CandleCache.Key(market: .crypto, asset: "BTC/USDT")

    #expect(await cache.load(key) { [] }.isEmpty)
    #expect(cache.cached(key).isEmpty)
    #expect(!cache.isFresh(key))
}

private actor LifecycleGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false

    func wait() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor SuspendedMarketDataService: DeskMarketDataServing {
    let gate = LifecycleGate()

    func scan(market: DeskMarket, asset: String, session: OandaSession?) async throws -> MarketScanSnapshot {
        await gate.wait()
        let candle = Candle(time: 1_000, open: 100, high: 101, low: 99, close: 100)
        return MarketScanSnapshot(
            signal: EngineSignal(asset: asset, cabinetSide: "WAIT", call: "WAIT", why: "test", price: 100),
            candles: [candle],
            m5Candles: [],
            bid: 99,
            ask: 101,
            spread: 2,
            expirySeconds: 60,
            engineSHA: "test",
            policy: "test",
            source: "test",
            veto: nil
        )
    }

    func quotes(market: DeskMarket, assets: [String], session: OandaSession?) async -> MarketQuoteResult {
        MarketQuoteResult(quotes: [], status: .network)
    }

    func candles(market: DeskMarket, asset: String, session: OandaSession?, count: Int) async -> [Candle] { [] }
}

@MainActor
@Test func backgroundInvalidatesCancellationIgnoringScanAndForegroundDoesNotPublishIt() async {
    let service = SuspendedMarketDataService()
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-market-lifecycle-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root, marketData: service)
    model.marketMode = .crypto

    let scan = Task { @MainActor in await model.scanCrypto(asset: "BTC/USDT") }
    while await !service.gate.waiting { await Task.yield() }
    model.handleAppBackgrounded(now: Date(timeIntervalSince1970: 2_000))
    await service.gate.open()
    await scan.value

    #expect(!model.scanning)
    #expect(model.candles.isEmpty)
    #expect(model.frame == nil)

    model.handleAppForegrounded(now: Date(timeIntervalSince1970: 2_010))
    #expect(model.foregroundResumeCount == 1)
    #expect(model.frame == nil)
}
