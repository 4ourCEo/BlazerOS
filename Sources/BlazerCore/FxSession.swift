import Foundation

/// FX week in New York time. Sunday 17:00 opens. Friday 17:00 closes. Saturday is shut.
public enum FxSession {
    public static func isOpen(_ date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let close = 17 * 60
        switch weekday {
        case 1:
            return minutes >= close
        case 7:
            return false
        case 6:
            return minutes < close
        default:
            return true
        }
    }

    public static func label(_ date: Date = Date()) -> String {
        if isOpen(date) {
            return "LIVE FX"
        }
        return "FX closed — SKIP"
    }

    /// Identifies the active market session in UTC for market-open positioning.
    public static func activeSessionName(_ date: Date = Date()) -> String {
        guard isOpen(date) else { return "MARKET CLOSED" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let hour = calendar.component(.hour, from: date)

        // London: 07:00 - 16:00 UTC
        // New York: 12:00 - 21:00 UTC
        // Overlap: 12:00 - 16:00 UTC (peak binary options volume)
        // Tokyo / Asian: 23:00 - 08:00 UTC
        if hour >= 12 && hour < 16 {
            return "LONDON / NY OVERLAP"
        } else if hour >= 7 && hour < 16 {
            return "LONDON OPEN"
        } else if hour >= 12 && hour < 21 {
            return "NEW YORK OPEN"
        } else if hour >= 23 || hour < 8 {
            return "TOKYO / ASIAN OPEN"
        } else {
            return "MARKET ACTIVE"
        }
    }
}
