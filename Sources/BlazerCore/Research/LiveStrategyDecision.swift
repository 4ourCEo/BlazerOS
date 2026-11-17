import Foundation

/// A profile/version reference carried into persisted decision provenance.
public struct LiveDecisionProfileReference: Codable, Sendable, Equatable, Hashable {
    public let profileID: String
    public let profileVersion: String

    public init(profileID: String, profileVersion: String) {
        self.profileID = profileID
        self.profileVersion = profileVersion
    }
}

/// The Live desk's market decision and structural plan. It contains no broker
/// order authority. Optional provenance fields preserve decoding of old records;
/// legacy records without them are history and must restore as WAIT.
public struct LiveStrategyDecision: Codable, Sendable, Equatable {
    public let id: String
    public let instrument: String
    public let action: LiveStrategyAction
    public let supportingStrategies: [String]
    public let plan: V3TradePlan?
    public let reasons: [String]
    public let sourceReferences: [String]
    public let observedAt: Date
    public let selectedProfileID: String?
    public let selectedProfileVersion: String?
    public let promotionRecordID: String?
    public let supportingProfiles: [LiveDecisionProfileReference]?
    public let selectorPolicyVersion: String?
    public let selectorPolicySHA256: String?
    public let selectorCodeSHA256: String?

    public init(instrument: String, action: LiveStrategyAction,
                supportingStrategies: [String], plan: V3TradePlan?,
                reasons: [String], sourceReferences: [String] = [], observedAt: Date,
                selectedProfileID: String? = nil, selectedProfileVersion: String? = nil,
                promotionRecordID: String? = nil,
                supportingProfiles: [LiveDecisionProfileReference]? = nil,
                selectorPolicyVersion: String? = nil,
                selectorPolicySHA256: String? = nil,
                selectorCodeSHA256: String? = nil) {
        self.instrument = instrument
        self.action = action
        self.supportingStrategies = supportingStrategies
        self.plan = plan
        self.reasons = reasons
        self.sourceReferences = sourceReferences
        self.observedAt = observedAt
        self.selectedProfileID = selectedProfileID
        self.selectedProfileVersion = selectedProfileVersion
        self.promotionRecordID = promotionRecordID
        self.supportingProfiles = supportingProfiles
        self.selectorPolicyVersion = selectorPolicyVersion
        self.selectorPolicySHA256 = selectorPolicySHA256
        self.selectorCodeSHA256 = selectorCodeSHA256
        let safeInstrument = instrument.replacingOccurrences(of: "/", with: "-")
        let identity = plan?.id ?? "wait"
        id = "live-\(safeInstrument)-\(identity)-\(Int(observedAt.timeIntervalSince1970 * 1_000))"
    }
}

public enum LiveStrategyAction: String, Codable, Sendable, Equatable {
    case buy = "BUY"
    case sell = "SELL"
    case wait = "WAIT"
}

/// Sanitized observation for a separate research-only projection. It deliberately
/// omits direction and all price/plan fields so callers cannot accidentally render
/// an unpromoted candidate as a trade setup.
public struct LiveStrategyResearchObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let profileID: String?
    public let strategyID: String
    public let strategyVersion: String
    public let status: LiveResearchObservationStatus
    public let reasons: [String]
    public let observedAt: Date?

    public init(candidate: AdaptiveOpportunityCandidate, profileID: String?,
                status: LiveResearchObservationStatus, reasons: [String]) {
        self.id = candidate.id
        self.profileID = profileID
        self.strategyID = candidate.strategyID
        self.strategyVersion = candidate.strategyVersion
        self.status = status
        self.reasons = reasons
        self.observedAt = candidate.observedAt
    }
}

public enum LiveResearchObservationStatus: String, Codable, Sendable, Equatable {
    case evaluated
    case rejected
    case unregistered
}

/// Decision and research observations travel as separate values. The latter must
/// never contribute to the decision, its plan, or production notifications.
public struct LiveStrategySelection: Sendable, Equatable {
    public let decision: LiveStrategyDecision
    public let researchObservations: [LiveStrategyResearchObservation]

    public init(decision: LiveStrategyDecision,
                researchObservations: [LiveStrategyResearchObservation]) {
        self.decision = decision
        self.researchObservations = researchObservations
    }
}

/// Chooses only among exact profile/version identities backed by a production
/// promotion record. A single distinct validated plan is required; rankScore is
/// never used to arbitrate across incompatible strategies or plans.
public enum LiveStrategySelector {
    public static func select(instrument: String,
                              candidates: [AdaptiveOpportunityCandidate],
                              now: Date,
                              maximumAge: TimeInterval = 8) -> LiveStrategyDecision {
        evaluate(instrument: instrument, candidates: candidates, now: now,
                 maximumAge: maximumAge).decision
    }

    public static func evaluate(instrument: String,
                                candidates: [AdaptiveOpportunityCandidate],
                                now: Date,
                                maximumAge: TimeInterval = 8,
                                profiles: [StrategyResearchProfile] = StrategyResearchRegistry.profiles,
                                promotionRecords: [StrategyPromotionRecord] = StrategyResearchRegistry.productionPromotionRecords)
    -> LiveStrategySelection {
        let relevant = candidates.filter { $0.instrument == instrument }
        let registryErrors = StrategyResearchRegistry.duplicateIdentityErrors(in: profiles)
        if !registryErrors.isEmpty {
            let observations = relevant.map {
                LiveStrategyResearchObservation(candidate: $0, profileID: nil,
                    status: .rejected, reasons: ["strategy_registry_integrity_failure"])
            }.sorted {
                if $0.strategyID != $1.strategyID { return $0.strategyID < $1.strategyID }
                if $0.strategyVersion != $1.strategyVersion { return $0.strategyVersion < $1.strategyVersion }
                return $0.id < $1.id
            }
            return LiveStrategySelection(
                decision: wait(instrument, now: now, reason: "strategy_registry_integrity_failure"),
                researchObservations: observations)
        }
        var research: [LiveStrategyResearchObservation] = []
        var promoted: [(candidate: AdaptiveOpportunityCandidate,
                        profile: StrategyResearchProfile,
                        promotion: StrategyPromotionRecord)] = []
        var controls: [AdaptiveOpportunityCandidate] = []

        for candidate in relevant {
            switch resolve(candidate, profiles: profiles) {
            case .ambiguous:
                research.append(.init(candidate: candidate, profileID: nil,
                    status: .rejected, reasons: ["strategy_identity_ambiguous"]))
            case .unknown:
                research.append(.init(candidate: candidate, profileID: nil,
                    status: .unregistered, reasons: ["strategy_identity_unregistered"]))
            case .versionMismatch(let profile):
                research.append(.init(candidate: candidate, profileID: profile.id,
                    status: .rejected, reasons: ["strategy_version_mismatch"]))
            case .matched(let profile):
                switch profile.decisionRole {
                case .control:
                    controls.append(candidate)
                case .shadow:
                    research.append(researchObservation(candidate, profileID: profile.id,
                                                        now: now, maximumAge: maximumAge))
                case .liveSignal:
                    let matches = promotionRecords.filter {
                        $0.profileID == profile.id && $0.profileVersion == profile.version
                    }
                    guard matches.count == 1, let promotion = matches.first,
                          promotion.validationErrors(for: profile, candidate: candidate).isEmpty else {
                        research.append(.init(candidate: candidate, profileID: profile.id,
                            status: .rejected, reasons: ["promotion_proof_unavailable_or_invalid"]))
                        continue
                    }
                    promoted.append((candidate, profile, promotion))
                }
            }
        }

        let decision = decide(instrument: instrument, relevant: relevant,
            promoted: promoted, controls: controls, now: now, maximumAge: maximumAge)
        research.sort {
            if $0.strategyID != $1.strategyID { return $0.strategyID < $1.strategyID }
            if $0.strategyVersion != $1.strategyVersion { return $0.strategyVersion < $1.strategyVersion }
            return $0.id < $1.id
        }
        return LiveStrategySelection(decision: decision, researchObservations: research)
    }

    private static func decide(instrument: String,
                               relevant: [AdaptiveOpportunityCandidate],
                               promoted: [(candidate: AdaptiveOpportunityCandidate,
                                           profile: StrategyResearchProfile,
                                           promotion: StrategyPromotionRecord)],
                               controls: [AdaptiveOpportunityCandidate],
                               now: Date, maximumAge: TimeInterval) -> LiveStrategyDecision {
        guard !promoted.isEmpty else {
            return wait(instrument, now: now,
                        reason: "no_strategy_passed_live_promotion_gate")
        }
        let eligible = promoted.filter {
            isEligible($0.candidate, now: now, maximumAge: maximumAge)
        }
        guard !eligible.isEmpty else {
            return wait(instrument, now: now, reason: "promoted_strategy_candidate_unavailable")
        }

        let structural = eligible.filter { item in
            guard let plan = item.candidate.plan,
                  plan.state == .validated,
                  plan.validation().isEmpty,
                  plan.instrument == instrument,
                  plan.strategyID == item.candidate.strategyID,
                  plan.strategyVersion == item.candidate.strategyVersion,
                  let spread = item.candidate.spread,
                  spread <= plan.maxSpread else { return false }
            let expectedSide: V3SpotSide = item.candidate.direction == .long ? .long : .short
            return plan.side == expectedSide
        }
        guard !structural.isEmpty else {
            return wait(instrument, now: now,
                        reason: "confirmed_structural_plan_unavailable")
        }

        let orderedStructural = structural.sorted {
            if $0.profile.id != $1.profile.id { return $0.profile.id < $1.profile.id }
            return $0.candidate.id < $1.candidate.id
        }
        var uniquePlans: [(candidate: AdaptiveOpportunityCandidate,
                           profile: StrategyResearchProfile,
                           promotion: StrategyPromotionRecord,
                           plan: V3TradePlan)] = []
        for item in orderedStructural {
            guard let plan = item.candidate.plan else { continue }
            if !uniquePlans.contains(where: { $0.plan == plan }) {
                uniquePlans.append((item.candidate, item.profile, item.promotion, plan))
            }
        }
        guard uniquePlans.count == 1, let selected = uniquePlans.first else {
            return wait(instrument, now: now, reason: "structural_plan_ambiguous")
        }

        let direction = selected.candidate.direction
        guard !eligible.contains(where: { $0.candidate.direction != direction }) else {
            return wait(instrument, now: now, reason: "eligible_strategy_direction_conflict")
        }
        if legacyControlVetoes(controls, opposing: direction, now: now,
                               maximumAge: maximumAge) {
            return wait(instrument, now: now, reason: "legacy_control_unanimous_opposition")
        }

        let supporters = uniquePlans
        let references = supporters.map {
            LiveDecisionProfileReference(profileID: $0.profile.id, profileVersion: $0.profile.version)
        }.uniqued.sorted {
            if $0.profileID != $1.profileID { return $0.profileID < $1.profileID }
            return $0.profileVersion < $1.profileVersion
        }
        let familyIDs = references.map(\.profileID).uniqued.sorted()
        return LiveStrategyDecision(instrument: instrument,
            action: direction == .long ? .buy : .sell,
            supportingStrategies: familyIDs, plan: selected.plan, reasons: [],
            sourceReferences: StrategyResearchRegistry.sourceReferences(for: familyIDs),
            observedAt: now, selectedProfileID: selected.profile.id,
            selectedProfileVersion: selected.profile.version,
            promotionRecordID: selected.promotion.id,
            supportingProfiles: references,
            selectorPolicyVersion: LiveStrategySelectorPolicy.version,
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
    }

    private static func resolve(_ candidate: AdaptiveOpportunityCandidate,
                                profiles: [StrategyResearchProfile]) -> StrategyCandidateResolution {
        let identity = StrategyCandidateIdentity(strategyID: candidate.strategyID,
                                                 strategyVersion: candidate.strategyVersion)
        let exactProfiles = profiles.filter { $0.acceptedCandidateIdentities.contains(identity) }
        if exactProfiles.count > 1 { return .ambiguous }
        if let exact = exactProfiles.first {
            return .matched(exact)
        }
        if let sameID = profiles.first(where: { profile in
            profile.acceptedCandidateIdentities.contains { $0.strategyID == candidate.strategyID }
        }) {
            return .versionMismatch(sameID)
        }
        return .unknown
    }

    private static func legacyControlVetoes(_ candidates: [AdaptiveOpportunityCandidate],
                                             opposing direction: AdaptiveDirection,
                                             now: Date, maximumAge: TimeInterval) -> Bool {
        let expected: [String: String] = [
            "baseline": "JSC_baseline",
            "continuation": "JSC_continuation",
            "reversal": "JSC_reversal",
            "regime": "JSC_regime"
        ]
        guard candidates.count == expected.count else { return false }
        var seen = Set<String>()
        for candidate in candidates {
            guard expected[candidate.strategyID] == candidate.strategyVersion,
                  seen.insert(candidate.strategyID).inserted,
                  isEligible(candidate, now: now, maximumAge: maximumAge) else { return false }
        }
        guard seen == Set(expected.keys), let unanimous = candidates.first?.direction,
              candidates.allSatisfy({ $0.direction == unanimous }) else { return false }
        return unanimous != direction
    }

    private static func isEligible(_ candidate: AdaptiveOpportunityCandidate,
                                   now: Date, maximumAge: TimeInterval) -> Bool {
        let normalizedProvider = candidate.provider.uppercased().replacingOccurrences(of: "_", with: "-")
        guard normalizedProvider == "OANDA-LIVE",
              candidate.state == .eligible, candidate.direction != .wait,
              candidate.freshness == .fresh, candidate.spreadState == .accepted,
              let spread = candidate.spread, spread.isFinite, spread > 0,
              let observedAt = candidate.observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age >= -1 && age <= maximumAge
    }

    private static func researchObservation(_ candidate: AdaptiveOpportunityCandidate,
                                           profileID: String, now: Date,
                                           maximumAge: TimeInterval) -> LiveStrategyResearchObservation {
        guard candidate.state == .eligible else {
            return .init(candidate: candidate, profileID: profileID, status: .rejected,
                reasons: candidate.rejectionReasons.isEmpty ? ["strategy_rule_rejected"] : candidate.rejectionReasons)
        }
        guard candidate.freshness == .fresh, candidate.spreadState == .accepted,
              let observedAt = candidate.observedAt else {
            return .init(candidate: candidate, profileID: profileID, status: .rejected,
                reasons: [candidate.freshness != .fresh ? "quote_\(candidate.freshness.rawValue.lowercased())" : "spread_unavailable_or_rejected"])
        }
        let age = now.timeIntervalSince(observedAt)
        guard age >= -1 && age <= maximumAge else {
            return .init(candidate: candidate, profileID: profileID, status: .rejected,
                reasons: ["quote_stale"])
        }
        let normalizedProvider = candidate.provider.uppercased().replacingOccurrences(of: "_", with: "-")
        guard normalizedProvider == "OANDA-LIVE" else {
            return .init(candidate: candidate, profileID: profileID, status: .rejected,
                reasons: ["live_oanda_provenance_required"])
        }
        return .init(candidate: candidate, profileID: profileID, status: .evaluated,
                     reasons: ["profile_shadow_only"])
    }

    private static func wait(_ instrument: String, now: Date,
                             reason: String) -> LiveStrategyDecision {
        LiveStrategyDecision(instrument: instrument, action: .wait,
            supportingStrategies: [], plan: nil, reasons: [reason],
            sourceReferences: [], observedAt: now)
    }
}

private extension Sequence where Element: Hashable {
    var uniqued: [Element] { Array(Set(self)) }
}
