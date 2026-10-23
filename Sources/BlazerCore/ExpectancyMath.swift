import Foundation

/// Core mathematical foundation of trading expectancy, risk management, and capital allocation.
/// Grounded in the principle that trading is a mechanical, probability-driven process:
/// Expectancy = (Win Probability * Payout) - (Loss Probability * Risk).
public enum ExpectancyMath: Sendable {
    /// Standard baseline payout assumed across broker venues (e.g. 88% net profit on winning fixed-time contract).
    public static let standardPayout: Double = 0.88

    /// Standard maximum account risk per contract (1% - 2% ceiling for disciplined risk management).
    public static let maxAccountRiskCeiling: Double = 0.02

    /// Calculates the required break-even win rate for a given broker payout ratio.
    /// Formula: BreakEven = 1 / (1 + payoutRatio)
    /// At 88% (0.88) payout: 1 / 1.88 ≈ 53.19%
    public static func breakEvenWinRate(payoutRatio: Double = standardPayout) -> Double {
        guard payoutRatio.isFinite, payoutRatio > 0 else { return 1.0 }
        return 1.0 / (1.0 + payoutRatio)
    }

    /// Computes the net expected value (EV) per unit of risk for a given win rate and broker payout ratio.
    /// Formula: EV = (WinRate * Payout) - ((1 - WinRate) * 1.0)
    public static func expectedValue(winRate: Double, payoutRatio: Double = standardPayout, stake: Double = 1.0) -> Double {
        guard winRate.isFinite, payoutRatio.isFinite, stake.isFinite, payoutRatio > 0, stake >= 0 else { return 0.0 }
        let clampedRate = max(0.0, min(1.0, winRate))
        let evPerUnit = (clampedRate * payoutRatio) - ((1.0 - clampedRate) * 1.0)
        let result = evPerUnit * stake
        return result.isFinite ? result : 0
    }

    /// Full Kelly criterion fraction for fixed-payout binary contracts.
    /// Formula: f* = (p * b - (1 - p)) / b = Expectancy / b
    /// where p is win rate and b is net payout ratio.
    /// Returns 0.0 if expectancy is non-positive (instructing the trader to stay flat).
    public static func fullKellyFraction(winRate: Double, payoutRatio: Double = standardPayout) -> Double {
        guard payoutRatio.isFinite, payoutRatio > 0, winRate.isFinite else { return 0.0 }
        let ev = expectedValue(winRate: winRate, payoutRatio: payoutRatio)
        guard ev > 0 else { return 0.0 }
        return min(1.0, ev / payoutRatio)
    }

    /// Prudent, capital-preserving stake calculation using fractional Kelly (quarter-Kelly)
    /// clamped to a strict risk ceiling (default 2% of bankroll).
    /// If expected value <= 0, returns 0.0 ("Flat is a position").
    public static func recommendedStake(
        bankroll: Double,
        winRate: Double,
        payoutRatio: Double = standardPayout,
        fraction: Double = 0.25,
        maxRiskCeiling: Double = maxAccountRiskCeiling
    ) -> Double {
        guard bankroll.isFinite, bankroll > 0, fraction.isFinite, (0...1).contains(fraction),
              maxRiskCeiling.isFinite, (0...maxAccountRiskCeiling).contains(maxRiskCeiling) else { return 0.0 }
        let kelly = fullKellyFraction(winRate: winRate, payoutRatio: payoutRatio)
        guard kelly > 0 else { return 0.0 } // Negative or zero EV -> Flat is a position

        let fractionalKelly = kelly * fraction
        let effectiveRisk = min(fractionalKelly, maxRiskCeiling)
        return bankroll * effectiveRisk
    }

    /// Market posture recommendation derived directly from mathematical edge.
    public enum Posture: String, Sendable, Equatable {
        /// Edge is non-positive or unverified; preserving capital is the highest EV action.
        case stayFlat = "FLAT IS A POSITION"
        /// Positive mathematical expectancy with statistical significance.
        case tradeWithEdge = "POSITIVE EXPECTANCY"
        /// Marginal edge requiring reduced sizing and calibration.
        case calibrating = "CALIBRATING RISK"
    }

    /// Evaluates current trading posture from sample size and win rate.
    public static func evaluatePosture(wins: Int, sampleSize: Int, payoutRatio: Double = standardPayout) -> Posture {
        guard wins >= 0, wins <= sampleSize, payoutRatio.isFinite, payoutRatio > 0 else { return .stayFlat }
        guard sampleSize >= 15 else { return .calibrating }
        let be = breakEvenWinRate(payoutRatio: payoutRatio)
        let wr = Double(wins) / Double(sampleSize)
        let (lower95, _) = EdgeEvidence.wilsonScoreInterval(wins: wins, total: sampleSize)

        if wr <= be || lower95 < be * 0.90 {
            return .stayFlat
        } else if lower95 >= be {
            return .tradeWithEdge
        } else {
            return .calibrating
        }
    }

    /// Result of a Monte Carlo bootstrap resample test (500 iterations).
    public struct BootstrapResult: Sendable, Equatable {
        public var iterations: Int
        public var sampleSize: Int
        public var observedWinRate: Double
        public var medianWinRate: Double
        public var p5WinRate: Double
        public var p95WinRate: Double
        public var maxDrawdownMedian: Double
        public var maxDrawdownWorstCase: Double
        public var positiveEVRate: Double
    }

    /// Performs bootstrap resampling (default 500 iterations) to stress-test sequence vulnerability and drawdown risk.
    public static func bootstrapStressTest(
        wins: Int,
        sampleSize: Int,
        iterations: Int = 500,
        payoutRatio: Double = standardPayout
    ) -> BootstrapResult? {
        guard sampleSize > 0, wins >= 0, wins <= sampleSize, iterations > 0, payoutRatio.isFinite, payoutRatio > 0 else { return nil }
        let observedRate = Double(wins) / Double(sampleSize)
        let be = breakEvenWinRate(payoutRatio: payoutRatio)

        var simulatedWinRates: [Double] = []
        var maxDrawdowns: [Double] = []
        var positiveEVCount = 0

        // Fixed seed generator for deterministic testability
        var rngState: UInt64 = 0x123456789abcdef0

        func nextDouble() -> Double {
            rngState ^= rngState << 13
            rngState ^= rngState >> 7
            rngState ^= rngState << 17
            return Double(rngState & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        }

        for _ in 0..<iterations {
            var simWins = 0
            var peak: Double = 0.0
            var currentEquity: Double = 0.0
            var maxDD: Double = 0.0

            for _ in 0..<sampleSize {
                let isWin = nextDouble() < observedRate
                if isWin {
                    simWins += 1
                    currentEquity += payoutRatio
                } else {
                    currentEquity -= 1.0
                }
                if currentEquity > peak {
                    peak = currentEquity
                }
                let dd = peak - currentEquity
                if dd > maxDD {
                    maxDD = dd
                }
            }

            let simRate = Double(simWins) / Double(sampleSize)
            simulatedWinRates.append(simRate)
            maxDrawdowns.append(maxDD)
            if simRate > be {
                positiveEVCount += 1
            }
        }

        simulatedWinRates.sort()
        maxDrawdowns.sort()

        let p5Index = min(iterations - 1, max(0, Int(Double(iterations) * 0.05)))
        let p50Index = min(iterations - 1, max(0, Int(Double(iterations) * 0.50)))
        let p95Index = min(iterations - 1, max(0, Int(Double(iterations) * 0.95)))

        return BootstrapResult(
            iterations: iterations,
            sampleSize: sampleSize,
            observedWinRate: observedRate,
            medianWinRate: simulatedWinRates[p50Index],
            p5WinRate: simulatedWinRates[p5Index],
            p95WinRate: simulatedWinRates[p95Index],
            maxDrawdownMedian: maxDrawdowns[p50Index],
            maxDrawdownWorstCase: maxDrawdowns[iterations - 1],
            positiveEVRate: Double(positiveEVCount) / Double(iterations)
        )
    }
}

