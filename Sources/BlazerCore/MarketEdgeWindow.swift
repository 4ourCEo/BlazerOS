import Foundation

/// Pacific research schedules and unverified historical pair priors.
/// Session timing alone does not establish a profitable edge.
public enum MarketEdgeWindow: Sendable, Equatable {
    case morningPrime(hoursLabel: String)      // 5:00 AM - 10:00 AM PT; UTC offset varies with DST.
    case lateNightPrime(hoursLabel: String)    // 11:00 PM - 12:30 AM PT; not a fixed London session.
    case offPeak(nextWindowDescription: String, secondsUntilNext: TimeInterval)

    public var isSupremePrime: Bool {
        if case .morningPrime = self { return true }
        return false
    }

    public var isTactical: Bool {
        if case .lateNightPrime = self { return true }
        return false
    }

    public var isPrime: Bool {
        return isSupremePrime || isTactical
    }

    public var badgeTitle: String {
        switch self {
        case .morningPrime:
            return "SUPREME PRIME"
        case .lateNightPrime:
            return "TACTICAL SCALP"
        case .offPeak:
            return "OFF-PEAK"
        }
    }

    public var detailText: String {
        switch self {
        case .morningPrime(let label):
            return label
        case .lateNightPrime(let label):
            return "\(label) (Bursts Only)"
        case .offPeak(let next, _):
            return next == "Market Closed" ? "FX market closed" : "Next prime: \(next)"
        }
    }

    /// Evaluates current market edge window relative to Pacific Time.
    public static func current(at date: Date = Date()) -> MarketEdgeWindow {
        guard FxSession.isOpen(date) else {
            return .offPeak(nextWindowDescription: "Market Closed", secondsUntilNext: 0)
        }

        let totalMinutes = pacificMinutesOfDay(date)

        // 1. Morning NY Prime: 5:00 AM - 10:00 AM PT (300 to 600 mins)
        if totalMinutes >= morningStartMinutes && totalMinutes < morningEndMinutes {
            return .morningPrime(hoursLabel: "5:00 AM – 10:00 AM PT")
        }

        // 2. Late Night London Prime: 11:00 PM - 12:30 AM PT (23:00 to 24:30)
        if totalMinutes >= lateNightStartMinutes || totalMinutes < lateNightEndMinutes {
            return .lateNightPrime(hoursLabel: "11:00 PM – 12:30 AM PT")
        }

        // 3. Off-Peak: point at the next window using the same clock the windows use.
        guard let next = nextPrimeStart(after: date) else {
            return .offPeak(nextWindowDescription: "5:00 AM PT", secondsUntilNext: 0)
        }
        return .offPeak(
            nextWindowDescription: nextWindowLabel(for: next),
            secondsUntilNext: max(0, next.timeIntervalSince(date))
        )
    }

    /// Single source of truth for the live countdown.
    /// Window arithmetic lives here; screens only format `phase` and must not recompute boundaries.
    public static func countdown(at date: Date = Date()) -> MarketEdgeCountdown {
        let window = current(at: date)

        guard FxSession.isOpen(date) else {
            let opensAt = FxSession.nextOpen(after: date)
            return MarketEdgeCountdown(
                phase: .marketClosed(opensIn: max(0, opensAt.timeIntervalSince(date))),
                window: window
            )
        }

        switch window {
        case .morningPrime:
            let end = pacificTime(hour: 10, onDayContaining: date) ?? date
            return MarketEdgeCountdown(
                phase: .primeEndsIn(max(0, end.timeIntervalSince(date))),
                window: window
            )
        case .lateNightPrime:
            let minutes = pacificMinutesOfDay(date)
            let end = minutes >= lateNightStartMinutes
                ? pacificTime(hour: 0, minute: 30, onDayContaining: date, dayOffset: 1)
                : pacificTime(hour: 0, minute: 30, onDayContaining: date)
            return MarketEdgeCountdown(
                phase: .primeEndsIn(max(0, (end ?? date).timeIntervalSince(date))),
                window: window
            )
        case .offPeak(_, let secondsUntilNext):
            return MarketEdgeCountdown(
                phase: .nextPrimeIn(max(0, secondsUntilNext)),
                window: window
            )
        }
    }

    // MARK: - Schedule Primitives

    private static let morningStartMinutes = 5 * 60
    private static let morningEndMinutes = 10 * 60
    private static let lateNightStartMinutes = 23 * 60
    private static let lateNightEndMinutes = 30

    private static func pacificCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    private static func pacificMinutesOfDay(_ date: Date) -> Int {
        let calendar = pacificCalendar()
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// Wall-clock time in Pacific on the day containing `date`, optionally offset by whole days.
    /// Uses `date(bySettingHour:)` rather than adding hours, so a DST transition cannot shift it.
    private static func pacificTime(
        hour: Int,
        minute: Int = 0,
        onDayContaining date: Date,
        dayOffset: Int = 0
    ) -> Date? {
        let calendar = pacificCalendar()
        let day = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: calendar.startOfDay(for: date)
        ) ?? date
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    private static func nextPrimeStart(after date: Date) -> Date? {
        let minutes = pacificMinutesOfDay(date)
        if minutes < morningStartMinutes {
            return pacificTime(hour: 5, onDayContaining: date)
        }
        if minutes < lateNightStartMinutes {
            return pacificTime(hour: 23, onDayContaining: date)
        }
        return pacificTime(hour: 5, onDayContaining: date, dayOffset: 1)
    }

    private static func nextWindowLabel(for date: Date) -> String {
        pacificMinutesOfDay(date) == lateNightStartMinutes ? "11:00 PM PT" : "5:00 AM PT"
    }

    // MARK: - Pair-Specific Conviction

    public enum PairConviction: Sendable, Equatable {
        case edgeConfirmed(winRate: String, drift: String) // e.g. GBP/USD 57.8%, USD/JPY 54.2%
        case neutral(winRate: String)                       // EUR/USD, AUD/USD ~50-52%
        case chopRisk(winRate: String, warning: String)     // USD/CAD 36.4%

        public var label: String {
            switch self {
            case .edgeConfirmed: return "UNVERIFIED PRIOR"
            case .neutral:       return "BALANCED"
            case .chopRisk:      return "CHOP RISK"
            }
        }
    }

    public static func conviction(for asset: String) -> PairConviction {
        switch asset {
        case "GBP/USD":
            return .edgeConfirmed(winRate: "57.8%", drift: "+0.3p")
        case "USD/JPY":
            return .edgeConfirmed(winRate: "54.2%", drift: "+0.3p")
        case "GBP/JPY":
            return .neutral(winRate: "Calibrating (High ATR)")
        case "XAU/USD":
            return .neutral(winRate: "Calibrating (Gold)")
        case "USD/CAD":
            return .chopRisk(winRate: "36.4%", warning: "Sub-pip consolidations")
        case "AUD/USD":
            return .neutral(winRate: "52.7%")
        case "EUR/USD":
            return .neutral(winRate: "50.0%")
        case "EUR/GBP":
            return .chopRisk(winRate: "45.5%", warning: "Micro-pip spread trap (+0.01p avg drift)")
        default:
            return .neutral(winRate: "50.0%")
        }
    }
}

/// Live countdown derived from the same schedule as `MarketEdgeWindow.current`.
/// Screens format this; they must not recompute window boundaries themselves.
public struct MarketEdgeCountdown: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Inside a prime window: time until it closes.
        case primeEndsIn(TimeInterval)
        /// Outside a prime window while FX is open: time until the next one opens.
        case nextPrimeIn(TimeInterval)
        /// FX week is shut: time until the next Sunday 17:00 New York open.
        case marketClosed(opensIn: TimeInterval)
    }

    public let phase: Phase
    public let window: MarketEdgeWindow

    public init(phase: Phase, window: MarketEdgeWindow) {
        self.phase = phase
        self.window = window
    }

    public var remaining: TimeInterval {
        switch phase {
        case .primeEndsIn(let seconds),
             .nextPrimeIn(let seconds),
             .marketClosed(let seconds):
            return max(0, seconds)
        }
    }
}

/// Statistical context and confidence bounds for empirical edge win rates.
public struct EdgeEvidence: Sendable, Equatable {
    public let sampleSize: Int
    public let wins: Int
    public let winRate: Double
    public let lower95: Double
    public let upper95: Double
    public let caveat: String

    public static let standardCaveat = "Historical pair priors are unverified: original source, per-pair counts and independence evidence are unavailable. Use venue-confirmed records and clustered prospective validation; no profitable edge is established."

    public init(wins: Int, sampleSize: Int, caveat: String = standardCaveat) {
        self.wins = wins
        self.sampleSize = sampleSize
        self.caveat = caveat
        if sampleSize > 0 {
            self.winRate = Double(wins) / Double(sampleSize)
            let (lower, upper) = Self.wilsonScoreInterval(wins: wins, total: sampleSize)
            self.lower95 = lower
            self.upper95 = upper
        } else {
            self.winRate = 0
            self.lower95 = 0
            self.upper95 = 0
        }
    }

    /// Calculates a 95% Wilson score confidence interval (z ≈ 1.95996).
    public static func wilsonScoreInterval(wins: Int, total: Int, z: Double = 1.95996) -> (lower: Double, upper: Double) {
        guard total > 0, wins >= 0, wins <= total, z.isFinite, z > 0 else { return (0, 0) }
        let n = Double(total)
        let p = Double(wins) / n
        let z2 = z * z
        let denom = 1.0 + z2 / n
        let center = (p + z2 / (2.0 * n)) / denom
        let radicand = (p * (1.0 - p) / n) + (z2 / (4.0 * n * n))
        let half = (z * sqrt(max(0.0, radicand))) / denom
        let lower = max(0.0, center - half)
        let upper = min(1.0, center + half)
        guard lower.isFinite, upper.isFinite else { return (0, 1) }
        return (lower, upper)
    }
}
