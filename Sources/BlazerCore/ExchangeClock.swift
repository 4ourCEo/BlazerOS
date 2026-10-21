import Foundation

// MARK: - Exchange clock sync
//
// Strike contracts settle to the exact second. A local clock that drifts from the exchange
// clock can fire a countdown early/late or mis-time an expiry. This models the skew between the
// device clock and an authoritative server (exchange or NTP) using an NTP-style midpoint
// estimate, so the app can correct its display and warn when drift is unsafe.

/// A measured skew between the local device clock and an authoritative server clock.
public struct ClockOffset: Sendable, Equatable, Codable {
    /// Server time minus local time, in milliseconds. Add to a local instant to get server time.
    public var skewMs: Double
    /// Measured round-trip time of the sample, in milliseconds.
    public var roundTripMs: Double
    /// When the sample was taken (local clock).
    public var measuredAt: Date
    /// Provenance label (e.g. "exchange", "ntp").
    public var source: String

    public init(skewMs: Double, roundTripMs: Double, measuredAt: Date, source: String) {
        self.skewMs = skewMs
        self.roundTripMs = roundTripMs
        self.measuredAt = measuredAt
        self.source = source
    }
}

/// How dangerous a clock skew is for second-accurate settlement.
public enum ClockDrift: String, Sendable, Equatable, Codable, CaseIterable {
    case ok = "OK"
    case warn = "WARN"
    case critical = "CRITICAL"
}

public enum ExchangeClock {

    /// Skew beyond this is a warning. One second of contract time is a lot.
    public static let warningThresholdMs: Double = 500
    /// Skew beyond this is unsafe for settlement timing.
    public static let criticalThresholdMs: Double = 2_000
    /// Samples older than this are stale and should be re-measured.
    public static let defaultMaxSampleAgeMs: Double = 5 * 60 * 1000

    /// NTP-style offset from a single server timestamp.
    /// `sentAt` (t0) and `receivedAt` (t3) bracket the request; `serverTime` is the server's
    /// clock reading. Assumes symmetric latency, so the local midpoint is `t0 + rtt/2`.
    public static func offset(
        sentAt t0: Date,
        serverTime: Date,
        receivedAt t3: Date,
        source: String
    ) -> ClockOffset {
        let rttMs = max(0, t3.timeIntervalSince(t0) * 1000)
        let midpoint = t0.addingTimeInterval((rttMs / 2) / 1000)
        let skewMs = serverTime.timeIntervalSince(midpoint) * 1000
        return ClockOffset(skewMs: skewMs, roundTripMs: rttMs, measuredAt: t3, source: source)
    }

    /// Apply the measured skew to a local instant to obtain corrected server time.
    public static func correctedNow(localNow: Date, offset: ClockOffset) -> Date {
        localNow.addingTimeInterval(offset.skewMs / 1000)
    }

    public static func drift(of offset: ClockOffset) -> ClockDrift {
        let magnitude = abs(offset.skewMs)
        if magnitude >= criticalThresholdMs { return .critical }
        if magnitude >= warningThresholdMs { return .warn }
        return .ok
    }

    /// True when the offset sample is too old to trust and should be re-measured.
    public static func isSampleStale(
        offset: ClockOffset,
        now: Date = Date(),
        maxAgeMs: Double = ExchangeClock.defaultMaxSampleAgeMs
    ) -> Bool {
        now.timeIntervalSince(offset.measuredAt) * 1000 > maxAgeMs
    }
}
