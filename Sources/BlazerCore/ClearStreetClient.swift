import Foundation
import os

private let clearStreetLogger = Logger(subsystem: "com.blazer.os", category: "ClearStreetClient")

/// Clear Street Trading & Studio environment.
public enum ClearStreetEnvironment: String, Sendable, Equatable, Codable, CaseIterable {
    case demo
    case production

    public var host: String {
        switch self {
        case .demo:
            return "https://api.clearstreet.com"
        case .production:
            return "https://api.clearstreet.com"
        }
    }

    public var studioHost: String {
        "https://api.clearstreet.io/studio/v2"
    }
}

/// Credentials for Clear Street institutional prime & trading API.
/// Secured via device Keychain or process environment; never logged or serialized to unencrypted documents.
public struct ClearStreetSession: Sendable, Equatable {
    public var apiKey: String
    public var accountId: String?
    public var environment: ClearStreetEnvironment

    public init(apiKey: String, accountId: String? = nil, environment: ClearStreetEnvironment = .demo) {
        self.apiKey = apiKey
        self.accountId = accountId
        self.environment = environment
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Result of a Clear Street HTTP round-trip.
public enum ClearStreetTransport: Equatable, Sendable {
    case ok
    case missingKey
    case unauthorized
    case rateLimited
    case timeout
    case network
    case serverError(statusCode: Int)
}

public struct ClearStreetQuoteBatch: Sendable {
    public var quotes: [LiveQuote]
    public var transport: ClearStreetTransport

    public init(quotes: [LiveQuote], transport: ClearStreetTransport) {
        self.quotes = quotes
        self.transport = transport
    }
}

/// Token-bucket rate limiter for Clear Street API endpoints.
public actor ClearStreetRateLimit {
    public static let shared = ClearStreetRateLimit()

    private let steadyRate: Double = 10.0 // 10 req/s steady rate
    private let burstCapacity: Double = 20.0
    private var tokens: Double = 20.0
    private var lastRefill = Date()

    public init() {}

    public func acquire() async throws {
        try Task.checkCancellation()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        lastRefill = now
        tokens = min(burstCapacity, tokens + elapsed * steadyRate)

        if tokens >= 1.0 {
            tokens -= 1.0
            return
        }

        let needed = 1.0 - tokens
        let sleepSeconds = needed / steadyRate
        tokens = 0.0
        try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        try Task.checkCancellation()
    }
}

/// Production & Sandbox client for Clear Street institutional trading.
public enum ClearStreetClient {
    public static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 15.0
        return URLSession(configuration: config)
    }()

    /// Pings latency to Clear Street API.
    public static func pingLatency(session: ClearStreetSession) async -> (ok: Bool, latencyMs: Double?, fault: String?) {
        guard session.isConfigured else {
            return (false, nil, "Clear Street API key missing")
        }
        do { try await ClearStreetRateLimit.shared.acquire() }
        catch { return (false, nil, "Cancelled") }
        guard let url = URL(string: "\(session.environment.host)/v1/instruments?limit=1") else {
            return (false, nil, "Malformed URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(session.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await urlSession.data(for: request)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return (true, elapsedMs, nil)
            } else if let http = response as? HTTPURLResponse {
                return (false, elapsedMs, "HTTP \(http.statusCode)")
            }
            return (false, nil, "Invalid response")
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    /// Fetches quotes for a list of equity/option symbols from Clear Street.
    public static func fetchQuoteBatch(symbols: [String], session: ClearStreetSession) async -> ClearStreetQuoteBatch {
        guard session.isConfigured else {
            return ClearStreetQuoteBatch(quotes: [], transport: .missingKey)
        }
        guard !symbols.isEmpty else {
            return ClearStreetQuoteBatch(quotes: [], transport: .ok)
        }

        do { try await ClearStreetRateLimit.shared.acquire() }
        catch { return ClearStreetQuoteBatch(quotes: [], transport: .network) }
        let joinedSymbols = symbols.joined(separator: ",")
        guard let url = URL(string: "\(session.environment.host)/v1/market-data/quotes?symbols=\(joinedSymbols)") else {
            return ClearStreetQuoteBatch(quotes: [], transport: .network)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(session.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return ClearStreetQuoteBatch(quotes: [], transport: .network)
            }
            if http.statusCode == 401 { return ClearStreetQuoteBatch(quotes: [], transport: .unauthorized) }
            if http.statusCode == 429 { return ClearStreetQuoteBatch(quotes: [], transport: .rateLimited) }
            guard (200...299).contains(http.statusCode) else {
                return ClearStreetQuoteBatch(quotes: [], transport: .serverError(statusCode: http.statusCode))
            }

            let quotes = parseQuotes(from: data, requestedSymbols: symbols)
            return ClearStreetQuoteBatch(quotes: quotes, transport: .ok)
        } catch let err as URLError where err.code == .timedOut {
            return ClearStreetQuoteBatch(quotes: [], transport: .timeout)
        } catch {
            return ClearStreetQuoteBatch(quotes: [], transport: .network)
        }
    }

    /// Internal parser translating Clear Street quote JSON into Blazer's LiveQuote model.
    public static func parseQuotes(from data: Data, requestedSymbols: [String]) -> [LiveQuote] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Handles either array of quotes or dictionary keyed by symbol
        var results: [LiveQuote] = []
        let nowMs = Date().timeIntervalSince1970 * 1000

        if let quoteList = root["data"] as? [[String: Any]] ?? root["quotes"] as? [[String: Any]] {
            for item in quoteList {
                if let quote = extractQuote(from: item, fallbackTimeMs: nowMs) {
                    results.append(quote)
                }
            }
        } else {
            for symbol in requestedSymbols {
                if let item = root[symbol] as? [String: Any],
                   let quote = extractQuote(from: item, symbolOverride: symbol, fallbackTimeMs: nowMs) {
                    results.append(quote)
                }
            }
        }

        return results
    }

    private static func extractQuote(from dict: [String: Any], symbolOverride: String? = nil, fallbackTimeMs: Double) -> LiveQuote? {
        let symbol = symbolOverride ?? (dict["symbol"] as? String)
        guard let symbol else { return nil }

        let bid = (dict["bid"] as? Double) ?? (dict["bid_price"] as? Double) ?? 0.0
        let ask = (dict["ask"] as? Double) ?? (dict["ask_price"] as? Double) ?? 0.0
        let mid = (dict["mid"] as? Double) ?? (dict["mid_price"] as? Double) ?? (bid > 0 && ask > 0 ? (bid + ask) / 2.0 : 0.0)
        let asOf = (dict["timestamp"] as? Double) ?? (dict["as_of_ms"] as? Double) ?? fallbackTimeMs

        guard bid > 0 || ask > 0 || mid > 0 else { return nil }

        return LiveQuote(
            asset: symbol,
            bid: bid > 0 ? bid : mid,
            ask: ask > 0 ? ask : mid,
            mid: mid > 0 ? mid : (bid + ask) / 2.0,
            asOfMs: asOf,
            source: "clearstreet"
        )
    }
}
