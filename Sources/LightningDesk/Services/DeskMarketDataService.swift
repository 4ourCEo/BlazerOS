import BlazerCore
import BlazerCrypto
import Foundation

/// Provider-neutral transport outcomes consumed by the desk. Concrete brokers map their
/// native errors here so future OTC adapters do not leak networking details into the view model.
enum MarketTransportStatus: Sendable, Equatable {
    case ok
    case missingCredentials
    case unauthorized
    case rateLimited
    case timeout
    case network

    init(_ transport: OandaTransport) {
        switch transport {
        case .ok: self = .ok
        case .missingToken: self = .missingCredentials
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .timeout: self = .timeout
        case .network: self = .network
        }
    }

    var oandaTransport: OandaTransport {
        switch self {
        case .ok: .ok
        case .missingCredentials: .missingToken
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .timeout: .timeout
        case .network: .network
        }
    }
}

struct MarketQuoteResult: Sendable, Equatable {
    let quotes: [LiveQuote]
    let status: MarketTransportStatus
}

/// Normalized, immutable input returned to scan orchestration. It contains everything needed
/// to freeze a commit without exposing OANDA/Binance response models to the facade.
struct MarketScanSnapshot: Sendable {
    let signal: EngineSignal
    let candles: [Candle]
    let m5Candles: [Candle]
    let bid: Double?
    let ask: Double?
    let spread: Double?
    let expirySeconds: Int
    let engineSHA: String
    let policy: String
    let source: String
    let veto: String?
}

/// Raw network seam. Tests can substitute cancellation-ignoring, failing, or reordered
/// transports without teaching `LightningDeskModel` about a broker SDK.
protocol MarketDataTransporting: Sendable {
    func fetchFXScan(asset: String, session: OandaSession) async throws -> ScanEnvelope
    func fetchFXQuotes(assets: [String], session: OandaSession) async -> OandaQuoteBatch
    func fetchFXCandles(asset: String, session: OandaSession, count: Int) async -> [Candle]
    func fetchCryptoBundle(asset: String) async throws -> CryptoCandleBatch?
    func fetchCryptoQuote(asset: String) async -> LiveQuote?
}

struct LiveMarketDataTransport: MarketDataTransporting {
    func fetchFXScan(asset: String, session: OandaSession) async throws -> ScanEnvelope {
        try await ScanKernel.fetch(asset: asset, session: session)
    }

    func fetchFXQuotes(assets: [String], session: OandaSession) async -> OandaQuoteBatch {
        await OandaClient.fetchQuoteBatch(assets: assets, session: session)
    }

    func fetchFXCandles(asset: String, session: OandaSession, count: Int) async -> [Candle] {
        await OandaClient.fetchCandles(
            asset: asset,
            session: session,
            granularity: "M1",
            count: count
        )
    }

    func fetchCryptoBundle(asset: String) async throws -> CryptoCandleBatch? {
        try await BinanceClient.fetchCryptoBundle(asset: asset)
    }

    func fetchCryptoQuote(asset: String) async -> LiveQuote? {
        await BinanceClient.fetchQuote(asset: asset)
    }
}

protocol DeskMarketDataServing: Sendable {
    func scan(market: DeskMarket, asset: String, session: OandaSession?) async throws -> MarketScanSnapshot
    func quotes(market: DeskMarket, assets: [String], session: OandaSession?) async -> MarketQuoteResult
    func candles(market: DeskMarket, asset: String, session: OandaSession?, count: Int) async -> [Candle]
}

enum DeskMarketDataError: LocalizedError, Sendable {
    case missingSession
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingSession: "OANDA token missing"
        case .unavailable(let asset): "Scan missed \(asset)"
        }
    }
}

/// Normalizes concrete provider output at one boundary. Adding an OTC provider should extend or
/// replace this service; it must not add broker networking to `LightningDeskModel`.
struct LiveDeskMarketDataService: DeskMarketDataServing {
    let transport: any MarketDataTransporting

    init(transport: any MarketDataTransporting = LiveMarketDataTransport()) {
        self.transport = transport
    }

    func scan(
        market: DeskMarket,
        asset: String,
        session: OandaSession?
    ) async throws -> MarketScanSnapshot {
        switch market {
        case .fx:
            guard let session else { throw DeskMarketDataError.missingSession }
            let envelope = try await transport.fetchFXScan(asset: asset, session: session)
            guard let signal = envelope.signal else {
                throw DeskMarketDataError.unavailable(asset)
            }
            return MarketScanSnapshot(
                signal: signal,
                candles: envelope.snapshotBars ?? envelope.candles ?? [],
                m5Candles: envelope.snapshotM5Bars ?? [],
                bid: envelope.bid,
                ask: envelope.ask,
                spread: envelope.spread,
                expirySeconds: envelope.expirySeconds ?? Timing.expirySec,
                engineSHA: envelope.engineSHA ?? EngineIdentity.loadedSHA1() ?? "unverified",
                policy: "baseline",
                source: envelope.source ?? signal.source ?? "oanda",
                veto: nil
            )

        case .crypto:
            guard let batch = try await transport.fetchCryptoBundle(asset: asset),
                  !batch.candles.isEmpty else {
                throw DeskMarketDataError.unavailable(asset)
            }
            let signal = CryptoDeskSignal.make(asset: asset, batch: batch)
            return MarketScanSnapshot(
                signal: signal,
                candles: batch.candles.map {
                    Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
                },
                m5Candles: [],
                bid: batch.bid,
                ask: batch.ask,
                spread: batch.spread,
                expirySeconds: 60,
                engineSHA: CryptoDeskSignal.engineIdentity,
                policy: CryptoDeskSignal.policy,
                source: batch.source,
                veto: CryptoDeskSignal.veto(asset: asset, batch: batch, signal: signal)
            )
        }
    }

    func quotes(
        market: DeskMarket,
        assets: [String],
        session: OandaSession?
    ) async -> MarketQuoteResult {
        switch market {
        case .fx:
            guard let session else {
                return MarketQuoteResult(quotes: [], status: .missingCredentials)
            }
            let batch = await transport.fetchFXQuotes(assets: assets, session: session)
            return MarketQuoteResult(quotes: batch.quotes, status: MarketTransportStatus(batch.transport))
        case .crypto:
            var quotes: [LiveQuote] = []
            for asset in assets {
                if let quote = await transport.fetchCryptoQuote(asset: asset) {
                    quotes.append(quote)
                }
            }
            return MarketQuoteResult(quotes: quotes, status: quotes.isEmpty ? .network : .ok)
        }
    }

    func candles(
        market: DeskMarket,
        asset: String,
        session: OandaSession?,
        count: Int
    ) async -> [Candle] {
        switch market {
        case .fx:
            guard let session else { return [] }
            return await transport.fetchFXCandles(asset: asset, session: session, count: count)
        case .crypto:
            guard let batch = try? await transport.fetchCryptoBundle(asset: asset) else { return [] }
            return batch.candles.map {
                Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }
        }
    }
}

/// Main-actor cache because its only consumer is the SwiftUI facade. It owns TTL decisions and
/// in-flight deduplication; the facade owns only which cached result is visible.
@MainActor
final class CandleCache {
    struct Key: Hashable, Sendable {
        let market: String
        let asset: String

        init(market: DeskMarket, asset: String) {
            self.market = market.rawValue
            self.asset = asset
        }
    }

    private struct Entry {
        let candles: [Candle]
        let fetchedAt: Date
    }

    private let ttl: TimeInterval
    private let now: () -> Date
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<[Candle], Never>] = [:]

    init(ttl: TimeInterval = 45, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    func cached(_ key: Key) -> [Candle] {
        entries[key]?.candles ?? []
    }

    func isFresh(_ key: Key) -> Bool {
        guard let entry = entries[key] else { return false }
        return now().timeIntervalSince(entry.fetchedAt) < ttl
    }

    func store(_ candles: [Candle], for key: Key, fetchedAt: Date? = nil) {
        guard !candles.isEmpty else { return }
        entries[key] = Entry(candles: candles, fetchedAt: fetchedAt ?? now())
    }

    func load(
        _ key: Key,
        force: Bool = false,
        fetch: @escaping @MainActor () async -> [Candle]
    ) async -> [Candle] {
        if !force, isFresh(key), let entry = entries[key] {
            return entry.candles
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task { @MainActor in await fetch() }
        inFlight[key] = task
        let candles = await task.value
        inFlight[key] = nil
        store(candles, for: key)
        return candles
    }
}
