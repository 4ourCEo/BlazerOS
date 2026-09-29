import Foundation

/// High-conviction market trading windows and statistical pair-edge intelligence.
/// Calibrated empirically from 372 live forward-tested 60-second binary contracts.
public enum MarketEdgeWindow: Sendable, Equatable {
    case morningPrime(hoursLabel: String)      // 5:00 AM - 10:00 AM PT (12:00 - 17:00 UTC) -> 59.1% - 61.2% WR
    case lateNightPrime(hoursLabel: String)    // 11:00 PM - 12:30 AM PT (06:00 - 07:30 UTC) -> 69.2% WR
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
        return isSupremePrime
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
            return "Next prime: \(next)"
        }
    }

    /// Evaluates current market edge window relative to Pacific Time.
    public static func current(at date: Date = Date()) -> MarketEdgeWindow {
        guard FxSession.isOpen(date) else {
            return .offPeak(nextWindowDescription: "Market Closed", secondsUntilNext: 0)
        }

        var calendar = Calendar(identifier: .gregorian)
        guard let ptZone = TimeZone(identifier: "America/Los_Angeles") else {
            return .offPeak(nextWindowDescription: "5:00 AM PT", secondsUntilNext: 0)
        }
        calendar.timeZone = ptZone

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let totalMinutes = hour * 60 + minute

        // 1. Morning NY Prime: 5:00 AM - 10:00 AM PT (300 to 600 mins)
        if totalMinutes >= 5 * 60 && totalMinutes < 10 * 60 {
            return .morningPrime(hoursLabel: "5:00 AM – 10:00 AM PT")
        }

        // 2. Late Night London Prime: 11:00 PM - 12:30 AM PT (23:00 to 24:30)
        if totalMinutes >= 23 * 60 || totalMinutes < 30 {
            return .lateNightPrime(hoursLabel: "11:00 PM – 12:30 AM PT")
        }

        // 3. Off-Peak: calculate next window
        let nextTargetMinutes: Int
        let nextLabel: String

        if totalMinutes < 5 * 60 {
            nextTargetMinutes = 5 * 60
            nextLabel = "5:00 AM PT"
        } else if totalMinutes < 23 * 60 {
            nextTargetMinutes = 23 * 60
            nextLabel = "11:00 PM PT"
        } else {
            nextTargetMinutes = 5 * 60
            nextLabel = "5:00 AM PT"
        }

        let diffMinutes = nextTargetMinutes >= totalMinutes ? nextTargetMinutes - totalMinutes : (1440 - totalMinutes + nextTargetMinutes)
        let secondsUntil = TimeInterval(diffMinutes * 60)

        return .offPeak(nextWindowDescription: nextLabel, secondsUntilNext: secondsUntil)
    }

    // MARK: - Pair-Specific Conviction

    public enum PairConviction: Sendable, Equatable {
        case edgeConfirmed(winRate: String, drift: String) // e.g. GBP/USD 57.8%, USD/JPY 54.2%
        case neutral(winRate: String)                       // EUR/USD, AUD/USD ~50-52%
        case chopRisk(winRate: String, warning: String)     // USD/CAD 36.4%

        public var label: String {
            switch self {
            case .edgeConfirmed: return "EDGE PRIME"
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
        case "USD/CAD":
            return .chopRisk(winRate: "36.4%", warning: "Sub-pip consolidations")
        case "AUD/USD":
            return .neutral(winRate: "52.7%")
        case "EUR/USD":
            return .neutral(winRate: "50.0%")
        case "EUR/GBP":
            return .neutral(winRate: "45.5%")
        default:
            return .neutral(winRate: "50.0%")
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

    public static let standardCaveat = "Forward-tested on 372 binary contracts across 6 pairs. Sample sizes per pair (~60) yield wide 95% confidence intervals (±10-13%). Numbers reflect past forward-test sample, not guaranteed future edge."

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
        guard total > 0 else { return (0, 0) }
        let n = Double(total)
        let p = Double(wins) / n
        let z2 = z * z
        let denom = 1.0 + z2 / n
        let center = (p + z2 / (2.0 * n)) / denom
        let radicand = (p * (1.0 - p) / n) + (z2 / (4.0 * n * n))
        let half = (z * sqrt(max(0.0, radicand))) / denom
        let lower = max(0.0, center - half)
        let upper = min(1.0, center + half)
        return (lower, upper)
    }
}

