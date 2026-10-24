import Foundation

// MARK: - CryptoEngine
// Swift-native signal generation for crypto 60s binary forward-testing.
//
// DESIGN PHILOSOPHY:
// BTC/USDT 1m candles have fundamentally different microstructure from FX:
//   - Volume is real, public, and predictive (FX has no centralised volume)
//   - Moves are driven by liquidation cascades and order-book absorption
//   - 60s momentum continuation is the primary exploitable edge at this timeframe
//   - Reversal signals are unreliable without order-book depth data
//
// This engine does NOT call scan-engine.js. It is entirely Swift.
//
// SIGNAL MODEL (60s horizon):
// High conviction = 3+ independent indicators agreeing on direction.
// The indicators are deliberately simple — complexity destroys edge on 1m crypto.
//
// INDICATORS (max contribution in points):
//   1. Volume-weighted momentum (last 3 candles)      — up to 28 pts
//   2. Candle body strength (ATR-normalised)           — up to 20 pts
//   3. Wick absorption / rejection                     — up to 15 pts
//   4. EMA(5) vs EMA(20) trend alignment               — up to 12 pts
//   5. Bollinger Band position (squeeze / boundary)    — up to 10 pts
//   6. Volume surge vs 13 prior-bar average (legacy suffix(14).dropLast window)               — up to 10 pts
//   7. Trade-count surge (institutional activity)      — up to 5 pts
//   Total possible: 116 pts
//
// The engine emits a directional candidate when the dominant score is >= 25 and the
// margin is >= 5. It does NOT decide whether the desk may enter: the desk gate
// (`CTAssets.minConviction`, spread, ATR) is separate and can veto a candidate.

public enum CryptoEngine {

    // MARK: - Output Signal

    public struct Signal: Sendable {
        public let side:        String      // "HIGH", "LOW", "WAIT"
        public let conviction:  Int         // 0–100
        public let why:         String      // primary reason
        public let evidence:    [String]    // list of confirming indicators
        public let highScore:   Int         // raw bullish score (for debugging)
        public let lowScore:    Int         // raw bearish score (for debugging)
        public let atrPips:     Double      // 14-period ATR in pips
        public let volumeSurge: Double      // current vol / 13 prior-bar avg vol (legacy window)
    }

    // MARK: - Entry Point

    public static func evaluate(
        batch: CryptoCandleBatch,
        asset: String = "BTC/USDT"
    ) -> Signal {
        let candles = batch.candles
        // Invalid provider data must fail closed before any floating-point to Int conversion.
        guard candles.allSatisfy(\.isValidMarketInput),
              CryptoCandle.isValidQuote(bid: batch.bid, ask: batch.ask),
              zip(candles, candles.dropFirst()).allSatisfy({ $0.time < $1.time }),
              CTAssets.pipScale(for: asset).isFinite,
              CTAssets.pipScale(for: asset) > 0 else {
            return Signal(side: "WAIT", conviction: 0,
                          why: "Invalid market data", evidence: [],
                          highScore: 0, lowScore: 0, atrPips: 0, volumeSurge: 0)
        }
        guard candles.count >= 22 else {
            return waitSignal(why: "Insufficient candles (\(candles.count) < 22)", candles: candles, asset: asset)
        }

        let pipScale = CTAssets.pipScale(for: asset)

        // Pre-compute shared indicators
        let atr14     = computeATR(candles: Array(candles.suffix(15)))
        let atrPips   = atr14 / pipScale
        let ema5      = computeEMA(candles: candles, period: 5)
        let ema20     = computeEMA(candles: candles, period: 20)
        let bb        = computeBollingerBands(candles: candles, period: 20)
        let avgVol    = averageQuoteVolume(candles: Array(candles.suffix(14).dropLast(1)))  // exclude current
        let avgTrades = averageTrades(candles: Array(candles.suffix(14).dropLast(1)))
        let recent3   = Array(candles.suffix(3))

        var highScore = 0
        var lowScore  = 0
        var evidence: [String] = []

        // ──────────────────────────────────────────────────────────────
        // 1. Volume-weighted momentum (last 3 candles, recent = 3x weight)
        //    Points: up to 28 (10 × 1 + 10 × 2 + 10 × 3 — then normalized to 28 max)
        //    Rationale: short-term momentum persistence on 60s crypto is the
        //    primary exploitable signal at this timeframe.
        // ──────────────────────────────────────────────────────────────
        var momentumHigh = 0.0
        var momentumLow  = 0.0
        let momentumWeights = [1.0, 2.0, 3.0]  // oldest → newest

        for (i, candle) in recent3.enumerated() {
            let weight     = momentumWeights[i]
            let volMult    = avgVol > 0 ? min(2.0, candle.quoteVolume / avgVol) : 1.0
            let bodyFactor = atr14 > 0 ? min(1.0, candle.bodySize / atr14) : 0.5

            if candle.isBullish {
                momentumHigh += weight * volMult * bodyFactor
            } else {
                momentumLow  += weight * volMult * bodyFactor
            }
        }
        // max raw per direction = 1×2×1 + 2×2×1 + 3×2×1 = 2+4+6 = 12
        // normalize to 28 pts
        let momentumMax     = 1.0*2.0 + 2.0*2.0 + 3.0*2.0  // = 12.0 (correct)
        let momentumHighPts = Int((momentumHigh / momentumMax) * 28.0)
        let momentumLowPts  = Int((momentumLow  / momentumMax) * 28.0)

        highScore += momentumHighPts
        lowScore  += momentumLowPts

        let net = momentumHighPts - momentumLowPts
        if abs(net) >= 8 {
            let dir = net > 0 ? "Bullish" : "Bearish"
            evidence.append("\(dir) 3-candle volume-weighted momentum (\(abs(net))pts)")
        }

        // ──────────────────────────────────────────────────────────────
        // 2. Candle body strength — last candle, ATR-normalised
        //    A strong body (>60% of ATR) in one direction is a high-quality signal.
        //    Doji-like candles (<15% of ATR) contribute nothing.
        //    Points: up to 20
        // ──────────────────────────────────────────────────────────────
        if let last = candles.last {
            let bodyRatio = atr14 > 0 ? last.bodySize / atr14 : 0
            let bodyPts   = Int(min(20.0, bodyRatio * 30.0))  // 0.67 ATR ratio → 20pts

            if last.isBullish {
                highScore += bodyPts
                if bodyRatio >= 0.5 {
                    evidence.append("Strong bullish body (\(String(format: "%.0f", bodyRatio * 100))% ATR)")
                }
            } else {
                lowScore += bodyPts
                if bodyRatio >= 0.5 {
                    evidence.append("Strong bearish body (\(String(format: "%.0f", bodyRatio * 100))% ATR)")
                }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // 3. Wick absorption / rejection — last candle
        //    Lower wick dominant → buying pressure absorbed selling → HIGH
        //    Upper wick dominant → selling pressure absorbed buying → LOW
        //    Only applies when wick > 1.5× body AND wick > 0.25× ATR (meaningful size)
        //    Points: up to 15
        // ──────────────────────────────────────────────────────────────
        if let last = candles.last {
            let minWick = atr14 * 0.25

            // Bullish absorption (long lower wick)
            if last.lowerWick > 1.5 * last.bodySize && last.lowerWick > minWick {
                let wickStrength = atr14 > 0 ? Int(min(15.0, (last.lowerWick / atr14) * 20)) : 0
                highScore += wickStrength
                evidence.append("Bullish lower-wick absorption (\(String(format: "%.1f", last.lowerWick / pipScale))p wick)")
            }

            // Bearish rejection (long upper wick)
            if last.upperWick > 1.5 * last.bodySize && last.upperWick > minWick {
                let wickStrength = atr14 > 0 ? Int(min(15.0, (last.upperWick / atr14) * 20)) : 0
                lowScore += wickStrength
                evidence.append("Bearish upper-wick rejection (\(String(format: "%.1f", last.upperWick / pipScale))p wick)")
            }
        }

        // ──────────────────────────────────────────────────────────────
        // 4. EMA(5) vs EMA(20) trend alignment
        //    Trend context — are we trading with or against the micro-trend?
        //    Points: up to 12
        // ──────────────────────────────────────────────────────────────
        if ema5 > ema20 {
            let separation = ema5 - ema20
            let sepPips    = separation / pipScale
            let emaPts     = Int(min(12.0, sepPips * 2))
            highScore += emaPts
            if emaPts >= 6 { evidence.append("EMA(5) above EMA(20) by \(String(format: "%.1f", sepPips))p") }
        } else if ema20 > ema5 {
            let separation = ema20 - ema5
            let sepPips    = separation / pipScale
            let emaPts     = Int(min(12.0, sepPips * 2))
            lowScore += emaPts
            if emaPts >= 6 { evidence.append("EMA(5) below EMA(20) by \(String(format: "%.1f", sepPips))p") }
        }

        // ──────────────────────────────────────────────────────────────
        // 5. Bollinger Band position
        //    Near lower band → potential bounce → HIGH
        //    Near upper band → potential rejection → LOW
        //    IMPORTANT: for crypto momentum we weight this LIGHTLY
        //    because trending moves can pin price at a band for many candles.
        //    Points: up to 10
        // ──────────────────────────────────────────────────────────────
        if let price = candles.last?.close, bb.bandwidth > 0 {
            let percentB = (price - bb.lower) / bb.bandwidth  // 0 = at lower, 1 = at upper

            if percentB < 0.15 {
                // Very close to lower band — bounce likely if momentum also bullish
                let bbPts = Int((0.15 - percentB) / 0.15 * 10)
                highScore += bbPts
                evidence.append("Price at lower BB (%B=\(String(format: "%.2f", percentB)))")
            } else if percentB > 0.85 {
                // Very close to upper band
                let bbPts = Int((percentB - 0.85) / 0.15 * 10)
                lowScore += bbPts
                evidence.append("Price at upper BB (%B=\(String(format: "%.2f", percentB)))")
            }

            // BB Squeeze: very tight bands = imminent breakout, direction unknown → reduce conviction
            let bandwidthPct = bb.bandwidth / bb.middle
            if bandwidthPct < 0.002 {
                // Deduct 5 from each score; preserve the legacy symmetric squeeze penalty
                highScore = max(0, highScore - 5)
                lowScore  = max(0, lowScore  - 5)
                evidence.append("BB squeeze active — direction deduction applied")
            }
        }

        // ──────────────────────────────────────────────────────────────
        // 6. Volume surge vs 13 prior-bar average (legacy suffix(14).dropLast window)
        //    High volume on the current candle confirms the move is institutional.
        //    Low volume = retail noise — deduct points.
        //    Points: +10 (surge), -5 (sub-average)
        // ──────────────────────────────────────────────────────────────
        let volSurge: Double
        if let currentVol = candles.last?.quoteVolume, avgVol > 0 {
            volSurge = currentVol / avgVol
        } else {
            volSurge = 1.0
        }

        if let last = candles.last {
            if volSurge >= 1.5 {
                let volPts = Int(min(10.0, (volSurge - 1.0) * 6))
                if last.isBullish {
                    highScore += volPts
                } else {
                    lowScore += volPts
                }
                evidence.append("Volume surge \(String(format: "%.1f", volSurge))× average")
            } else if volSurge < 0.6 {
                // Suspiciously low volume — dampen conviction
                highScore = max(0, highScore - 5)
                lowScore  = max(0, lowScore  - 5)
            }
        }

        // ──────────────────────────────────────────────────────────────
        // 7. Trade-count surge (large number of individual trades = algo activity)
        //    Points: up to 5
        // ──────────────────────────────────────────────────────────────
        if let lastTrades = candles.last?.trades, avgTrades > 0 {
            let tradeSurge = Double(lastTrades) / avgTrades
            if tradeSurge >= 1.5, let last = candles.last {
                let tPts = Int(min(5.0, (tradeSurge - 1.0) * 3))
                if last.isBullish { highScore += tPts } else { lowScore += tPts }
            }
        }

        // ──────────────────────────────────────────────────────────────
        // 8. Trapped-Liquidity Engulfing Confirmation (Craig Percoco Model)
        //    A decisive engulfing candle that completely absorbs the prior
        //    candle's body with above-average volume confirms trapped participants
        //    are being squeezed, fueling immediate follow-through.
        //    Points: up to 16
        // ──────────────────────────────────────────────────────────────
        if let last = candles.last, candles.count >= 2 {
            let prev = candles[candles.count - 2]
            let isBullishEngulfing = last.isBullish && !prev.isBullish
                && last.close > prev.open && last.open < prev.close
                && (last.high - last.low) > (prev.high - prev.low)
                && volSurge >= 1.15

            let isBearishEngulfing = !last.isBullish && prev.isBullish
                && last.close < prev.open && last.open > prev.close
                && (last.high - last.low) > (prev.high - prev.low)
                && volSurge >= 1.15

            if isBullishEngulfing {
                highScore += 16
                evidence.append("Bullish engulfing displacement trapping sellers (\(String(format: "%.1f", volSurge))× vol)")
            } else if isBearishEngulfing {
                lowScore += 16
                evidence.append("Bearish engulfing displacement trapping buyers (\(String(format: "%.1f", volSurge))× vol)")
            }
        }

        // ──────────────────────────────────────────────────────────────
        // Determine verdict
        // ──────────────────────────────────────────────────────────────

        // Neither side is compelling — dominant score below minimum threshold
        if highScore < 25 && lowScore < 25 {
            return waitSignal(
                why: "Insufficient directional confluence (H:\(highScore) L:\(lowScore))",
                candles: candles, asset: asset
            )
        }

        let dominant = highScore >= lowScore ? "HIGH" : "LOW"
        let domScore = dominant == "HIGH" ? highScore : lowScore
        let oppScore = dominant == "HIGH" ? lowScore  : highScore

        // Signals must be sufficiently one-sided — within 5 pts = conflicted
        if domScore - oppScore < 5 {
            return waitSignal(
                why: "Conflicted signal (H:\(highScore) vs L:\(lowScore) — margin too small)",
                candles: candles, asset: asset
            )
        }

        // ──────────────────────────────────────────────────────────────
        // Advanced Quantitative Safeguards (Videos 1, 2, 3)
        // ──────────────────────────────────────────────────────────────

        // 1. Trend/Microstructure Confluence Gate (Video 2)
        // Never take a 60s binary trade directly against the micro-trend EMA alignment
        if dominant == "HIGH" && ema5 < ema20 {
            return waitSignal(
                why: "Trend conflict: HIGH signal rejected against EMA(5) < EMA(20) downtrend",
                candles: candles, asset: asset
            )
        } else if dominant == "LOW" && ema5 > ema20 {
            return waitSignal(
                why: "Trend conflict: LOW signal rejected against EMA(5) > EMA(20) uptrend",
                candles: candles, asset: asset
            )
        }

        // 2. Liquidity Sweep & False Breakout Rejection Gate (Video 1)
        // Veto continuation if price swept a 20-bar extreme without a clean close beyond it
        if candles.count >= 21, let last = candles.last {
            let prior20 = candles.dropLast(1).suffix(20)
            let priorHigh = prior20.map(\.high).max() ?? Double.infinity
            let priorLow = prior20.map(\.low).min() ?? 0.0
            let totalRange = last.high - last.low

            if dominant == "HIGH", last.high > priorHigh, totalRange > 0 {
                let upperWickRatio = last.upperWick / totalRange
                let closedBelowSweep = last.close <= priorHigh
                if upperWickRatio > 0.25 || closedBelowSweep {
                    return waitSignal(
                        why: "Liquidity sweep veto: pierced 20-bar high with \(Int(upperWickRatio * 100))% upper wick rejection",
                        candles: candles, asset: asset
                    )
                }
            } else if dominant == "LOW", last.low < priorLow, totalRange > 0 {
                let lowerWickRatio = last.lowerWick / totalRange
                let closedAboveSweep = last.close >= priorLow
                if lowerWickRatio > 0.25 || closedAboveSweep {
                    return waitSignal(
                        why: "Liquidity sweep veto: pierced 20-bar low with \(Int(lowerWickRatio * 100))% lower wick rejection",
                        candles: candles, asset: asset
                    )
                }
            }
        }

        // 3. Market Overextension & Exhaustion Veto (Video 3)
        // Veto continuation after an oversized impulse expansion (>2.2x ATR) or outer BB puncture
        if let last = candles.last, atr14 > 0 {
            let candleRange = last.high - last.low
            let isClimax = candleRange > (2.2 * atr14)
            let isBBOverextended = bb.bandwidth > 0 && (
                (dominant == "HIGH" && last.close > bb.upper + (0.35 * bb.bandwidth)) ||
                (dominant == "LOW" && last.close < bb.lower - (0.35 * bb.bandwidth))
            )
            if isClimax || isBBOverextended {
                return waitSignal(
                    why: "Exhaustion veto: candle overextended (\(String(format: "%.1f", candleRange / atr14))x ATR) — mean reversion risk",
                    candles: candles, asset: asset
                )
            }
        }

        // Legacy display floor (55) and cap (97); raw scores remain available.
        // Entry still requires CTAssets.minConviction (75); this is not a probability.
        let conviction = min(97, max(55, domScore))
        let primaryReason = directionalReason(
            for: dominant,
            evidence: evidence,
            fallback: "\(dominant) momentum dominates (\(domScore) vs \(oppScore))"
        )

        return Signal(
            side:        dominant,
            conviction:  conviction,
            why:         primaryReason,
            evidence:    evidence,
            highScore:   highScore,
            lowScore:    lowScore,
            atrPips:     atrPips,
            volumeSurge: volSurge
        )
    }

    // MARK: - Evidence matching

    /// Never let the headline contradict the chosen side (for example, a bullish momentum
    /// line attached to a LOW signal).
    private static func directionalReason(for side: String, evidence: [String], fallback: String) -> String {
        let bullish = ["bullish", "above", "lower-wick", "lower bb", "swept the low", "bounce"]
        let bearish = ["bearish", "below", "upper-wick", "upper bb", "swept the high", "reject"]
        let keywords = side == "HIGH" ? bullish : bearish
        if let match = evidence.first(where: { line in
            let lower = line.lowercased()
            return keywords.contains(where: { lower.contains($0) })
        }) {
            return match
        }
        return fallback
    }

    // MARK: - WAIT Helper
    private static func waitSignal(why: String, candles: [CryptoCandle], asset: String) -> Signal {
        let atr14   = computeATR(candles: Array(candles.suffix(15)))
        let pipScale = CTAssets.pipScale(for: asset)
        let avgVol  = averageQuoteVolume(candles: Array(candles.suffix(14).dropLast(1)))
        let volSurge = (candles.last?.quoteVolume ?? 0) / max(1, avgVol)
        return Signal(
            side: "WAIT", conviction: 0, why: why,
            evidence: [], highScore: 0, lowScore: 0,
            atrPips: atr14 / pipScale, volumeSurge: volSurge
        )
    }

    // MARK: - Indicators

    /// 14-period Average True Range (price units, not pips)
    public static func computeATR(candles: [CryptoCandle]) -> Double {
        guard candles.count >= 2, candles.allSatisfy(\.isValidMarketInput) else { return 0 }
        var trs: [Double] = []
        var prev = candles[0]
        for bar in candles.dropFirst() {
            let tr = Swift.max(
                bar.high - bar.low,
                abs(bar.high - prev.close),
                abs(bar.low  - prev.close)
            )
            trs.append(tr)
            prev = bar
        }
        let window = trs.suffix(14)
        return window.reduce(0, +) / Double(window.count)
    }

    /// Exponential Moving Average over the last `period` candles
    static func computeEMA(candles: [CryptoCandle], period: Int) -> Double {
        guard period > 0, !candles.isEmpty else { return 0 }
        guard candles.count >= period else {
            return candles.map(\.close).reduce(0, +) / Double(candles.count)
        }
        let k      = 2.0 / Double(period + 1)
        let window = candles.suffix(period * 3)  // legacy seed: short histories receive fewer updates
        var ema    = window.prefix(period).map(\.close).reduce(0, +) / Double(period)
        for bar in window.dropFirst(period) {
            ema = bar.close * k + ema * (1 - k)
        }
        return ema
    }

    /// Bollinger Bands (20-period, 2 std dev)
    struct BollingerBands {
        let upper: Double
        let middle: Double
        let lower: Double
        var bandwidth: Double { upper - lower }
    }

    static func computeBollingerBands(candles: [CryptoCandle], period: Int = 20) -> BollingerBands {
        let window = candles.suffix(period).map(\.close)
        guard window.count >= period else {
            let mid = window.reduce(0, +) / Double(window.count)
            return BollingerBands(upper: mid, middle: mid, lower: mid)
        }
        let sma = window.reduce(0, +) / Double(period)
        let variance = window.map { ($0 - sma) * ($0 - sma) }.reduce(0, +) / Double(period)
        let std = sqrt(variance)
        return BollingerBands(upper: sma + 2 * std, middle: sma, lower: sma - 2 * std)
    }

    /// Average quote volume of the supplied candles (excludes the in-progress candle — pass suffix(14).dropLast(1))
    static func averageQuoteVolume(candles: [CryptoCandle]) -> Double {
        guard !candles.isEmpty else { return 0 }
        return candles.map(\.quoteVolume).reduce(0, +) / Double(candles.count)
    }

    /// Average trade count
    static func averageTrades(candles: [CryptoCandle]) -> Double {
        guard !candles.isEmpty else { return 0 }
        return candles.map { Double($0.trades) }.reduce(0, +) / Double(candles.count)
    }
}
