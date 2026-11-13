import Foundation

public enum SpotFXPracticeLifecycleState: String, Codable, Sendable, CaseIterable {
    case forming = "FORMING"
    case actionable = "ACTIONABLE"
    case rejected = "REJECTED/NO_TRADE"
    case invalidated = "INVALIDATED"
    case expired = "EXPIRED"
    case manuallyConfirmed = "MANUALLY_CONFIRMED"
    case brokerVerified = "BROKER_VERIFIED"
    case unresolved = "UNRESOLVED"
}

/// Evidence supplied independently of the quote and plan. A manual report is deliberately
/// not this type: it can acknowledge an action, but can never prove a fill.
public struct SpotFXBrokerExecutionEvidence: Codable, Sendable, Equatable {
    public let evidenceID: String
    public let planID: String
    public let instrument: String
    public let broker: String
    public let transactionID: String
    public let environment: V3ProviderEnvironment
    public let executedAt: Date
    public let evidenceKind: V3EvidenceKind

    public init(evidenceID: String, planID: String, instrument: String, broker: String,
                transactionID: String, environment: V3ProviderEnvironment, executedAt: Date,
                evidenceKind: V3EvidenceKind = .brokerExecution) {
        self.evidenceID = evidenceID; self.planID = planID; self.instrument = instrument
        self.broker = broker; self.transactionID = transactionID; self.environment = environment
        self.executedAt = executedAt; self.evidenceKind = evidenceKind
    }

    fileprivate func validation(for plan: V3TradePlan, recordedAt: Date? = nil) -> [String] {
        var issues: [String] = []
        if evidenceID.isEmpty || planID != plan.id || instrument != plan.instrument { issues.append("broker_evidence_identity_invalid") }
        if broker.isEmpty || transactionID.isEmpty { issues.append("broker_identity_missing") }
        if environment != .oandaPractice || evidenceKind != .brokerExecution { issues.append("broker_evidence_not_practice_execution") }
        if !executedAt.timeIntervalSince1970.isFinite { issues.append("broker_evidence_time_invalid") }
        if let recordedAt, executedAt > recordedAt { issues.append("broker_evidence_after_recorded_time") }
        return issues
    }
}

public struct SpotFXPracticeLifecycleInput: Sendable {
    public let decision: ORBDecision
    public let plan: V3TradePlan?
    public let observation: V3MarketObservation?
    public let risk: V3RiskSizingResult?
    public let hardRiskCapUSD: Double
    public let environment: V3ProviderEnvironment?
    public let expiresAt: Date
    public let now: Date
    public let pipScale: Double?
    public let brokerEvidence: SpotFXBrokerExecutionEvidence?

    public init(decision: ORBDecision, plan: V3TradePlan?, observation: V3MarketObservation?,
                risk: V3RiskSizingResult?, hardRiskCapUSD: Double, environment: V3ProviderEnvironment?,
                expiresAt: Date, now: Date, pipScale: Double? = nil,
                brokerEvidence: SpotFXBrokerExecutionEvidence? = nil) {
        self.decision = decision; self.plan = plan; self.observation = observation; self.risk = risk
        self.hardRiskCapUSD = hardRiskCapUSD; self.environment = environment; self.expiresAt = expiresAt
        self.now = now; self.pipScale = pipScale; self.brokerEvidence = brokerEvidence
    }
}

public struct SpotFXPracticeLifecycleResult: Codable, Sendable, Equatable {
    public let state: SpotFXPracticeLifecycleState
    public let reason: String
    public let spreadPips: Double?
    public let planID: String?

    public init(state: SpotFXPracticeLifecycleState, reason: String, spreadPips: Double? = nil,
                planID: String? = nil) {
        self.state = state; self.reason = reason; self.spreadPips = spreadPips; self.planID = planID
    }
}

public enum SpotFXPracticeLifecycle {
    public static let defaultQuoteMaxAge: TimeInterval = 5

    public static func evaluate(_ input: SpotFXPracticeLifecycleInput) -> SpotFXPracticeLifecycleResult {
        let planID = input.plan?.id
        guard input.now.timeIntervalSince1970.isFinite, input.expiresAt.timeIntervalSince1970.isFinite else {
            return .init(state: .unresolved, reason: "lifecycle_time_invalid", planID: planID)
        }
        if input.now >= input.expiresAt { return .init(state: .expired, reason: "setup_expired", planID: planID) }
        if input.decision.stage == .invalidated || input.decision.setupState == .invalidated {
            return .init(state: .invalidated, reason: "setup_invalidated", planID: planID)
        }
        if input.decision.stage == .expired || input.decision.setupState == .setupExpired {
            return .init(state: .expired, reason: "setup_expired", planID: planID)
        }
        guard input.decision.stage == .setupConfirmed,
              input.decision.setupState == .confirmed else {
            switch input.decision.setupState {
            case .forming, .approaching:
                return .init(state: .forming, reason: "setup_not_confirmed", planID: planID)
            case .unresolved:
                return .init(state: .unresolved, reason: "setup_unresolved", planID: planID)
            default:
                return .init(state: .rejected, reason: "setup_not_actionable", planID: planID)
            }
        }
        guard let plan = input.plan else { return .init(state: .unresolved, reason: "plan_missing") }
        guard let candidate = input.decision.candidate, candidate.plan.id == plan.id else {
            return .init(state: .unresolved, reason: "candidate_plan_mismatch", planID: plan.id)
        }
        let directionMatches = (candidate.direction == .long && plan.side == .long)
            || (candidate.direction == .short && plan.side == .short)
        let decisionDirectionMatches = input.decision.direction == candidate.direction
        guard directionMatches, decisionDirectionMatches else {
            return .init(state: .rejected, reason: "candidate_direction_mismatch", planID: plan.id)
        }
        guard plan.validation().isEmpty else { return .init(state: .rejected, reason: "plan_invalid", planID: plan.id) }
        guard let environment = input.environment else {
            return .init(state: .unresolved, reason: "environment_missing", planID: plan.id)
        }
        guard environment == .oandaPractice else {
            return .init(state: .rejected, reason: "environment_not_practice", planID: plan.id)
        }
        if let evidence = input.brokerEvidence, evidence.validation(for: plan, recordedAt: input.now).isEmpty {
            return .init(state: .brokerVerified, reason: "broker_execution_verified", planID: plan.id)
        }
        guard input.brokerEvidence == nil else {
            return .init(state: .unresolved, reason: "broker_evidence_invalid", planID: plan.id)
        }
        guard let observation = input.observation else { return .init(state: .unresolved, reason: "quote_missing", planID: plan.id) }
        guard observation.environment == .oandaPractice else {
            return .init(state: .rejected, reason: "quote_not_practice", planID: plan.id)
        }
        guard observation.sourceTime <= input.now else {
            return .init(state: .unresolved, reason: "future_source_time", planID: plan.id)
        }
        guard observation.receivedAt <= input.now else {
            return .init(state: .unresolved, reason: "future_received_time", planID: plan.id)
        }
        let quoteIssues = observation.validation(now: input.now, maxAge: defaultQuoteMaxAge)
        guard quoteIssues.isEmpty else {
            return .init(state: .unresolved, reason: quoteIssues.sorted().first ?? "quote_invalid", planID: plan.id)
        }
        guard observation.instrument == plan.instrument else {
            return .init(state: .rejected, reason: "instrument_mismatch", planID: plan.id)
        }
        guard input.now.timeIntervalSince(observation.receivedAt) <= defaultQuoteMaxAge else {
            return .init(state: .unresolved, reason: "stale_receipt", planID: plan.id)
        }
        guard let pip = input.pipScale, pip.isFinite, pip > 0 else {
            return .init(state: .unresolved, reason: "pip_scale_missing", planID: plan.id)
        }
        let expectedPip = Assets.pipScale(for: plan.instrument)
        guard expectedPip.isFinite, expectedPip > 0,
              abs(pip - expectedPip) <= max(1e-12, expectedPip * 1e-9) else {
            return .init(state: .unresolved, reason: "pip_scale_mismatch", planID: plan.id)
        }
        let spreadPips = observation.spread / pip
        guard spreadPips.isFinite else { return .init(state: .unresolved, reason: "spread_invalid", planID: plan.id) }
        guard observation.spread <= plan.maxSpread else {
            return .init(state: .rejected, reason: "spread_exceeds_plan_max", spreadPips: spreadPips, planID: plan.id)
        }
        guard let risk = input.risk else { return .init(state: .unresolved, reason: "risk_missing", spreadPips: spreadPips, planID: plan.id) }
        guard input.hardRiskCapUSD.isFinite, input.hardRiskCapUSD > 0,
              risk.accepted, risk.units.isFinite, risk.units > 0, risk.units == plan.units,
              let loss = risk.estimatedWorstCaseLossUSD, loss.isFinite, loss > 0 else {
            return .init(state: .rejected, reason: "risk_rejected", spreadPips: spreadPips, planID: plan.id)
        }
        guard loss <= input.hardRiskCapUSD else {
            return .init(state: .rejected, reason: "risk_exceeds_hard_cap", spreadPips: spreadPips, planID: plan.id)
        }
        return .init(state: .actionable, reason: "all_evidence_valid", spreadPips: spreadPips, planID: plan.id)
    }
}

public struct SpotFXPracticeLifecycleEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let instrument: String
    /// Provider environment under which this lifecycle evidence was produced. Optional only for
    /// decoding pre-environment-tagged records; new native FX events always write Practice.
    public let environment: V3ProviderEnvironment?
    public let state: SpotFXPracticeLifecycleState
    public let reason: String
    public let recordedAt: Date
    public let manualAcknowledged: Bool
    public let brokerEvidence: SpotFXBrokerExecutionEvidence?
    public let observationID: String?
    public let sourceTime: Date?
    public let receivedAt: Date?
    public let spread: Double?
    public let spreadPips: Double?
    public let pipScale: Double?
    public let expiresAt: Date?
    public let riskAccepted: Bool?
    public let riskUnits: Double?
    public let estimatedWorstCaseLossUSD: Double?

    public init(id: String, planID: String, instrument: String,
                environment: V3ProviderEnvironment? = nil, state: SpotFXPracticeLifecycleState,
                reason: String, recordedAt: Date, manualAcknowledged: Bool = false,
                brokerEvidence: SpotFXBrokerExecutionEvidence? = nil, observationID: String? = nil,
                sourceTime: Date? = nil, receivedAt: Date? = nil, spread: Double? = nil,
                spreadPips: Double? = nil, pipScale: Double? = nil, expiresAt: Date? = nil,
                riskAccepted: Bool? = nil, riskUnits: Double? = nil,
                estimatedWorstCaseLossUSD: Double? = nil) {
        self.id = id; self.planID = planID; self.instrument = instrument
        self.environment = environment; self.state = state
        self.reason = reason; self.recordedAt = recordedAt; self.manualAcknowledged = manualAcknowledged
        self.brokerEvidence = brokerEvidence
        self.observationID = observationID; self.sourceTime = sourceTime; self.receivedAt = receivedAt
        self.spread = spread; self.spreadPips = spreadPips; self.pipScale = pipScale
        self.expiresAt = expiresAt; self.riskAccepted = riskAccepted; self.riskUnits = riskUnits
        self.estimatedWorstCaseLossUSD = estimatedWorstCaseLossUSD
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || planID.isEmpty || instrument.isEmpty || reason.isEmpty { issues.append("identity_missing") }
        if !recordedAt.timeIntervalSince1970.isFinite { issues.append("timestamp_invalid") }
        for date in [sourceTime, receivedAt, expiresAt] {
            if let date, !date.timeIntervalSince1970.isFinite { issues.append("evidence_timestamp_invalid") }
        }
        for number in [spread, spreadPips, pipScale, riskUnits, estimatedWorstCaseLossUSD] {
            if let number, !number.isFinite { issues.append("evidence_number_invalid") }
        }
        if let evidence = brokerEvidence,
           evidence.planID != planID || evidence.instrument != instrument {
            issues.append("broker_evidence_identity_invalid")
        }
        if state == .manuallyConfirmed && !manualAcknowledged { issues.append("manual_acknowledgment_missing") }
        if state == .brokerVerified {
            if let evidence = brokerEvidence, evidence.evidenceKind == .brokerExecution,
               !evidence.evidenceID.isEmpty, !evidence.broker.isEmpty, !evidence.transactionID.isEmpty,
               evidence.planID == planID, evidence.instrument == instrument,
                  evidence.environment == .oandaPractice,
                  evidence.executedAt <= recordedAt,
               evidence.executedAt.timeIntervalSince1970.isFinite {
                // valid
            } else {
                issues.append("broker_execution_evidence_missing")
            }
        }
        if state != .manuallyConfirmed && manualAcknowledged { issues.append("manual_flag_state_mismatch") }
        if state == .actionable {
            if observationID?.isEmpty != false || sourceTime == nil || receivedAt == nil || spread == nil
                || spreadPips == nil || pipScale == nil || expiresAt == nil {
                issues.append("quote_trace_missing")
            }
            if riskAccepted == nil || riskUnits == nil || estimatedWorstCaseLossUSD == nil {
                issues.append("risk_trace_missing")
            }
        }
        return issues
    }
}
