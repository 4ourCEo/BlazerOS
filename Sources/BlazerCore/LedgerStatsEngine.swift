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
    /// Observations that were never confirmed against the venue. Never part of `sampleSize`.
    public let referenceSampleSize: Int
    public let referenceWins: Int

    public init(
        pair: String,
        window: String = "All",
        sampleSize: Int,
        wins: Int,
        payoutRatio: Double = 0.88,
        priorCalibratedRate: Double? = nil,
        verifiedOutcomes: Bool = false,
        referenceSampleSize: Int = 0,
        referenceWins: Int = 0
    ) {
        self.pair = pair
        self.window = window
        self.sampleSize = sampleSize
        self.wins = wins
        self.losses = max(0, sampleSize - wins)
        self.payoutRatio = payoutRatio
        self.breakEvenRate = 1.0 / (1.0 + payoutRatio)
        self.referenceSampleSize = referenceSampleSize
        self.referenceWins = referenceWins

        if sampleSize > 0 {
            let wr = Double(wins) / Double(sampleSize)
            self.winRate = wr
            let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: wins, total: sampleSize)
            self.lower95 = lower
            self.upper95 = upper
            self.expectancy = (wr * payoutRatio) - ((1.0 - wr) * 1.0)

            if !verifiedOutcomes {
                self.statusBadge = "UNVERIFIED LABELS (n=\(sampleSize))"
                self.isProvenEdge = false
            } else if sampleSize >= 250 && lower > breakEvenRate {
                self.statusBadge = "STATISTICALLY PROMOTED (n=\(sampleSize))"
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
            self.caveat = "Confirmed ledger: \(wins)/\(sampleSize) venue-confirmed wins. Nominal independent-trial 95% Wilson CI: [\(lowerPct), \(upperPct)]. Break-even: \(bePct) at assumed \(Int(payoutRatio * 100))% payout. Independence and policy stability still require validation."
        } else if referenceSampleSize > 0 {
            // Reference observations are shown, but they are not broker outcomes
            // and can never promote a pair.
            let rwr = Double(referenceWins) / Double(referenceSampleSize)
            self.winRate = rwr
            let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: referenceWins, total: referenceSampleSize)
            self.lower95 = lower
            self.upper95 = upper
            self.expectancy = (rwr * payoutRatio) - ((1.0 - rwr) * 1.0)
            self.statusBadge = "UNVERIFIED REFERENCE (n=\(referenceSampleSize))"
            self.isProvenEdge = false
            self.caveat = "OANDA reference observations only: \(referenceWins)/\(referenceSampleSize) suggested wins. These are not venue-confirmed broker results and do not count toward measured performance."
        } else {
            // Prior benchmark fallback (372 contracts forward-test calibration)
            let prior = priorCalibratedRate ?? 0.50
            self.winRate = prior
            self.lower95 = max(0, prior - 0.12)
            self.upper95 = min(1.0, prior + 0.12)
            self.expectancy = (prior * payoutRatio) - ((1.0 - prior) * 1.0)
            self.statusBadge = "UNVERIFIED PRIOR"
            self.isProvenEdge = false
            self.caveat = "Unverified historical prior. No local ledger trades recorded yet for \(pair); original source and per-pair sample counts are unavailable."
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
        "GBP/JPY": 0.500,
        "XAU/USD": 0.500,
    ]

    /// Tallies confirmed ledger rows for a specific pair. Reference observations are
    /// reported separately and never enter the measured sample.
    public static func evaluate(pair: String, rows: [LedgerRow], payoutRatio: Double = 0.88) -> PairEdgeStats {
        let pairRows = rows.filter { $0.pair == pair && ($0.outcome == "HIT" || $0.outcome == "MISS") }
        let confirmed = pairRows.filter { $0.labelSource == "venue-confirmed" }
        let reference = pairRows.filter { $0.labelSource != "venue-confirmed" }
        let wins = confirmed.filter { $0.outcome == "HIT" }.count
        let referenceWins = reference.filter { $0.outcome == "HIT" }.count

        return PairEdgeStats(
            pair: pair,
            sampleSize: confirmed.count,
            wins: wins,
            payoutRatio: payoutRatio,
            priorCalibratedRate: priors[pair],
            verifiedOutcomes: !confirmed.isEmpty,
            referenceSampleSize: reference.count,
            referenceWins: referenceWins
        )
    }

    /// Evaluates all known pairs against the ledger.
    public static func evaluateAll(rows: [LedgerRow], payoutRatio: Double = 0.88) -> [String: PairEdgeStats] {
        var result: [String: PairEdgeStats] = [:]
        let allPairs = Assets.watchlist + ["USD/CAD", "EUR/GBP"]
        for pair in allPairs {
            result[pair] = evaluate(pair: pair, rows: rows, payoutRatio: payoutRatio)
        }
        return result
    }
}
