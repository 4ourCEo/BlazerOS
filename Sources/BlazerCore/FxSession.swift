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
}
