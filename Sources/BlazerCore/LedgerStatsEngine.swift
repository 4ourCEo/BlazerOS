import Foundation

/// Mathematical statistics and edge conviction derived directly from ledger execution history.
public struct PairEdgeStats: Sendable, Equatable {
    public let pair: String
    public let window: String
    public let sampleSize: Int
    public let wins: Int
    public let losses: Int
    public let winRate: Double
    public let lower95: Double
    public let upper95: Double
    public let payoutRatio: Double
    public let breakEvenRate: Double
    public let expectancy: Double
    public let statusBadge: String
    public let isProvenEdge: Bool
    public let caveat: String

    public init(
        pair: String,
        window: String = "All",
        sampleSize: Int,
        wins: Int,
        payoutRatio: Double = 0.88,
        priorCalibratedRate: Double? = nil
    ) {
        self.pair = pair
        self.window = window
        self.sampleSize = sampleSize
        self.wins = wins
        self.losses = max(0, sampleSize - wins)
        self.payoutRatio = payoutRatio
        self.breakEvenRate = 1.0 / (1.0 + payoutRatio)

        if sampleSize > 0 {
            let wr = Double(wins) / Double(sampleSize)
            self.winRate = wr
            let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: wins, total: sampleSize)
            self.lower95 = lower
            self.upper95 = upper
            self.expectancy = (wr * payoutRatio) - ((1.0 - wr) * 1.0)

            if sampleSize >= 30 && lower > breakEvenRate {
                self.statusBadge = "PROVEN EDGE"
                self.isProvenEdge = true
            } else if sampleSize >= 15 && wr > breakEvenRate {
                self.statusBadge = "TENTATIVE (n=\(sampleSize))"
                self.isProvenEdge = false
            } else if sampleSize < 15 {
                self.statusBadge = "CALIBRATING (n=\(sampleSize))"
                self.isProvenEdge = false
            } else {
                self.statusBadge = "CHOP RISK"
                self.isProvenEdge = false
            }

            let lowerPct = String(format: "%.1f%%", lower * 100)
            let upperPct = String(format: "%.1f%%", upper * 100)
            let bePct = String(format: "%.1f%%", breakEvenRate * 100)
            self.caveat = "Empirical ledger: \(wins)/\(sampleSize) wins. 95% Wilson CI: [\(lowerPct), \(upperPct)]. Break-even: \(bePct) at \(Int(payoutRatio * 100))% payout."
        } else {
            // Prior benchmark fallback (372 contracts forward-test calibration)
            let prior = priorCalibratedRate ?? 0.50
            self.winRate = prior
            self.lower95 = max(0, prior - 0.12)
            self.upper95 = min(1.0, prior + 0.12)
            self.expectancy = (prior * payoutRatio) - ((1.0 - prior) * 1.0)
            self.statusBadge = "PRIOR (n=372)"
            self.isProvenEdge = false
            self.caveat = "Prior forward-test calibration (372 contracts, ~60 per pair). No local ledger trades recorded yet for \(pair)."
        }
    }
}

/// Computes empirical edge intelligence across all recorded ledger rows.
public enum LedgerStatsEngine {
    /// Static baseline calibration priors from the 372 forward-tested contracts.
    public static let priors: [String: Double] = [
        "GBP/USD": 0.578,
        "USD/JPY": 0.542,
        "EUR/USD": 0.500,
        "AUD/USD": 0.527,
        "USD/CAD": 0.364,
        "EUR/GBP": 0.455,
    ]

    /// Tallies all ledger rows for a specific pair and returns empirical stats.
    public static func evaluate(pair: String, rows: [LedgerRow], payoutRatio: Double = 0.88) -> PairEdgeStats {
        let pairRows = rows.filter { $0.pair == pair && ($0.outcome == "HIT" || $0.outcome == "MISS") }
        let sampleSize = pairRows.count
        let wins = pairRows.filter { $0.outcome == "HIT" }.count

        return PairEdgeStats(
            pair: pair,
            sampleSize: sampleSize,
            wins: wins,
            payoutRatio: payoutRatio,
            priorCalibratedRate: priors[pair]
        )
    }

    /// Evaluates all known pairs against the ledger.
    public static func evaluateAll(rows: [LedgerRow], payoutRatio: Double = 0.88) -> [String: PairEdgeStats] {
        var result: [String: PairEdgeStats] = [:]
        let allPairs = ["GBP/USD", "USD/JPY", "EUR/USD", "AUD/USD", "USD/CAD", "EUR/GBP"]
        for pair in allPairs {
            result[pair] = evaluate(pair: pair, rows: rows, payoutRatio: payoutRatio)
        }
        return result
    }
}
