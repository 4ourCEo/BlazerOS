import Foundation

public struct ShadowDataSourceIdentity: Codable, Sendable, Equatable {
    public let providerID: String
    public let displayName: String
    public let venueID: String
    public let directBrokerConnection: Bool

    public init(providerID: String, displayName: String, venueID: String, directBrokerConnection: Bool) {
        self.providerID = providerID
        self.displayName = displayName
        self.venueID = venueID
        self.directBrokerConnection = directBrokerConnection
    }
}

public enum ShadowConnectionState: String, Codable, Sendable, Equatable {
    case disabled, connecting, live, degraded, throttled, disconnected
}

public struct ShadowInstrumentAvailability: Codable, Sendable, Equatable {
    public let identity: ShadowMarketIdentity
    public let isOpen: Bool?
    public let payoutPercent: Double?

    public init(identity: ShadowMarketIdentity, isOpen: Bool?, payoutPercent: Double?) {
        self.identity = identity
        self.isOpen = isOpen
        self.payoutPercent = payoutPercent
    }
}

public enum ShadowProviderUpdate: Sendable, Equatable {
    case connection(ShadowConnectionState, reason: String?)
    case observation(ShadowMarketObservation)
}

/// Interchangeable research-only provider boundary. It deliberately has no order method.
public protocol ShadowMarketObservationProvider: Sendable {
    var sourceIdentity: ShadowDataSourceIdentity { get }
    func instruments() async throws -> [ShadowInstrumentAvailability]
    func candles(for identity: ShadowMarketIdentity, intervalSeconds: Int, limit: Int) async throws -> [ShadowCandle]
    func updates(for identities: [ShadowMarketIdentity]) async throws
        -> AsyncThrowingStream<ShadowProviderUpdate, any Error>
}

public enum ShadowVerificationState: String, Codable, Sendable, Equatable {
    case unverifiedVendorData
    case manuallyMatched
    case independentlyVerified
    case syntheticTestFixture
}

public enum ShadowFreshness: String, Codable, Sendable, Equatable {
    case fresh, aging, expired

    public static func classify(sourceTime: Date, receivedAt: Date, now: Date,
                                freshFor: TimeInterval = 3, expiresAfter: TimeInterval = 10) -> Self {
        guard sourceTime <= now, receivedAt <= now, freshFor >= 0, expiresAfter >= freshFor else { return .expired }
        let age = max(now.timeIntervalSince(sourceTime), now.timeIntervalSince(receivedAt))
        if age <= freshFor { return .fresh }
        if age <= expiresAfter { return .aging }
        return .expired
    }
}

/// Keeps the provider's original epoch value alongside the documented normalization.
public struct ShadowProviderTimestamp: Codable, Sendable, Equatable {
    public let rawUnixSeconds: Double
    public let normalizationSeconds: Double

    public init(rawUnixSeconds: Double, normalizationSeconds: Double = 0) {
        self.rawUnixSeconds = rawUnixSeconds
        self.normalizationSeconds = normalizationSeconds
    }

    public var normalized: Date { Date(timeIntervalSince1970: rawUnixSeconds + normalizationSeconds) }
}

public struct ShadowQuote: Codable, Sendable, Equatable {
    public let price: Double
    public let bid: Double?
    public let ask: Double?

    public init(price: Double, bid: Double? = nil, ask: Double? = nil) {
        self.price = price
        self.bid = bid
        self.ask = ask
    }

    public var isValid: Bool {
        price.isFinite && price > 0
            && bid.map { $0.isFinite && $0 > 0 }.unwrap(or: true)
            && ask.map { $0.isFinite && $0 > 0 }.unwrap(or: true)
            && !(bid != nil && ask != nil && bid! > ask!)
    }
}

public struct ShadowCandle: Codable, Sendable, Equatable {
    public let identity: ShadowMarketIdentity
    public let intervalSeconds: Int
    public let providerTimestamp: ShadowProviderTimestamp
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(identity: ShadowMarketIdentity, intervalSeconds: Int,
                providerTimestamp: ShadowProviderTimestamp, open: Double, high: Double,
                low: Double, close: Double, complete: Bool) {
        self.identity = identity
        self.intervalSeconds = intervalSeconds
        self.providerTimestamp = providerTimestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.complete = complete
    }

    public var isValid: Bool {
        intervalSeconds > 0 && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && low <= min(open, close) && high >= max(open, close) && low <= high
    }
}

public struct ShadowMarketObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let source: ShadowDataSourceIdentity
    public let identity: ShadowMarketIdentity
    public let quote: ShadowQuote
    public let candle: ShadowCandle?
    public let providerTimestamp: ShadowProviderTimestamp
    public let receivedAt: Date
    public let payoutPercent: Double?
    public let marketOpen: Bool?
    public let connectionState: ShadowConnectionState
    public let verification: ShadowVerificationState
    public let provenance: String
    public let researchOnly: Bool
    public let mayAuthorizeEntry: Bool

    public init(id: String = UUID().uuidString, source: ShadowDataSourceIdentity,
                identity: ShadowMarketIdentity, quote: ShadowQuote, candle: ShadowCandle? = nil,
                providerTimestamp: ShadowProviderTimestamp, receivedAt: Date,
                payoutPercent: Double? = nil, marketOpen: Bool? = nil,
                connectionState: ShadowConnectionState, verification: ShadowVerificationState,
                provenance: String, researchOnly: Bool = true, mayAuthorizeEntry: Bool = false) {
        self.id = id
        self.source = source
        self.identity = identity
        self.quote = quote
        self.candle = candle
        self.providerTimestamp = providerTimestamp
        self.receivedAt = receivedAt
        self.payoutPercent = payoutPercent
        self.marketOpen = marketOpen
        self.connectionState = connectionState
        self.verification = verification
        self.provenance = provenance
        self.researchOnly = researchOnly
        self.mayAuthorizeEntry = mayAuthorizeEntry
    }

    public func freshness(at now: Date) -> ShadowFreshness {
        .classify(sourceTime: providerTimestamp.normalized, receivedAt: receivedAt, now: now)
    }

    public var isValid: Bool {
        !id.isEmpty && !source.providerID.isEmpty && !identity.venueSymbol.isEmpty
            && quote.isValid
            // A candle attached to a quote must describe the same instrument and interval.
            && candle.map { $0.isValid && $0.identity == identity && $0.intervalSeconds > 0 }.unwrap(or: true)
            && payoutPercent.map { $0.isFinite && $0 >= 0 && $0 <= 100 }.unwrap(or: true)
            && !provenance.isEmpty && researchOnly && !mayAuthorizeEntry
    }

    public var point: ShadowMarketDataPoint {
        ShadowMarketDataPoint(identity: identity, providerID: source.providerID,
            sourceTime: providerTimestamp.normalized, receivedAt: receivedAt,
            price: quote.price, provenance: provenance,
            status: verification == .independentlyVerified ? .verified : .unverified)
    }
}

private extension Optional where Wrapped == Bool {
    func unwrap(or fallback: Bool) -> Bool { self ?? fallback }
}

public enum ManualAgreement: String, Codable, Sendable, Equatable, CaseIterable {
    case agrees, discrepancy, notAssessed
}

public enum ManualVerificationConfidence: String, Codable, Sendable, Equatable, CaseIterable {
    case low, medium, high
}

public struct ManualBrokerChartObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let identity: ShadowMarketIdentity
    public let observedAt: Date
    public let brokerDisplayedPrice: Double
    public let providerObservationID: String?
    public let providerPrice: Double?
    public let candleTimestamp: Date?
    public let payoutPercent: Double?
    public let screenshotReference: String?
    public let agreement: ManualAgreement
    public let confidence: ManualVerificationConfidence
    public let provenance: String
    public let researchOnly: Bool
    public let mayAuthorizeEntry: Bool

    public init(id: String = UUID().uuidString, identity: ShadowMarketIdentity, observedAt: Date,
                brokerDisplayedPrice: Double, providerObservationID: String? = nil,
                providerPrice: Double? = nil, candleTimestamp: Date? = nil,
                payoutPercent: Double? = nil, screenshotReference: String? = nil,
                agreement: ManualAgreement, confidence: ManualVerificationConfidence) {
        self.id = id
        self.identity = identity
        self.observedAt = observedAt
        self.brokerDisplayedPrice = brokerDisplayedPrice
        self.providerObservationID = providerObservationID
        self.providerPrice = providerPrice
        self.candleTimestamp = candleTimestamp
        self.payoutPercent = payoutPercent
        self.screenshotReference = screenshotReference
        self.agreement = agreement
        self.confidence = confidence
        self.provenance = "Manual observation of the account owner's visible Pocket Option chart"
        self.researchOnly = true
        self.mayAuthorizeEntry = false
    }

    public var isValid: Bool {
        !id.isEmpty && identity.marketKind == .otc && observedAt <= Date()
            && brokerDisplayedPrice.isFinite && brokerDisplayedPrice > 0
            && providerPrice.map { $0.isFinite && $0 > 0 }.unwrap(or: true)
            && payoutPercent.map { $0.isFinite && $0 >= 0 && $0 <= 100 }.unwrap(or: true)
            // The captured candle must not post-date the observation that references it.
            && candleTimestamp.map { $0 <= observedAt }.unwrap(or: true)
            && screenshotReference.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.unwrap(or: true)
            && researchOnly && !mayAuthorizeEntry
    }
}

