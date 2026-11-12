import Foundation

/// The instrument contract is deliberately more specific than a display ticker.
public enum ShadowMarketKind: String, Codable, Sendable, Equatable { case standard, otc }
public enum ShadowSessionKind: String, Codable, Sendable, Equatable { case regularSession, weekendSession }
public enum ShadowSettlementBasis: String, Codable, Sendable, Equatable { case spotReference, venueDisplayed }

public struct ShadowMarketIdentity: Codable, Sendable, Equatable {
    public let marketKind: ShadowMarketKind
    public let venue: String
    public let venueSymbol: String
    public let displaySymbol: String
    public let session: ShadowSessionKind
    public let settlementBasis: ShadowSettlementBasis

    public init(marketKind: ShadowMarketKind, venue: String, venueSymbol: String,
                displaySymbol: String, session: ShadowSessionKind,
                settlementBasis: ShadowSettlementBasis) {
        self.marketKind = marketKind
        self.venue = venue
        self.venueSymbol = venueSymbol
        self.displaySymbol = displaySymbol
        self.session = session
        self.settlementBasis = settlementBasis
    }
}

public enum ShadowPointStatus: String, Codable, Sendable, Equatable { case unavailable, unverified, syntheticDocumentationOnly, verified }

public struct ShadowMarketDataPoint: Codable, Sendable, Equatable {
    public let identity: ShadowMarketIdentity
    public let providerID: String
    public let sourceTime: Date
    public let receivedAt: Date
    public let price: Double
    public let provenance: String
    public let status: ShadowPointStatus

    public init(identity: ShadowMarketIdentity, providerID: String, sourceTime: Date,
                receivedAt: Date, price: Double, provenance: String, status: ShadowPointStatus) {
        self.identity = identity
        self.providerID = providerID
        self.sourceTime = sourceTime
        self.receivedAt = receivedAt
        self.price = price
        self.provenance = provenance
        self.status = status
    }
}

public enum ShadowMarketDataError: Error, Sendable, Equatable { case disabled, invalidPoint }

/// Read-only boundary. Implementations return observations and expose no order methods.
public protocol ShadowMarketDataProvider: Sendable {
    func point(for identity: ShadowMarketIdentity, at time: Date) async throws -> ShadowMarketDataPoint
}

/// Safe default: no transport, credentials, or market observations are configured.
public struct DisabledShadowMarketDataProvider: ShadowMarketDataProvider {
    public init() {}
    public func point(for identity: ShadowMarketIdentity, at time: Date) async throws -> ShadowMarketDataPoint {
        throw ShadowMarketDataError.disabled
    }
}

public enum ShadowMarketDataFixtures {
    public static let standardEURUSD = ShadowMarketIdentity(
        marketKind: .standard, venue: "reference", venueSymbol: "EUR/USD",
        displaySymbol: "EUR/USD", session: .regularSession, settlementBasis: .spotReference)
    public static let pocketOptionEURUSDOTC = ShadowMarketIdentity(
        marketKind: .otc, venue: "Pocket Option", venueSymbol: "EURUSD_otc",
        displaySymbol: "EUR/USD OTC", session: .weekendSession, settlementBasis: .venueDisplayed)

    /// Deterministic examples for documentation and tests; never verified records.
    public static func points(at time: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> [ShadowMarketDataPoint] {
        [
            ShadowMarketDataPoint(identity: standardEURUSD, providerID: "fixture.standard.v1",
                sourceTime: time, receivedAt: time, price: 1.1,
                provenance: "Synthetic documentation-only fixture", status: .syntheticDocumentationOnly),
            ShadowMarketDataPoint(identity: pocketOptionEURUSDOTC, providerID: "fixture.otc.v1",
                sourceTime: time, receivedAt: time, price: 1.1007,
                provenance: "Synthetic documentation-only fixture", status: .syntheticDocumentationOnly)
        ]
    }
}

public enum ShadowDirection: String, Codable, Sendable { case up, down, unchanged }
public enum ShadowComparisonStatus: String, Codable, Sendable { case comparable, unavailable, invalid, identityMismatch, excessiveTimestampSkew }

/// Descriptive synchronized comparison only. It carries no trade or settlement authority.
public struct ShadowMarketComparison: Codable, Sendable, Equatable {
    public let status: ShadowComparisonStatus
    public let standardIdentity: ShadowMarketIdentity?
    public let otcIdentity: ShadowMarketIdentity?
    public let standardProviderID: String?
    public let otcProviderID: String?
    public let standardPointStatus: ShadowPointStatus?
    public let otcPointStatus: ShadowPointStatus?
    public let directionAgreement: Bool?
    public let timestampSkewSeconds: Double?
    public let priceDisplacement: Double?
    public let researchOnly: Bool
    public let mayAuthorizeEntry: Bool
    public let explanation: String
}

public enum ShadowMarketDataComparison {
    public static func compare(_ lhs: ShadowMarketDataPoint?, _ rhs: ShadowMarketDataPoint?,
                               previousLHS: ShadowMarketDataPoint?, previousRHS: ShadowMarketDataPoint?,
                               at now: Date, maximumTimestampSkew: TimeInterval,
                               maximumAge: TimeInterval = 30) -> ShadowMarketComparison {
        func report(_ status: ShadowComparisonStatus, _ explanation: String) -> ShadowMarketComparison {
            let provided = [lhs, rhs, previousLHS, previousRHS].compactMap { $0 }
            let standard = provided.first(where: { $0.identity.marketKind == .standard })
            let otc = provided.first(where: { $0.identity.marketKind == .otc })
            return ShadowMarketComparison(status: status,
                standardIdentity: standard?.identity, otcIdentity: otc?.identity,
                standardProviderID: standard?.providerID, otcProviderID: otc?.providerID,
                standardPointStatus: standard?.status, otcPointStatus: otc?.status,
                directionAgreement: nil, timestampSkewSeconds: nil, priceDisplacement: nil,
                researchOnly: true, mayAuthorizeEntry: false, explanation: explanation)
        }
        guard let lhs, let rhs, let previousLHS, let previousRHS else { return report(.unavailable, "Required observations are missing") }
        guard lhs.identity == previousLHS.identity, rhs.identity == previousRHS.identity,
              lhs.identity != rhs.identity,
              lhs.identity.marketKind != rhs.identity.marketKind,
              [lhs.identity.marketKind, rhs.identity.marketKind].contains(.standard),
              [lhs.identity.marketKind, rhs.identity.marketKind].contains(.otc) else {
            return report(.identityMismatch, "Market identities do not match exactly")
        }
        let points = [lhs, rhs, previousLHS, previousRHS]
        guard maximumTimestampSkew.isFinite, maximumTimestampSkew >= 0,
              maximumAge.isFinite, maximumAge >= 0,
              points.allSatisfy({ $0.price.isFinite && $0.price > 0 && $0.sourceTime <= now && $0.receivedAt <= now && !$0.providerID.isEmpty && !$0.provenance.isEmpty }),
              points.allSatisfy({ now.timeIntervalSince($0.sourceTime).isFinite && now.timeIntervalSince($0.sourceTime) >= 0
                  && now.timeIntervalSince($0.receivedAt) >= 0
                  && now.timeIntervalSince($0.sourceTime) <= maximumAge
                  && now.timeIntervalSince($0.receivedAt) <= maximumAge }) else {
            return report(.invalid, "Observation is future dated or invalid")
        }
        let skew = abs(lhs.sourceTime.timeIntervalSince(rhs.sourceTime))
        guard skew <= maximumTimestampSkew else { return report(.excessiveTimestampSkew, "Source timestamps exceed the declared skew") }
        guard previousLHS.sourceTime < lhs.sourceTime, previousRHS.sourceTime < rhs.sourceTime else {
            return report(.invalid, "Previous observations must precede current observations")
        }
        let previousSkew = abs(previousLHS.sourceTime.timeIntervalSince(previousRHS.sourceTime))
        guard previousSkew <= maximumTimestampSkew else {
            return report(.excessiveTimestampSkew, "Previous source timestamps exceed the declared skew")
        }
        guard points.allSatisfy({ $0.status != .unavailable }) else {
            return report(.unavailable, "A provider observation is marked unavailable")
        }
        let leftDirection = direction(lhs.price - previousLHS.price)
        let rightDirection = direction(rhs.price - previousRHS.price)
        let standard = lhs.identity.marketKind == .standard ? lhs : rhs
        let otc = lhs.identity.marketKind == .otc ? lhs : rhs
        let standardDirection = lhs.identity.marketKind == .standard ? leftDirection : rightDirection
        let otcDirection = lhs.identity.marketKind == .otc ? leftDirection : rightDirection
        return ShadowMarketComparison(status: .comparable,
            standardIdentity: standard.identity, otcIdentity: otc.identity,
            standardProviderID: standard.providerID, otcProviderID: otc.providerID,
            standardPointStatus: standard.status, otcPointStatus: otc.status,
            directionAgreement: standardDirection == otcDirection,
            timestampSkewSeconds: skew, priceDisplacement: otc.price - standard.price,
            researchOnly: true, mayAuthorizeEntry: false,
            explanation: "Descriptive price and direction comparison; no venue outcome or authority")
    }

    private static func direction(_ delta: Double) -> ShadowDirection {
        delta > 0 ? .up : (delta < 0 ? .down : .unchanged)
    }
}
