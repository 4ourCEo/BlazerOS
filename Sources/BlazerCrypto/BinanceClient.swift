import BlazerCore
import Foundation
import os

private let binanceLog = Logger(subsystem: "com.blazer.ct", category: "BinanceClient")

// MARK: - BinanceClient
// Primary crypto price feed. No API key required for market data.
// Falls back to KrakenClient automatically on any non-200 response.
//
// Primary endpoint:
//   GET /api/v3/klines?symbol=BTCUSDT&interval=1m&limit=65
//   Returns full OHLCV + quoteVolume + tradeCount — all used by CryptoEngine.
//
// Secondary endpoint:
//   GET /api/v3/bookTicker — best bid/ask for spread gate.
//
// BlazerOS FX daemon is NEVER touched by this file.

public enum BinanceClient {

    public static let symbolMap: [String: String] = [
        "BTC/USDT": "BTCUSDT",
        "ETH/USDT": "ETHUSDT",
        "SOL/USDT": "SOLUSDT",
    ]

    // Binance.com is geo-blocked in the US (HTTP 451).
    // Binance.us is the legal US alternative — same REST API, same endpoint paths.
    // We try .com first; on 451 we fall back to .us automatically.
    private static let baseURLs = [
        "https://api.binance.com",
        "https://api.binance.us",
    ]

    /// Returns the first Binance base URL that returns HTTP 200 for a lightweight ping.
    /// The cache is guarded because callers can resolve concurrently from different tasks.
    nonisolated(unsafe) private static var _resolvedBase: String? = nil
    private static let baseLock = NSLock()

    private static func cachedBase() -> String? {
        baseLock.lock()
        defer { baseLock.unlock() }
        return _resolvedBase
    }

    private static func cacheBase(_ base: String?) {
        baseLock.lock()
        _resolvedBase = base
        baseLock.unlock()
    }

    private static func resolvedBase() async -> String {
        if let cached = cachedBase() { return cached }
        for base in baseURLs {
            if let url = URL(string: "\(base)/api/v3/ping"),
               let (_, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                binanceLog.info("Binance endpoint resolved: \(base)")
                cacheBase(base)
                return base
            }
        }
        cacheBase(baseURLs[1])
        return baseURLs[1]
    }

    /// A restricted-geography response invalidates the cached endpoint for the next call.
    private static func invalidateBase() {
        cacheBase(nil)
    }

    // Fetches up to `limit` completed 1m candles for walk-forward benchmarking.
    // Separate from fetchCryptoBundle (limit=65) to keep live polling fast.
    // Binance allows up to 1000 candles per request with no API key.

    public static func fetchBenchmarkCandles(
        asset: String,
        limit: Int = 500
    ) async throws -> [CryptoCandle] {
        guard let symbol = symbolMap[asset] else {
            throw CTFeedError.unsupportedPair(asset)
        }

        await BinanceRateLimit.shared.acquire()

        let base = await resolvedBase()
        let url = URL(string:
            "\(base)/api/v3/klines?symbol=\(symbol)&interval=1m&limit=\(min(limit + 1, 1000))"
        )!

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CTFeedError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let rawOuter = try? JSONDecoder().decode([[BinanceKlineField]].self, from: data) else {
            throw CTFeedError.decodingError("benchmark klines")
        }

        // Drop last — always the in-progress candle
        let candles = rawOuter.dropLast(1).compactMap { CryptoCandle.from(row: $0) }
        binanceLog.info("Benchmark fetch: \(candles.count) candles for \(asset)")
        return candles
    }


    public static func fetchCryptoBundle(
        asset: String,
        fallbackToKraken: Bool = true
    ) async throws -> CryptoCandleBatch? {

        guard let symbol = symbolMap[asset] else {
            throw CTFeedError.unsupportedPair(asset)
        }

        await BinanceRateLimit.shared.acquire()

        let base = await resolvedBase()
        let candleURL = URL(string:
            "\(base)/api/v3/klines?symbol=\(symbol)&interval=1m&limit=65"
        )!

        let candleData: Data
        let candleResponse: URLResponse
        do {
            (candleData, candleResponse) = try await URLSession.shared.data(from: candleURL)
        } catch {
            binanceLog.error("Binance klines network error for \(asset): \(error)")
            if fallbackToKraken {
                return try await KrakenClient.fetchCryptoBundle(asset: asset)
            }
            throw CTFeedError.networkError(error.localizedDescription)
        }

        guard (candleResponse as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (candleResponse as? HTTPURLResponse)?.statusCode ?? 0
            if code == 451 { invalidateBase() }
            binanceLog.warning("Binance klines HTTP \(code) for \(asset) — trying Kraken")
            if fallbackToKraken {
                return try await KrakenClient.fetchCryptoBundle(asset: asset)
            }
            throw CTFeedError.httpError(code)
        }

        guard let rawOuter = try? JSONDecoder().decode([[BinanceKlineField]].self, from: candleData) else {
            // Binance returns HTTP 200 with a JSON error body from restricted regions
            // (e.g. "Service unavailable from a restricted location"). Fall back instead of
            // dead-ending the desk.
            if fallbackToKraken {
                return try await KrakenClient.fetchCryptoBundle(asset: asset)
            }
            throw CTFeedError.decodingError("klines outer array")
        }

        // Drop the last row — it represents the current (incomplete) candle.
        let completedRaw = rawOuter.dropLast(1)

        let candles: [CryptoCandle] = completedRaw.compactMap { row in
            CryptoCandle.from(row: row)
        }

        guard candles.count >= 60 else {
            throw CTFeedError.insufficientBars(candles.count, required: 60)
        }

        // Fetch bid/ask for spread gate
        await BinanceRateLimit.shared.acquire()
        let tickerURL = URL(string:
            "\(base)/api/v3/ticker/bookTicker?symbol=\(symbol)"
        )!
        guard let (tickerData, _) = try? await URLSession.shared.data(from: tickerURL),
              let ticker = try? JSONDecoder().decode(BinanceTicker.self, from: tickerData),
              let bid = Double(ticker.bidPrice),
              let ask = Double(ticker.askPrice),
              ask > bid
        else {
            if fallbackToKraken {
                return try await KrakenClient.fetchCryptoBundle(asset: asset)
            }
            throw CTFeedError.decodingError("bookTicker")
        }

        return CryptoCandleBatch(
            candles: candles,
            bid:     bid,
            ask:     ask,
            asset:   asset,
            source:  "binance"
        )
    }

    // MARK: - fetchQuote (settlement price — bid/ask only)

    public static func fetchQuote(asset: String) async -> LiveQuote? {
        guard let symbol = symbolMap[asset] else { return nil }

        await BinanceRateLimit.shared.acquire()

        let base = await resolvedBase()
        if let url = URL(string: "\(base)/api/v3/ticker/bookTicker?symbol=\(symbol)"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let ticker = try? JSONDecoder().decode(BinanceTicker.self, from: data),
           let bid = Double(ticker.bidPrice),
           let ask = Double(ticker.askPrice),
           ask > bid {
            return LiveQuote(
                asset:  asset,
                bid:    bid,
                ask:    ask,
                mid:    (bid + ask) / 2.0,
                asOfMs: Date().timeIntervalSince1970 * 1000,
                source: "binance"
            )
        }

        // Binance unavailable (e.g. restricted region) — use the Kraken fallback.
        return await KrakenClient.fetchQuote(asset: asset)
    }

    // MARK: - fetchBundle (kept for benchmark compat — wraps fetchCryptoBundle)
    // Returns a StrategyEngine.MarketInput so benchmark code that still references
    // the old path compiles. New live path uses fetchCryptoBundle exclusively.

    public static func fetchBundle(
        asset: String,
        fallbackToKraken: Bool = true
    ) async throws -> StrategyEngine.MarketInput? {
        guard let batch = try await fetchCryptoBundle(asset: asset, fallbackToKraken: fallbackToKraken) else {
            return nil
        }
        let payloads = batch.candles.map {
            StrategyEngine.CandlePayload(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
        return StrategyEngine.MarketInput(
            asset:         asset,
            source:        batch.source,
            candles1m:     payloads,
            candles5m:     payloads,
            lastPrice:     batch.mid,
            bid:           batch.bid,
            ask:           batch.ask,
            spread:        batch.spread,
            expirySeconds: 60
        )
    }
}

// MARK: - Binance Decoding Helpers

// Binance kline rows mix Int64 timestamps and string-encoded decimals.
public enum BinanceKlineField: Decodable, Sendable {
    case integer(Int64)
    case string(String)
    case double(Double)

    public var doubleValue: Double? {
        switch self {
        case .integer(let i): return Double(i)
        case .string(let s):  return Double(s)
        case .double(let d):  return d
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self)  { self = .integer(i); return }
        if let s = try? c.decode(String.self) { self = .string(s);  return }
        if let d = try? c.decode(Double.self) { self = .double(d);  return }
        throw DecodingError.typeMismatch(BinanceKlineField.self,
            .init(codingPath: decoder.codingPath,
                  debugDescription: "BinanceKlineField: unexpected JSON type"))
    }
}

struct BinanceTicker: Decodable {
    let symbol:   String
    let bidPrice: String
    let askPrice: String
}
