import Foundation

// MARK: - Foreground resume
//
// iOS suspends WebSockets and timers when the app is backgrounded. Returning from the
// Crypto.com app (to place a trade) therefore needs a resume policy: what to re-establish,
// and how long a suspension is "long enough" that the feed and clock must be rebuilt.
//
// This is pure and session-free. Crypto resumes the same way at any hour.

/// What the app should do when it returns to the foreground.
public struct ForegroundResumeDecision: Sendable, Equatable {
    /// Tear down and re-establish the market-data feed.
    public var needsFeedReconnect: Bool
    /// Re-sample the exchange clock offset.
    public var needsClockRemeasure: Bool
    /// Show CONNECTING / NO FEED until a fresh tick arrives (do not paint a stale LIVE).
    public var treatFeedAsDisconnected: Bool
}

public enum ForegroundResume {
    /// A suspension at least this long is treated as a full reconnect.
    public static let defaultSuspensionThresholdMs: Double = 15_000

    /// Decide the resume action from timings captured at background entry.
    /// - `suspendedForMs`: wall-clock time the app spent in the background.
    /// - `lastPollAgeMs`: age of the last successful feed poll at background entry (nil = never).
    /// - `clockSampleAgeMs`: age of the last clock sample at background entry (nil = never).
    public static func decide(
        suspendedForMs: Double,
        lastPollAgeMs: Double?,
        clockSampleAgeMs: Double?,
        thresholdMs: Double = ForegroundResume.defaultSuspensionThresholdMs
    ) -> ForegroundResumeDecision {
        let longSuspension = suspendedForMs >= thresholdMs
        let feedUnknown = lastPollAgeMs == nil || (lastPollAgeMs ?? .infinity) >= thresholdMs
        let clockUnknown = clockSampleAgeMs == nil
            || (clockSampleAgeMs ?? .infinity) >= ExchangeClock.defaultMaxSampleAgeMs

        return ForegroundResumeDecision(
            needsFeedReconnect: longSuspension || feedUnknown,
            needsClockRemeasure: longSuspension || clockUnknown,
            treatFeedAsDisconnected: longSuspension || feedUnknown
        )
    }
}
