import Foundation

/// Coarse correlation group used to stop concurrent, correlated scans from being counted
/// as independent trials. It is deliberately crude: the goal is to prevent the obvious
/// inflation (one macro move triggering six "independent" USD pairs) without pretending to
/// know the covariance structure.
public enum CorrelationGroup: String, Codable, Sendable, CaseIterable {
    /// Any pair quoted in USD, including gold. A single USD shock moves all of these.
    case usd
    /// FX crosses without a USD leg (for example EUR/GBP).
    case cross
    /// Digital assets. Grouped together because they share one risk driver.
    case crypto
    /// Anything not recognised. All unknown instruments share one conservative group, so
    /// unrelated but concurrent observations are never counted as independent.
    case other
}

/// One resolved observation (a HIT or a MISS) placed on the time axis.
public struct ClusteredObservation: Sendable, Equatable {
    public var pair: String
    /// Observation time in milliseconds since the epoch.
    public var capturedAtMs: Double
    public var won: Bool

    public init(pair: String, capturedAtMs: Double, won: Bool) {
        self.pair = pair
        self.capturedAtMs = capturedAtMs
        self.won = won
    }
}

/// A confidence interval that accounts for correlated observations.
///
/// The adjustment is an approximate design effect, not a measured covariance model:
/// `n_eff = n / (1 + (meanBlockSize - 1) * ICC)`. With the default ICC of 1, concurrent observations count at most as their candidate blocks.
/// Unequal block sizes further reduce the effective count.
/// `effectiveSize` is therefore an upper bound on independent evidence, never a promotion
/// argument on its own.
public struct ClusterAdjustedSample: Sendable, Equatable {
    /// Observations supplied (HIT + MISS only).
    public let nominalSize: Int
    public let wins: Int
    /// Distinct (correlation group, time bucket) cells. The candidate time blocks.
    public let blocks: Int
    public let meanBlockSize: Double
    public let designEffect: Double
    public let effectiveSize: Double
    /// Nominal wins scaled down to `effectiveSize`, used for the Wilson interval.
    public let effectiveWins: Int
    public let assumedICC: Double
    public let bucketMs: Double
    public let lower95: Double
    public let upper95: Double

    public init(
        nominalSize: Int,
        wins: Int,
        blocks: Int,
        meanBlockSize: Double,
        designEffect: Double,
        effectiveSize: Double,
        effectiveWins: Int,
        assumedICC: Double,
        bucketMs: Double,
        lower95: Double,
        upper95: Double
    ) {
        self.nominalSize = nominalSize
        self.wins = wins
        self.blocks = blocks
        self.meanBlockSize = meanBlockSize
        self.designEffect = designEffect
        self.effectiveSize = effectiveSize
        self.effectiveWins = effectiveWins
        self.assumedICC = assumedICC
        self.bucketMs = bucketMs
        self.lower95 = lower95
        self.upper95 = upper95
    }

    /// True when at least two observations shared a block, i.e. the adjustment did something.
    public var isClustered: Bool {
        nominalSize > 0 && blocks < nominalSize
    }

    /// True when the interval was widened by clustering, so the nominal interval overstates
    /// confidence.
    public var nominalIntervalOverstatesConfidence: Bool {
        isClustered
    }

    public var caveat: String {
        guard nominalSize > 0 else {
            return "No resolved observations. No confidence interval is possible."
        }
        if isClustered {
            return "Clustered: \(nominalSize) observations in \(blocks) candidate time blocks "
                + "(mean \(String(format: "%.2f", meanBlockSize)) per block, assumed ICC "
                + "\(String(format: "%.2f", assumedICC))). Effective N "
                + "\(String(format: "%.1f", effectiveSize)); the nominal interval overstates confidence."
        }
        return "No concurrent correlated observations detected under this grouping. Serial dependence remains unverified."
    }

    public static let empty = ClusterAdjustedSample(
        nominalSize: 0, wins: 0, blocks: 0, meanBlockSize: 0, designEffect: 1,
        effectiveSize: 0, effectiveWins: 0, assumedICC: EvidenceClustering.defaultICC,
        bucketMs: EvidenceClustering.defaultBucketMs, lower95: 0, upper95: 0
    )
}

public enum EvidenceClustering {
    /// Width of the time bucket that defines "concurrent". One minute matches the M1 bar
    /// cadence the engine evaluates.
    public static let defaultBucketMs: Double = 60_000
    /// Assumed intra-cluster correlation. A sensitivity assumption, never an empirically verified correlation.
    /// Default to full within-block dependence; never certify independence from timestamps.
    public static let defaultICC: Double = 1.0

    private static let cryptoBases: Set<String> = [
        "BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "LTC", "AVAX", "DOT", "LINK", "BNB", "MATIC",
    ]

    /// Maps an instrument to its correlation group.
    public static func group(for pair: String) -> CorrelationGroup {
        let upper = pair.uppercased()
        let legs = upper.split(separator: "/").map(String.init)
        if let base = legs.first, cryptoBases.contains(base) {
            return .crypto
        }
        if upper.contains("/USD") || upper.contains("USD/") {
            return .usd
        }
        if legs.count == 2 {
            return .cross
        }
        return .other
    }

    /// Floor of the observation time to its bucket start.
    public static func bucketStartMs(_ ms: Double, widthMs: Double = defaultBucketMs) -> Double {
        guard ms.isFinite, widthMs.isFinite, widthMs > 0 else { return 0 }
        let result = (ms / widthMs).rounded(.down) * widthMs
        return result.isFinite ? result : 0
    }

    /// Collapses concurrent observations inside a correlation group into one block, then
    /// applies the design-effect adjustment before computing a Wilson interval.
    public static func adjust(
        _ observations: [ClusteredObservation],
        icc: Double = defaultICC,
        bucketMs: Double = defaultBucketMs
    ) -> ClusterAdjustedSample {
        let usable = observations.filter { $0.capturedAtMs.isFinite }
        let n = usable.count
        guard n > 0 else { return .empty }

        let wins = usable.filter(\.won).count
        let width = bucketMs.isFinite && bucketMs >= defaultBucketMs ? bucketMs : defaultBucketMs
        var sizes: [Int] = []
        // Connected time blocks avoid treating prints on opposite sides of a clock bucket
        // boundary as independent. The whole correlated group shares a block.
        for group in CorrelationGroup.allCases {
            let times = usable.filter { Self.group(for: $0.pair) == group }
                .map(\.capturedAtMs).sorted()
            var previous: Double?
            for time in times {
                if let previous, time - previous < width {
                    sizes[sizes.count - 1] += 1
                } else { sizes.append(1) }
                previous = time
            }
        }
        let blocks = sizes.count
        let meanBlockSize = Double(n) / Double(blocks)
        let boundedICC = min(1, max(0, icc.isFinite ? icc : defaultICC))
        // Unequal block sizes require the size-weighted mean, not N / blocks.
        let weightedSize = sizes.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(n)
        let designEffect = 1 + (weightedSize - 1) * boundedICC
        let effectiveSize = Double(n) / designEffect
        let winRate = Double(wins) / Double(n)
        let effectiveWins = Int((winRate * effectiveSize).rounded(.down))
        // Fractional effective N avoids rounding an assumed evidence count upwards.
        let z = 1.959963984540054
        let z2 = z * z
        let denominator = 1 + z2 / effectiveSize
        let center = (winRate + z2 / (2 * effectiveSize)) / denominator
        let margin = z * sqrt(winRate * (1 - winRate) / effectiveSize
            + z2 / (4 * effectiveSize * effectiveSize)) / denominator
        let interval = (lower: max(0, center - margin), upper: min(1, center + margin))

        return ClusterAdjustedSample(
            nominalSize: n,
            wins: wins,
            blocks: blocks,
            meanBlockSize: meanBlockSize,
            designEffect: designEffect,
            effectiveSize: effectiveSize,
            effectiveWins: effectiveWins,
            assumedICC: boundedICC,
            bucketMs: width,
            lower95: interval.lower,
            upper95: interval.upper
        )
    }
}
