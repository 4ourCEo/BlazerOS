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

    /// Next instant the FX week opens: Sunday 17:00 New York.
    /// Only meaningful while the market is shut; returns the next Sunday open otherwise.
    public static func nextOpen(after date: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let close = 17 * 60

        let daysAhead: Int
        switch weekday {
        case 1:  daysAhead = minutes < close ? 0 : 7   // Sunday: today's open, else next week
        case 7:  daysAhead = 1                          // Saturday
        case 6:  daysAhead = 2                          // Friday: next open is Sunday
        default: daysAhead = (8 - weekday) % 7          // Mon–Thu: next Sunday
        }

        let day = calendar.date(
            byAdding: .day,
            value: daysAhead,
            to: calendar.startOfDay(for: date)
        ) ?? date
        return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day) ?? day
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
