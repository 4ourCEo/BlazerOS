import Foundation

/// Translates existing authorities into the composition contract without changing them.
public enum AdaptiveOpportunityAdapters {
    public static func effectiveConfiguration(strategyID: String, instrument: String) -> StrategyEffectiveConfiguration? {
        switch strategyID {
        case "ORB_BREAK_RETEST_V1", "ORB_BREAK_RETEST":
            let c = ORBBreakRetestV1.configuration(for: instrument)
            return .init(profileID: "ORB_BREAK_RETEST", profileVersion: c.strategyVersion,
                evaluatorVersion: c.engineVersion, adapterVersion: StrategyImplementationDigests.adapterVersion,
                instrument: instrument, stringSettings: [
                    "timeZoneIdentifier": c.timeZoneIdentifier,
                    "adapter.candleSource": "candles1m_completed",
                    "adapter.planConstruction": "ORBDecision.plan_as_emitted",
                    "adapter.spreadUnits": "instrument_price_units"
                ], numericSettings: [
                    "openingHour": Double(c.openingHour), "openingMinute": Double(c.openingMinute),
                    "openingRangeMinutes": Double(c.openingRangeMinutes), "barMinutes": Double(c.barMinutes),
                    "minimumBreakoutThreshold": c.minimumBreakoutThreshold,
                    "retestTolerance": c.retestTolerance, "confirmationBuffer": c.confirmationBuffer,
                    "stopBuffer": c.stopBuffer, "rewardRisk": c.rewardRisk,
                    "maximumSetupMinutes": Double(c.maximumSetupMinutes), "maximumSpread": c.maximumSpread,
                    "riskFraction": c.riskFraction, "plannedUnits": c.plannedUnits
                ])
        case "CANDIDATE_001_CHOCH_FVG_FIB":
            let c = Candidate001Configuration(requireM15Confirmation: true, signalFreshnessSeconds: 300)
            return .init(profileID: "CHOCH_FVG_FIB", profileVersion: Candidate001Analyzer.version,
                evaluatorVersion: Candidate001Analyzer.version, adapterVersion: StrategyImplementationDigests.adapterVersion,
                instrument: instrument, stringSettings: [
                    "adapter.m1Source": "input.candles1m",
                    "adapter.m15Aggregation": "epoch-15m;exactly-3-m5;300000ms-adjacent;exact-bucket-start;first-open-max-high-min-low-last-close;causal-m1-close;latest-only-no-fallback",
                    "adapter.planConstruction": "none;candidate-observation-only",
                    "adapter.spreadUnits": "instrument_price_units"
                ], numericSettings: [
                    "swingLeftBars": Double(c.swingLeftBars), "swingRightBars": Double(c.swingRightBars),
                    "minimumFVGSize": c.minimumFVGSize, "expirationBars": Double(c.expirationBars),
                    "signalFreshnessSeconds": Double(c.resolvedSignalFreshnessSeconds),
                    "requireM15Confirmation": c.requireM15Confirmation ? 1 : 0,
                    "pipScale": Assets.pipScale(for: instrument), "maximumSpreadPips": 3
                ])
        case "CANDIDATE_002_AUCTION_FAILURE":
            let c = Candidate002Configuration(signalFreshnessSeconds: 120)
            return .init(profileID: "AUCTION_FAILURE", profileVersion: Candidate002Analyzer.version,
                evaluatorVersion: Candidate002Analyzer.version, adapterVersion: StrategyImplementationDigests.adapterVersion,
                instrument: instrument, stringSettings: [
                    "adapter.m1Source": "input.candles1m",
                    "adapter.m15Aggregation": "epoch-15m;exactly-3-m5;300000ms-adjacent;exact-bucket-start;first-open-max-high-min-low-last-close;causal-failure-close;latest-only-no-fallback",
                    "adapter.planConstruction": "prior-lookback-range;entry-confirmation-close;stop-failure-extreme-plus/minus-one-pip;target-opposite-range-edge;units-1;riskFraction-0.01;validated-only-if-plan.validation-empty",
                    "adapter.spreadUnits": "instrument_price_units"
                ], numericSettings: [
                    "lookbackBars": Double(c.lookbackBars), "confirmationBars": Double(c.confirmationBars),
                    "signalFreshnessSeconds": Double(c.resolvedSignalFreshnessSeconds),
                    "locationTolerance": c.locationTolerance, "fibonacciRatio": c.fibonacciRatio,
                    "pipScale": Assets.pipScale(for: instrument), "planUnits": 1,
                    "planRiskFraction": 0.01, "planMaximumSpreadPips": 3
                ])
        case "baseline", "continuation", "reversal", "regime":
            return .init(profileID: "LEGACY_V1", profileVersion: "pinned-control",
                evaluatorVersion: "JSC_\(strategyID)", adapterVersion: StrategyImplementationDigests.adapterVersion,
                instrument: instrument, stringSettings: [
                    "adapter.candleSource": "StrategyEngine.MarketInput.completedCandles",
                    "adapter.policy": strategyID,
                    "adapter.quoteFreshnessSeconds": "8",
                    "adapter.planConstruction": "none;directional-control-only",
                    "adapter.spreadUnits": "instrument_price_units"
                ])
        default: return nil
        }
    }

    private static func provenance(_ strategyID: String, _ instrument: String) -> (String?, String?, String?, String?) {
        let config = effectiveConfiguration(strategyID: strategyID, instrument: instrument)?.sha256()
        let family: String
        switch strategyID {
        case "ORB_BREAK_RETEST_V1": family = "ORB_BREAK_RETEST"
        case "CANDIDATE_001_CHOCH_FVG_FIB": family = "CHOCH_FVG_FIB"
        case "CANDIDATE_002_AUCTION_FAILURE": family = "AUCTION_FAILURE"
        default: family = "LEGACY_V1"
        }
        return (config, StrategyImplementationDigests.evaluatorCodeSHA256[family],
                StrategyImplementationDigests.adapterCodeSHA256,
                StrategyImplementationDigests.selectorCodeSHA256)
    }
    public static func evaluateEngine(_ input: StrategyEngine.MarketInput,
                                      policy: ScanPolicy,
                                      at startedAt: Date = Date()) async throws -> AdaptiveOpportunityCandidate {
        var candidateInput = input
        candidateInput.policy = policy
        let result = try await StrategyEngine.evaluate(input: candidateInput)
        return engine(candidateInput, policy: policy, startedAt: startedAt,
                      completedAt: Date(), result: result)
    }

    public static func evaluateORB(_ input: StrategyEngine.MarketInput,
                                   asOf: Date = Date(),
                                   startedAt: Date = Date()) -> AdaptiveOpportunityCandidate {
        let decision = ORBBreakRetestV1.evaluate(input: input, asOf: asOf)
        return orb(input, startedAt: startedAt, completedAt: Date(), decision: decision)
    }

    /// Adapts the existing CHoCH/FVG/Fibonacci analyzer to the shared candidate
    /// contract. This remains a research vote; it does not create a trade plan.
    public static func evaluateCandidate001(_ input: StrategyEngine.MarketInput,
                                            asOf: Date = Date(),
                                            startedAt: Date = Date()) -> [AdaptiveOpportunityCandidate] {
        guard case .completed(let candidates) = evaluateCandidate001Result(input, asOf: asOf, startedAt: startedAt)
        else { return [] }
        return candidates
    }

    public static func evaluateCandidate001Result(_ input: StrategyEngine.MarketInput,
                                                  asOf: Date = Date(),
                                                  startedAt: Date = Date()) -> AdaptiveCandidateEvaluationBatch {
        return switch evaluateCandidate001DetailedResult(input, asOf: asOf, startedAt: startedAt) {
        case .completed(let candidates, _): .completed(candidates)
        case .failed(let reason): .failed(reason)
        }
    }

    public static func evaluateCandidate001DetailedResult(_ input: StrategyEngine.MarketInput,
                                                          asOf: Date = Date(),
                                                          startedAt: Date = Date()) -> AdaptiveDetailedCandidateEvaluationBatch {
        let candles = input.candles1m.map(candidate001Candle)
        let m15 = aggregateM15(input.candles5m).map(candidate001Candle)
        // Ask the analyzer to expose the raw retracement recognition even when
        // M15 confirmation is missing. The adapter applies the configured
        // confirmation gate before emitting an eligible candidate and records
        // the unmet condition in diagnostics.
        let configuration = Candidate001Configuration(requireM15Confirmation: false,
            signalFreshnessSeconds: 300)
        let analyzed: [Candidate001Candidate]
        do {
            analyzed = try Candidate001Analyzer.analyze(candles: candles,
                m15Candles: m15, configuration: configuration)
        } catch { return .failed("candidate001_analyzer_failed") }
        let observedAt = input.quoteAsOfMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
        let completion = Date()
        let spreadAccepted = acceptedSpread(input)
        var diagnostics: [AdaptiveCandidateRawDiagnostic] = []
        let adapted = analyzed.compactMap { candidate -> AdaptiveOpportunityCandidate? in
            let namespacedID = "candidate001:\(candidate.id)"
            guard candidate.terminalState == .candidateTriggered,
                  let triggeredAt = candidate.triggeredAt,
                  eventIsWithinSignalTTL(start: triggeredAt, asOf: asOf,
                      ttlSeconds: TimeInterval(configuration.resolvedSignalFreshnessSeconds)),
                  candidate.m15Confirmed else {
                let reason: String
                switch candidate.terminalState {
                case .expired: reason = "setup_expired"
                case .invalidated: reason = "setup_invalidated"
                case .candidateTriggered where !candidate.m15Confirmed: reason = "m15_confirmation_missing"
                case .candidateTriggered where candidate.triggeredAt == nil: reason = "trigger_time_missing"
                case .candidateTriggered: reason = "entry_window_expired"
                case .observe, .structureConfirmed, .fvgConfirmed, .retracementEligible:
                    reason = "conditions_not_met"
                }
                diagnostics.append(AdaptiveCandidateRawDiagnostic(candidateID: namespacedID,
                    rawState: candidate.terminalState.rawValue, reasonCode: reason))
                return nil
            }
            return AdaptiveOpportunityCandidate(id: namespacedID,
                strategyID: "CANDIDATE_001_CHOCH_FVG_FIB", strategyVersion: candidate.version,
                instrument: input.asset, provider: input.source,
                direction: candidate.direction == .bullish ? .long : .short,
                regime: "structure-fvg-retracement", session: nil, observedAt: observedAt,
                validUntil: observedAt.map { eventValidUntil(quoteAt: $0, eventStart: triggeredAt,
                    ttlSeconds: TimeInterval(configuration.resolvedSignalFreshnessSeconds)) },
                evaluationStartedAt: startedAt, evaluationCompletedAt: completion,
                state: observedAt == nil || !spreadAccepted ? .rejected : .eligible,
                rejectionReasons: observedAt == nil ? ["quote_missing"] : [],
                entryReference: candidate.fibonacci.level618, plan: nil,
                evidenceReferences: [namespacedID, candidate.fvg.formedAt.ISO8601Format()],
                provenance: candidate.version, freshness: freshness(observedAt, now: completion),
                spread: input.spread,
                spreadState: spreadAccepted ? .accepted : .rejected, rankingScore: 1,
                effectiveConfigurationSHA256: provenance("CANDIDATE_001_CHOCH_FVG_FIB", input.asset).0,
                evaluatorCodeSHA256: provenance("CANDIDATE_001_CHOCH_FVG_FIB", input.asset).1,
                adapterCodeSHA256: provenance("CANDIDATE_001_CHOCH_FVG_FIB", input.asset).2,
                selectorCodeSHA256: provenance("CANDIDATE_001_CHOCH_FVG_FIB", input.asset).3)
        }
        return .completed(candidates: adapted, diagnostics: diagnostics)
    }

    /// Adapts the existing OHLC auction-failure analyzer. Its higher timeframe
    /// input is deterministic M15 aggregation from the same OANDA M5 snapshot.
    public static func evaluateCandidate002(_ input: StrategyEngine.MarketInput,
                                            asOf: Date = Date(),
                                            startedAt: Date = Date()) -> [AdaptiveOpportunityCandidate] {
        guard case .completed(let candidates) = evaluateCandidate002Result(input, asOf: asOf, startedAt: startedAt)
        else { return [] }
        return candidates
    }

    public static func evaluateCandidate002Result(_ input: StrategyEngine.MarketInput,
                                                  asOf: Date = Date(),
                                                  startedAt: Date = Date()) -> AdaptiveCandidateEvaluationBatch {
        return switch evaluateCandidate002DetailedResult(input, asOf: asOf, startedAt: startedAt) {
        case .completed(let candidates, _): .completed(candidates)
        case .failed(let reason): .failed(reason)
        }
    }

    public static func evaluateCandidate002DetailedResult(_ input: StrategyEngine.MarketInput,
                                                          asOf: Date = Date(),
                                                          startedAt: Date = Date()) -> AdaptiveDetailedCandidateEvaluationBatch {
        let candles = input.candles1m.map(candidate002Candle)
        let m15 = aggregateM15(input.candles5m).map(candidate002Candle)
        let configuration = Candidate002Configuration(signalFreshnessSeconds: 120)
        let analyzed: [Candidate002Candidate]
        do {
            analyzed = try Candidate002Analyzer.analyze(candles: candles,
                higherTimeframe: m15, configuration: configuration)
        } catch { return .failed("candidate002_analyzer_failed") }
        let observedAt = input.quoteAsOfMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
        let completion = Date()
        let spreadAccepted = acceptedSpread(input)
        var diagnostics: [AdaptiveCandidateRawDiagnostic] = []
        let adapted = analyzed.compactMap { candidate -> AdaptiveOpportunityCandidate? in
            let namespacedID = "candidate002:\(candidate.id)"
            guard candidate.terminalState == .confirmed,
                  let confirmedAt = candidate.confirmationAt,
                  eventIsWithinSignalTTL(start: confirmedAt, asOf: asOf,
                      ttlSeconds: TimeInterval(configuration.resolvedSignalFreshnessSeconds)) else {
                let reason: String
                switch candidate.terminalState {
                case .invalidated: reason = "setup_invalidated"
                case .expired: reason = "confirmation_window_expired"
                case .confirmed where candidate.confirmationAt == nil: reason = "confirmation_missing"
                case .confirmed: reason = "entry_window_expired"
                }
                diagnostics.append(AdaptiveCandidateRawDiagnostic(candidateID: namespacedID,
                    rawState: candidate.terminalState.rawValue, reasonCode: reason))
                return nil
            }
            let hasM15Context = candidate.environment != .unavailable
            let plan = hasM15Context
                ? candidate002Plan(candidate, candles: candles, instrument: input.asset,
                                   configuration: configuration)
                : nil
            if !hasM15Context {
                diagnostics.append(AdaptiveCandidateRawDiagnostic(candidateID: namespacedID,
                    rawState: candidate.terminalState.rawValue, reasonCode: "m15_context_unavailable"))
            } else if plan == nil {
                diagnostics.append(AdaptiveCandidateRawDiagnostic(candidateID: namespacedID,
                    rawState: candidate.terminalState.rawValue, reasonCode: "entry_plan_incomplete"))
            }
            var rejectionReasons: [String] = []
            if observedAt == nil { rejectionReasons.append("quote_missing") }
            if !spreadAccepted { rejectionReasons.append("spread_rejected") }
            if !hasM15Context { rejectionReasons.append("m15_context_unavailable") }
            return AdaptiveOpportunityCandidate(id: namespacedID,
                strategyID: "CANDIDATE_002_AUCTION_FAILURE", strategyVersion: candidate.version,
                instrument: input.asset, provider: input.source,
                direction: hasM15Context
                    ? (candidate.direction == .bullish ? .long : .short) : .wait,
                regime: candidate.environment.rawValue, session: nil, observedAt: observedAt,
                validUntil: observedAt.map { eventValidUntil(quoteAt: $0, eventStart: confirmedAt,
                    ttlSeconds: TimeInterval(configuration.resolvedSignalFreshnessSeconds)) },
                evaluationStartedAt: startedAt, evaluationCompletedAt: completion,
                state: observedAt == nil || !spreadAccepted || !hasM15Context ? .rejected : .eligible,
                rejectionReasons: rejectionReasons,
                entryReference: plan?.entryPrice, plan: plan,
                evidenceReferences: [namespacedID, candidate.failedAt.ISO8601Format(), confirmedAt.ISO8601Format()],
                provenance: candidate.version,
                freshness: freshness(observedAt, now: completion), spread: input.spread,
                spreadState: spreadAccepted ? .accepted : .rejected, rankingScore: 1,
                effectiveConfigurationSHA256: provenance("CANDIDATE_002_AUCTION_FAILURE", input.asset).0,
                evaluatorCodeSHA256: provenance("CANDIDATE_002_AUCTION_FAILURE", input.asset).1,
                adapterCodeSHA256: provenance("CANDIDATE_002_AUCTION_FAILURE", input.asset).2,
                selectorCodeSHA256: provenance("CANDIDATE_002_AUCTION_FAILURE", input.asset).3)
        }
        return .completed(candidates: adapted, diagnostics: diagnostics)
    }

    private static func acceptedSpread(_ input: StrategyEngine.MarketInput) -> Bool {
        input.spread.isFinite && input.spread > 0
            && input.spread <= 3 * Assets.pipScale(for: input.asset)
    }

    static func eventIsWithinSignalTTL(start: Date, asOf: Date, ttlSeconds: TimeInterval) -> Bool {
        let availableAt = start.addingTimeInterval(60)
        let age = asOf.timeIntervalSince(availableAt)
        return availableAt.timeIntervalSince1970.isFinite
            && asOf.timeIntervalSince1970.isFinite
            && ttlSeconds.isFinite && ttlSeconds > 0
            && age.isFinite && age >= 0 && age <= ttlSeconds
    }

    public static func eventValidUntil(quoteAt: Date, eventStart: Date,
                                       ttlSeconds: TimeInterval) -> Date {
        let quoteDeadline = quoteAt.addingTimeInterval(EntryQuality.maxAgeSeconds)
        let eventDeadline = eventStart.addingTimeInterval(60 + ttlSeconds)
        return min(quoteDeadline, eventDeadline)
    }

    private static func freshness(_ observedAt: Date?, now: Date) -> AdaptiveFreshnessState {
        guard let observedAt else { return .missing }
        if observedAt > now.addingTimeInterval(1) { return .future }
        return now.timeIntervalSince(observedAt) <= EntryQuality.maxAgeSeconds ? .fresh : .stale
    }

    private static func candidate001Candle(_ candle: StrategyEngine.CandlePayload) -> Candidate001Candle {
        Candidate001Candle(time: Date(timeIntervalSince1970: candle.time / 1_000),
            open: candle.open, high: candle.high, low: candle.low, close: candle.close)
    }

    private static func candidate002Candle(_ candle: StrategyEngine.CandlePayload) -> Candidate002Candle {
        Candidate002Candle(time: Date(timeIntervalSince1970: candle.time / 1_000),
            open: candle.open, high: candle.high, low: candle.low, close: candle.close)
    }

    private static func candidate002Plan(_ candidate: Candidate002Candidate,
                                         candles: [Candidate002Candle], instrument: String,
                                         configuration: Candidate002Configuration) -> V3TradePlan? {
        guard let failureIndex = candles.firstIndex(where: { $0.time == candidate.failedAt }),
              failureIndex >= configuration.lookbackBars,
              let confirmationAt = candidate.confirmationAt,
              let confirmation = candles.first(where: { $0.time == confirmationAt }) else { return nil }
        let prior = candles[(failureIndex - configuration.lookbackBars)..<failureIndex]
        guard let rangeHigh = prior.map(\.high).max(), let rangeLow = prior.map(\.low).min(),
              rangeHigh > rangeLow else { return nil }
        let pip = Assets.pipScale(for: instrument)
        let side: V3SpotSide = candidate.direction == .bullish ? .long : .short
        let entry = confirmation.close
        let stop = side == .long ? candles[failureIndex].low - pip : candles[failureIndex].high + pip
        let target = side == .long ? rangeHigh : rangeLow
        let idSuffix = candidate.id.filter(\.isNumber)
        let safeInstrument = instrument.replacingOccurrences(of: "/", with: "-")
        let plan = V3TradePlan(id: "candidate-002-\(safeInstrument)-\(idSuffix)",
            instrument: instrument, strategyID: "CANDIDATE_002_AUCTION_FAILURE",
            strategyVersion: candidate.version, engineVersion: candidate.version,
            sourceObservationID: "\(instrument)-\(confirmationAt.timeIntervalSince1970)",
            state: .validated, side: side, entryPrice: entry, stopPrice: stop,
            targetPrice: target, units: 1, maxSpread: 3 * pip, riskFraction: 0.01,
            evidenceIDs: [candidate.id, "prior-range-high", "prior-range-low"],
            createdAt: confirmationAt)
        return plan.validation().isEmpty ? plan : nil
    }

    /// Aggregates only complete, epoch-aligned groups of three native OANDA M5 bars.
    /// Kept module-internal so `@testable` fixtures can verify this boundary directly.
    static func aggregateM15(_ candles: [StrategyEngine.CandlePayload]) -> [StrategyEngine.CandlePayload] {
        let maxExactMillisecond = 9_007_199_254_740_991.0 // 2^53 - 1
        let bucketable = candles.filter {
            $0.time.isFinite && abs($0.time) <= maxExactMillisecond
        }
        let groups = Dictionary(grouping: bucketable) { Int(floor($0.time / 900_000)) }
        return groups.keys.sorted().compactMap { bucket in
            guard let rows = groups[bucket]?.sorted(by: { $0.time < $1.time }), rows.count == 3 else {
                return nil
            }
            let bucketStart = Double(bucket) * 900_000
            let expectedTimes = [bucketStart, bucketStart + 300_000, bucketStart + 600_000]
            guard rows.allSatisfy({
                $0.time.rounded() == $0.time
                    && $0.time.truncatingRemainder(dividingBy: 300_000) == 0
                    && $0.open.isFinite && $0.high.isFinite && $0.low.isFinite && $0.close.isFinite
                    && $0.high >= max($0.open, $0.close)
                    && $0.low <= min($0.open, $0.close)
                    && $0.high >= $0.low
            }), rows.map(\.time) == expectedTimes,
                  let high = rows.map(\.high).max(), let low = rows.map(\.low).min() else {
                return nil
            }
            return StrategyEngine.CandlePayload(time: bucketStart,
                open: rows[0].open, high: high, low: low, close: rows[2].close)
        }
    }

    public static func engine(_ input: StrategyEngine.MarketInput, policy: ScanPolicy,
                              startedAt: Date, completedAt: Date,
                              result: StrategyEngine.EvaluateResult) -> AdaptiveOpportunityCandidate {
        let signal = result.signal
        let direction: AdaptiveDirection
        switch signal.cabinetSide {
        case "HIGH": direction = .long
        case "LOW": direction = .short
        default: direction = .wait
        }
        let observedAt = input.quoteAsOfMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
        let freshness: AdaptiveFreshnessState = observedAt == nil ? .missing :
            (observedAt! > completedAt.addingTimeInterval(1) ? .future :
             completedAt.timeIntervalSince(observedAt!) <= 8 ? .fresh : .stale)
        var reasons = signal.vetoes ?? []
        if direction == .wait && reasons.isEmpty { reasons = [signal.why] }
        if freshness != .fresh { reasons.append("quote_\(freshness.rawValue.lowercased())") }
        let spreadAccepted = input.spread.isFinite && input.spread > 0
            && !(signal.vetoes ?? []).contains("Spread relative to volatility")
        let state: AdaptiveCandidateState = direction != .wait && freshness == .fresh && spreadAccepted
            ? .eligible : .rejected
        let proof = provenance("\(policy.rawValue)", input.asset)
        return AdaptiveOpportunityCandidate(
            id: "\(policy.rawValue)-\(input.asset)-\(input.evaluatedAtMs ?? completedAt.timeIntervalSince1970 * 1_000)",
            strategyID: policy.rawValue, strategyVersion: "JSC_\(policy.rawValue)",
            instrument: input.asset, provider: input.source, direction: direction,
            regime: signal.features?.regime, session: FxSession.activeSessionName(completedAt),
            observedAt: observedAt, evaluationStartedAt: startedAt,
            evaluationCompletedAt: completedAt, state: state, rejectionReasons: reasons,
             entryReference: signal.entryPrice ?? signal.price,
             // A directional engine result does not itself prove a holding
             // horizon. Completed, source-matched research must be attached by
             // the research layer; never use the instrument name as evidence.
             horizonsSeconds: [], evidenceReferences: [],
             provenance: "existing-javascriptcore-\(policy.rawValue)",
            freshness: freshness, spread: input.spread,
            spreadState: spreadAccepted ? .accepted : .rejected,
            rankingScore: signal.opportunity ?? signal.confidence ?? 0,
            effectiveConfigurationSHA256: proof.0, evaluatorCodeSHA256: proof.1,
            adapterCodeSHA256: proof.2, selectorCodeSHA256: proof.3)
    }

    public static func orb(_ input: StrategyEngine.MarketInput, startedAt: Date,
                           completedAt: Date, decision: ORBDecision) -> AdaptiveOpportunityCandidate {
        let observedAt = input.quoteAsOfMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
        let direction: AdaptiveDirection = switch decision.direction {
        case .long: .long
        case .short: .short
        case nil: .wait
        }
        let freshness: AdaptiveFreshnessState = observedAt == nil ? .missing :
            (observedAt! > completedAt.addingTimeInterval(1) ? .future :
             completedAt.timeIntervalSince(observedAt!) <= 5 ? .fresh : .stale)
        var reasons = decision.candidate == nil ? [decision.reason] : []
        if freshness != .fresh { reasons.append("quote_\(freshness.rawValue.lowercased())") }
        let state: AdaptiveCandidateState = decision.candidate != nil && freshness == .fresh ? .eligible : .rejected
        let plan = decision.candidate?.plan
        let configuration = ORBBreakRetestV1.configuration(for: input.asset)
        let setupExpiry = decision.sessionStart?.addingTimeInterval(
            TimeInterval((configuration.openingRangeMinutes + configuration.maximumSetupMinutes) * 60))
        let proof = provenance("ORB_BREAK_RETEST_V1", input.asset)
        return AdaptiveOpportunityCandidate(
            id: plan?.id ?? "orb-\(input.asset)-\(completedAt.timeIntervalSince1970)",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: plan?.strategyVersion ?? "ORB_BREAK_RETEST_V1",
            instrument: input.asset, provider: input.source, direction: direction,
            regime: "opening-range", session: "New York",
            observedAt: observedAt,
            validUntil: observedAt.map { quoteAt in min(quoteAt.addingTimeInterval(5), setupExpiry ?? .distantFuture) },
            evaluationStartedAt: startedAt,
            evaluationCompletedAt: completedAt, state: state, rejectionReasons: reasons,
            entryReference: plan?.entryPrice, plan: plan, horizonsSeconds: [],
            evidenceReferences: plan?.evidenceIDs ?? [], provenance: "existing-orb-research",
            freshness: freshness, spread: input.spread,
             spreadState: input.spread.isFinite && input.spread > 0
                 && input.spread <= ORBBreakRetestV1.configuration(for: input.asset).maximumSpread
                 ? .accepted : .rejected,
            rankingScore: plan == nil ? 0 : 1,
            effectiveConfigurationSHA256: proof.0, evaluatorCodeSHA256: proof.1,
            adapterCodeSHA256: proof.2, selectorCodeSHA256: proof.3)
    }
}
