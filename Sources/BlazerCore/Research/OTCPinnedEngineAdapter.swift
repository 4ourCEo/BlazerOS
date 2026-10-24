import Foundation

/// Result of running the pinned production engine on eligible, normalized OTC inputs.
/// This is a comparison arm only: it is never published as an entry authorization.
public struct OTCPinnedEngineEvaluation: Codable, Sendable, Equatable {
    public let eligible: Bool
    public let decision: OTCSignalDecision
    public let score: Int?
    public let reason: String?
    public let engineSHA: String
    public let policy: String

    public init(eligible: Bool, decision: OTCSignalDecision, score: Int?,
                reason: String?, engineSHA: String, policy: String = "baseline") {
        self.eligible = eligible
        self.decision = decision
        self.score = score
        self.reason = reason
        self.engineSHA = engineSHA
        self.policy = policy
    }

    public static func ineligible(_ reason: String) -> OTCPinnedEngineEvaluation {
        OTCPinnedEngineEvaluation(
            eligible: false, decision: .wait, score: nil, reason: reason,
            engineSHA: EngineIdentity.loadedSHA1() ?? "unverified")
    }
}

public protocol OTCScanEngineEvaluating: Sendable {
    func evaluate(_ input: OTCResearchInput,
                  configuration: OTCResearchConfiguration) async -> OTCPinnedEngineEvaluation
}

/// Runs the pinned deterministic engine where the OTC data is technically eligible: completed,
/// aligned 60-second candles, a real bid/ask spread, and a full frozen history. OTC timing,
/// five-minute aggregation, and thresholds are not assumed to transfer; the adapter only feeds
/// normalized bars and reports the engine's own answer.
public struct PinnedEngineOTCAdapter: OTCScanEngineEvaluating {
    public init() {}

    public func evaluate(_ input: OTCResearchInput,
                         configuration: OTCResearchConfiguration) async -> OTCPinnedEngineEvaluation {
        guard input.instrument.isResearchOnly else { return .ineligible("Instrument is not OTC") }
        guard StrategyEngine.isReady else {
            return .ineligible(StrategyEngine.offlineReason ?? "Pinned engine unavailable")
        }
        guard input.candles.count >= configuration.minimumCandles,
              input.candles.allSatisfy({ $0.complete && $0.isValid }),
              Set(input.candles.map(\.intervalSeconds)) == [configuration.intervalSeconds]
        else {
            return .ineligible("OTC candles are not eligible for the pinned engine")
        }
        for index in 1..<input.candles.count {
            let previous = input.candles[index - 1].providerTimestamp.normalized
            let current = input.candles[index].providerTimestamp.normalized
            guard abs(current.timeIntervalSince(previous)
                        - TimeInterval(configuration.intervalSeconds)) <= 0.001 else {
                return .ineligible("OTC candles are not aligned to a single interval")
            }
        }
        guard let bid = input.quote.bid, let ask = input.quote.ask,
              bid.isFinite, ask.isFinite, bid > 0, ask >= bid, ask - bid > 0 else {
            return .ineligible("OTC quote has no usable bid/ask spread")
        }
        let m1 = input.candles.map {
            StrategyEngine.CandlePayload(
                time: $0.providerTimestamp.normalized.timeIntervalSince1970,
                open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
        let m5 = aggregateFiveMinute(input.candles)
        let marketInput = StrategyEngine.MarketInput(
            asset: input.instrument.identity.venueSymbol,
            source: "pocket-option-otc:" + input.source.providerID,
            candles1m: m1,
            candles5m: m5,
            lastPrice: input.quote.price,
            bid: bid,
            ask: ask,
            spread: ask - bid,
            expirySeconds: configuration.horizonSeconds,
            quoteAsOfMs: input.quoteTimestamp.timeIntervalSince1970 * 1_000,
            evaluatedAtMs: input.evaluatedAt.timeIntervalSince1970 * 1_000)
        do {
            let result = try await StrategyEngine.evaluate(input: marketInput)
            let signal = result.signal
            let decision: OTCSignalDecision
            switch signal.cabinetSide {
            case "HIGH": decision = .high
            case "LOW": decision = .low
            default: decision = .wait
            }
            let raw = signal.opportunity ?? signal.confidence ?? 0
            let score = raw.isFinite && (0...100).contains(raw) ? Int(raw.rounded()) : 0
            return OTCPinnedEngineEvaluation(
                eligible: true, decision: decision, score: score, reason: nil,
                engineSHA: EngineIdentity.loadedSHA1() ?? "unverified",
                policy: "baseline")
        } catch {
            return OTCPinnedEngineEvaluation(
                eligible: false, decision: .wait, score: nil,
                reason: "Pinned engine could not evaluate the OTC input",
                engineSHA: EngineIdentity.loadedSHA1() ?? "unverified")
        }
    }

    private func aggregateFiveMinute(_ candles: [ShadowCandle]) -> [StrategyEngine.CandlePayload] {
        var buckets: [Int: [ShadowCandle]] = [:]
        for candle in candles {
            let time = Int(candle.providerTimestamp.normalized.timeIntervalSince1970)
            buckets[time - time % 300, default: []].append(candle)
        }
        return buckets.keys.sorted().compactMap { key in
            guard let group = buckets[key], group.count == 5 else { return nil }
            return StrategyEngine.CandlePayload(
                time: Double(key),
                open: group[0].open,
                high: group.map(\.high).max() ?? group[0].high,
                low: group.map(\.low).min() ?? group[0].low,
                close: group[4].close)
        }
    }
}
