import Foundation

/// Presentation rules for Live Activities. They are pure so expiry behavior is testable
/// without ActivityKit rendering.
public enum LiveActivityPresentation {
    public static func isExpired(endsAt: Date, isStale: Bool, now: Date = Date()) -> Bool {
        isStale || endsAt <= now
    }

    public static func word(verb: String, endsAt: Date, isStale: Bool, now: Date = Date()) -> String {
        isExpired(endsAt: endsAt, isStale: isStale, now: now) ? "EXPIRED" : verb
    }

    public static func footer(endsAt: Date, isStale: Bool, now: Date = Date()) -> String? {
        isExpired(endsAt: endsAt, isStale: isStale, now: now)
            ? "EXPIRED · CONFIRM THE VENUE RESULT"
            : nil
    }
}
