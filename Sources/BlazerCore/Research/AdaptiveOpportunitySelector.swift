import Foundation

/// Deterministic research-only composition of existing candidate authorities.
public enum AdaptiveOpportunitySelector {
    public static func select(_ candidates: [AdaptiveOpportunityCandidate], now: Date,
                              maximumAge: TimeInterval = 8,
                              decisionAt: Date = Date()) -> AdaptiveOpportunityDecision {
        var reviewed = candidates
        var reasonsByID: [String: [String]] = [:]
        for candidate in candidates {
            var reasons = candidate.rejectionReasons
            if candidate.state != .eligible { reasons.append("candidate_not_eligible") }
            if candidate.direction == .wait { reasons.append("non_directional") }
            if candidate.freshness != .fresh { reasons.append("stale_or_missing_observation") }
            if candidate.spreadState != .accepted { reasons.append("spread_not_accepted") }
            if let plan = candidate.plan, !plan.validation().isEmpty { reasons.append(contentsOf: plan.validation()) }
            if let observedAt = candidate.observedAt, now.timeIntervalSince(observedAt) > maximumAge {
                reasons.append("observation_expired")
            }
            reasonsByID[candidate.id] = Array(Set(reasons)).sorted()
        }

        let directional = candidates.filter {
            (reasonsByID[$0.id] ?? []).isEmpty && $0.direction != .wait
        }
        let instruments = Set(directional.map(\.instrument))
        var conflicts = Set<String>()
        for instrument in instruments {
            let directions = Set(directional.filter { $0.instrument == instrument }.map(\.direction))
            if directions.count > 1 { conflicts.formUnion(directional.filter { $0.instrument == instrument }.map(\.id)) }
        }
        for id in conflicts { reasonsByID[id, default: []].append("conflicting_direction") }

        reviewed = candidates.map { candidate in
            let reasons = Array(Set(reasonsByID[candidate.id] ?? [])).sorted()
            return AdaptiveOpportunityCandidate(
                id: candidate.id, strategyID: candidate.strategyID, strategyVersion: candidate.strategyVersion,
                instrument: candidate.instrument, provider: candidate.provider, direction: candidate.direction,
                regime: candidate.regime, session: candidate.session, observedAt: candidate.observedAt,
                evaluationStartedAt: candidate.evaluationStartedAt, evaluationCompletedAt: candidate.evaluationCompletedAt,
                state: candidate.state == .unavailable ? .unavailable :
                    (reasons.isEmpty ? .eligible : .rejected), rejectionReasons: reasons,
                entryReference: candidate.entryReference, plan: candidate.plan,
                horizonsSeconds: candidate.horizonsSeconds, evidenceReferences: candidate.evidenceReferences,
                provenance: candidate.provenance, freshness: candidate.freshness, spread: candidate.spread,
                spreadState: candidate.spreadState, rankingScore: candidate.rankingScore)
        }
        let eligible = reviewed.filter { $0.state == .eligible }
            .sorted { lhs, rhs in
                if lhs.rankingScore != rhs.rankingScore { return lhs.rankingScore > rhs.rankingScore }
                if lhs.evaluationCompletedAt != rhs.evaluationCompletedAt {
                    return lhs.evaluationCompletedAt < rhs.evaluationCompletedAt
                }
                return lhs.id < rhs.id
            }
        let selected = eligible.first
        let timing = AdaptiveDecisionTiming(
            observationAt: candidates.compactMap(\.observedAt).min(),
            candidateEvaluationStartedAt: candidates.map(\.evaluationStartedAt).min() ?? decisionAt,
            candidateEvaluationCompletedAt: candidates.map(\.evaluationCompletedAt).max() ?? decisionAt,
            selectorDecisionAt: decisionAt)
        let noTradeReason: String?
        if selected != nil {
            noTradeReason = nil
        } else if candidates.isEmpty {
            noTradeReason = "no_candidates"
        } else if reviewed.contains(where: { $0.state == .unavailable }) {
            noTradeReason = "candidate_unavailable"
        } else {
            noTradeReason = "no_eligible_candidate"
        }
        return AdaptiveOpportunityDecision(selectedCandidateID: selected?.id,
            noTradeReason: noTradeReason,
            candidates: reviewed, timing: timing)
    }
}
