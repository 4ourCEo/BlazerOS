import Foundation
import os

private let oandaLogger = Logger(subsystem: "com.blazer.os", category: "OandaClient")

/// Practice vs live host. The token never leaves the device that holds it.
public enum OandaEnvironment: String, Codable, Sendable, Equatable {
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

    public var streamHost: String {
        switch self {
        case .live: return "https://stream-fxtrade.oanda.com"
        case .practice: return "https://stream-fxpractice.oanda.com"
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
public enum OandaTransport: Codable, Equatable, Sendable {
    case ok
    case missingToken
    case unauthorized
    case rateLimited
    case timeout
    case network
}

public enum OandaDiagnosticState: String, Codable, Sendable, Equatable {
    case credentialsMissing = "CREDENTIALS_MISSING"
    case liveEnvironmentRejected = "LIVE_ENVIRONMENT_REJECTED"
    case unauthorized = "UNAUTHORIZED"
    case rateLimited = "RATE_LIMITED"
    case timeout = "TIMEOUT"
    case network = "NETWORK"
    case accountAuthenticated = "ACCOUNT_AUTHENTICATED"
    case marketDataUnavailable = "MARKET_DATA_UNAVAILABLE"
    case ready = "READY"
}

public struct OandaDiagnostic: Codable, Sendable, Equatable {
    public let state: OandaDiagnosticState
    public let environment: OandaEnvironment
    public let instrument: String
    public let latencyMs: Double?
    public let quoteCount: Int
    public let candleCount: Int
    public let message: String

    public init(state: OandaDiagnosticState, environment: OandaEnvironment, instrument: String,
                latencyMs: Double? = nil, quoteCount: Int = 0, candleCount: Int = 0,
                message: String) {
        self.state = state
        self.environment = environment
        self.instrument = instrument
        self.latencyMs = latencyMs
        self.quoteCount = quoteCount
        self.candleCount = candleCount
        self.message = message
    }
}

public struct OandaQuoteBatch: Sendable {
    public var quotes: [LiveQuote]
    public var transport: OandaTransport

    public init(quotes: [LiveQuote], transport: OandaTransport) {
        self.quotes = quotes
        self.transport = transport
    }
}

/// Historical OANDA bid/ask candle data. Candle extremes are not tick
/// quotations: when both a stop and target are crossed inside one candle, the
/// execution order remains unknown and must be recorded as ambiguous.
public struct OandaBidAskCandle: Codable, Sendable, Equatable {
    public let instrument: String
    public let granularity: String
    public let sourceTime: Date
    public let complete: Bool
    public let bidOpen: Double
    public let bidHigh: Double
    public let bidLow: Double
    public let bidClose: Double
    public let askOpen: Double
    public let askHigh: Double
    public let askLow: Double
    public let askClose: Double

    public init(instrument: String, granularity: String, sourceTime: Date, complete: Bool,
                bidOpen: Double, bidHigh: Double, bidLow: Double, bidClose: Double,
                askOpen: Double, askHigh: Double, askLow: Double, askClose: Double) {
        self.instrument = instrument; self.granularity = granularity
        self.sourceTime = sourceTime; self.complete = complete
        self.bidOpen = bidOpen; self.bidHigh = bidHigh; self.bidLow = bidLow; self.bidClose = bidClose
        self.askOpen = askOpen; self.askHigh = askHigh; self.askLow = askLow; self.askClose = askClose
    }

    public var validation: [String] {
        let values = [bidOpen, bidHigh, bidLow, bidClose, askOpen, askHigh, askLow, askClose]
        var issues: [String] = []
        if instrument.isEmpty || granularity.isEmpty { issues.append("identity_missing") }
        if !sourceTime.timeIntervalSince1970.isFinite { issues.append("timestamp_invalid") }
        if !values.allSatisfy({ $0.isFinite && $0 > 0 }) { issues.append("price_invalid") }
        if bidHigh < max(bidOpen, bidClose) || bidLow > min(bidOpen, bidClose)
            || askHigh < max(askOpen, askClose) || askLow > min(askOpen, askClose) {
            issues.append("ohlc_invalid")
        }
        if bidOpen >= askOpen || bidHigh >= askHigh || bidLow >= askLow || bidClose >= askClose {
            issues.append("crossed_bid_ask")
        }
        return issues
    }

    public var intrabarSequenceIsKnown: Bool { false }
}

public struct OandaHistoricalBidAskBatch: Codable, Sendable, Equatable {
    public let instrument: String
    public let granularity: String
    public let requestedFrom: Date
    public let requestedTo: Date
    public let candles: [OandaBidAskCandle]
    public let transport: OandaTransport
    public let practiceOnlyRejected: Bool
    public let httpStatus: Int?
    public let serverError: String?

    public init(instrument: String, granularity: String, requestedFrom: Date,
                requestedTo: Date, candles: [OandaBidAskCandle], transport: OandaTransport,
                practiceOnlyRejected: Bool = false, httpStatus: Int? = nil,
                serverError: String? = nil) {
        self.instrument = instrument; self.granularity = granularity
        self.requestedFrom = requestedFrom; self.requestedTo = requestedTo
        self.candles = candles; self.transport = transport
        self.practiceOnlyRejected = practiceOnlyRejected
        self.httpStatus = httpStatus
        self.serverError = serverError
    }
}

/// Bounded forward Practice pricing observations. These are not historical
/// data and must never be merged into a historical archive without their
/// capture interval and forward-capture provenance.
public struct OandaForwardQuoteCapture: Codable, Sendable, Equatable {
    public let instrument: String
    public let source: String
    public let environment: OandaEnvironment
    public let startedAt: Date
    public let endedAt: Date
    public let quotes: [LiveQuote]
    public let transport: OandaTransport
    public let httpStatus: Int?
    public let contentType: String?
    public let heartbeatCount: Int
    public let parseFailures: Int
    public let termination: String
    public let errorCode: String?

    public init(instrument: String, source: String = "oanda-pricing-stream",
                environment: OandaEnvironment, startedAt: Date, endedAt: Date,
                quotes: [LiveQuote], transport: OandaTransport, httpStatus: Int? = nil,
                contentType: String? = nil, heartbeatCount: Int = 0,
                parseFailures: Int = 0, termination: String = "unknown",
                errorCode: String? = nil) {
        self.instrument = instrument; self.source = source; self.environment = environment
        self.startedAt = startedAt; self.endedAt = endedAt; self.quotes = quotes
        self.transport = transport
        self.httpStatus = httpStatus; self.contentType = contentType
        self.heartbeatCount = heartbeatCount; self.parseFailures = parseFailures
        self.termination = termination; self.errorCode = errorCode
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
        _ = await acquire(timeout: .greatestFiniteMagnitude)
    }

    /// Bounded variant used by finite diagnostics and rehearsals.
    public func acquire(timeout: TimeInterval) async -> Bool {
        let started = Date()
        refill()
        while tokens < 1 {
            if Date().timeIntervalSince(started) >= timeout { return false }
            let deficit = 1 - tokens
            let waitSec = deficit / steadyRate
            let remaining = max(0, timeout - Date().timeIntervalSince(started))
            let nanos = UInt64(min(max(0.05, waitSec), remaining) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return false }
            refill()
        }
        tokens -= 1
        return true
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
    public static let historicalGranularities = ["M1", "M5", "M15", "H1"]

    /// Returns an interval-aligned end that is at least one whole candle behind
    /// `now`, so the requested range cannot include a forming candle.
    public static func historicalClosedEnd(now: Date, granularity: String) -> Date? {
        let seconds: TimeInterval
        switch granularity {
        case "M1": seconds = 60
        case "M5": seconds = 5 * 60
        case "M15": seconds = 15 * 60
        case "H1": seconds = 60 * 60
        default: return nil
        }
        let unix = now.timeIntervalSince1970
        guard unix.isFinite else { return nil }
        let boundary = floor(unix / seconds) * seconds - seconds
        return Date(timeIntervalSince1970: boundary)
    }
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
        "GBP/JPY": "GBP_JPY",
        "XAU/USD": "XAU_USD",
    ]

    public static func instrument(for asset: String) -> String? {
        instrumentMap[asset]
    }

    /// Read-only operational probe. It deliberately separates credentials, auth,
    /// transport, account access, and market-observation availability.
    public static func diagnose(session: OandaSession, asset: String = "EUR/USD") async -> OandaDiagnostic {
        guard session.isConfigured else {
            return OandaDiagnostic(state: .credentialsMissing, environment: session.environment,
                                   instrument: asset, message: "OANDA credentials are not configured")
        }
        guard session.environment == .practice else {
            return OandaDiagnostic(state: .liveEnvironmentRejected, environment: session.environment,
                                   instrument: asset, message: "ORB research requires OANDA Practice")
        }
        let ping = await pingLatency(session: session)
        if let fault = ping.fault {
            let state: OandaDiagnosticState
            switch fault {
            case "OANDA unauthorized": state = .unauthorized
            case "Rate limit.": state = .rateLimited
            case "Feed timeout": state = .timeout
            default: state = .network
            }
            return OandaDiagnostic(state: state, environment: session.environment, instrument: asset,
                                   latencyMs: ping.latencyMs, message: fault)
        }
        guard let mapped = instrument(for: asset) else {
            return OandaDiagnostic(state: .marketDataUnavailable, environment: session.environment,
                                   instrument: asset, latencyMs: ping.latencyMs,
                                   message: "Instrument is not supported by the OANDA mapping")
        }
        async let candles = fetchCandlesResult(asset: asset, granularity: "M1", count: 120, session: session)
        async let quotes = fetchQuoteBatch(assets: [asset], session: session)
        let candleResult = await candles
        let quoteResult = await quotes
        let transport = [candleResult.transport, quoteResult.transport]
        if transport.contains(.unauthorized) {
            return OandaDiagnostic(state: .unauthorized, environment: session.environment, instrument: mapped,
                                   latencyMs: ping.latencyMs, message: "OANDA account or instrument access denied")
        }
        if transport.contains(.rateLimited) {
            return OandaDiagnostic(state: .rateLimited, environment: session.environment, instrument: mapped,
                                   latencyMs: ping.latencyMs, message: "OANDA rate limit reached")
        }
        if transport.contains(.timeout) {
            return OandaDiagnostic(state: .timeout, environment: session.environment, instrument: mapped,
                                   latencyMs: ping.latencyMs, message: "OANDA market-data request timed out")
        }
        let quoteCount = quoteResult.quotes.count
        let candleCount = candleResult.candles.count
        guard quoteCount > 0, candleCount > 0 else {
            return OandaDiagnostic(state: .marketDataUnavailable, environment: session.environment,
                                   instrument: mapped, latencyMs: ping.latencyMs, quoteCount: quoteCount,
                                   candleCount: candleCount, message: "Account authenticated but no usable market observation was returned")
        }
        return OandaDiagnostic(state: .ready, environment: session.environment, instrument: mapped,
                               latencyMs: ping.latencyMs, quoteCount: quoteCount,
                               candleCount: candleCount, message: "Authenticated OANDA Practice market data available")
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
        guard await OandaRateLimit.shared.acquire(timeout: 15) else {
            return (false, nil, "Rate limit.")
        }
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
        guard await OandaRateLimit.shared.acquire(timeout: 15) else {
            return OandaQuoteBatch(quotes: [], transport: .rateLimited)
        }
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
            throw ScanError.failed("OANDA unauthorized")
        }
        if candles1m.transport == .network || candles5m.transport == .network
            || batch.transport == .network {
            throw ScanError.failed("OANDA network failure")
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
            expirySeconds: Timing.expirySec,
            quoteAsOfMs: quote.asOfMs,
            evaluatedAtMs: Date().timeIntervalSince1970 * 1000
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

    /// Fetches authentic historical bid/ask candles from OANDA Practice. This
    /// is intentionally not a tick-history claim: callers must preserve
    /// intrabar ambiguity when evaluating stops and targets.
    public static func fetchHistoricalBidAskCandles(
        asset: String, from: Date, to: Date, granularity: String = "M1",
        session: OandaSession
    ) async -> OandaHistoricalBidAskBatch {
        let instrumentName = instrument(for: asset) ?? asset
        let base = OandaHistoricalBidAskBatch(instrument: instrumentName,
            granularity: granularity, requestedFrom: from, requestedTo: to,
            candles: [], transport: .network)
        guard historicalGranularities.contains(granularity) else { return base }
        guard session.isConfigured, session.environment == .practice,
              from.timeIntervalSince1970.isFinite, to > from else {
            return OandaHistoricalBidAskBatch(instrument: instrumentName,
                granularity: granularity, requestedFrom: from, requestedTo: to,
                candles: [], transport: session.isConfigured ? .network : .missingToken,
                practiceOnlyRejected: session.environment != .practice)
        }
        guard let instrumentName = instrument(for: asset),
              await OandaRateLimit.shared.acquire(timeout: 15),
              var components = URLComponents(
                  string: "\(session.environment.host)/v3/instruments/\(instrumentName)/candles") else {
            return base
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        components.queryItems = [
            URLQueryItem(name: "granularity", value: granularity),
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to)),
            // OANDA v20 encodes multiple candle components without a comma:
            // BA requests bid and ask OHLC together.
            URLQueryItem(name: "price", value: "BA"),
            URLQueryItem(name: "smooth", value: "false"),
            URLQueryItem(name: "includeFirst", value: "true")
        ]
        guard let url = components.url else { return base }
        do {
            let (data, response) = try await URLSession.shared.data(for: authorized(url, session: session, timeout: 20))
            guard let http = response as? HTTPURLResponse else { return base }
            if http.statusCode == 401 || http.statusCode == 403 {
            return OandaHistoricalBidAskBatch(instrument: instrumentName, granularity: granularity,
                    requestedFrom: from, requestedTo: to, candles: [], transport: .unauthorized,
                    httpStatus: http.statusCode)
            }
            if http.statusCode == 429 {
            return OandaHistoricalBidAskBatch(instrument: instrumentName, granularity: granularity,
                    requestedFrom: from, requestedTo: to, candles: [], transport: .rateLimited,
                    httpStatus: http.statusCode)
            }
            guard http.statusCode < 400 else {
                let error = try? decoder.decode(OandaErrorResponse.self, from: data)
                return OandaHistoricalBidAskBatch(instrument: instrumentName, granularity: granularity,
                    requestedFrom: from, requestedTo: to, candles: [], transport: .network,
                    httpStatus: http.statusCode,
                    serverError: error?.errorCode ?? error?.errorMessage)
            }
            let decoded = try decoder.decode(CandlesResponse.self, from: data)
            let parsed = (decoded.candles ?? []).compactMap {
                bidAskCandle(from: $0, instrument: instrumentName, granularity: granularity)
            }.filter { $0.sourceTime >= from && $0.sourceTime <= to }
            let ordered = parsed.sorted { $0.sourceTime < $1.sourceTime }
            return OandaHistoricalBidAskBatch(instrument: instrumentName, granularity: granularity,
                requestedFrom: from, requestedTo: to,
                candles: ordered, transport: .ok, httpStatus: http.statusCode)
        } catch let error as URLError where error.code == .timedOut {
            return OandaHistoricalBidAskBatch(instrument: instrumentName, granularity: granularity,
                requestedFrom: from, requestedTo: to, candles: [], transport: .timeout)
        } catch {
            return base
        }
    }

    /// Captures a bounded forward Practice pricing stream. This is an
    /// authenticated observation tool, not historical tick reconstruction.
    public static func captureForwardQuotes(
        asset: String, duration: TimeInterval = 30, maxQuotes: Int = 100,
        session: OandaSession
    ) async -> OandaForwardQuoteCapture {
        let instrumentName = instrument(for: asset) ?? asset
        guard session.isConfigured, session.environment == .practice,
              let mapped = instrument(for: asset), duration > 0, maxQuotes > 0 else {
            return OandaForwardQuoteCapture(instrument: instrumentName,
                environment: session.environment, startedAt: Date(), endedAt: Date(),
                quotes: [], transport: session.isConfigured ? .network : .missingToken)
        }
        guard await OandaRateLimit.shared.acquire(timeout: 15),
               var components = URLComponents(
                   string: "\(session.environment.streamHost)/v3/accounts/\(session.accountId)/pricing/stream") else {
            return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                startedAt: Date(), endedAt: Date(), quotes: [], transport: .network)
        }
        // The requested observation interval begins only after rate limiting has
        // admitted the request; waiting for a token is not capture time.
        let started = Date()
        components.queryItems = [URLQueryItem(name: "instruments", value: mapped)]
        guard let url = components.url else {
            return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                startedAt: started, endedAt: Date(), quotes: [], transport: .network)
        }
        var request = authorized(url, session: session, timeout: duration + 5)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        var quotes: [LiveQuote] = []
        var heartbeatCount = 0
        var parseFailures = 0
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                    startedAt: started, endedAt: Date(), quotes: [], transport: .network,
                    termination: "invalid_response")
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")
            let httpTransport = forwardHTTPTransport(statusCode: http.statusCode)
            if httpTransport != .ok {
                let termination = httpTransport == .rateLimited
                    ? "http_rate_limited"
                    : (httpTransport == .unauthorized ? "http_auth_rejected" : "http_failure")
                return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                    startedAt: started, endedAt: Date(), quotes: [], transport: httpTransport,
                    httpStatus: http.statusCode, contentType: contentType,
                    termination: termination)
            }
            var termination = "stream_ended"
            for try await line in bytes.lines {
                if Date().timeIntervalSince(started) >= duration {
                    termination = "duration_reached"
                    break
                }
                if quotes.count >= maxQuotes {
                    termination = "quote_limit_reached"
                    break
                }
                guard let data = line.data(using: .utf8) else {
                    parseFailures += 1
                    continue
                }
                if let message = try? decoder.decode(StreamMessage.self, from: data),
                   message.type == "HEARTBEAT" {
                    heartbeatCount += 1
                    continue
                }
                guard let row = try? decoder.decode(ClientPrice.self, from: data),
                      row.instrument == mapped,
                      let quote = parse(asset: asset, row: row) else {
                    parseFailures += 1
                    continue
                }
                quotes.append(quote)
            }
            let endedAt = Date()
            let final = finalizeForwardStream(endedAt: endedAt, startedAt: started,
                duration: duration, quoteCount: quotes.count, maxQuotes: maxQuotes,
                termination: termination)
            return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                startedAt: started, endedAt: endedAt, quotes: quotes, transport: final.transport,
                httpStatus: http.statusCode, contentType: contentType,
                heartbeatCount: heartbeatCount, parseFailures: parseFailures,
                termination: final.termination)
        } catch {
            let failure = classifyForwardError(error)
            return OandaForwardQuoteCapture(instrument: mapped, environment: session.environment,
                startedAt: started, endedAt: Date(), quotes: quotes, transport: failure.transport,
                heartbeatCount: heartbeatCount, parseFailures: parseFailures,
                termination: failure.termination, errorCode: failure.errorCode)
        }
    }

    /// Classifies a completed stream without depending on URLSession. A normal
    /// EOF before the requested interval is incomplete and cannot be archived
    /// or reported as a successful capture. Delayed provider messages are not
    /// rejected here; only the bounded capture interval is considered.
    static func finalizeForwardStream(endedAt: Date, startedAt: Date,
                                      duration: TimeInterval, quoteCount: Int,
                                      maxQuotes: Int, termination: String)
        -> (transport: OandaTransport, termination: String) {
        if termination == "duration_reached"
            || quoteCount >= maxQuotes {
            return (.ok, termination == "duration_reached" ? termination : "quote_limit_reached")
        }
        if endedAt.timeIntervalSince(startedAt) < duration {
            return (.network, "early_eof")
        }
        return (.ok, "duration_reached")
    }

    static func forwardHTTPTransport(statusCode: Int) -> OandaTransport {
        if statusCode == 429 { return .rateLimited }
        if statusCode == 401 || statusCode == 403 { return .unauthorized }
        return statusCode >= 400 ? .network : .ok
    }

    static func classifyForwardError(_ error: Error)
        -> (transport: OandaTransport, termination: String, errorCode: String?) {
        if error is CancellationError {
            return (.network, "cancelled", nil)
        }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return (.network, "cancelled", urlError.code.rawValue.description)
            }
            if urlError.code == .timedOut {
                return (.timeout, "timeout", urlError.code.rawValue.description)
            }
        }
        return (.network, "network_failure", (error as NSError).code.description)
    }

    static func isValidForwardBidAsk(bid: Double, ask: Double) -> Bool {
        bid.isFinite && ask.isFinite && bid > 0 && ask > 0 && ask > bid
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
        guard await OandaRateLimit.shared.acquire(timeout: 15) else {
            return CandleFetch(candles: [], transport: .rateLimited)
        }
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

    private static func bidAskCandle(from row: CandleRow, instrument: String,
                                     granularity: String) -> OandaBidAskCandle? {
        guard row.complete == true, let raw = row.time,
              let seconds = parseOandaTimeMs(raw),
              let bid = row.bid, let ask = row.ask,
              let b0 = Double(bid.o ?? ""), let bh = Double(bid.h ?? ""),
              let bl = Double(bid.l ?? ""), let bc = Double(bid.c ?? ""),
              let a0 = Double(ask.o ?? ""), let ah = Double(ask.h ?? ""),
              let al = Double(ask.l ?? ""), let ac = Double(ask.c ?? "") else {
            return nil
        }
        let candle = OandaBidAskCandle(instrument: instrument, granularity: granularity,
            sourceTime: Date(timeIntervalSince1970: seconds / 1000), complete: true,
            bidOpen: b0, bidHigh: bh, bidLow: bl, bidClose: bc,
            askOpen: a0, askHigh: ah, askLow: al, askClose: ac)
        return candle.validation.isEmpty ? candle : nil
    }

    private static func parse(asset: String, row: ClientPrice) -> LiveQuote? {
        let bid =
            Double(row.bids?.first?.price ?? "")
            ?? Double(row.closeoutBid ?? "")
        let ask =
            Double(row.asks?.first?.price ?? "")
            ?? Double(row.closeoutAsk ?? "")
        guard let bid, let ask, isValidForwardBidAsk(bid: bid, ask: ask) else { return nil }
        guard let raw = row.time, let asOf = parseOandaTimeMs(raw) else { return nil }
        let mid = (bid + ask) / 2
        guard mid.isFinite else { return nil }
        return LiveQuote(asset: asset, bid: bid, ask: ask, mid: mid, asOfMs: asOf, source: "oanda")
    }

    private struct PricingResponse: Decodable {
        var prices: [ClientPrice]?
    }

    private struct OandaErrorResponse: Decodable {
        var errorCode: String?
        var errorMessage: String?
    }

    private struct ClientPrice: Decodable {
        var type: String?
        var instrument: String?
        var time: String?
        var bids: [PriceLevel]?
        var asks: [PriceLevel]?
        var closeoutBid: String?
        var closeoutAsk: String?
    }

    private struct StreamMessage: Decodable {
        var type: String?
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
        var bid: MidOHLC?
        var ask: MidOHLC?
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
