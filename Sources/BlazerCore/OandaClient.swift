import Foundation
import os

private let oandaLogger = Logger(subsystem: "com.blazer.os", category: "OandaClient")

/// Practice vs live host. The token never leaves the device that holds it.
public enum OandaEnvironment: String, Sendable, Equatable {
    case practice
    case live

    public var host: String {
        switch self {
        case .live:
            return "https://api-fxtrade.oanda.com"
        case .practice:
            return "https://api-fxpractice.oanda.com"
        }
    }
}

/// Keychain-backed credentials supplied by the app. BlazerCore does not store them.
public struct OandaSession: Sendable, Equatable {
    public var token: String
    public var accountId: String
    public var environment: OandaEnvironment

    public init(token: String, accountId: String, environment: OandaEnvironment = .practice) {
        self.token = token
        self.accountId = accountId
        self.environment = environment
    }

    public var isConfigured: Bool {
        !token.isEmpty && !accountId.isEmpty
    }
}

/// Outcome of a regulated OANDA HTTP round-trip. Never invents a tap side.
public enum OandaTransport: Equatable, Sendable {
    case ok
    case missingToken
    case unauthorized
    case rateLimited
    case timeout
    case network
}

public struct OandaQuoteBatch: Sendable {
    public var quotes: [LiveQuote]
    public var transport: OandaTransport

    public init(quotes: [LiveQuote], transport: OandaTransport) {
        self.quotes = quotes
        self.transport = transport
    }
}

/// Token-bucket rate limit for all OANDA HTTP. Never picks or flips a tap side.
public actor OandaRateLimit {
    public static let shared = OandaRateLimit()

    private let steadyRate: Double = 3
    private let burstCapacity: Double = 4
    private var tokens: Double = 4
    private var lastRefill = Date()

    public init() {}

    /// Wait until a token is available, then consume one. Call before each OANDA HTTP.
    public func acquire() async {
        refill()
        while tokens < 1 {
            let deficit = 1 - tokens
            let waitSec = deficit / steadyRate
            let nanos = UInt64(max(0.05, waitSec) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            refill()
        }
        tokens -= 1
    }

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        if elapsed > 0 {
            tokens = min(burstCapacity, tokens + elapsed * steadyRate)
            lastRefill = now
        }
    }
}

public enum OandaClient {
    private static let proofLock = NSLock()
    nonisolated(unsafe) private static var _loggedProof = false
    private static var loggedProof: Bool {
        get {
            proofLock.lock()
            defer { proofLock.unlock() }
            return _loggedProof
        }
        set {
            proofLock.lock()
            defer { proofLock.unlock() }
            _loggedProof = newValue
        }
    }
    private static let decoder = JSONDecoder()
    private static let instrumentMap: [String: String] = [
        "EUR/USD": "EUR_USD",
        "GBP/USD": "GBP_USD",
        "USD/JPY": "USD_JPY",
        "EUR/GBP": "EUR_GBP",
        "AUD/USD": "AUD_USD",
        "USD/CAD": "USD_CAD",
        "EUR/JPY": "EUR_JPY",
    ]

    public static func instrument(for asset: String) -> String? {
        instrumentMap[asset]
    }

    /// Broker candle/quote timestamps. Shared so Mac and iPhone reject the same malformed prints.
    public static func parseTimeMs(_ raw: String) -> Double? {
        parseOandaTimeMs(raw)
    }

    /// Background ping. Fail only on missing token, auth, network, or timeout.
    public static func pingLatency(session: OandaSession) async -> (ok: Bool, latencyMs: Double?, fault: String?) {
        guard session.isConfigured else {
            return (false, nil, "OANDA token missing")
        }
        await OandaRateLimit.shared.acquire()
        guard var components = URLComponents(
            string: "\(session.environment.host)/v3/accounts/\(session.accountId)/pricing"
        ) else {
            return (false, nil, "Feed timeout")
        }
        components.queryItems = [
            URLQueryItem(name: "instruments", value: "EUR_USD"),
        ]
        guard let url = components.url else {
            return (false, nil, "Feed timeout")
        }
        let request = authorized(url, session: session, timeout: 8)
        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ms = Date().timeIntervalSince(started) * 1000
            guard let http = response as? HTTPURLResponse else {
                return (false, ms, "Feed timeout")
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return (false, ms, "OANDA unauthorized")
            }
            if http.statusCode == 429 {
                return (false, ms, "Rate limit.")
            }
            if http.statusCode >= 400 {
                return (false, ms, "Feed timeout")
            }
            return (true, ms, nil)
        } catch let error as URLError where error.code == .timedOut {
            let ms = Date().timeIntervalSince(started) * 1000
            return (false, ms, "Feed timeout")
        } catch {
            let ms = Date().timeIntervalSince(started) * 1000
            return (false, ms, "Feed timeout")
        }
    }

    public static func fetchQuotes(
        assets: [String] = Assets.watchlist,
        session: OandaSession
    ) async -> [LiveQuote] {
        let batch = await fetchQuoteBatch(assets: assets, session: session)
        return batch.quotes
    }

    public static func fetchQuoteBatch(
        assets: [String] = Assets.watchlist,
        session: OandaSession
    ) async -> OandaQuoteBatch {
        guard session.isConfigured else {
            return OandaQuoteBatch(quotes: [], transport: .missingToken)
        }
        let instruments = assets.compactMap { instrument(for: $0) }
        guard !instruments.isEmpty else {
            return OandaQuoteBatch(quotes: [], transport: .network)
        }
        await OandaRateLimit.shared.acquire()
        guard var components = URLComponents(
            string: "\(session.environment.host)/v3/accounts/\(session.accountId)/pricing"
        ) else {
            return OandaQuoteBatch(quotes: [], transport: .network)
        }
        components.queryItems = [
            URLQueryItem(name: "instruments", value: instruments.joined(separator: ",")),
        ]
        guard let url = components.url else {
            return OandaQuoteBatch(quotes: [], transport: .network)
        }
        let request = authorized(url, session: session, timeout: 8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return OandaQuoteBatch(quotes: [], transport: .network)
            }
            if http.statusCode == 429 {
                return OandaQuoteBatch(quotes: [], transport: .rateLimited)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return OandaQuoteBatch(quotes: [], transport: .unauthorized)
            }
            guard http.statusCode < 400 else {
                return OandaQuoteBatch(quotes: [], transport: .network)
            }
            let decoded = try decoder.decode(PricingResponse.self, from: data)
            var out: [LiveQuote] = []
            for asset in assets {
                guard let instrument = instrument(for: asset) else { continue }
                guard let row = decoded.prices?.first(where: { $0.instrument == instrument })
                else { continue }
                guard let quote = parse(asset: asset, row: row) else { continue }
                out.append(quote)
            }
            if !loggedProof, let first = out.first {
                loggedProof = true
                oandaLogger.debug("BlazerCore feed source=\(first.source, privacy: .public) asset=\(first.asset, privacy: .public)")
            }
            return OandaQuoteBatch(quotes: out, transport: .ok)
        } catch let error as URLError where error.code == .timedOut {
            return OandaQuoteBatch(quotes: [], transport: .timeout)
        } catch {
            return OandaQuoteBatch(quotes: [], transport: .network)
        }
    }

    /// Completed M1 + M5 candles + quote for in-process strategy SCAN.
    /// Requires a real pricing row — never synthesizes bid/ask = mid / spread 0.
    public static func fetchBundle(
        asset: String,
        session: OandaSession
    ) async throws -> StrategyEngine.MarketInput? {
        guard session.isConfigured, instrument(for: asset) != nil else {
            if !session.isConfigured { throw ScanError.failed("OANDA token missing") }
            return nil
        }
        async let oneMinute = fetchCandlesResult(asset: asset, granularity: "M1", count: 120, session: session)
        async let fiveMinute = fetchCandlesResult(asset: asset, granularity: "M5", count: 120, session: session)
        async let quoteBatch = fetchQuoteBatch(assets: [asset], session: session)
        let candles1m = await oneMinute
        let candles5m = await fiveMinute
        let batch = await quoteBatch
        if candles1m.transport == .rateLimited || candles5m.transport == .rateLimited
            || batch.transport == .rateLimited
        {
            throw ScanError.failed("Rate limit.")
        }
        if candles1m.transport == .timeout || candles5m.transport == .timeout
            || batch.transport == .timeout
        {
            throw ScanError.failed("Feed timeout")
        }
        if batch.transport == .missingToken || candles1m.transport == .missingToken {
            throw ScanError.failed("OANDA token missing")
        }
        if batch.transport == .unauthorized {
            throw ScanError.failed("OANDA token missing")
        }
        let quote = batch.quotes.first
        guard candles1m.candles.count >= 20, candles5m.candles.count >= 20 else { return nil }
        guard let quote else { return nil }
        guard QuoteFreshness.isFresh(quote) else {
            throw ScanError.failed("Feed timeout")
        }
        let spread = quote.ask - quote.bid
        guard spread.isFinite, spread > 0 else {
            throw ScanError.failed("Feed incomplete.")
        }
        return StrategyEngine.MarketInput(
            asset: asset,
            source: "oanda",
            candles1m: candles1m.candles.compactMap(payload(from:)),
            candles5m: candles5m.candles.compactMap(payload(from:)),
            lastPrice: quote.mid,
            bid: quote.bid,
            ask: quote.ask,
            spread: spread,
            expirySeconds: Timing.expirySec
        )
    }

    public static func fetchCandles(
        asset: String,
        session: OandaSession,
        granularity: String = "M1",
        count: Int = 80
    ) async -> [Candle] {
        let result = await fetchCandlesResult(
            asset: asset,
            granularity: granularity,
            count: count,
            session: session
        )
        return result.candles
    }

    private struct CandleFetch: Sendable {
        var candles: [Candle]
        var transport: OandaTransport
    }

    private static func fetchCandlesResult(
        asset: String,
        granularity: String,
        count: Int,
        session: OandaSession
    ) async -> CandleFetch {
        guard session.isConfigured, let instrument = instrument(for: asset) else {
            return CandleFetch(candles: [], transport: session.isConfigured ? .network : .missingToken)
        }
        await OandaRateLimit.shared.acquire()
        guard var components = URLComponents(
            string: "\(session.environment.host)/v3/instruments/\(instrument)/candles"
        ) else {
            return CandleFetch(candles: [], transport: .network)
        }
        components.queryItems = [
            URLQueryItem(name: "granularity", value: granularity),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "price", value: "M"),
        ]
        guard let url = components.url else {
            return CandleFetch(candles: [], transport: .network)
        }
        let timeout: TimeInterval = granularity == "M1" && count <= 80 ? 8 : 12
        let request = authorized(url, session: session, timeout: timeout)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                oandaLogger.error("BlazerCore fetchCandles response not HTTP for \(asset, privacy: .public)")
                return CandleFetch(candles: [], transport: .network)
            }
            if http.statusCode == 429 {
                oandaLogger.warning("BlazerCore fetchCandles 429 rate limited for \(asset, privacy: .public)")
                return CandleFetch(candles: [], transport: .rateLimited)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                oandaLogger.warning("BlazerCore fetchCandles 401/403 unauthorized for \(asset, privacy: .public)")
                return CandleFetch(candles: [], transport: .unauthorized)
            }
            guard http.statusCode < 400 else {
                oandaLogger.error("BlazerCore fetchCandles HTTP \(http.statusCode) for \(asset, privacy: .public)")
                return CandleFetch(candles: [], transport: .network)
            }
            let decoded = try decoder.decode(CandlesResponse.self, from: data)
            var out: [Candle] = []
            var seenTimes = Set<Double>()
            for row in decoded.candles ?? [] {
                guard row.complete == true else { continue }
                guard let mid = row.mid,
                    let open = Double(mid.o ?? ""),
                    let high = Double(mid.h ?? ""),
                    let low = Double(mid.l ?? ""),
                    let close = Double(mid.c ?? ""),
                    open.isFinite, high.isFinite, low.isFinite, close.isFinite,
                    let timeRaw = row.time,
                    let timeMs = parseOandaTimeMs(timeRaw)
                else { continue }
                if seenTimes.contains(timeMs), let idx = out.firstIndex(where: { $0.time == timeMs }) {
                    out[idx] = Candle(time: timeMs, open: open, high: high, low: low, close: close)
                    continue
                }
                seenTimes.insert(timeMs)
                out.append(Candle(time: timeMs, open: open, high: high, low: low, close: close))
            }
            oandaLogger.debug("BlazerCore fetchCandles parsed \(out.count) completed bars for \(asset, privacy: .public)")
            return CandleFetch(candles: out, transport: .ok)
        } catch let error as URLError where error.code == .timedOut {
            oandaLogger.warning("BlazerCore fetchCandles timed out for \(asset, privacy: .public)")
            return CandleFetch(candles: [], transport: .timeout)
        } catch {
            oandaLogger.error("BlazerCore fetchCandles error for \(asset, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return CandleFetch(candles: [], transport: .network)
        }
    }

    private static func authorized(_ url: URL, session: OandaSession, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        return request
    }

    private static func payload(from candle: Candle) -> StrategyEngine.CandlePayload? {
        guard let time = candle.time else { return nil }
        return StrategyEngine.CandlePayload(
            time: time,
            open: candle.bodyOpen,
            high: candle.bodyHigh,
            low: candle.bodyLow,
            close: candle.close
        )
    }

    private static func parse(asset: String, row: ClientPrice) -> LiveQuote? {
        let bid =
            Double(row.bids?.first?.price ?? "")
            ?? Double(row.closeoutBid ?? "")
        let ask =
            Double(row.asks?.first?.price ?? "")
            ?? Double(row.closeoutAsk ?? "")
        guard let bid, let ask, bid.isFinite, ask.isFinite, ask > bid else { return nil }
        guard let raw = row.time, let asOf = parseOandaTimeMs(raw) else { return nil }
        let mid = (bid + ask) / 2
        guard mid.isFinite else { return nil }
        return LiveQuote(asset: asset, bid: bid, ask: ask, mid: mid, asOfMs: asOf, source: "oanda")
    }

    private struct PricingResponse: Decodable {
        var prices: [ClientPrice]?
    }

    private struct ClientPrice: Decodable {
        var instrument: String?
        var time: String?
        var bids: [PriceLevel]?
        var asks: [PriceLevel]?
        var closeoutBid: String?
        var closeoutAsk: String?
    }

    private struct PriceLevel: Decodable {
        var price: String?
    }

    private struct CandlesResponse: Decodable {
        var candles: [CandleRow]?
    }

    private struct CandleRow: Decodable {
        var time: String?
        var complete: Bool?
        var mid: MidOHLC?
    }

    private struct MidOHLC: Decodable {
        var o: String?
        var h: String?
        var l: String?
        var c: String?
    }
}

private let oandaFormatLock = NSLock()
nonisolated(unsafe) private let oandaFractionalFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
nonisolated(unsafe) private let oandaPlainFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseOandaTimeMs(_ raw: String) -> Double? {
    oandaFormatLock.lock()
    defer { oandaFormatLock.unlock() }
    if let date = oandaFractionalFormatter.date(from: raw) {
        return date.timeIntervalSince1970 * 1000
    }
    if let date = oandaPlainFormatter.date(from: raw) {
        return date.timeIntervalSince1970 * 1000
    }
    if let dot = raw.firstIndex(of: "."), let z = raw.lastIndex(of: "Z") {
        let head = String(raw[..<dot])
        let frac = String(raw[raw.index(after: dot)..<z])
        let ms = String(frac.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        let trimmed = "\(head).\(ms)Z"
        if let date = oandaFractionalFormatter.date(from: trimmed) {
            return date.timeIntervalSince1970 * 1000
        }
    }
    return nil
}
