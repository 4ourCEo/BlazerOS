import Foundation
import Testing
@testable import BlazerCore

struct LiveStrategySelectorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let configDigest = String(repeating: "a", count: 64)

    private func candidate(_ id: String, strategy: String, version: String,
                          direction: AdaptiveDirection,
                          provider: String = "OANDA_LIVE",
                          state: AdaptiveCandidateState = .eligible,
                          observedOffset: TimeInterval = 0,
                          hasObservedAt: Bool = true,
                          numericSpread: Double? = 0.01,
                          spreadState: AdaptiveSpreadState = .accepted,
                          plan: V3TradePlan? = nil,
                          rankingScore: Double = 1,
                          configSHA: String? = nil,
                          evaluatorSHA: String? = nil,
                          adapterSHA: String? = nil,
                          selectorSHA: String = StrategyImplementationDigests.selectorCodeSHA256) -> AdaptiveOpportunityCandidate {
        let freshness: AdaptiveFreshnessState = !hasObservedAt ? .missing :
            (observedOffset > 1 ? .future : (observedOffset < -8 ? .stale : .fresh))
        return AdaptiveOpportunityCandidate(id: id, strategyID: strategy, strategyVersion: version,
            instrument: "USD/JPY", provider: provider,
            direction: direction, observedAt: hasObservedAt ? now.addingTimeInterval(observedOffset) : nil,
            evaluationStartedAt: now, evaluationCompletedAt: now, state: state,
            entryReference: 150, plan: plan, provenance: "fixture",
            freshness: freshness, spread: numericSpread, spreadState: spreadState, rankingScore: rankingScore,
            effectiveConfigurationSHA256: configSHA ?? configDigest,
            evaluatorCodeSHA256: evaluatorSHA ?? String(repeating: "f", count: 64),
            adapterCodeSHA256: adapterSHA ?? String(repeating: "1", count: 64),
            selectorCodeSHA256: selectorSHA)
    }

    private func shortPlan(id: String = "plan-short", entry: Double = 150,
                          state: V3TradePlanState = .validated) -> V3TradePlan {
        V3TradePlan(id: id, instrument: "USD/JPY", strategyID: "TEST_ORB",
            strategyVersion: "test-orb-v1", engineVersion: "test-orb-v1",
            sourceObservationID: "confirmation-1", state: state, side: .short,
            entryPrice: entry, stopPrice: entry + 0.2, targetPrice: entry - 0.4,
            units: 1, maxSpread: 0.03, riskFraction: 0.01, createdAt: now)
    }

    private func liveProfile() -> StrategyResearchProfile {
        StrategyResearchProfile(id: "TEST_ORB_PROFILE", version: "test-orb-v1",
            family: "Test ORB", status: .researchCandidate, sourceReferences: ["fixture"],
            decisionRole: .liveSignal,
            acceptedCandidateIdentities: [
                .init(strategyID: "TEST_ORB", strategyVersion: "test-orb-v1")
            ], configurationSHA256: configDigest,
            configurationSHA256ByInstrument: ["USD/JPY": configDigest],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
    }

    private func promotion(for profile: StrategyResearchProfile,
                           verdict: StrategyCampaignVerdict = .passed,
                           instrument: String = "USD/JPY",
                           selectorSHA: String = StrategyImplementationDigests.selectorCodeSHA256) -> StrategyPromotionRecord {
        StrategyPromotionRecord(id: "test-promotion-1", profileID: profile.id,
            profileVersion: profile.version, hypothesisID: "test-hypothesis-1",
            configurationSHA256: configDigest,
            instrument: instrument, evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: selectorSHA,
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            campaignID: "test-campaign-1", campaignManifestSHA256: String(repeating: "b", count: 64),
            heldOutArtifactSHA256: String(repeating: "c", count: 64),
            campaignCompletion: .completed, campaignVerdict: verdict,
            preregistered: true, protectedHoldout: true,
            costModelSHA256: String(repeating: "d", count: 64),
            ownerApprovalID: "owner-approval-1",
            ownerApprovalSHA256: String(repeating: "e", count: 64))
    }

    private func legacy(_ name: String, _ direction: AdaptiveDirection,
                        observedOffset: TimeInterval = 0) -> AdaptiveOpportunityCandidate {
        candidate("legacy-\(name)", strategy: name, version: "JSC_\(name)",
                  direction: direction, observedOffset: observedOffset)
    }

    private var legacyProfile: StrategyResearchProfile {
        StrategyResearchRegistry.profiles.first { $0.id == "LEGACY_V1" }!
    }

    @Test func productionResearchCandidatesCannotCreateLiveSignal() {
        let plan = V3TradePlan(id: "orb-plan-1", instrument: "USD/JPY",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "confirmation-1",
            state: .validated, side: .short, entryPrice: 150, stopPrice: 150.2,
            targetPrice: 149.6, units: 1, maxSpread: 0.03, riskFraction: 0.01,
            createdAt: now)
        let candidates = [candidate("orb", strategy: "ORB_BREAK_RETEST_V1",
            version: "ORB_BREAK_RETEST_V1", direction: .short, plan: plan),
            legacy("baseline", .short), legacy("continuation", .short),
            legacy("reversal", .short), legacy("regime", .short)]

        let selection = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: candidates, now: now)

        #expect(selection.decision.action == .wait)
        #expect(selection.decision.reasons == ["no_strategy_passed_live_promotion_gate"])
        #expect(selection.decision.plan == nil)
        #expect(selection.researchObservations.map(\.profileID).contains("ORB_BREAK_RETEST"))
        #expect(selection.researchObservations.allSatisfy { !$0.reasons.isEmpty })
    }

    @Test func explicitlyPromotedExactProfileCanProduceStructuralSignal() {
        let profile = liveProfile()
        let record = promotion(for: profile)
        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                                 direction: .short, plan: shortPlan())

        let selection = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [selected], now: now, profiles: [profile], promotionRecords: [record])

        #expect(selection.decision.action == .sell)
        #expect(selection.decision.plan == shortPlan())
        #expect(selection.decision.selectedProfileID == profile.id)
        #expect(selection.decision.selectedProfileVersion == profile.version)
        #expect(selection.decision.promotionRecordID == record.id)
        #expect(selection.decision.selectorPolicyVersion == LiveStrategySelectorPolicy.version)
        #expect(selection.decision.selectorPolicySHA256 == LiveStrategySelectorPolicy.sha256)
        #expect(selection.decision.selectorCodeSHA256 == StrategyImplementationDigests.selectorCodeSHA256)
        #expect(selection.researchObservations.isEmpty)
    }

    @Test func wrongVersionIsShadowedAndCannotCreateSignal() {
        let profile = liveProfile()
        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "old-version",
                                 direction: .short, plan: shortPlan())
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
            now: now, profiles: [profile], promotionRecords: [promotion(for: profile)])

        #expect(result.decision.action == .wait)
        #expect(result.researchObservations.first?.status == .rejected)
        #expect(result.researchObservations.first?.reasons == ["strategy_version_mismatch"])
    }

    @Test func nonLiveProviderCannotCreateLiveSignal() {
        let profile = liveProfile()
        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
            direction: .short, provider: "OANDA_HISTORICAL", plan: shortPlan())
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
            now: now, profiles: [profile], promotionRecords: [promotion(for: profile)])

        #expect(result.decision.action == .wait)
        #expect(result.decision.reasons == ["promoted_strategy_candidate_unavailable"])
    }

    @Test func staleFutureMissingAndRejectedSpreadCannotCreateLiveSignal() {
        let profile = liveProfile()
        let proof = promotion(for: profile)
        let invalidCandidates = [
            candidate("stale", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, observedOffset: -12, plan: shortPlan()),
            candidate("future", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, observedOffset: 2, plan: shortPlan()),
            candidate("missing-quote", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, hasObservedAt: false, plan: shortPlan()),
            candidate("wide-spread", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, spreadState: .rejected, plan: shortPlan())
        ]
        for candidate in invalidCandidates {
            let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [candidate],
                now: now, profiles: [profile], promotionRecords: [proof])
            #expect(result.decision.action == .wait)
            #expect(result.decision.reasons == ["promoted_strategy_candidate_unavailable"])
        }
    }

    @Test func malformedOrWrongInstrumentPlanCannotCreateLiveSignal() {
        let profile = liveProfile()
        let proof = promotion(for: profile)
        let valid = shortPlan()
        let wrongInstrument = V3TradePlan(id: "wrong-instrument", instrument: "EUR/USD",
            strategyID: valid.strategyID, strategyVersion: valid.strategyVersion,
            engineVersion: valid.engineVersion, sourceObservationID: valid.sourceObservationID,
            state: .validated, side: .short, entryPrice: 1.1, stopPrice: 1.101,
            targetPrice: 1.098, units: 1, maxSpread: 0.0003, riskFraction: 0.01,
            createdAt: now)
        let wrongSide = valid.replacingSideForTest(.long)
        let candidates = [
            candidate("wrong-instrument", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, plan: wrongInstrument),
            candidate("wrong-side", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, plan: wrongSide)
        ]
        for candidate in candidates {
            let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [candidate],
                now: now, profiles: [profile], promotionRecords: [proof])
            #expect(result.decision.action == .wait)
            #expect(result.decision.reasons == ["confirmed_structural_plan_unavailable"])
        }
    }

    @Test func onlyValidatedPlanStateCanCreateLiveSignal() {
        let profile = liveProfile()
        let proof = promotion(for: profile)
        for state in [V3TradePlanState.draft, .offered, .triggered, .invalidated, .expired] {
            let selected = candidate("plan-\(state.rawValue)", strategy: "TEST_ORB",
                version: "test-orb-v1", direction: .short, plan: shortPlan(state: state))
            let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
                now: now, profiles: [profile], promotionRecords: [proof])
            #expect(result.decision.action == .wait)
            #expect(result.decision.reasons == ["confirmed_structural_plan_unavailable"])
        }

        let validated = candidate("validated-plan", strategy: "TEST_ORB",
            version: "test-orb-v1", direction: .short, plan: shortPlan(state: .validated))
        let accepted = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [validated],
            now: now, profiles: [profile], promotionRecords: [proof])
        #expect(accepted.decision.action == .sell)
        #expect(accepted.decision.plan?.state == .validated)
    }

    @Test func numericSpreadMustBeValidAndWithinPlanLimit() {
        let profile = liveProfile()
        let proof = promotion(for: profile)
        let cases: [(String, Double?, String)] = [
            ("nil", nil, "promoted_strategy_candidate_unavailable"),
            ("nan", .nan, "promoted_strategy_candidate_unavailable"),
            ("zero", 0, "promoted_strategy_candidate_unavailable"),
            ("over-plan-limit", 0.031, "confirmed_structural_plan_unavailable")
        ]
        for (name, spread, reason) in cases {
            let selected = candidate(name, strategy: "TEST_ORB", version: "test-orb-v1",
                direction: .short, numericSpread: spread, spreadState: .accepted, plan: shortPlan())
            let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
                now: now, profiles: [profile], promotionRecords: [proof])
            #expect(result.decision.action == .wait)
            #expect(result.decision.reasons == [reason])
        }

        let acceptedSpread = candidate("within-plan-limit", strategy: "TEST_ORB",
            version: "test-orb-v1", direction: .short, numericSpread: 0.03,
            spreadState: .accepted, plan: shortPlan())
        let accepted = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [acceptedSpread],
            now: now, profiles: [profile], promotionRecords: [proof])
        #expect(accepted.decision.action == .sell)
    }

    @Test func unknownIdentityDoesNotAliasLegacy() {
        let selected = candidate("candidate-1", strategy: "made-up-policy", version: "v1",
                                 direction: .short, plan: shortPlan())
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected], now: now)

        #expect(result.decision.action == .wait)
        #expect(result.researchObservations.first?.status == .unregistered)
        #expect(result.researchObservations.first?.reasons == ["strategy_identity_unregistered"])
        #expect(StrategyResearchRegistry.family(for: "made-up-policy") == nil)
    }

    @Test func duplicateExactProfileIdentityIsRejectedAsAmbiguous() {
        let profile = liveProfile()
        let duplicate = StrategyResearchProfile(id: profile.id + "-DUP", version: profile.version,
            family: profile.family, status: profile.status, sourceReferences: [],
            decisionRole: .liveSignal,
            acceptedCandidateIdentities: [.init(strategyID: "TEST_ORB", strategyVersion: "test-orb-v1")],
            configurationSHA256: configDigest,
            configurationSHA256ByInstrument: ["USD/JPY": configDigest],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256)
        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                                  direction: .short, plan: shortPlan())
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
            now: now, profiles: [profile, duplicate], promotionRecords: [promotion(for: profile)])
        #expect(result.decision.action == .wait)
        #expect(result.decision.reasons == ["strategy_registry_integrity_failure"])
        #expect(result.researchObservations.first?.reasons == ["strategy_registry_integrity_failure"])
    }

    @Test func decodedProfileWithDuplicateIdentityFailsClosedDespiteValidPromotion() throws {
        let profile = liveProfile()
        let encoded = try JSONEncoder().encode(profile)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let duplicate = ["strategyID": "TEST_ORB", "strategyVersion": "test-orb-v1"]
        object["acceptedCandidateIdentities"] = [duplicate, duplicate]
        let decodedData = try JSONSerialization.data(withJSONObject: object)
        let decodedProfile = try JSONDecoder().decode(StrategyResearchProfile.self, from: decodedData)
        #expect(decodedProfile.acceptedCandidateIdentities.count == 2)

        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                                  direction: .short, plan: shortPlan())
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
            now: now, profiles: [decodedProfile], promotionRecords: [promotion(for: profile)])
        #expect(result.decision.action == .wait)
        #expect(result.decision.reasons == ["strategy_registry_integrity_failure"])
        #expect(result.researchObservations.first?.reasons == ["strategy_registry_integrity_failure"])
    }

    @Test func promotionRequiresCandidateConfigAndCodeDigestsToMatch() {
        let profile = liveProfile()
        let proof = promotion(for: profile)
        let mismatched = [
            candidate("cfg", strategy: "TEST_ORB", version: "test-orb-v1", direction: .short,
                plan: shortPlan(), configSHA: String(repeating: "2", count: 64)),
            candidate("eval", strategy: "TEST_ORB", version: "test-orb-v1", direction: .short,
                plan: shortPlan(), evaluatorSHA: String(repeating: "3", count: 64)),
            candidate("adapter", strategy: "TEST_ORB", version: "test-orb-v1", direction: .short,
                plan: shortPlan(), adapterSHA: String(repeating: "4", count: 64)),
            candidate("selector", strategy: "TEST_ORB", version: "test-orb-v1", direction: .short,
                plan: shortPlan(), selectorSHA: String(repeating: "5", count: 64)),
            candidate("selector-missing", strategy: "TEST_ORB", version: "test-orb-v1", direction: .short,
                plan: shortPlan(), selectorSHA: "")
        ]
        for item in mismatched {
            let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [item],
                now: now, profiles: [profile], promotionRecords: [proof])
            #expect(result.decision.action == .wait)
            #expect(result.researchObservations.first?.reasons == ["promotion_proof_unavailable_or_invalid"])
        }
        let correctCandidate = candidate("instrument", strategy: "TEST_ORB", version: "test-orb-v1",
            direction: .short, plan: shortPlan())
        let wrongInstrumentProof = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [correctCandidate], now: now, profiles: [profile],
            promotionRecords: [promotion(for: profile, instrument: "EUR/USD")])
        #expect(wrongInstrumentProof.decision.action == .wait)

        let profileWithoutInstrumentConfig = StrategyResearchProfile(id: profile.id,
            version: profile.version, family: profile.family, status: profile.status,
            sourceReferences: profile.sourceReferences, decisionRole: .liveSignal,
            acceptedCandidateIdentities: profile.acceptedCandidateIdentities,
            configurationSHA256: configDigest, selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
        let missingInstrumentConfig = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [correctCandidate], now: now, profiles: [profileWithoutInstrumentConfig],
            promotionRecords: [promotion(for: profileWithoutInstrumentConfig)])
        #expect(missingInstrumentConfig.decision.action == .wait)
        #expect(missingInstrumentConfig.researchObservations.first?.reasons ==
            ["promotion_proof_unavailable_or_invalid"])

        let staleSelectorProof = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [correctCandidate], now: now, profiles: [profile],
            promotionRecords: [promotion(for: profile, selectorSHA: String(repeating: "6", count: 64))])
        #expect(staleSelectorProof.decision.action == .wait)
        let missingSelectorProof = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [correctCandidate], now: now, profiles: [profile],
            promotionRecords: [promotion(for: profile, selectorSHA: "")])
        #expect(missingSelectorProof.decision.action == .wait)

        let staleSelectorProfile = StrategyResearchProfile(id: profile.id, version: profile.version,
            family: profile.family, status: profile.status, sourceReferences: [],
            decisionRole: .liveSignal, acceptedCandidateIdentities: profile.acceptedCandidateIdentities,
            configurationSHA256ByInstrument: ["USD/JPY": configDigest],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: String(repeating: "7", count: 64))
        let staleProfile = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [correctCandidate], now: now, profiles: [staleSelectorProfile],
            promotionRecords: [promotion(for: staleSelectorProfile)])
        #expect(staleProfile.decision.action == .wait)
    }

    @Test func failedHeldOutCampaignCannotPromoteProfile() {
        let profile = liveProfile()
        let record = promotion(for: profile, verdict: .failed)
        let selected = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                                 direction: .short, plan: shortPlan())

        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [selected],
            now: now, profiles: [profile], promotionRecords: [record])

        #expect(record.validationErrors(for: profile) == ["held_out_criteria_not_passed"])
        #expect(result.decision.action == .wait)
        #expect(result.researchObservations.first?.reasons == ["promotion_proof_unavailable_or_invalid"])
    }

    @Test func incompleteOrUnprotectedEvidenceCannotPromoteProfile() {
        let profile = liveProfile()
        let complete = promotion(for: profile)
        let record = StrategyPromotionRecord(id: complete.id, profileID: complete.profileID,
            profileVersion: complete.profileVersion, hypothesisID: complete.hypothesisID,
            configurationSHA256: complete.configurationSHA256,
            instrument: complete.instrument, evaluatorCodeSHA256: complete.evaluatorCodeSHA256,
            adapterCodeSHA256: complete.adapterCodeSHA256,
            selectorCodeSHA256: complete.selectorCodeSHA256,
            selectorPolicySHA256: complete.selectorPolicySHA256, campaignID: complete.campaignID,
            campaignManifestSHA256: complete.campaignManifestSHA256,
            heldOutArtifactSHA256: complete.heldOutArtifactSHA256,
            campaignCompletion: .incomplete, campaignVerdict: .passed,
            preregistered: false, protectedHoldout: false,
            costModelSHA256: complete.costModelSHA256, ownerApprovalID: complete.ownerApprovalID,
            ownerApprovalSHA256: complete.ownerApprovalSHA256)

        let errors = record.validationErrors(for: profile)
        #expect(errors.contains("campaign_incomplete"))
        #expect(errors.contains("hypothesis_not_preregistered"))
        #expect(errors.contains("held_out_set_not_protected"))
    }

    @Test func incompatibleStructuralPlansWaitRegardlessOfRankingScore() {
        let profile = liveProfile()
        let record = promotion(for: profile)
        let first = candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                              direction: .short, plan: shortPlan(), rankingScore: 999)
        let other = V3TradePlan(id: "plan-short-2", instrument: "USD/JPY", strategyID: "TEST_ORB",
            strategyVersion: "test-orb-v1", engineVersion: "test-orb-v1",
            sourceObservationID: "confirmation-2", state: .validated, side: .short,
            entryPrice: 150.01, stopPrice: 150.21, targetPrice: 149.61,
            units: 1, maxSpread: 0.03, riskFraction: 0.01, createdAt: now)
        let second = candidate("candidate-2", strategy: "TEST_ORB", version: "test-orb-v1",
                               direction: .short, plan: other)
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY",
            candidates: [first, second], now: now, profiles: [profile], promotionRecords: [record])

        #expect(result.decision.action == .wait)
        #expect(result.decision.reasons == ["structural_plan_ambiguous"])
    }

    @Test func identicalValidatedPlansDeduplicateDeterministically() {
        let profile = liveProfile()
        let record = promotion(for: profile)
        let samePlan = shortPlan()
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [
            candidate("candidate-1", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, plan: samePlan),
            candidate("candidate-2", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, plan: samePlan)
        ], now: now, profiles: [profile], promotionRecords: [record])

        #expect(result.decision.action == .sell)
        #expect(result.decision.plan == samePlan)
        #expect(result.decision.supportingProfiles == [
            LiveDecisionProfileReference(profileID: profile.id, profileVersion: profile.version)
        ])
    }

    @Test func opposingPromotedCandidateWithoutPlanStillVetoes() {
        let profile = liveProfile()
        let record = promotion(for: profile)
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [
            candidate("candidate-short", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .short, plan: shortPlan()),
            candidate("candidate-long", strategy: "TEST_ORB", version: "test-orb-v1",
                      direction: .long)
        ], now: now, profiles: [profile], promotionRecords: [record])

        #expect(result.decision.action == .wait)
        #expect(result.decision.reasons == ["eligible_strategy_direction_conflict"])
    }

    @Test func legacyControlNeedsFourFreshEligibleUnanimousVotesToVeto() {
        let profile = liveProfile()
        let record = promotion(for: profile)
        let live = candidate("candidate-long", strategy: "TEST_ORB", version: "test-orb-v1",
                             direction: .long, plan: shortPlan().replacingSideForTest(.long))
        let allOppose = [legacy("baseline", .short), legacy("continuation", .short),
                         legacy("reversal", .short), legacy("regime", .short)]
        let vetoed = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [live] + allOppose,
            now: now, profiles: [profile, legacyProfile], promotionRecords: [record])
        #expect(vetoed.decision.action == .wait)
        #expect(vetoed.decision.reasons == ["legacy_control_unanimous_opposition"])

        let oneStale = [legacy("baseline", .short, observedOffset: -12),
                        legacy("continuation", .short), legacy("reversal", .short), legacy("regime", .short)]
        let notVetoed = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [live] + oneStale,
            now: now, profiles: [profile, legacyProfile], promotionRecords: [record])
        #expect(notVetoed.decision.action == .buy)

        let oneDisagrees = [legacy("baseline", .short), legacy("continuation", .short),
                            legacy("reversal", .long), legacy("regime", .short)]
        let alsoNotVetoed = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [live] + oneDisagrees,
            now: now, profiles: [profile, legacyProfile], promotionRecords: [record])
        #expect(alsoNotVetoed.decision.action == .buy)
    }

    @Test func legacyControlAloneNeverCreatesASignal() {
        let result = LiveStrategySelector.evaluate(instrument: "USD/JPY", candidates: [
            legacy("baseline", .short), legacy("continuation", .short),
            legacy("reversal", .short), legacy("regime", .short)
        ], now: now)
        #expect(result.decision.action == .wait)
        #expect(result.decision.plan == nil)
    }

    @Test func oldPersistedDecisionDecodesWithoutPromotionProvenance() throws {
        let current = LiveStrategyDecision(instrument: "USD/JPY", action: .wait,
            supportingStrategies: [], plan: nil, reasons: ["fixture"], observedAt: now,
            selectedProfileID: "new-field", selectedProfileVersion: "new-version",
            promotionRecordID: "new-promotion", supportingProfiles: [],
            selectorPolicyVersion: "new-policy", selectorPolicySHA256: configDigest)
        let encoded = try JSONEncoder().encode(current)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["selectedProfileID", "selectedProfileVersion", "promotionRecordID",
                    "supportingProfiles", "selectorPolicyVersion", "selectorPolicySHA256",
                    "selectorCodeSHA256"] {
            object.removeValue(forKey: key)
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LiveStrategyDecision.self, from: legacyData)
        #expect(decoded.selectedProfileID == nil)
        #expect(decoded.promotionRecordID == nil)
        #expect(decoded.selectorCodeSHA256 == nil)
        #expect(decoded.selectorPolicyVersion == nil)
    }
}

private extension V3TradePlan {
    func replacingSideForTest(_ side: V3SpotSide) -> V3TradePlan {
        V3TradePlan(id: "plan-long", instrument: instrument, strategyID: strategyID,
            strategyVersion: strategyVersion, engineVersion: engineVersion,
            sourceObservationID: sourceObservationID, state: state, side: side,
            entryPrice: entryPrice, stopPrice: side == .long ? entryPrice - 0.2 : entryPrice + 0.2,
            targetPrice: side == .long ? entryPrice + 0.4 : entryPrice - 0.4,
            units: units, maxSpread: maxSpread, riskFraction: riskFraction, createdAt: createdAt)
    }
}
