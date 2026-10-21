import Foundation

// MARK: - Strike position tracking (event-sourced, exact money)
//
// A tracked position is built from immutable events applied EXACTLY ONCE. Money is exact
// base-10 `Decimal`. Missing price/quantity/fee makes P&L UNKNOWN (never $0). Exits only reduce
// owned quantity; they never flip or increase a position. Outcome provenance is preserved so a
// user-reported result is never confused with a venue-verified one.

/// How a held-side outcome was determined.
public enum StrikeOutcomeProvenance: String, Sendable, Codable, CaseIterable {
    case userReported = "USER_REPORTED"
    case venueVerified = "VENUE_VERIFIED"
}

/// The settled result of the held side.
public enum StrikeResult: String, Sendable, Codable, CaseIterable {
    case inTheMoney = "ITM"      // held side won -> pays contract value
    case outOfTheMoney = "OTM"   // held side lost -> pays 0
}

/// A recorded settlement. Provenance is explicit; no proxy price ever settles a contract.
public struct StrikeSettlement: Sendable, Equatable, Codable {
    public var result: StrikeResult
    public var provenance: StrikeOutcomeProvenance
    public var settledAt: Date

    public init(result: StrikeResult, provenance: StrikeOutcomeProvenance, settledAt: Date) {
        self.result = result
        self.provenance = provenance
        self.settledAt = settledAt
    }
}

/// One immutable event in a position's history.
public enum StrikeEventKind: Sendable, Equatable, Codable {
    /// Record an entry fill. `fee` is the TOTAL fee for this fill (not per contract).
    case open(quantity: Int, pricePerContract: Decimal?, fee: Decimal?, at: Date)
    /// Sell to close (partial or full). Reduces owned quantity only.
    case exit(quantity: Int, pricePerContract: Decimal?, at: Date)
    /// Record the settled outcome.
    case settle(result: StrikeResult, provenance: StrikeOutcomeProvenance, at: Date)
}

public struct StrikeEvent: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var positionID: String
    public var kind: StrikeEventKind

    public init(id: String, positionID: String, kind: StrikeEventKind) {
        self.id = id
        self.positionID = positionID
        self.kind = kind
    }
}

/// Current state of a tracked position, derived by applying events once.
public struct StrikePosition: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var symbol: String
    public var side: StrikeSide
    public var strike: Double
    public var predicate: StrikePredicate
    public var spec: StrikeContractSpec
    public var expiry: Date

    // Quantity accounting (invariant: entered == exited + settled + open)
    public var enteredQuantity: Int
    public var exitedQuantity: Int
    public var settledQuantity: Int
    public var openQuantity: Int

    // Exact cash accounting
    public var entryCost: Decimal
    public var exitProceeds: Decimal
    public var settlementPayout: Decimal

    public var settlement: StrikeSettlement?
    /// True when any fill/exit lacked a price or fee — P&L must read as unknown, not zero.
    public var hasUnknownMoney: Bool
    /// Event ids already applied (idempotency).
    public var appliedEventIDs: [String]

    public init(
        id: String,
        symbol: String,
        side: StrikeSide,
        strike: Double,
        predicate: StrikePredicate,
        spec: StrikeContractSpec,
        expiry: Date
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.strike = strike
        self.predicate = predicate
        self.spec = spec
        self.expiry = expiry
        self.enteredQuantity = 0
        self.exitedQuantity = 0
        self.settledQuantity = 0
        self.openQuantity = 0
        self.entryCost = .zero
        self.exitProceeds = .zero
        self.settlementPayout = .zero
        self.settlement = nil
        self.hasUnknownMoney = false
        self.appliedEventIDs = []
    }

    public var isPending: Bool { settlement == nil }

    /// entered == exited + settled + open.
    public var conservesQuantity: Bool {
        enteredQuantity == exitedQuantity + settledQuantity + openQuantity
    }
}

/// P&L is either exact or explicitly unknown. Unknown never renders as $0.
public enum StrikePnL: Sendable, Equatable {
    case known(Decimal)
    case unknown(reason: String)
}

public extension StrikePosition {
    /// Net cash flow from CLOSED and SETTLED portions. Entry cash is negative.
    /// Returns `.unknown` if any fill/exit lacked money inputs.
    func netCashFlow() -> StrikePnL {
        if hasUnknownMoney {
            return .unknown(reason: "missing price/quantity/fee on a fill or exit")
        }
        let inflow = exitProceeds + settlementPayout
        return .known(inflow - entryCost)
    }

    /// Net cash flow that is still unrealized (open contracts, pending or partial).
    func openExposure() -> StrikePnL {
        if hasUnknownMoney {
            return .unknown(reason: "missing price/quantity/fee on a fill or exit")
        }
        return .known(Decimal(openQuantity) * spec.contractValue)
    }
}

public enum StrikeLedgerError: Error, Equatable {
    case unknownPosition(String)
    case mismatchedPosition(expected: String, got: String)
    case invalidQuantity(Int)
    case overExit(requested: Int, available: Int)
    case alreadySettled
}

public enum StrikeLedger {
    /// Apply an event to a position in place. Duplicate event ids are a no-op (idempotent).
    public static func apply(_ event: StrikeEvent, to position: inout StrikePosition) throws {
        if position.appliedEventIDs.contains(event.id) { return }
        guard event.positionID == position.id else {
            throw StrikeLedgerError.mismatchedPosition(expected: position.id, got: event.positionID)
        }

        switch event.kind {
        case let .open(quantity, price, fee, _):
            guard quantity > 0 else { throw StrikeLedgerError.invalidQuantity(quantity) }
            if let price {
                position.entryCost += Decimal(quantity) * price
            } else {
                position.hasUnknownMoney = true
            }
            if let fee {
                position.entryCost += fee
            } else {
                position.hasUnknownMoney = true
            }
            position.enteredQuantity += quantity
            position.openQuantity += quantity

        case let .exit(quantity, price, _):
            guard quantity > 0 else { throw StrikeLedgerError.invalidQuantity(quantity) }
            guard quantity <= position.openQuantity else {
                throw StrikeLedgerError.overExit(requested: quantity, available: position.openQuantity)
            }
            position.openQuantity -= quantity
            position.exitedQuantity += quantity
            if let price {
                position.exitProceeds += Decimal(quantity) * price
            } else {
                position.hasUnknownMoney = true
            }

        case let .settle(result, provenance, at):
            guard position.settlement == nil else { throw StrikeLedgerError.alreadySettled }
            let payout = result == .inTheMoney
                ? position.spec.contractValue * Decimal(position.openQuantity)
                : Decimal.zero
            position.settlement = StrikeSettlement(result: result, provenance: provenance, settledAt: at)
            position.settlementPayout = payout
            position.settledQuantity += position.openQuantity
            position.openQuantity = 0
        }

        position.appliedEventIDs.append(event.id)
    }
}
