import Foundation

/// Direction-neutral composition contract for research candidates. This type has no
/// execution authority and deliberately does not expose a probability claim.
public enum AdaptiveDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
    case wait = "WAIT"
}

public enum AdaptiveCandidateState: String, Codable, Sendable, Equatable {
    case eligible = "ELIGIBLE"
    case rejected = "REJECTED"
    case unavailable = "UNAVAILABLE"
}

public enum AdaptiveFreshnessState: String, Codable, Sendable, Equatable {
    case fresh = "FRESH"
    case stale = "STALE"
    case missing = "MISSING"
    case future = "FUTURE"
}

public enum AdaptiveSpreadState: String, Codable, Sendable, Equatable {
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
    case unavailable = "UNAVAILABLE"
}

public struct AdaptiveOpportunityCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let strategyID: String
    public let strategyVersion: String
    public let instrument: String
    public let provider: String
    public let direction: AdaptiveDirection
    public let regime: String?
    public let session: String?
    public let observedAt: Date?
    public let evaluationStartedAt: Date
    public let evaluationCompletedAt: Date
    public let state: AdaptiveCandidateState
    public let rejectionReasons: [String]
    public let entryReference: Double?
    public let plan: V3TradePlan?
    public let horizonsSeconds: [Int]
    public let evidenceReferences: [String]
    public let provenance: String
    public let freshness: AdaptiveFreshnessState
    public let spread: Double?
    public let spreadState: AdaptiveSpreadState
    /// Ranking input only. It is conviction/order information, never a probability.
    public let rankingScore: Double

    public init(id: String, strategyID: String, strategyVersion: String,
                instrument: String, provider: String, direction: AdaptiveDirection,
                regime: String? = nil, session: String? = nil, observedAt: Date? = nil,
                evaluationStartedAt: Date, evaluationCompletedAt: Date,
                state: AdaptiveCandidateState, rejectionReasons: [String] = [],
                entryReference: Double? = nil, plan: V3TradePlan? = nil,
                 horizonsSeconds: [Int] = [],
                evidenceReferences: [String] = [], provenance: String,
                freshness: AdaptiveFreshnessState, spread: Double? = nil,
                spreadState: AdaptiveSpreadState, rankingScore: Double = 0) {
        self.id = id; self.strategyID = strategyID; self.strategyVersion = strategyVersion
        self.instrument = instrument; self.provider = provider; self.direction = direction
        self.regime = regime; self.session = session; self.observedAt = observedAt
        self.evaluationStartedAt = evaluationStartedAt; self.evaluationCompletedAt = evaluationCompletedAt
        self.state = state; self.rejectionReasons = rejectionReasons; self.entryReference = entryReference
        self.plan = plan; self.horizonsSeconds = horizonsSeconds; self.evidenceReferences = evidenceReferences
        self.provenance = provenance; self.freshness = freshness; self.spread = spread
        self.spreadState = spreadState; self.rankingScore = rankingScore
    }
}

public struct AdaptiveDecisionTiming: Codable, Sendable, Equatable {
    public let observationAt: Date?
    public let candidateEvaluationStartedAt: Date
    public let candidateEvaluationCompletedAt: Date
    public let selectorDecisionAt: Date
    public let publicationAt: Date?

    public init(observationAt: Date?, candidateEvaluationStartedAt: Date,
                candidateEvaluationCompletedAt: Date, selectorDecisionAt: Date,
                publicationAt: Date? = nil) {
        self.observationAt = observationAt
        self.candidateEvaluationStartedAt = candidateEvaluationStartedAt
        self.candidateEvaluationCompletedAt = candidateEvaluationCompletedAt
        self.selectorDecisionAt = selectorDecisionAt
        self.publicationAt = publicationAt
    }

    public var calculationLatency: TimeInterval {
        candidateEvaluationCompletedAt.timeIntervalSince(candidateEvaluationStartedAt)
    }

    public var publicationLatency: TimeInterval? {
        guard let publicationAt else { return nil }
        return publicationAt.timeIntervalSince(selectorDecisionAt)
    }
}

public struct AdaptiveOpportunityDecision: Codable, Sendable, Equatable {
    public let selectedCandidateID: String?
    public let noTradeReason: String?
    public let candidates: [AdaptiveOpportunityCandidate]
    public let timing: AdaptiveDecisionTiming

    public init(selectedCandidateID: String?, noTradeReason: String?,
                candidates: [AdaptiveOpportunityCandidate], timing: AdaptiveDecisionTiming) {
        self.selectedCandidateID = selectedCandidateID
        self.noTradeReason = noTradeReason
        self.candidates = candidates
        self.timing = timing
    }

    public var isNoTrade: Bool { selectedCandidateID == nil }
}
