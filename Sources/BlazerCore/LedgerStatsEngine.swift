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
    /// Mean venue payout actually recorded on the resolved rows (falling back to the
    /// supplied default when a row has no payout). This is the rate the expectancy uses.
    public let payoutRatio: Double
    /// Lowest payout seen in the cohort. Promotion must clear break-even at this rate,
    /// otherwise a high-payout subset can carry a losing book.
    public let minimumPayoutRatio: Double
    /// `"recorded"`, `"mixed"`, or `"assumed"` — how much of the cohort carries a real payout.
    public let payoutSource: String
    public let breakEvenRate: Double
    public let breakEvenRateAtMinimumPayout: Double
    public let expectancy: Double
    public let statusBadge: String
    /// True only when every promotion criterion holds. The name is retained for existing
    /// call sites; it means "criteria met", not a guarantee of future edge.
    public let isProvenEdge: Bool
    /// Explicit alias for `isProvenEdge`.
    public let meetsPromotionCriteria: Bool
    public let caveat: String
    /// Observations that were never confirmed against the venue. Never part of `sampleSize`.
    public let referenceSampleSize: Int
    public let referenceWins: Int

    public init(
        pair: String,
        window: String = "All",
        sampleSize suppliedSampleSize: Int,
        wins suppliedWins: Int,
        payoutRatio: Double = 0.88,
        priorCalibratedRate: Double? = nil,
        verifiedOutcomes: Bool = false,
        referenceSampleSize: Int = 0,
        referenceWins: Int = 0,
        /// Per-row payouts, in any order. `nil` entries fall back to `payoutRatio`.
        /// Pass `nil` (or a count that does not match `sampleSize`) to score a flat payout.
        perRowPayouts: [Double?]? = nil,
        perRowWins: [Bool]? = nil,
        observations: [ClusteredObservation]? = nil,
        clusteringWindowMs: Double = EvidenceClustering.defaultBucketMs
    ) {
        let sampleSize = max(0, suppliedSampleSize)
        let wins = min(sampleSize, max(0, suppliedWins))
        self.pair = pair
        self.window = window
        self.sampleSize = sampleSize
        self.wins = wins
        self.losses = max(0, sampleSize - wins)
        self.referenceSampleSize = referenceSampleSize
        self.referenceWins = referenceWins

        let fallbackPayout = payoutRatio.isFinite && payoutRatio > 0 && payoutRatio <= 1e100 ? payoutRatio : 0.88
        // Resolve the payout that each resolved row actually paid.
        let resolvedPayouts: [Double]
        let recordedCount: Int
        if let perRowPayouts, perRowPayouts.count == sampleSize, sampleSize > 0 {
            resolvedPayouts = perRowPayouts.map { value in
                guard let value, value.isFinite, value > 0, value <= 1e100 else { return fallbackPayout }
                return value
            }
            recordedCount = perRowPayouts.compactMap { $0 }.filter { $0.isFinite && $0 > 0 && $0 <= 1e100 }.count
        } else {
            resolvedPayouts = []
            recordedCount = 0
        }

        let effectivePayout: Double
        let minimumPayout: Double
        if resolvedPayouts.isEmpty {
            effectivePayout = fallbackPayout
            minimumPayout = fallbackPayout
        } else {
            effectivePayout = resolvedPayouts.reduce(0, +) / Double(resolvedPayouts.count)
            minimumPayout = resolvedPayouts.min() ?? fallbackPayout
        }

        self.payoutRatio = effectivePayout
        self.minimumPayoutRatio = minimumPayout
        if recordedCount == 0 {
            self.payoutSource = "assumed"
        } else if recordedCount == sampleSize {
            self.payoutSource = "recorded"
        } else {
            self.payoutSource = "mixed"
        }
        self.breakEvenRate = 1.0 / (1.0 + effectivePayout)
        self.breakEvenRateAtMinimumPayout = 1.0 / (1.0 + minimumPayout)

        if sampleSize > 0 {
            let wr = Double(wins) / Double(sampleSize)
            self.winRate = wr
            let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: wins, total: sampleSize)
            let clustered = observations.map { EvidenceClustering.adjust($0, bucketMs: clusteringWindowMs) }
            let completeTiming = clustered?.nominalSize == sampleSize
            self.lower95 = completeTiming ? (clustered?.lower95 ?? 0) : 0
            self.upper95 = completeTiming ? (clustered?.upper95 ?? 1) : 1
            // Equal stakes: a win returns `payout`, a loss returns -1.
            if let perRowWins, perRowWins.count == sampleSize, resolvedPayouts.count == sampleSize {
                self.expectancy = zip(perRowWins, resolvedPayouts).reduce(0.0) {
                    $0 + ($1.0 ? $1.1 : -1)
                } / Double(sampleSize)
            } else {
                self.expectancy = (wr * effectivePayout) - (1 - wr)
            }

            // Counts alone cannot establish prospective independence, policy stability,
            // a registered stopping rule or independent review. No pair summary promotes.
            self.meetsPromotionCriteria = false
            self.isProvenEdge = false
            self.statusBadge = verifiedOutcomes
                ? "INSUFFICIENT EVIDENCE (n=\(sampleSize))"
                : "INSUFFICIENT EVIDENCE · UNVERIFIED LABELS (n=\(sampleSize))"

            let lowerPct = String(format: "%.1f%%", lower * 100)
            let upperPct = String(format: "%.1f%%", upper * 100)
            let bePct = String(format: "%.1f%%", self.breakEvenRate * 100)
            let minBePct = String(format: "%.1f%%", self.breakEvenRateAtMinimumPayout * 100)
            let payoutPct = String(format: "%.1f%%", effectivePayout * 100)
            self.caveat = (verifiedOutcomes ? "Confirmed ledger: " : "Unverified labels: ")
                + "\(wins)/\(sampleSize) wins. "
                + "Payout \(payoutPct) (\(self.payoutSource)); break-even \(bePct), "
                + "or \(minBePct) at the lowest recorded payout. "
                + "Nominal 95% Wilson CI: [\(lowerPct), \(upperPct)]. "
                + "Independence, holdout, basket coverage and policy stability still require validation. "
                + (clustered?.caveat ?? "Clustering metadata unavailable.")
        } else if referenceSampleSize > 0 {
            // Reference observations are shown, but they are not broker outcomes
            // and can never promote a pair.
            let rwr = Double(referenceWins) / Double(referenceSampleSize)
            self.winRate = rwr
            let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: referenceWins, total: referenceSampleSize)
            self.lower95 = lower
            self.upper95 = upper
            self.expectancy = (rwr * effectivePayout) - ((1.0 - rwr) * 1.0)
            self.statusBadge = "INSUFFICIENT EVIDENCE · UNVERIFIED REFERENCE (n=\(referenceSampleSize))"
            self.meetsPromotionCriteria = false
            self.isProvenEdge = false
            self.caveat = "OANDA reference observations only: \(referenceWins)/\(referenceSampleSize) "
                + "suggested wins. These are not venue-confirmed broker results and do not count "
                + "toward measured performance."
        } else {
            // Prior benchmark fallback (372 contracts forward-test calibration)
            let prior = priorCalibratedRate ?? 0.50
            self.winRate = prior
            self.lower95 = max(0, prior - 0.12)
            self.upper95 = min(1.0, prior + 0.12)
            self.expectancy = (prior * effectivePayout) - ((1.0 - prior) * 1.0)
            self.statusBadge = "INSUFFICIENT EVIDENCE · UNVERIFIED PRIOR"
            self.meetsPromotionCriteria = false
            self.isProvenEdge = false
            self.caveat = "Unverified historical prior. No local ledger trades recorded yet for \(pair); "
                + "original source and per-pair sample counts are unavailable."
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
    ///
    /// - Parameter payoutRatio: Fallback only. A row's own `payout` is preferred, so a book
    ///   written at 80% is not scored against an assumed 88%.
    public static func evaluate(pair: String, rows: [LedgerRow], payoutRatio: Double = 0.88) -> PairEdgeStats {
        let unique = Dictionary(grouping: rows, by: \.outcomeEventID).values
            .filter { $0.count == 1 }.compactMap(\.first)
            .filter { $0.pair == pair && ($0.outcome == "HIT" || $0.outcome == "MISS") }
        let confirmed = unique.filter { $0.labelSource == "venue-confirmed" }
        let reference = unique.filter { $0.labelSource != "venue-confirmed" }
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
            referenceWins: referenceWins,
            perRowPayouts: confirmed.map(\.payout),
            perRowWins: confirmed.map { $0.outcome == "HIT" },
            observations: confirmed.compactMap {
                guard let entered = $0.enteredAt, let horizon = $0.horizonSeconds,
                      [60, 180, 300].contains(horizon) else { return nil }
                return ClusteredObservation(pair: $0.pair,
                    capturedAtMs: entered.timeIntervalSince1970 * 1000, won: $0.outcome == "HIT")
            },
            clusteringWindowMs: Double(max(60, confirmed.compactMap(\.horizonSeconds).max() ?? 60)) * 1000
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
