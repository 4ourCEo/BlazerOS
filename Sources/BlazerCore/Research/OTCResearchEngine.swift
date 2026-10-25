import Foundation

/// Required research decision vocabulary. It is deliberately not an execution order type.
public enum OTCSignalDecision: String, Codable, Sendable, Equatable, CaseIterable {
    case high = "HIGH"
    case low = "LOW"
    case wait = "WAIT"

    public var isDirectional: Bool { self == .high || self == .low }
}

public enum OTCFeedQuality: String, Codable, Sendable, Equatable {
    case live
    case degraded
    case stale
    case unavailable

    public static func classify(_ state: ShadowConnectionState) -> OTCFeedQuality {
        switch state {
        case .live: return .live
        case .connecting, .degraded: return .degraded
        case .throttled: return .stale
        case .disabled, .disconnected: return .unavailable
        }
    }
}

public enum OTCResearchVeto: String, Codable, Sendable, Equatable, CaseIterable {
    case wrongInstrument
    case invalidConfiguration
    case invalidQuote
    case staleQuote
    case futureQuote
    case insufficientHistory
    case invalidCandle
    case incompleteCandles
    case misalignedCandles
    case staleCandles
    case futureCandles
    case priceEnvelopeViolation
    case sessionClosed
    case feedNotLive
    case insufficientConfluence
    case conflictingSignals
}

public struct OTCResearchConfiguration: Codable, Sendable, Equatable {
    public let engineVersion: String
    public let strategyVersion: String
    public let horizonSeconds: Int
    public let intervalSeconds: Int
    public let minimumCandles: Int
    public let maximumQuoteAge: TimeInterval
    public let maximumCandleAge: TimeInterval
    public let quoteFreshFor: TimeInterval
    public let quoteExpiresAfter: TimeInterval
    /// Deterministic score floor for a directional research result. Never a probability.
    public let directionalThreshold: Int

    public init(
        engineVersion: String = "otc-research-engine-v1",
        strategyVersion: String = "otc-momentum-structure-v1",
        horizonSeconds: Int = 60,
        intervalSeconds: Int = 60,
        minimumCandles: Int = 24,
        maximumQuoteAge: TimeInterval = 5,
        // One completed interval is the usable window. A later evaluation is still a research
        // signal for the next 60 seconds, but its delay is recorded and bounded.
        maximumCandleAge: TimeInterval = 60,
        quoteFreshFor: TimeInterval = 3,
        quoteExpiresAfter: TimeInterval = 10,
        directionalThreshold: Int = 60
    ) {
        self.engineVersion = engineVersion
        self.strategyVersion = strategyVersion
        self.horizonSeconds = horizonSeconds
        self.intervalSeconds = intervalSeconds
        self.minimumCandles = minimumCandles
        self.maximumQuoteAge = maximumQuoteAge
        self.maximumCandleAge = maximumCandleAge
        self.quoteFreshFor = quoteFreshFor
        self.quoteExpiresAfter = quoteExpiresAfter
        self.directionalThreshold = directionalThreshold
    }

    public static let standard = OTCResearchConfiguration()
}

/// Normalized input to the OTC challenger. Candles must already be completed, aligned, and
/// ordered oldest → newest. The evaluator never fetches, downsamples, or invents missing bars.
public struct OTCResearchInput: Codable, Sendable, Equatable {
    public let instrument: OTCInstrumentIdentity
    public let source: ShadowDataSourceIdentity
    public let snapshotID: String
    public let quote: ShadowQuote
    public let quoteTimestamp: Date
    public let receivedAt: Date
    public let candles: [ShadowCandle]
    public let payoutPercent: Double?
    public let marketOpen: Bool
    public let connectionState: ShadowConnectionState
    public let verification: ShadowVerificationState
    public let provenance: String
    public let evaluatedAt: Date

    public init(
        instrument: OTCInstrumentIdentity,
        source: ShadowDataSourceIdentity,
        snapshotID: String,
        quote: ShadowQuote,
        quoteTimestamp: Date,
        receivedAt: Date,
        candles: [ShadowCandle],
        payoutPercent: Double? = nil,
        marketOpen: Bool = true,
        connectionState: ShadowConnectionState = .live,
        verification: ShadowVerificationState = .unverifiedVendorData,
        provenance: String = "OTC vendor observation",
        evaluatedAt: Date
    ) {
        self.instrument = instrument
        self.source = source
        self.snapshotID = snapshotID
        self.quote = quote
        self.quoteTimestamp = quoteTimestamp
        self.receivedAt = receivedAt
        self.candles = candles
        self.payoutPercent = payoutPercent
        self.marketOpen = marketOpen
        self.connectionState = connectionState
        self.verification = verification
        self.provenance = provenance
        self.evaluatedAt = evaluatedAt
    }

    public init(
        observation: ShadowMarketObservation,
        candles: [ShadowCandle],
        snapshotID: String,
        marketOpen: Bool? = nil
    ) {
        self.init(
            instrument: OTCInstrumentIdentity(
                instrumentID: "pocketoption:\(observation.identity.venueSymbol)",
                identity: observation.identity),
            source: observation.source,
            snapshotID: snapshotID,
            quote: observation.quote,
            quoteTimestamp: observation.providerTimestamp.normalized,
            receivedAt: observation.receivedAt,
            candles: candles,
            payoutPercent: observation.payoutPercent,
            marketOpen: marketOpen ?? observation.marketOpen ?? true,
            connectionState: observation.connectionState,
            verification: observation.verification,
            provenance: observation.provenance,
            evaluatedAt: observation.receivedAt)
    }

    public var feedQuality: OTCFeedQuality { .classify(connectionState) }
}

/// Deterministic feature readout. Values are rounded for cross-platform stability; the raw
/// strategy still uses the rounded values so repeated evaluation is byte-identical.
public struct OTCResearchFeatures: Codable, Sendable, Equatable {
    public let emaFast: Double?
    public let emaSlow: Double?
    public let atr: Double?
    public let atrPercent: Double?
    public let momentumATR: Double?
    public let rsi: Double?
    public let compressionRatio: Double?
    public let trendScore: Int
    public let momentumScore: Int
    public let structureScore: Int
    public let expansionScore: Int
    public let reversalScore: Int
    public let continuationScore: Int
    public let structure: String
    public let compression: String
    public let reversal: Bool
    public let continuation: Bool

    public static let empty = OTCResearchFeatures(
        emaFast: nil, emaSlow: nil, atr: nil, atrPercent: nil, momentumATR: nil,
        rsi: nil, compressionRatio: nil, trendScore: 0, momentumScore: 0,
        structureScore: 0, expansionScore: 0, reversalScore: 0,
        continuationScore: 0, structure: "unavailable", compression: "unavailable",
        reversal: false, continuation: false)
}

/// Research-only signal. No field can be used as an execution authorization.
public struct OTCResearchSignal: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: OTCInstrumentIdentity
    public let source: ShadowDataSourceIdentity
    public let engineVersion: String
    public let strategyVersion: String
    public let sourceSnapshotID: String
    public let evaluatedAt: Date
    public let horizonSeconds: Int
    public let decision: OTCSignalDecision
    /// "HIGH" / "LOW" for a directional result, nil for WAIT.
    public let direction: String?
    public let score: Int
    public let vetoes: [OTCResearchVeto]
    public let explanation: String
    public let quotePrice: Double
    public let quoteTimestamp: Date
    public let candleCloseTime: Date?
    public let quoteAgeSeconds: Double?
    public let candleAgeSeconds: Double?
    public let freshness: ShadowFreshness
    public let feedQuality: OTCFeedQuality
    public let payoutPercent: Double?
    public let verification: ShadowVerificationState
    public let features: OTCResearchFeatures
    public let researchOnly: Bool
    public let mayAuthorizeEntry: Bool
    /// Always false. A deterministic score is not a calibrated probability.
    public let scoreIsCalibratedWinProbability: Bool

    public var isActionableResearch: Bool {
        researchOnly && !mayAuthorizeEntry && decision.isDirectional && vetoes.isEmpty
    }
}

/// Isolated OTC challenger. It does not call OANDA, the pinned engine, the entry gate, or the
/// ledger. Every decision is a pure function of the frozen input and the fixed configuration.
public enum OTCResearchEvaluator {

    public static func evaluate(
        _ input: OTCResearchInput,
        configuration: OTCResearchConfiguration = .standard
    ) -> OTCResearchSignal {
        var vetoes: [OTCResearchVeto] = []

        func fail(_ veto: OTCResearchVeto) {
            if !vetoes.contains(veto) { vetoes.append(veto) }
        }

        let identity = input.instrument.identity
        guard input.instrument.isResearchOnly,
              identity.marketKind == .otc,
              identity.venue == "Pocket Option",
              identity.session == .weekendSession,
              identity.settlementBasis == .venueDisplayed,
              identity.venueSymbol.hasSuffix("_otc"),
              input.instrument.isValid
        else {
            vetoes.append(.wrongInstrument)
            return signal(input, configuration: configuration, decision: .wait,
                          score: 0, vetoes: vetoes, features: .empty,
                          quoteAge: nil, candleAge: nil)
        }
        if input.snapshotID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fail(.invalidConfiguration)
        }

        let quoteAge = input.evaluatedAt.timeIntervalSince(input.quoteTimestamp)
        let receivedAge = input.evaluatedAt.timeIntervalSince(input.receivedAt)
        if !input.quote.isValid {
            fail(.invalidQuote)
        }
        if !quoteAge.isFinite || !receivedAge.isFinite {
            fail(.futureQuote)
        } else {
            if quoteAge < -0.001 || receivedAge < -0.001 { fail(.futureQuote) }
            if quoteAge > configuration.maximumQuoteAge { fail(.staleQuote) }
        }
        if input.payoutPercent.map({ !$0.isFinite || $0 < 0 || $0 > 100 }).unwrap(or: false) {
            fail(.invalidQuote)
        }
        if !input.marketOpen { fail(.sessionClosed) }
        if input.feedQuality != .live { fail(.feedNotLive) }

        var candleAge: TimeInterval?
        if input.candles.count < configuration.minimumCandles {
            fail(.insufficientHistory)
        }
        if !input.candles.isEmpty {
            for candle in input.candles {
                if candle.identity != identity
                    || candle.intervalSeconds != configuration.intervalSeconds
                    || !candle.isValid {
                    fail(candle.identity == identity ? .invalidCandle : .wrongInstrument)
                }
                if !candle.complete { fail(.incompleteCandles) }
            }
            let interval = TimeInterval(configuration.intervalSeconds)
            for index in 1..<input.candles.count {
                let previous = input.candles[index - 1].providerTimestamp.normalized
                let current = input.candles[index].providerTimestamp.normalized
                let delta = current.timeIntervalSince(previous)
                if abs(delta - interval) > 0.001 {
                    fail(.misalignedCandles)
                }
            }
            // A series that is not phase-aligned to the declared interval is not a 60-second
            // research series even if the gaps between bars are uniform.
            for candle in input.candles {
                let phase = candle.providerTimestamp.normalized.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: interval)
                if min(abs(phase), abs(interval - abs(phase))) > 0.001 {
                    fail(.misalignedCandles)
                }
            }
            if let last = input.candles.last {
                let closeTime = last.providerTimestamp.normalized
                    .addingTimeInterval(TimeInterval(configuration.intervalSeconds))
                let age = input.evaluatedAt.timeIntervalSince(closeTime)
                candleAge = age
                if age < 0 { fail(.futureCandles) }
                if age > configuration.maximumCandleAge { fail(.staleCandles) }
                let atr = averageTrueRange(input.candles, period: 14)
                let tolerance = max((atr ?? 0) * 2, input.quote.price * 0.00005, 0.00005)
                if input.quote.price < last.low - tolerance || input.quote.price > last.high + tolerance {
                    fail(.priceEnvelopeViolation)
                }
            }
        }

        let features = features(for: input.candles)
        let net = features.trendScore + features.momentumScore + features.structureScore
            + features.expansionScore + features.reversalScore + features.continuationScore
        let score = min(100, abs(net))

        var decision: OTCSignalDecision = .wait
        if !vetoes.isEmpty {
            decision = .wait
        } else if abs(features.trendScore) >= 10, abs(features.momentumScore) >= 10,
                  features.trendScore.signum() != features.momentumScore.signum() {
            fail(.conflictingSignals)
            decision = .wait
        } else if score >= configuration.directionalThreshold {
            decision = net > 0 ? .high : .low
        } else {
            fail(.insufficientConfluence)
            decision = .wait
        }

        return signal(input, configuration: configuration, decision: decision,
                      score: score, vetoes: vetoes, features: features,
                      quoteAge: quoteAge.isFinite ? quoteAge : nil,
                      candleAge: candleAge)
    }

    private static func signal(
        _ input: OTCResearchInput,
        configuration: OTCResearchConfiguration,
        decision: OTCSignalDecision,
        score: Int,
        vetoes: [OTCResearchVeto],
        features: OTCResearchFeatures,
        quoteAge: TimeInterval?,
        candleAge: TimeInterval?
    ) -> OTCResearchSignal {
        let freshness = ShadowFreshness.classify(
            sourceTime: input.quoteTimestamp,
            receivedAt: input.receivedAt,
            now: input.evaluatedAt,
            freshFor: configuration.quoteFreshFor,
            expiresAfter: configuration.quoteExpiresAfter)
        let candleClose = input.candles.last.map {
            $0.providerTimestamp.normalized.addingTimeInterval(
                TimeInterval(configuration.intervalSeconds))
        }
        let reason = vetoes.map(\.rawValue).joined(separator: ",")
        let explanation: String
        if decision == .wait {
            explanation = "OTC research WAIT (score \(score))"
                + (reason.isEmpty ? "" : ": \(reason)")
        } else {
            explanation = "OTC research \(decision.rawValue) (score \(score), "
                + "trend \(features.trendScore), momentum \(features.momentumScore), "
                + "structure \(features.structureScore))"
        }
        return OTCResearchSignal(
            id: "\(input.instrument.instrumentID)#\(input.snapshotID)",
            instrument: input.instrument,
            source: input.source,
            engineVersion: configuration.engineVersion,
            strategyVersion: configuration.strategyVersion,
            sourceSnapshotID: input.snapshotID,
            evaluatedAt: input.evaluatedAt,
            horizonSeconds: configuration.horizonSeconds,
            decision: decision,
            direction: decision.isDirectional ? decision.rawValue : nil,
            score: score,
            vetoes: vetoes,
            explanation: explanation,
            quotePrice: input.quote.price,
            quoteTimestamp: input.quoteTimestamp,
            candleCloseTime: candleClose,
            quoteAgeSeconds: quoteAge.map(round),
            candleAgeSeconds: candleAge.map(round),
            freshness: freshness,
            feedQuality: input.feedQuality,
            payoutPercent: input.payoutPercent,
            verification: input.verification,
            features: features,
            researchOnly: true,
            mayAuthorizeEntry: false,
            scoreIsCalibratedWinProbability: false)
    }

    // MARK: - Deterministic features

    private static func features(for candles: [ShadowCandle]) -> OTCResearchFeatures {
        guard candles.count >= 8 else { return .empty }
        let closes = candles.map(\.close)
        let last = candles[candles.count - 1]
        let previous = candles[candles.count - 2]
        // Round every score-driving value before it can cross a threshold. Readout rounding alone
        // would leave the decision sensitive to the last bits of a platform's libm.
        let atr = averageTrueRange(candles, period: 14).map(round)
        let fastATR = averageTrueRange(candles, period: 5).map(round)
        let emaFast = exponentialMovingAverage(closes, period: min(8, closes.count)).map(round)
        let emaSlow = exponentialMovingAverage(closes, period: min(21, closes.count)).map(round)
        let momentumReference = closes[max(0, closes.count - 6)]
        let momentum = atr.map { $0 > 0 ? round((last.close - momentumReference) / $0) : 0 }
        let rsi = relativeStrengthIndex(closes, period: 14).map(round)
        let compressionRatio: Double? = {
            guard let atr, atr > 0, let fastATR else { return nil }
            return round(fastATR / atr)
        }()

        var trendScore = 0
        if let emaFast, let emaSlow, let atr, atr > 0 {
            let separation = emaFast - emaSlow
            if abs(separation) >= atr * 0.15 {
                trendScore = separation > 0 ? 20 : -20
            }
        }

        var momentumScore = 0
        if let momentum {
            if momentum >= 0.75 { momentumScore = 20 }
            else if momentum >= 0.25 { momentumScore = 10 }
            else if momentum <= -0.75 { momentumScore = -20 }
            else if momentum <= -0.25 { momentumScore = -10 }
        }

        let swing = swingStructure(candles)
        var structureScore = 0
        if swing.rising { structureScore = 15 }
        if swing.falling { structureScore = -15 }

        var expansionScore = 0
        let priorHigh = candles.suffix(6).prefix(5).map(\.high).max()
        let priorLow = candles.suffix(6).prefix(5).map(\.low).min()
        if let compressionRatio, compressionRatio < 0.8 {
            if let priorHigh, last.close > priorHigh { expansionScore = 15 }
            if let priorLow, last.close < priorLow { expansionScore = -15 }
        } else if let compressionRatio, compressionRatio > 1.2 {
            if last.close > last.open { expansionScore = 10 }
            if last.close < last.open { expansionScore = -10 }
        }

        let priorTrend = round(closes[closes.count - 2] - closes[max(0, closes.count - 11)])
        var reversalScore = 0
        var reversal = false
        if priorTrend < 0, last.close > last.open, last.close > previous.high {
            reversalScore = 10
            reversal = true
        } else if priorTrend > 0, last.close < last.open, last.close < previous.low {
            reversalScore = -10
            reversal = true
        }

        var continuationScore = 0
        var continuation = false
        // A reversal bar and a continuation bar are mutually exclusive. Counting the same breakout
        // as both would inflate confluence without adding independent evidence.
        if !reversal, last.close > previous.high, last.close > last.open {
            continuationScore = 10
            continuation = true
        } else if !reversal, last.close < previous.low, last.close < last.open {
            continuationScore = -10
            continuation = true
        }

        // Overbought pressure trims a long, oversold pressure trims a short; it never creates
        // a direction on its own.
        var rsiAdjustment = 0
        if let rsi {
            if rsi >= 75 { rsiAdjustment = -5 }
            if rsi <= 25 { rsiAdjustment = 5 }
        }
        momentumScore += rsiAdjustment

        let structure: String
        if swing.rising { structure = "higher-highs-higher-lows" }
        else if swing.falling { structure = "lower-highs-lower-lows" }
        else { structure = "mixed" }

        let compression: String
        if let compressionRatio {
            if compressionRatio < 0.8 { compression = "compressed" }
            else if compressionRatio > 1.2 { compression = "expanded" }
            else { compression = "normal" }
        } else {
            compression = "unavailable"
        }

        return OTCResearchFeatures(
            emaFast: emaFast.map(round),
            emaSlow: emaSlow.map(round),
            atr: atr.map(round),
            atrPercent: atr.map { round($0 / last.close * 100) },
            momentumATR: momentum.map(round),
            rsi: rsi.map(round),
            compressionRatio: compressionRatio.map(round),
            trendScore: trendScore,
            momentumScore: momentumScore,
            structureScore: structureScore,
            expansionScore: expansionScore,
            reversalScore: reversalScore,
            continuationScore: continuationScore,
            structure: structure,
            compression: compression,
            reversal: reversal,
            continuation: continuation)
    }

    private static func swingStructure(_ candles: [ShadowCandle]) -> (rising: Bool, falling: Bool) {
        guard candles.count >= 7 else { return (false, false) }
        let recent = Array(candles.suffix(7))
        let firstHighs = recent[0...2].map(\.high).max() ?? 0
        let secondHighs = recent[3...5].map(\.high).max() ?? 0
        let firstLows = recent[0...2].map(\.low).min() ?? 0
        let secondLows = recent[3...5].map(\.low).min() ?? 0
        return (secondHighs > firstHighs && secondLows > firstLows,
                secondHighs < firstHighs && secondLows < firstLows)
    }

    private static func exponentialMovingAverage(_ values: [Double], period: Int) -> Double? {
        guard period > 0, values.count >= period, values.allSatisfy(\.isFinite) else { return nil }
        let seed = values.prefix(period).reduce(0, +) / Double(period)
        let multiplier = 2.0 / Double(period + 1)
        return values.dropFirst(period).reduce(seed) { ema, value in
            (value - ema) * multiplier + ema
        }
    }

    private static func averageTrueRange(_ candles: [ShadowCandle], period: Int) -> Double? {
        guard period > 0, candles.count > period else { return nil }
        let slice = Array(candles.suffix(period + 1))
        var previousClose = slice[0].close
        var sum = 0.0
        for candle in slice.dropFirst() {
            let trueRange = max(candle.high - candle.low,
                                abs(candle.high - previousClose),
                                abs(candle.low - previousClose))
            guard trueRange.isFinite else { return nil }
            sum += trueRange
            previousClose = candle.close
        }
        let value = sum / Double(period)
        return value.isFinite ? value : nil
    }

    private static func relativeStrengthIndex(_ closes: [Double], period: Int) -> Double? {
        guard period > 0, closes.count > period else { return nil }
        let changes = zip(closes, closes.dropFirst()).map { $1 - $0 }
        let recent = changes.suffix(period)
        var gains = 0.0
        var losses = 0.0
        for change in recent {
            guard change.isFinite else { return nil }
            if change > 0 { gains += change } else { losses -= change }
        }
        if losses == 0 { return gains == 0 ? 50 : 100 }
        let rs = gains / losses
        return 100 - 100 / (1 + rs)
    }

    /// Eight significant digits, not a fixed number of decimal places. FX-scale ATRs are
    /// ~1.5e-4; decimal rounding at four places would distort them by tens of percent and move
    /// momentum/compression thresholds. Significant-digit rounding is still deterministic.
    private static func round(_ value: Double) -> Double {
        guard value.isFinite, value != 0 else { return value }
        let magnitude = floor(log10(abs(value)))
        let scale = pow(10, 8 - magnitude)
        guard scale.isFinite, scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }
}

private extension Optional where Wrapped == Bool {
    func unwrap(or fallback: Bool) -> Bool { self ?? fallback }
}
