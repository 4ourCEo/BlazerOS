import Foundation

/// Translates existing authorities into the composition contract without changing them.
public enum AdaptiveOpportunityAdapters {
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
            rankingScore: signal.opportunity ?? signal.confidence ?? 0)
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
        return AdaptiveOpportunityCandidate(
            id: plan?.id ?? "orb-\(input.asset)-\(completedAt.timeIntervalSince1970)",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: plan?.strategyVersion ?? "ORB_BREAK_RETEST_V1",
            instrument: input.asset, provider: input.source, direction: direction,
            regime: "opening-range", session: "New York",
            observedAt: observedAt, evaluationStartedAt: startedAt,
            evaluationCompletedAt: completedAt, state: state, rejectionReasons: reasons,
            entryReference: plan?.entryPrice, plan: plan, horizonsSeconds: [],
            evidenceReferences: plan?.evidenceIDs ?? [], provenance: "existing-orb-research",
            freshness: freshness, spread: input.spread,
             spreadState: input.spread.isFinite && input.spread > 0
                 && input.spread <= ORBBreakRetestV1.configuration.maximumSpread
                 ? .accepted : .rejected,
            rankingScore: plan == nil ? 0 : 1)
    }
}
