import Foundation

// MARK: - Crypto feed health
//
// Crypto markets are 24/7. Feed health for crypto must NOT inherit FX session rules
// (no London/NY overlap, no weekend closure). This state machine judges a crypto feed purely
// from connection state, tick recency, and a heartbeat/reconnect policy.
//
// Views paint `CryptoFeedState` (or its `FeedStatus` bridge). They do not invent a second check.

/// Thresholds and reconnect policy for a crypto market-data feed. All times in milliseconds.
public struct FeedHealthPolicy: Sendable, Equatable, Codable {
    /// Wall-clock age up to which a tick is considered LIVE.
    public var liveMaxAgeMs: Double
    /// Wall-clock age up to which a tick is considered STALE (beyond this is NO FEED).
    public var staleMaxAgeMs: Double
    /// No tick for at least this long triggers a reconnect attempt.
    public var reconnectAfterMs: Double
    /// Expected tick cadence used for heartbeat checks.
    public var heartbeatMs: Double
    /// First reconnect backoff delay.
    public var reconnectBaseMs: Double
    /// Reconnect backoff ceiling.
    public var reconnectMaxMs: Double

    public init(
        liveMaxAgeMs: Double,
        staleMaxAgeMs: Double,
        reconnectAfterMs: Double,
        heartbeatMs: Double,
        reconnectBaseMs: Double,
        reconnectMaxMs: Double
    ) {
        self.liveMaxAgeMs = liveMaxAgeMs
        self.staleMaxAgeMs = staleMaxAgeMs
        self.reconnectAfterMs = reconnectAfterMs
        self.heartbeatMs = heartbeatMs
        self.reconnectBaseMs = reconnectBaseMs
        self.reconnectMaxMs = reconnectMaxMs
    }

    /// Reasonable defaults for a sub-second crypto tick feed.
    public static let cryptoDefault = FeedHealthPolicy(
        liveMaxAgeMs: 2_000,
        staleMaxAgeMs: 8_000,
        reconnectAfterMs: 8_000,
        heartbeatMs: 1_000,
        reconnectBaseMs: 500,
        reconnectMaxMs: 30_000
    )
}

/// Crypto feed-health word. Session-free — driven only by connectivity and tick recency.
public enum CryptoFeedState: String, Sendable, Equatable, Codable, CaseIterable {
    case connecting = "CONNECTING"
    case live = "LIVE"
    case stale = "STALE"
    case noFeed = "NO FEED"
}

/// The single crypto feed-health authority. Deterministic; no FX session dependency.
public enum CryptoFeedHealth {

    /// Classify the current crypto feed state.
    public static func state(
        connected: Bool,
        everReceivedTick: Bool,
        lastTickAt: Date?,
        now: Date = Date(),
        policy: FeedHealthPolicy = .cryptoDefault
    ) -> CryptoFeedState {
        guard connected else {
            // Never connected vs. dropped connection read differently to the user.
            return everReceivedTick ? .noFeed : .connecting
        }
        guard everReceivedTick, let lastTickAt else {
            return .connecting
        }
        let ageMs = max(0, now.timeIntervalSince(lastTickAt) * 1000)
        if ageMs <= policy.liveMaxAgeMs { return .live }
        if ageMs <= policy.staleMaxAgeMs { return .stale }
        return .noFeed
    }

    /// True when the transport should be torn down and re-established.
    public static func shouldReconnect(
        connected: Bool,
        everReceivedTick: Bool,
        lastTickAt: Date?,
        now: Date = Date(),
        policy: FeedHealthPolicy = .cryptoDefault
    ) -> Bool {
        guard connected else { return true }
        guard everReceivedTick, let lastTickAt else { return true }
        let ageMs = max(0, now.timeIntervalSince(lastTickAt) * 1000)
        return ageMs >= policy.reconnectAfterMs
    }

    /// Exponential backoff (capped) for reconnect attempt number `attempt` (0-based).
    public static func reconnectDelayMs(
        attempt: Int,
        policy: FeedHealthPolicy = .cryptoDefault
    ) -> Double {
        let exponent = pow(2.0, Double(max(0, attempt)))
        return min(policy.reconnectBaseMs * exponent, policy.reconnectMaxMs)
    }

    /// True when a tick has not arrived within the expected heartbeat cadence.
    public static func isHeartbeatOverdue(
        lastTickAt: Date?,
        now: Date = Date(),
        policy: FeedHealthPolicy = .cryptoDefault
    ) -> Bool {
        guard let lastTickAt else { return true }
        let ageMs = max(0, now.timeIntervalSince(lastTickAt) * 1000)
        return ageMs > policy.heartbeatMs
    }

    /// Bridge to the existing Desk `FeedStatus` word so views can reuse their painting.
    public static func feedStatus(for state: CryptoFeedState) -> FeedStatus {
        switch state {
        case .live: return .live
        case .stale: return .stale
        case .noFeed: return .disconnected
        case .connecting: return .connecting
        }
    }
}
