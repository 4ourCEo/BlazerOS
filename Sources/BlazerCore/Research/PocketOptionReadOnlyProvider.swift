import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PocketOptionSocketFrame: Sendable, Equatable {
    case text(String)
    case data(Data)
}

public protocol PocketOptionReadOnlyTransport: Sendable {
    func connect(_ request: URLRequest) async throws
        -> AsyncThrowingStream<PocketOptionSocketFrame, any Error>
    func send(_ text: String) async throws
    func disconnect() async
}

public enum PocketOptionReadOnlyError: Error, Sendable, Equatable {
    case disabled
    case invalidCredential
    case invalidIdentity
    case invalidResponse
    case authenticationRejected
    case connectionClosed
    case connectionAlreadyOpen
    case wrongInstrument(expected: String, received: String)
    case staleOrOutOfOrder
    case historicalCandlesUnavailable
}

public struct PocketOptionReadOnlyConfiguration: Sendable {
    public let authFrame: String
    public let enabled: Bool
    public let endpoint: URL

    public init(
        authFrame: String,
        enabled: Bool = false,
        endpoint: URL = URL(
            string: "wss://demo-api-eu.po.market/socket.io/?EIO=4&transport=websocket"
        )!
    ) {
        self.authFrame = authFrame.trimmingCharacters(in: .whitespacesAndNewlines)
        self.enabled = enabled
        self.endpoint = endpoint
    }
}

public actor NativePocketOptionReadOnlyTransport: PocketOptionReadOnlyTransport {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(_ request: URLRequest) async throws
        -> AsyncThrowingStream<PocketOptionSocketFrame, any Error> {
        await disconnect()
        // Pocket Option may not accept an immediate replacement for the same demo session.
        try await Task.sleep(for: .milliseconds(500))
        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()

        return AsyncThrowingStream { continuation in
            let receiver = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        guard let message = try await self?.task?.receive() else {
                            throw PocketOptionReadOnlyError.connectionClosed
                        }
                        switch message {
                        case .string(let value): continuation.yield(.text(value))
                        case .data(let value): continuation.yield(.data(value))
                        @unknown default: throw PocketOptionReadOnlyError.invalidResponse
                        }
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                receiver.cancel()
            }
        }
    }

    public func send(_ text: String) async throws {
        guard let task else { throw PocketOptionReadOnlyError.connectionClosed }
        try await task.send(.string(text))
    }

    public func disconnect() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

public actor PocketOptionReadOnlyProvider: ShadowMarketObservationProvider {
    public nonisolated let sourceIdentity = ShadowDataSourceIdentity(
        providerID: "pocket-option.direct.read-only.v1",
        displayName: "Pocket Option (direct read-only)",
        venueID: "pocket-option",
        directBrokerConnection: true
    )

    public nonisolated static let brokerClockCorrection: TimeInterval = -7_200

    private let configuration: PocketOptionReadOnlyConfiguration
    private let transport: any PocketOptionReadOnlyTransport
    private let clock: any OTCResearchClock
    private var activeStreamID: UUID?

    public init(
        configuration: PocketOptionReadOnlyConfiguration,
        transport: any PocketOptionReadOnlyTransport = NativePocketOptionReadOnlyTransport(),
        clock: any OTCResearchClock = SystemOTCResearchClock()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.clock = clock
    }

    public func instruments() async throws -> [ShadowInstrumentAvailability] {
        try validateConfiguration()
        // Declare only the configured research identity here. Actual open state and payout are
        // accepted only from the broker asset frame on the single quote connection.
        return [ShadowInstrumentAvailability(
            identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
            isOpen: nil,
            payoutPercent: nil
        )]
    }

    public func candles(
        for identity: ShadowMarketIdentity,
        intervalSeconds: Int,
        limit: Int
    ) async throws -> [ShadowCandle] {
        try validate(identity)
        guard intervalSeconds > 0, limit > 0 else {
            throw PocketOptionReadOnlyError.invalidResponse
        }
        throw PocketOptionReadOnlyError.historicalCandlesUnavailable
    }

    public func updates(for identities: [ShadowMarketIdentity]) async throws
        -> AsyncThrowingStream<ShadowProviderUpdate, any Error> {
        try validateConfiguration()
        guard activeStreamID == nil else {
            throw PocketOptionReadOnlyError.connectionAlreadyOpen
        }
        guard identities.count == 1, let identity = identities.first else {
            throw PocketOptionReadOnlyError.invalidIdentity
        }
        try validate(identity)
        let streamID = UUID()
        activeStreamID = streamID
        let frames: AsyncThrowingStream<PocketOptionSocketFrame, any Error>
        do {
            frames = try await transport.connect(makeRequest())
        } catch {
            activeStreamID = nil
            throw error
        }
        let source = sourceIdentity
        let clock = self.clock

        return AsyncThrowingStream { continuation in
            let task = Task {
                var state = ProtocolState()
                var lastTimestamp = -Double.infinity
                do {
                    continuation.yield(.connection(.connecting, reason: nil))
                    for try await frame in frames {
                        try Task.checkCancellation()
                        let output = try await self.consume(
                            frame,
                            state: &state,
                            expectedSymbol: identity.venueSymbol
                        )
                        // Authentication alone is not healthy market data. The desk moves to
                        // LIVE only after the first validated observation arrives.
                        for tick in output.ticks {
                            guard tick.timestamp >= lastTimestamp else {
                                throw PocketOptionReadOnlyError.staleOrOutOfOrder
                            }
                            lastTimestamp = tick.timestamp
                            let receivedAt = clock.now()
                            let stamp = ShadowProviderTimestamp(
                                rawUnixSeconds: tick.timestamp,
                                normalizationSeconds: Self.brokerClockCorrection
                            )
                            guard stamp.normalized <= receivedAt.addingTimeInterval(5),
                                  receivedAt.timeIntervalSince(stamp.normalized) <= 10 else {
                                throw PocketOptionReadOnlyError.staleOrOutOfOrder
                            }
                            guard let payout = state.payoutBySymbol[tick.symbol],
                                  let marketOpen = state.openBySymbol[tick.symbol] else {
                                throw PocketOptionReadOnlyError.invalidResponse
                            }
                            let observation = ShadowMarketObservation(
                                source: source,
                                identity: identity,
                                quote: ShadowQuote(price: tick.price),
                                providerTimestamp: stamp,
                                receivedAt: receivedAt,
                                payoutPercent: payout,
                                marketOpen: marketOpen,
                                connectionState: .live,
                                verification: .unverifiedVendorData,
                                provenance: "Direct Pocket Option demo-account WebSocket tick; the transport path was manually compared with the visible EUR/USD OTC chart on 2026-10-24, but this individual tick was not manually matched",
                                researchOnly: true,
                                mayAuthorizeEntry: false
                            )
                            guard observation.isValid else {
                                throw PocketOptionReadOnlyError.invalidResponse
                            }
                            continuation.yield(.observation(observation))
                        }
                    }
                    continuation.yield(.connection(.disconnected, reason: "Stream ended"))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.finishStream(streamID)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.finishStream(streamID) }
            }
        }
    }

    private func finishStream(_ streamID: UUID) async {
        guard activeStreamID == streamID else { return }
        activeStreamID = nil
        await transport.disconnect()
    }

    private func validateConfiguration() throws {
        guard configuration.enabled else { throw PocketOptionReadOnlyError.disabled }
        guard configuration.endpoint.scheme == "wss",
              Self.isValidAuthFrame(configuration.authFrame) else {
            throw PocketOptionReadOnlyError.invalidCredential
        }
    }

    private func validate(_ identity: ShadowMarketIdentity) throws {
        guard identity.marketKind == .otc,
              identity.venue == "Pocket Option",
              identity.settlementBasis == .venueDisplayed,
              identity.venueSymbol.hasSuffix("_otc") else {
            throw PocketOptionReadOnlyError.invalidIdentity
        }
    }

    private func makeRequest() -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.timeoutInterval = 15
        request.setValue("https://pocketoption.com", forHTTPHeaderField: "Origin")
        return request
    }

    private func consume(
        _ frame: PocketOptionSocketFrame,
        state: inout ProtocolState,
        expectedSymbol: String?
    ) async throws -> ProtocolOutput {
        switch frame {
        case .text(let text):
            if text == "2" {
                try await transport.send("3")
                return ProtocolOutput()
            }
            if text.hasPrefix("0") {
                try await transport.send("40")
                return ProtocolOutput()
            }
            if text.hasPrefix("40") {
                try await transport.send(configuration.authFrame)
                return ProtocolOutput()
            }
            if text == "41" || text.contains("NotAuthorized") || text.contains("auth_error") {
                throw PocketOptionReadOnlyError.authenticationRejected
            }
            if text.hasPrefix("451-") {
                state.pendingBinaryEvent = Self.socketEventName(text)
                return ProtocolOutput()
            }
            if let event = Self.socketEvent(text) {
                return try await consume(event: event, state: &state, expectedSymbol: expectedSymbol)
            }
            return ProtocolOutput(ticks: try Self.decodeTicks(Data(text.utf8), expectedSymbol: expectedSymbol))
        case .data(let data):
            defer { state.pendingBinaryEvent = nil }
            if state.pendingBinaryEvent == "successauth" {
                return try await consume(
                    event: SocketEvent(name: "successauth", payload: data),
                    state: &state,
                    expectedSymbol: expectedSymbol
                )
            }
            if state.pendingBinaryEvent == "updateAssets" {
                let instruments = try Self.decodeAssets(data, state: &state)
                return ProtocolOutput(instruments: instruments)
            }
            if state.pendingBinaryEvent == "updateStream" {
                return ProtocolOutput(ticks: try Self.decodeTicks(
                    data,
                    expectedSymbol: expectedSymbol
                ))
            }
            // Account and chart frames are deliberately ignored. Only the explicitly named
            // read-only market-data frames above may enter the research pipeline.
            if state.pendingBinaryEvent != nil { return ProtocolOutput() }
            return ProtocolOutput(ticks: try Self.decodeTicks(data, expectedSymbol: expectedSymbol))
        }
    }

    private func consume(
        event: SocketEvent,
        state: inout ProtocolState,
        expectedSymbol: String?
    ) async throws -> ProtocolOutput {
        switch event.name {
        case "successauth":
            try await transport.send(#"42["assets/load"]"#)
            if let expectedSymbol {
                try await transport.send(#"42["changeSymbol",{"asset":"\#(expectedSymbol)","period":60}]"#)
                try await transport.send(#"42["subfor","\#(expectedSymbol)"]"#)
            }
            return ProtocolOutput()
        case "updateAssets":
            let instruments = try Self.decodeAssets(event.payload, state: &state)
            return ProtocolOutput(instruments: instruments)
        case "updateStream":
            return ProtocolOutput(ticks: try Self.decodeTicks(event.payload, expectedSymbol: expectedSymbol))
        default:
            return ProtocolOutput()
        }
    }

    public nonisolated static func isValidAuthFrame(_ frame: String) -> Bool {
        guard frame.hasPrefix(#"42["auth",{"#),
              let data = frame.dropFirst(2).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count == 2, array[0] as? String == "auth",
              let payload = array[1] as? [String: Any] else { return false }
        let hasSession = (payload["session"] as? String)?.isEmpty == false
        let isDemo = (payload["isDemo"] as? NSNumber)?.intValue == 1
        return hasSession && isDemo
    }

    private nonisolated static func socketEventName(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "[") else { return nil }
        let payload = String(text[start...])
        guard let data = payload.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return array.first as? String
    }

    private nonisolated static func socketEvent(_ text: String) -> SocketEvent? {
        guard text.hasPrefix("42"), let data = text.dropFirst(2).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String else { return nil }
        let payload = array.count > 1 ? array[1] : NSNull()
        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return SocketEvent(name: name, payload: payloadData)
    }

    private nonisolated static func decodeTicks(
        _ data: Data,
        expectedSymbol: String?
    ) throws -> [Tick] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return try rows.compactMap { row in
            guard row.count >= 3,
                  let symbol = row[0] as? String,
                  let timestamp = (row[1] as? NSNumber)?.doubleValue,
                  let price = (row[2] as? NSNumber)?.doubleValue,
                  timestamp.isFinite, timestamp > 0, price.isFinite, price > 0 else {
                throw PocketOptionReadOnlyError.invalidResponse
            }
            if let expectedSymbol, symbol != expectedSymbol {
                throw PocketOptionReadOnlyError.wrongInstrument(
                    expected: expectedSymbol,
                    received: symbol
                )
            }
            return Tick(symbol: symbol, timestamp: timestamp, price: price)
        }
    }

    private nonisolated static func decodeAssets(
        _ data: Data,
        state: inout ProtocolState
    ) throws -> [ShadowInstrumentAvailability] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            throw PocketOptionReadOnlyError.invalidResponse
        }
        state.payoutBySymbol.removeAll(keepingCapacity: true)
        state.openBySymbol.removeAll(keepingCapacity: true)
        return rows.compactMap { row in
            guard row.count > 15,
                  let symbol = row[1] as? String,
                  let name = row[2] as? String,
                  let payout = (row[5] as? NSNumber)?.doubleValue,
                  let otc = (row[9] as? NSNumber)?.intValue,
                  otc == 1, symbol.hasSuffix("_otc"), payout.isFinite,
                  (0...100).contains(payout) else { return nil }
            let active: Bool
            if let value = row[14] as? Bool {
                active = value
            } else if let value = row[14] as? NSNumber {
                active = value.intValue != 0
            } else {
                return nil
            }
            state.payoutBySymbol[symbol] = payout
            state.openBySymbol[symbol] = active
            let identity = ShadowMarketIdentity(
                marketKind: .otc,
                venue: "Pocket Option",
                venueSymbol: symbol,
                displaySymbol: name,
                session: .weekendSession,
                settlementBasis: .venueDisplayed
            )
            return ShadowInstrumentAvailability(
                identity: identity,
                isOpen: active,
                payoutPercent: payout
            )
        }
    }
}

private struct SocketEvent: Sendable {
    let name: String
    let payload: Data
}

private struct Tick: Sendable {
    let symbol: String
    let timestamp: Double
    let price: Double
}

private struct ProtocolOutput: Sendable {
    var instruments: [ShadowInstrumentAvailability]?
    var ticks: [Tick] = []
}

private struct ProtocolState: Sendable {
    var pendingBinaryEvent: String?
    var payoutBySymbol: [String: Double] = [:]
    var openBySymbol: [String: Bool] = [:]
}
