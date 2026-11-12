import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OTChartsHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public struct OTChartsServerEvent: Sendable, Equatable {
    public let name: String
    public let data: String
    public let id: String?

    public init(name: String, data: String, id: String? = nil) {
        self.name = name
        self.data = data
        self.id = id
    }
}

/// Line-oriented decoder for the OTCharts SSE tick protocol. The official client dispatches
/// each `data:` line immediately; blank-line event grouping is optional, not required.
struct OTChartsSSEDecoder {
    private var eventName = "message"
    private var eventID: String?

    mutating func consume(_ line: String) -> [OTChartsServerEvent] {
        guard !line.isEmpty else {
            eventName = "message"
            eventID = nil
            return []
        }
        if line.hasPrefix(":") { return [] }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return []
        }
        if line.hasPrefix("id:") {
            eventID = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            return []
        }
        guard line.hasPrefix("data:") else { return [] }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        defer {
            eventName = "message"
            eventID = nil
        }
        guard !payload.isEmpty else { return [] }
        return [OTChartsServerEvent(name: eventName, data: payload, id: eventID)]
    }
}

public protocol OTChartsTransport: Sendable {
    func data(for request: URLRequest) async throws -> OTChartsHTTPResponse
    func events(for request: URLRequest) -> AsyncThrowingStream<OTChartsServerEvent, any Error>
}

public protocol OTCResearchClock: Sendable {
    func now() -> Date
}

public struct SystemOTCResearchClock: OTCResearchClock {
    public init() {}
    public func now() -> Date { Date() }
}

public enum OTChartsError: Error, Sendable, Equatable {
    case disabled
    case invalidCredential
    case invalidIdentity
    case invalidResponse
    case httpStatus(Int)
    case throttled(retryAfterSeconds: Int?)
    case wrongInstrument(expected: String, received: String)
    case staleOrOutOfOrder
    case providerClosed(String)
}

public struct OTChartsConfiguration: Sendable, Equatable {
    public let apiKey: String
    public let enabled: Bool
    public let baseURL: URL

    public init(apiKey: String, enabled: Bool = false,
                baseURL: URL = URL(string: "https://otcharts.com")!) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.enabled = enabled
        self.baseURL = baseURL
    }
}

public final class NativeOTChartsTransport: OTChartsTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> OTChartsHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OTChartsError.invalidResponse }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return OTChartsHTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }

    public func events(for request: URLRequest) -> AsyncThrowingStream<OTChartsServerEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session] in
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw OTChartsError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        let retry = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init)
                        if http.statusCode == 429 { throw OTChartsError.throttled(retryAfterSeconds: retry) }
                        throw OTChartsError.httpStatus(http.statusCode)
                    }
                    var decoder = OTChartsSSEDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in decoder.consume(line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public actor OTChartsProvider: ShadowMarketObservationProvider {
    public nonisolated let sourceIdentity = ShadowDataSourceIdentity(
        providerID: "otcharts.pocket-option.v1", displayName: "OTCharts",
        venueID: "otc", directBrokerConnection: false)

    private let configuration: OTChartsConfiguration
    private let transport: any OTChartsTransport
    private let clock: any OTCResearchClock

    public init(configuration: OTChartsConfiguration,
                transport: any OTChartsTransport = NativeOTChartsTransport(),
                clock: any OTCResearchClock = SystemOTCResearchClock()) {
        self.configuration = configuration
        self.transport = transport
        self.clock = clock
    }

    public func instruments() async throws -> [ShadowInstrumentAvailability] {
        let request = try makeRequest(path: "/v1/symbols", query: [
            URLQueryItem(name: "venue", value: "otc")
        ])
        let response = try await checkedResponse(for: request)
        let payload = try JSONDecoder().decode(SymbolsEnvelope.self, from: response.data)
        // The official client reads only `symbols`; `venue` is informational when present.
        if let venue = payload.venue, venue != "otc" { throw OTChartsError.invalidResponse }
        return try payload.symbols.map { item in
            let identity = try identity(for: item.symbol, name: item.name)
            guard item.payout.map({ $0.isFinite && $0 >= 0 && $0 <= 100 }) ?? true else {
                throw OTChartsError.invalidResponse
            }
            return ShadowInstrumentAvailability(identity: identity, isOpen: item.open,
                                                payoutPercent: item.payout)
        }
    }

    public func candles(for identity: ShadowMarketIdentity, intervalSeconds: Int,
                        limit: Int) async throws -> [ShadowCandle] {
        try validate(identity)
        guard intervalSeconds > 0, (1...500).contains(limit) else { throw OTChartsError.invalidResponse }
        let request = try makeRequest(path: "/v1/candles", query: [
            URLQueryItem(name: "venue", value: "otc"),
            URLQueryItem(name: "symbol", value: identity.venueSymbol),
            URLQueryItem(name: "tf", value: String(intervalSeconds)),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let response = try await checkedResponse(for: request)
        let payload = try JSONDecoder().decode(CandlesEnvelope.self, from: response.data)
        // The documented response is `{"candles":[...]}` with no top-level symbol. Verify the
        // symbol only when the server supplies one.
        if let returned = payload.symbol, returned != identity.venueSymbol {
            throw OTChartsError.wrongInstrument(expected: identity.venueSymbol, received: returned)
        }
        let now = clock.now()
        return try payload.candles.enumerated().map { index, item in
            let stamp = ShadowProviderTimestamp(rawUnixSeconds: item.time,
                                                normalizationSeconds: Self.pocketOptionClockCorrection)
            guard item.time.isFinite, stamp.normalized <= now.addingTimeInterval(5) else {
                throw OTChartsError.staleOrOutOfOrder
            }
            let candle = ShadowCandle(identity: identity, intervalSeconds: intervalSeconds,
                providerTimestamp: stamp, open: item.open, high: item.high,
                low: item.low, close: item.close,
                complete: stamp.normalized.addingTimeInterval(TimeInterval(intervalSeconds)) <= now)
            guard candle.isValid,
                  index == 0 || payload.candles[index - 1].time < item.time else {
                throw OTChartsError.staleOrOutOfOrder
            }
            return candle
        }
    }

    public func updates(for identities: [ShadowMarketIdentity]) async throws
        -> AsyncThrowingStream<ShadowProviderUpdate, any Error> {
        guard !identities.isEmpty else { throw OTChartsError.invalidIdentity }
        try identities.forEach(validate)
        let uniqueSymbols = Array(Set(identities.map(\.venueSymbol))).sorted()
        guard uniqueSymbols.count == identities.count else { throw OTChartsError.invalidIdentity }
        let identityBySymbol = Dictionary(uniqueKeysWithValues: identities.map { ($0.venueSymbol, $0) })
        let request = try makeRequest(path: "/v1/stream", query: [
            URLQueryItem(name: "venue", value: "otc"),
            URLQueryItem(name: "symbol", value: uniqueSymbols.joined(separator: ",")),
        ], accept: "text/event-stream")
        let upstream = transport.events(for: request)
        let clock = self.clock
        let source = sourceIdentity
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastTimestampBySymbol: [String: Double] = [:]
                do {
                    continuation.yield(.connection(.connecting, reason: nil))
                    for try await event in upstream {
                        try Task.checkCancellation()
                        let payload = Data(event.data.utf8)
                        // OTCharts ticks are `data:` JSON lines and may omit the event name and
                        // (on a single-instrument stream) the symbol. The official client treats
                        // every data line as a tick candidate, so do the same before inspecting
                        // named control frames.
                        if let tick = try? JSONDecoder().decode(Tick.self, from: payload) {
                            let resolvedSymbol = tick.symbol
                                ?? (identities.count == 1 ? identities[0].venueSymbol : nil)
                            guard let resolvedSymbol,
                                  let identity = identityBySymbol[resolvedSymbol] else {
                                throw OTChartsError.wrongInstrument(
                                    expected: uniqueSymbols.joined(separator: ","),
                                    received: tick.symbol ?? "unlabelled")
                            }
                            guard tick.price.isFinite, tick.price > 0,
                                  tick.time.isFinite, tick.time > 0 else {
                                throw OTChartsError.invalidResponse
                            }
                            guard
                                  // Equal timestamps are legitimate: several prints can share the
                                  // same source second. Only a strictly older print is out of order.
                                  tick.time >= (lastTimestampBySymbol[resolvedSymbol] ?? -.infinity) else {
                                throw OTChartsError.staleOrOutOfOrder
                            }
                            let receivedAt = clock.now()
                            let normalizedTime = Date(timeIntervalSince1970:
                                tick.time + Self.pocketOptionClockCorrection)
                            guard normalizedTime <= receivedAt.addingTimeInterval(5) else {
                                throw OTChartsError.staleOrOutOfOrder
                            }
                            lastTimestampBySymbol[resolvedSymbol] = tick.time
                            let observation = ShadowMarketObservation(
                                // The server event id is untrusted, unbounded text; never persist it.
                                id: UUID().uuidString, source: source, identity: identity,
                                quote: ShadowQuote(price: tick.price),
                                providerTimestamp: ShadowProviderTimestamp(
                                    rawUnixSeconds: tick.time,
                                    normalizationSeconds: Self.pocketOptionClockCorrection),
                                receivedAt: receivedAt, connectionState: .live,
                                verification: .unverifiedVendorData,
                                provenance: "OTCharts venue=otc SSE tick; vendor attribution to Pocket Option is not independently verified")
                            guard observation.isValid else { throw OTChartsError.invalidResponse }
                            continuation.yield(.observation(observation))
                            continue
                        }
                        switch event.name {
                        case "connected":
                            continuation.yield(.connection(.live, reason: nil))
                        case "closed", "dropped":
                            continuation.yield(.connection(.degraded, reason: nil))
                        case "replaced":
                            throw OTChartsError.providerClosed("Stream replaced by a newer connection")
                        default:
                            // A connect frame may carry only the subscribed symbol list.
                            if let connected = try? JSONDecoder().decode(Connected.self, from: payload),
                               !connected.symbols.isEmpty {
                                continuation.yield(.connection(.live, reason: nil))
                            }
                            continue
                        }
                    }
                    continuation.yield(.connection(.disconnected, reason: "Stream ended"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// OTCharts documents the Pocket Option book's epoch values as broker UTC+2.
    /// Preserve the raw value and subtract two hours for UTC comparisons.
    public nonisolated static let pocketOptionClockCorrection: TimeInterval = -7_200

    private func validate(_ identity: ShadowMarketIdentity) throws {
        guard identity.marketKind == .otc, identity.venue == "Pocket Option",
              identity.settlementBasis == .venueDisplayed,
              identity.venueSymbol.hasSuffix("_otc") else { throw OTChartsError.invalidIdentity }
    }

    private func identity(for symbol: String, name: String) throws -> ShadowMarketIdentity {
        guard symbol.hasSuffix("_otc"), !name.isEmpty else { throw OTChartsError.invalidIdentity }
        return ShadowMarketIdentity(marketKind: .otc, venue: "Pocket Option", venueSymbol: symbol,
            displaySymbol: name, session: .weekendSession, settlementBasis: .venueDisplayed)
    }

    private func makeRequest(path: String, query: [URLQueryItem], accept: String = "application/json") throws -> URLRequest {
        guard configuration.enabled else { throw OTChartsError.disabled }
        guard !configuration.apiKey.isEmpty else { throw OTChartsError.invalidCredential }
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else {
            throw OTChartsError.invalidResponse
        }
        components.queryItems = query
        guard let url = components.url, url.scheme == "https" || configuration.baseURL.host == "localhost" else {
            throw OTChartsError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = accept == "text/event-stream" ? 86_400 : 15
        return request
    }

    private func checkedResponse(for request: URLRequest) async throws -> OTChartsHTTPResponse {
        let response = try await transport.data(for: request)
        if response.statusCode == 429 {
            throw OTChartsError.throttled(retryAfterSeconds: response.headers["retry-after"].flatMap(Int.init))
        }
        guard (200..<300).contains(response.statusCode) else { throw OTChartsError.httpStatus(response.statusCode) }
        return response
    }
}

private struct SymbolsEnvelope: Decodable {
    let venue: String?
    let symbols: [SymbolItem]
}

private struct SymbolItem: Decodable {
    let symbol: String
    let name: String
    let payout: Double?
    let open: Bool?
}

private struct CandlesEnvelope: Decodable {
    let symbol: String?
    let candles: [CandleItem]
}

private struct CandleItem: Decodable {
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let time: Double
}

private struct Connected: Decodable {
    let symbols: [String]
}

private struct Tick: Decodable {
    let symbol: String?
    let price: Double
    let time: Double

    private enum CodingKeys: String, CodingKey {
        case symbol, price, close, time
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Double.self, forKey: .time)
        if let price = try container.decodeIfPresent(Double.self, forKey: .price) {
            self.price = price
        } else if let close = try container.decodeIfPresent(Double.self, forKey: .close) {
            self.price = close
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .price, in: container,
                debugDescription: "tick payload has neither price nor close")
        }
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
    }
}
