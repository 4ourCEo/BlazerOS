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

/// Distinguishes an analyzer that completed with no eligible candidates from one
/// that failed before producing a result.
public enum AdaptiveCandidateEvaluationBatch: Sendable, Equatable {
    case completed([AdaptiveOpportunityCandidate])
    case failed(String)
}

/// Raw analyzer recognition preserved when the execution-ready adapter filters
/// an expired, invalidated, or unconfirmed structure from its candidate output.
public struct AdaptiveCandidateRawDiagnostic: Codable, Sendable, Equatable, Identifiable {
    public let candidateID: String
    public let rawState: String
    public let reasonCode: String
    public var id: String { "\(candidateID):\(rawState)" }

    public init(candidateID: String, rawState: String, reasonCode: String) {
        self.candidateID = candidateID
        self.rawState = rawState
        self.reasonCode = reasonCode
    }
}

public enum AdaptiveDetailedCandidateEvaluationBatch: Sendable, Equatable {
    case completed(candidates: [AdaptiveOpportunityCandidate],
                   diagnostics: [AdaptiveCandidateRawDiagnostic])
    case failed(String)
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
    /// Advisory observation deadline. Optional for backwards-compatible archives.
    public let validUntil: Date?
    public let evaluationStartedAt: Date
    public let evaluationCompletedAt: Date
    public let state: AdaptiveCandidateState
    public let rejectionReasons: [String]
    public let entryReference: Double?
    /// Structural signal levels do not imply broker units or risk approval.
    public let stopReference: Double?
    public let targetReference: Double?
    public let plan: V3TradePlan?
    public let horizonsSeconds: [Int]
    public let evidenceReferences: [String]
    public let provenance: String
    public let freshness: AdaptiveFreshnessState
    public let spread: Double?
    public let spreadState: AdaptiveSpreadState
    /// Ranking input only. It is conviction/order information, never a probability.
    public let rankingScore: Double
    /// Exact instrument/config/evaluator/adapter provenance. Nil on legacy archives
    /// and non-adapted callers; such candidates cannot satisfy a promotion record.
    public let effectiveConfigurationSHA256: String?
    public let evaluatorCodeSHA256: String?
    public let adapterCodeSHA256: String?
    public let selectorCodeSHA256: String?

    public init(id: String, strategyID: String, strategyVersion: String,
                instrument: String, provider: String, direction: AdaptiveDirection,
                regime: String? = nil, session: String? = nil, observedAt: Date? = nil,
                validUntil: Date? = nil,
                evaluationStartedAt: Date, evaluationCompletedAt: Date,
                state: AdaptiveCandidateState, rejectionReasons: [String] = [],
                entryReference: Double? = nil, stopReference: Double? = nil,
                targetReference: Double? = nil, plan: V3TradePlan? = nil,
                 horizonsSeconds: [Int] = [],
                evidenceReferences: [String] = [], provenance: String,
                freshness: AdaptiveFreshnessState, spread: Double? = nil,
                spreadState: AdaptiveSpreadState, rankingScore: Double = 0,
                effectiveConfigurationSHA256: String? = nil,
                evaluatorCodeSHA256: String? = nil,
                adapterCodeSHA256: String? = nil,
                selectorCodeSHA256: String? = nil) {
        self.id = id; self.strategyID = strategyID; self.strategyVersion = strategyVersion
        self.instrument = instrument; self.provider = provider; self.direction = direction
        self.regime = regime; self.session = session; self.observedAt = observedAt
        self.validUntil = validUntil
        self.evaluationStartedAt = evaluationStartedAt; self.evaluationCompletedAt = evaluationCompletedAt
        self.state = state; self.rejectionReasons = rejectionReasons; self.entryReference = entryReference
        self.stopReference = stopReference; self.targetReference = targetReference
        self.plan = plan; self.horizonsSeconds = horizonsSeconds; self.evidenceReferences = evidenceReferences
        self.provenance = provenance; self.freshness = freshness; self.spread = spread
        self.spreadState = spreadState; self.rankingScore = rankingScore
        self.effectiveConfigurationSHA256 = effectiveConfigurationSHA256?.lowercased()
        self.evaluatorCodeSHA256 = evaluatorCodeSHA256?.lowercased()
        self.adapterCodeSHA256 = adapterCodeSHA256?.lowercased()
        self.selectorCodeSHA256 = selectorCodeSHA256?.lowercased()
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
