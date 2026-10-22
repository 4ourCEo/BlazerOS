import Foundation

// MARK: - Strike Options domain contracts
//
// Crypto.com Strike Options are CFTC-regulated Event Contracts (Nadex/CDNA), US-only,
// retail app-only. Current contract value is $1.00 with a $0.01 tick and a $0.02 crypto
// exchange fee. The older $10 / $0.15 / $0.14 material is LEGACY and must never be used as a
// global default. All money terms are per-contract and stored as exact base-10 `Decimal`.

/// Which outcome the trader holds. The internal model owns fully-funded Yes/No outcomes only.
public enum StrikeSide: String, Sendable, Codable, CaseIterable {
    case yes = "YES"
    case no = "NO"
}

/// Settlement predicate for a listed strike.
public enum StrikePredicate: String, Sendable, Codable, CaseIterable {
    /// Reference index strictly greater than the strike.
    case aboveStrict
    /// Reference index greater than or equal to the strike.
    case aboveOrEqual

    public var label: String {
        switch self {
        case .aboveStrict: return "above (>)"
        case .aboveOrEqual: return "at or above (>=)"
        }
    }
}

/// Moneyness of the underlying relative to the strike at observation time. Deterministic.
public enum StrikeMoneyness: String, Sendable, Codable, CaseIterable {
    case inTheMoney = "ITM"
    case atTheMoney = "ATM"
    case outOfTheMoney = "OTM"
}

/// Deterministic decay gate for entries near expiry. Never a model output.
public enum StrikeDecayGate: String, Sendable, Codable, CaseIterable {
    /// Enough time remaining to consider a new entry.
    case open = "OPEN"
    /// Inside the late window but still in the money: allowed, flagged.
    case lateWindow = "LATE_WINDOW"
    /// Too little time remaining and not in the money: no new entry.
    case blocked = "BLOCKED"
    /// The contract deadline has passed.
    case expired = "EXPIRED"
}

/// Immutable, versioned contract terms. Payout, tick, and fees are per-contract, never global.
public struct StrikeContractSpec: Sendable, Equatable, Codable {
    public var contractValue: Decimal
    public var tickSize: Decimal
    public var exchangeFee: Decimal
    public var technologyFee: Decimal
    /// Provenance label for the spec (which product / where it came from).
    public var source: String

    public init(
        contractValue: Decimal,
        tickSize: Decimal,
        exchangeFee: Decimal,
        technologyFee: Decimal,
        source: String
    ) {
        self.contractValue = contractValue
        self.tickSize = tickSize
        self.exchangeFee = exchangeFee
        self.technologyFee = technologyFee
        self.source = source
    }

    /// Current crypto Strike spec (authoritative): $1.00 / $0.01 / $0.02, technology fee waived.
    public static let currentCrypto = StrikeContractSpec(
        contractValue: Decimal.strikeMoney("1.00"),
        tickSize: Decimal.strikeMoney("0.01"),
        exchangeFee: Decimal.strikeMoney("0.02"),
        technologyFee: .zero,
        source: "nadex.com/crypto (crypto Strike Options)"
    )

    /// Current FX Strike spec: $1.00 / $0.01, $0.10 exchange + $0.10 technology fee.
    /// Out of v1 scope; provided so the contract template can override.
    public static let currentFX = StrikeContractSpec(
        contractValue: Decimal.strikeMoney("1.00"),
        tickSize: Decimal.strikeMoney("0.01"),
        exchangeFee: Decimal.strikeMoney("0.10"),
        technologyFee: Decimal.strikeMoney("0.10"),
        source: "nadex.com/crypto (FX Strike Options)"
    )

    /// LEGACY $10 rolling contract (stale). Kept only so a record can override, never a default.
    public static let legacyRolling10 = StrikeContractSpec(
        contractValue: Decimal.strikeMoney("10.00"),
        tickSize: Decimal.strikeMoney("0.01"),
        exchangeFee: Decimal.strikeMoney("0.15"),
        technologyFee: Decimal.strikeMoney("0.14"),
        source: "legacy rolling Strike (stale)"
    )

    /// Total per-contract entry fee (exchange + technology).
    public var totalEntryFee: Decimal { exchangeFee + technologyFee }
}

extension Decimal {
    /// Exact base-10 decimal from a fixed-precision string (e.g. "0.02").
    static func strikeMoney(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
    }
}
