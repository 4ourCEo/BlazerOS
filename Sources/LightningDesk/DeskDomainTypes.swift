import Foundation
import BlazerCore

/// Desk market mode. `.crypto` uses the shared BlazerCrypto engine; `.fx` uses OANDA.
public enum DeskMarket: String, Sendable, CaseIterable, Equatable {
    case crypto
    case fx
}

/// Post-settlement receipt. Presentation only: the ledger row is already written.
public struct SettleReceipt: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let outcome: DeskOutcome
    public let pair: String
    public let pips: Double?
    public let payout: Double
    public let labelSource: String

    public init(
        id: UUID = UUID(),
        outcome: DeskOutcome,
        pair: String,
        pips: Double?,
        payout: Double,
        labelSource: String
    ) {
        self.id = id
        self.outcome = outcome
        self.pair = pair
        self.pips = pips
        self.payout = payout
        self.labelSource = labelSource
    }
}
