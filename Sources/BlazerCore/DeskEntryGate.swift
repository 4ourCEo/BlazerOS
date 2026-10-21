import Foundation

/// The single set of preconditions for turning an armed beam into a manual entry.
/// Pure and testable so the view layer cannot invent a weaker gate.
public enum DeskEntryGate {

    public struct Context: Sendable {
        public var commit: ScanCommit?
        public var frame: DeskFrame?
        public var signal: EngineSignal?
        public var quote: LiveQuote?
        public var lastFreshPollAt: Date?
        public var activeTrade: ActiveTrade?
        public var awaitingOutcome: Bool
        public var settlementInFlight: Bool
        public var scanning: Bool
        public var historical: Bool
        public var armedAt: Date?
        public var armID: String?

        public init(
            commit: ScanCommit?,
            frame: DeskFrame?,
            signal: EngineSignal?,
            quote: LiveQuote?,
            lastFreshPollAt: Date?,
            activeTrade: ActiveTrade?,
            awaitingOutcome: Bool,
            settlementInFlight: Bool,
            scanning: Bool,
            historical: Bool,
            armedAt: Date?,
            armID: String?
        ) {
            self.commit = commit
            self.frame = frame
            self.signal = signal
            self.quote = quote
            self.lastFreshPollAt = lastFreshPollAt
            self.activeTrade = activeTrade
            self.awaitingOutcome = awaitingOutcome
            self.settlementInFlight = settlementInFlight
            self.scanning = scanning
            self.historical = historical
            self.armedAt = armedAt
            self.armID = armID
        }
    }

    /// Returns nil only when every execution precondition holds.
    public static func veto(_ context: Context, now: Date = Date()) -> EntryGateFailure? {
        if context.activeTrade != nil { return .activePositionExists }
        if context.awaitingOutcome || context.settlementInFlight { return .activePositionExists }
        if context.scanning { return .noArmedBeam }
        if context.historical { return .historical }
        guard let commit = context.commit,
              context.armedAt != nil,
              context.armID != nil
        else { return .noArmedBeam }
        if let veto = commit.veto { return .vetoed(veto) }
        guard context.frame?.isActionable == true else { return .expiredBeam }
        guard let signal = context.signal else { return .noArmedBeam }
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return .notDirectional }
        guard let quote = context.quote, quote.asset == commit.asset else { return .staleFeed }
        if let veto = EntryQuality.veto(signal: signal, quote: quote, at: now) {
            if veto.contains("expired") { return .expiredBeam }
            if veto.contains("stale") || veto.contains("unavailable") { return .staleFeed }
            return .vetoed(veto)
        }
        guard QuoteFreshness.isPollFresh(lastFreshPollAt: context.lastFreshPollAt, now: now) else {
            return .staleFeed
        }
        return nil
    }
}
