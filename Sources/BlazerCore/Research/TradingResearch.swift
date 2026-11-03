import CryptoKit
import Foundation

/// A candle shape accepted by TradingView Lightweight Charts. The source remains attached
/// to the series; the chart format does not imply that TradingView supplied the data.
public struct TradingViewCompatibleCandle: Codable, Sendable, Equatable {
    public let time: Int
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(time: Int, open: Double, high: Double, low: Double, close: Double) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    public init(_ candle: ShadowCandle) throws {
        let timestamp = candle.providerTimestamp.normalized.timeIntervalSince1970
        guard timestamp.isFinite, timestamp >= 0, timestamp <= Double(Int.max),
              candle.isValid, candle.complete else {
            throw TradingResearchError.invalidCandle
        }
        self.init(time: Int(timestamp), open: candle.open, high: candle.high,
                  low: candle.low, close: candle.close)
    }
}

public struct TradingViewCompatibleSeries: Codable, Sendable, Equatable {
    public let source: ShadowDataSourceIdentity
    public let identity: ShadowMarketIdentity
    public let intervalSeconds: Int
    public let candles: [TradingViewCompatibleCandle]

    public init(source: ShadowDataSourceIdentity, identity: ShadowMarketIdentity,
                intervalSeconds: Int, candles: [TradingViewCompatibleCandle]) throws {
        guard intervalSeconds > 0, !candles.isEmpty,
              candles.allSatisfy({ $0.open > 0 && $0.high >= max($0.open, $0.close)
                  && $0.low <= min($0.open, $0.close) && $0.low > 0 }) else {
            throw TradingResearchError.invalidSeries
        }
        self.source = source
        self.identity = identity
        self.intervalSeconds = intervalSeconds
        self.candles = candles
    }

    public init(source: ShadowDataSourceIdentity, candles: [ShadowCandle]) throws {
        guard let first = candles.first,
              candles.allSatisfy({ $0.identity == first.identity
                  && $0.intervalSeconds == first.intervalSeconds }) else {
            throw TradingResearchError.invalidSeries
        }
        try self.init(source: source, identity: first.identity,
                      intervalSeconds: first.intervalSeconds,
                      candles: try candles.map(TradingViewCompatibleCandle.init))
    }
}

public struct PineScriptWebhookAlert: Codable, Sendable, Equatable {
    public let id: String
    public let symbol: String
    public let direction: String
    public let timestamp: Date
    public let price: Double
    public let timeframeSeconds: Int
    public let strategyVersion: String
    public let source: String

    public init(id: String, symbol: String, direction: String, timestamp: Date,
                price: Double, timeframeSeconds: Int, strategyVersion: String,
                source: String = "tradingview-pine") {
        self.id = id
        self.symbol = symbol
        self.direction = direction
        self.timestamp = timestamp
        self.price = price
        self.timeframeSeconds = timeframeSeconds
        self.strategyVersion = strategyVersion
        self.source = source
    }

    public var isValid: Bool {
        !id.isEmpty && !symbol.isEmpty && ["HIGH", "LOW"].contains(direction)
            && timestamp.timeIntervalSince1970.isFinite && price.isFinite && price > 0
            && timeframeSeconds > 0 && !strategyVersion.isEmpty
            && source == "tradingview-pine"
    }
}

public enum TradingResearchError: Error, Sendable, Equatable {
    case invalidCandle
    case invalidSeries
    case invalidAlert
    case unauthorized
    case staleAlert
    case duplicateAlert
    case replayedAlert
    case missingObservation
    case mismatchedSource
    case replayStorageFailure
}

/// Minimal webhook boundary. It is intentionally transport-agnostic so an HTTP server can
/// be added by the host app without adding a broker, chart vendor, or network listener here.
public actor PineScriptWebhookStore {
    private var acceptedIDs: Set<String> = []
    private var latestTimestampByID: [String: Date] = [:]
    private let secret: Data
    private let maxClockSkew: TimeInterval
    private let replayURL: URL
    private var replayLoaded = false

    public init(secret: String, maxClockSkew: TimeInterval = 120,
                replayURL: URL = FileLocations.applicationSupport()
                    .appendingPathComponent("Research/pine-webhook-replay.json")) {
        self.secret = Data(secret.utf8)
        self.maxClockSkew = maxClockSkew
        self.replayURL = replayURL
    }

    public func ingest(_ data: Data, authorization: String, now: Date = Date())
        throws -> PineScriptWebhookAlert {
        try loadReplayState()
        guard !secret.isEmpty else { throw TradingResearchError.unauthorized }
        let expected = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: secret))
        let expectedData = Data(expected)
        let supplied = Data(hex: authorization)
        guard let supplied, supplied.count == expectedData.count,
              supplied.elementsEqual(expectedData) else {
            throw TradingResearchError.unauthorized
        }
        let alert: PineScriptWebhookAlert
        do {
            alert = try JSONDecoder().decode(PineScriptWebhookAlert.self, from: data)
        } catch {
            throw TradingResearchError.invalidAlert
        }
        guard alert.isValid else { throw TradingResearchError.invalidAlert }
        guard maxClockSkew.isFinite, maxClockSkew >= 0,
              abs(now.timeIntervalSince(alert.timestamp)) <= maxClockSkew else {
            throw TradingResearchError.staleAlert
        }
        guard !acceptedIDs.contains(alert.id) else { throw TradingResearchError.duplicateAlert }
        guard latestTimestampByID[alert.id] == nil else { throw TradingResearchError.replayedAlert }
        acceptedIDs.insert(alert.id)
        latestTimestampByID[alert.id] = alert.timestamp
        try persistReplayState()
        return alert
    }

    private func loadReplayState() throws {
        guard !replayLoaded else { return }
        replayLoaded = true
        guard FileManager.default.fileExists(atPath: replayURL.path) else { return }
        do {
            let data = try Data(contentsOf: replayURL)
            let values = try JSONDecoder().decode([String: Date].self, from: data)
            latestTimestampByID = values
            acceptedIDs = Set(values.keys)
        } catch {
            throw TradingResearchError.replayStorageFailure
        }
    }

    private func persistReplayState() throws {
        do {
            let parent = replayURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(latestTimestampByID)
            try AtomicFile.write(data, to: replayURL)
        } catch {
            throw TradingResearchError.replayStorageFailure
        }
    }
}

private extension Data {
    init?(hex: String) {
        let chars = Array(hex)
        guard chars.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[index...index + 1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}

public struct ResearchSignalComparison: Codable, Sendable, Equatable {
    public let authoritativeSide: String
    public let externalSide: String
    public let agrees: Bool
    public let authoritativeTimestamp: Date
    public let externalTimestamp: Date
    public let source: String
    public let researchOnly: Bool

    public init(authoritative: EngineSignal, external: PineScriptWebhookAlert) throws {
        guard authoritative.cabinetSide == "HIGH" || authoritative.cabinetSide == "LOW",
              external.isValid, authoritative.asset == external.symbol else {
            throw TradingResearchError.invalidAlert
        }
        guard let milliseconds = authoritative.asOfMs,
              milliseconds.isFinite else { throw TradingResearchError.invalidAlert }
        self.authoritativeSide = authoritative.cabinetSide
        self.externalSide = external.direction
        self.agrees = authoritative.cabinetSide == external.direction
        self.authoritativeTimestamp = Date(timeIntervalSince1970: milliseconds / 1000)
        self.externalTimestamp = external.timestamp
        self.source = external.source
        self.researchOnly = true
    }
}

public struct SixtySecondReplayResult: Codable, Sendable, Equatable {
    public let alertID: String
    public let direction: String
    public let entryAt: Date
    public let expiryAt: Date
    public let entryPrice: Double?
    public let expiryPrice: Double?
    public let resolution: ValidationResolution
    public let source: String
    public let reason: String?
    public let researchOnly: Bool

    public init(alert: PineScriptWebhookAlert, observations: [ValidationPriceObservation],
                entryDelaySeconds: TimeInterval = 0, toleranceSeconds: TimeInterval = 2) {
        let entryAt = alert.timestamp.addingTimeInterval(entryDelaySeconds)
        let expiryAt = entryAt.addingTimeInterval(60)
        let matching: (Date, Double)? = observations
            .filter { $0.instrumentID == alert.symbol && $0.venueID == alert.source
                && $0.authority != .directBroker
                && abs($0.observedAt.timeIntervalSince(entryAt)) <= toleranceSeconds }
            .sorted { $0.observedAt < $1.observedAt }
            .first
            .map { ($0.observedAt, $0.price) }
        let expiry: (Date, Double)? = observations
            .filter { $0.instrumentID == alert.symbol && $0.venueID == alert.source
                && abs($0.observedAt.timeIntervalSince(expiryAt)) <= toleranceSeconds
                && $0.observedAt >= expiryAt }
            .sorted { $0.observedAt < $1.observedAt }
            .first
            .map { ($0.observedAt, $0.price) }
        self.alertID = alert.id
        self.direction = alert.direction
        self.entryAt = entryAt
        self.expiryAt = expiryAt
        self.entryPrice = matching?.1
        self.expiryPrice = expiry?.1
        self.source = alert.source
        self.researchOnly = true
        guard let matching, let expiry else {
            self.resolution = .unresolved
            self.reason = "Timely source-matched observation missing"
            return
        }
        if expiry.1 == matching.1 { self.resolution = .tie }
        else {
            let wins = alert.direction == "HIGH" ? expiry.1 > matching.1 : expiry.1 < matching.1
            self.resolution = wins ? .win : .loss
        }
        self.reason = nil
    }
}
