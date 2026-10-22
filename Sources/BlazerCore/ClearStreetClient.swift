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

    public func acquire() async {
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
        try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
    }
}

/// Clear Street Order submission model.
public struct ClearStreetOrder: Sendable, Codable, Equatable {
    public enum Side: String, Sendable, Codable {
        case buy = "BUY"
        case sell = "SELL"
    }

    public enum OrderType: String, Sendable, Codable {
        case market = "MARKET"
        case limit = "LIMIT"
    }

    public enum TimeInForce: String, Sendable, Codable {
        case day = "DAY"
        case gtc = "GTC"
        case ioc = "IOC"
    }

    public var symbol: String
    public var side: Side
    public var orderType: OrderType
    public var quantity: Double
    public var limitPrice: Double?
    public var timeInForce: TimeInForce
    public var clientOrderId: String

    public init(
        symbol: String,
        side: Side,
        orderType: OrderType = .market,
        quantity: Double,
        limitPrice: Double? = nil,
        timeInForce: TimeInForce = .day,
        clientOrderId: String = UUID().uuidString
    ) {
        self.symbol = symbol
        self.side = side
        self.orderType = orderType
        self.quantity = quantity
        self.limitPrice = limitPrice
        self.timeInForce = timeInForce
        self.clientOrderId = clientOrderId
    }
}

/// Execution confirmation or order state returned by Clear Street.
public struct ClearStreetOrderReceipt: Sendable, Codable, Equatable {
    public var orderId: String
    public var clientOrderId: String
    public var symbol: String
    public var status: String
    public var filledQuantity: Double
    public var avgPrice: Double?
    public var createdAt: Double

    public init(
        orderId: String,
        clientOrderId: String,
        symbol: String,
        status: String,
        filledQuantity: Double = 0.0,
        avgPrice: Double? = nil,
        createdAt: Double = Date().timeIntervalSince1970 * 1000
    ) {
        self.orderId = orderId
        self.clientOrderId = clientOrderId
        self.symbol = symbol
        self.status = status
        self.filledQuantity = filledQuantity
        self.avgPrice = avgPrice
        self.createdAt = createdAt
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
        await ClearStreetRateLimit.shared.acquire()
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

        await ClearStreetRateLimit.shared.acquire()
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

    /// Submits a market or limit order to Clear Street.
    public static func submitOrder(_ order: ClearStreetOrder, session: ClearStreetSession) async throws -> ClearStreetOrderReceipt {
        guard session.isConfigured else {
            throw ScanError.failed("Clear Street API key missing")
        }
        guard let accountId = session.accountId, !accountId.isEmpty else {
            throw ScanError.failed("Clear Street Account ID required for order routing")
        }

        await ClearStreetRateLimit.shared.acquire()
        guard let url = URL(string: "\(session.environment.host)/v1/accounts/\(accountId)/orders") else {
            throw ScanError.failed("Malformed Clear Street Order URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(session.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var bodyDict: [String: Any] = [
            "symbol": order.symbol,
            "side": order.side.rawValue.lowercased(),
            "order_type": order.orderType.rawValue.lowercased(),
            "quantity": order.quantity,
            "time_in_force": order.timeInForce.rawValue.lowercased(),
            "client_order_id": order.clientOrderId
        ]
        if let limit = order.limitPrice {
            bodyDict["limit_price"] = limit
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown order rejection"
            throw ScanError.failed("Clear Street Order Error: \(msg)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let orderId = json["order_id"] as? String {
            return ClearStreetOrderReceipt(
                orderId: orderId,
                clientOrderId: order.clientOrderId,
                symbol: order.symbol,
                status: (json["status"] as? String) ?? "OPEN",
                filledQuantity: (json["filled_quantity"] as? Double) ?? 0.0,
                avgPrice: json["avg_price"] as? Double
            )
        }

        return ClearStreetOrderReceipt(
            orderId: UUID().uuidString,
            clientOrderId: order.clientOrderId,
            symbol: order.symbol,
            status: "SUBMITTED"
        )
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
