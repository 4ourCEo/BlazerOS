import CryptoKit
import Foundation
import Testing
@testable import BlazerCore

struct StrategyResearchRegistryTests {
    @Test func handoffFamiliesAreInventoriedWithoutClaimingRuleReadiness() {
        let ids = Set(StrategyResearchRegistry.profiles.map(\.id))
        #expect(ids.isSuperset(of: [
            "LEGACY_V1", "ORB_BREAK_RETEST", "BREAKOUT_ACCEPTANCE", "AUCTION_FAILURE",
            "TREND_PULLBACK", "RANGE_REJECTION", "LONDON_BREAK_RETEST", "LIQUIDITY_SWEEP", "CHOCH_FVG_FIB",
            "MARKET_REGIME_ROUTER", "MULTI_TIMEFRAME_SELECTION", "TOKYO_SESSION_SWEEP",
            "LATE_NIGHT_TACTICAL_SCALP", "MORNING_PRIME_NEW_YORK", "FX_INTRADAY_MOMENTUM",
            "FX_MEAN_REVERSION", "FIXED_HORIZON_COMPARISON"
        ]))

        #expect(StrategyResearchRegistry.profiles.first { $0.id == "BREAKOUT_ACCEPTANCE" }?.status
                == .partialResearch)
        let breakoutAcceptance = StrategyResearchRegistry.profiles.first { $0.id == "BREAKOUT_ACCEPTANCE" }
        #expect(breakoutAcceptance?.version == "BREAKOUT_ACCEPTANCE_V1")
        #expect(breakoutAcceptance?.sourceReferences.contains("Sources/BlazerCore/Research/BreakoutAcceptanceV1.swift") == true)
        #expect(breakoutAcceptance?.sourceReferences.contains("reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md") == true)
        #expect(breakoutAcceptance?.sourceReferences.contains("reports/source/BlazerOS_STRIKE_V3_Product_Engineering_PRD.md") == true)
        #expect(breakoutAcceptance?.mayAuthorizeOrder == false)
        #expect(StrategyResearchRegistry.profiles.first { $0.id == "TREND_PULLBACK" }?.status
                == .partialResearch)
        let trendPullback = StrategyResearchRegistry.profiles.first { $0.id == "TREND_PULLBACK" }
        #expect(trendPullback?.version == "STRAT-GBPJPY-TREND-PULLBACK-V1")
        #expect(trendPullback?.sourceReferences.contains("Sources/BlazerCore/Research/GBPJPYTrendPullbackV1.swift") == true)
        #expect(trendPullback?.sourceReferences.contains("reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md") == true)
        #expect(trendPullback?.mayAuthorizeOrder == false)
        let rangeRejection = StrategyResearchRegistry.profiles.first { $0.id == "RANGE_REJECTION" }
        #expect(rangeRejection?.version == "GBPJPY_RANGE_REJECTION_V1")
        #expect(rangeRejection?.status == .researchCandidate)
        #expect(rangeRejection?.sourceReferences.contains("Sources/BlazerCore/Research/GBPJPYRangeRejectionV1.swift") == true)
        #expect(rangeRejection?.mayAuthorizeOrder == false)
        let londonBreakRetestProfiles = StrategyResearchRegistry.profiles.filter { $0.id == "LONDON_BREAK_RETEST" }
        #expect(londonBreakRetestProfiles.count == 1)
        let londonBreakRetest = londonBreakRetestProfiles.first
        #expect(londonBreakRetest?.version == "GBPJPY_LONDON_RANGE_BREAK_RETEST_V1")
        #expect(londonBreakRetest?.family == "London GBP/JPY breakout + retest")
        #expect(londonBreakRetest?.status == .researchCandidate)
        #expect(londonBreakRetest?.sourceReferences.contains("Sources/BlazerCore/Research/GBPJPYLondonBreakRetestV1.swift") == true)
        #expect(londonBreakRetest?.sourceReferences.contains("reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md") == true)
        #expect(londonBreakRetest?.sourceReferences.contains("reports/STRAT_GBPJPY_LONDON_BREAK_RETEST_PLAN_2026-11-14.md") == true)
        #expect(londonBreakRetest?.mayAuthorizeOrder == false)
        #expect(StrategyResearchRegistry.profiles.first { $0.id == "FX_MEAN_REVERSION" }?.mayAuthorizeOrder
                == false)
    }

    @Test func londonBreakRetestStrategyAndProfileIDsMapToTheRegisteredFamily() {
        #expect(StrategyResearchRegistry.family(for: "GBPJPY_LONDON_RANGE_BREAK_RETEST") == "LONDON_BREAK_RETEST")
        #expect(StrategyResearchRegistry.family(for: "LONDON_BREAK_RETEST") == "LONDON_BREAK_RETEST")
    }

    @Test func ruleProvenanceDoesNotPretendEveryBookDefinesEveryCandidate() {
        let references = StrategyResearchRegistry.sourceReferences(for: ["AUCTION_FAILURE"])
        #expect(references.contains("Sources/BlazerCore/Research/Candidate002.swift"))
        #expect(!references.contains("CHAN_ALGORITHMIC_TRADING_2013:CH7"))
        #expect(StrategyResearchRegistry.researchMethodReferences.contains("ARONSON_EBTA_2007:CH3-6"))
    }

    @Test func legacyPolicyVariantsRemainOneFamily() {
        #expect(StrategyResearchRegistry.family(for: "baseline") == "LEGACY_V1")
        #expect(StrategyResearchRegistry.family(for: "continuation") == "LEGACY_V1")
        #expect(StrategyResearchRegistry.family(for: "reversal") == "LEGACY_V1")
        #expect(StrategyResearchRegistry.family(for: "regime") == "LEGACY_V1")
    }

    @Test func everyProductionProfileIsShadowOrControlAndCannotAuthorizeOrders() {
        #expect(StrategyResearchRegistry.productionPromotionRecords.isEmpty)
        #expect(StrategyResearchRegistry.duplicateIdentityErrors(in: StrategyResearchRegistry.profiles).isEmpty)
        #expect(StrategyResearchRegistry.profiles.allSatisfy { $0.mayAuthorizeOrder == false })
        #expect(StrategyResearchRegistry.profiles.allSatisfy {
            $0.decisionRole == .control || $0.decisionRole == .shadow
        })
        #expect(StrategyResearchRegistry.profiles.first { $0.id == "LEGACY_V1" }?.decisionRole == .control)
    }

    @Test func candidateResolutionRequiresExactIdentityAndVersion() {
        #expect(StrategyResearchRegistry.resolve(strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1") == .matched(
                StrategyResearchRegistry.profiles.first { $0.id == "ORB_BREAK_RETEST" }!))
        #expect(StrategyResearchRegistry.resolve(strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "unreviewed-version") == .versionMismatch(
                StrategyResearchRegistry.profiles.first { $0.id == "ORB_BREAK_RETEST" }!))
        #expect(StrategyResearchRegistry.resolve(strategyID: "invented-strategy",
            strategyVersion: "v1") == .unknown)
        #expect(StrategyResearchRegistry.family(for: "invented-strategy") == nil)
        let duplicate = StrategyResearchProfile(id: "DUP", version: "v1", family: "dup",
            status: .researchCandidate, sourceReferences: [],
            acceptedCandidateIdentities: [.init(strategyID: "baseline", strategyVersion: "JSC_baseline")])
        let legacy = StrategyResearchRegistry.profiles.first { $0.id == "LEGACY_V1" }!
        #expect(StrategyResearchRegistry.duplicateIdentityErrors(in: [legacy, duplicate]) ==
            ["duplicate_strategy_identity:baseline:JSC_baseline"])
        #expect(StrategyResearchRegistry.family(for: "baseline") == "LEGACY_V1")
    }

    @Test func promotionRequiresFrozenDigestsApprovalAndPassingHeldOutEvidence() {
        let configurationDigest = String(repeating: "a", count: 64)
        let profile = StrategyResearchProfile(id: "TEST", version: "test-v1", family: "test",
            status: .researchCandidate, sourceReferences: [], decisionRole: .liveSignal,
            acceptedCandidateIdentities: [.init(strategyID: "TEST_RULE", strategyVersion: "test-v1")],
            configurationSHA256: configurationDigest,
            configurationSHA256ByInstrument: ["USD/JPY": configurationDigest],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
        let record = StrategyPromotionRecord(id: "approval-1", profileID: "TEST",
            profileVersion: "test-v1", hypothesisID: "hypothesis-1",
            configurationSHA256: configurationDigest,
            instrument: "USD/JPY", evaluatorCodeSHA256: String(repeating: "f", count: 64),
            adapterCodeSHA256: String(repeating: "1", count: 64),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256,
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            campaignID: "campaign-1", campaignManifestSHA256: String(repeating: "b", count: 64),
            heldOutArtifactSHA256: String(repeating: "c", count: 64),
            campaignCompletion: .completed, campaignVerdict: .passed,
            preregistered: true, protectedHoldout: true,
            costModelSHA256: String(repeating: "d", count: 64),
            ownerApprovalID: "owner-approval-1", ownerApprovalSHA256: String(repeating: "e", count: 64))
        #expect(record.validationErrors(for: profile).isEmpty)

        let changedConfiguration = StrategyResearchProfile(id: profile.id, version: profile.version,
            family: profile.family, status: profile.status, sourceReferences: [],
            decisionRole: .liveSignal,
            acceptedCandidateIdentities: profile.acceptedCandidateIdentities,
            configurationSHA256: String(repeating: "f", count: 64),
            configurationSHA256ByInstrument: ["USD/JPY": String(repeating: "f", count: 64)],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256)
        #expect(record.validationErrors(for: changedConfiguration)
            .contains("promotion_configuration_digest_mismatch"))
    }

    @Test func effectiveConfigurationIsInstrumentKeyedAndRejectsNonFiniteSettings() {
        let eur = AdaptiveOpportunityAdapters.effectiveConfiguration(
            strategyID: "ORB_BREAK_RETEST_V1", instrument: "EUR/USD")!
        let jpy = AdaptiveOpportunityAdapters.effectiveConfiguration(
            strategyID: "ORB_BREAK_RETEST_V1", instrument: "USD/JPY")!
        #expect(eur.sha256() == "75e903666b18b60616957f5419dc5cd64f3c62dee51d994571863aa7161629a5")
        #expect(jpy.sha256() == "c904b3dc4a8e88e1a159900fb63b674e4be850ebb1d15688f4a7c53d763856c6")
        #expect(StrategyEffectiveConfiguration(profileID: "P", profileVersion: "1",
            evaluatorVersion: "E", adapterVersion: "A", instrument: "EUR/USD",
            stringSettings: [:], numericSettings: ["bad": .nan]).sha256() == nil)
        let withDate = StrategyEffectiveConfiguration(profileID: "P", profileVersion: "1",
            evaluatorVersion: "E", adapterVersion: "A", instrument: "EUR/USD",
            stringSettings: ["z": "last", "a": "first"], numericSettings: ["n": 1.25],
            dateSettingsMilliseconds: ["asOf": 1_800_000_000_123])
        #expect(withDate.sha256() == "670403fee84a0839118d0da3c8b379580194071d1a514193c4f173871a29423f")
        let reordered = StrategyEffectiveConfiguration(profileID: "P", profileVersion: "1",
            evaluatorVersion: "E", adapterVersion: "A", instrument: "EUR/USD",
            stringSettings: ["a": "first", "z": "last"], numericSettings: ["n": 1.25],
            dateSettingsMilliseconds: ["asOf": 1_800_000_000_123])
        #expect(reordered.sha256() == withDate.sha256())

        let c1 = AdaptiveOpportunityAdapters.effectiveConfiguration(
            strategyID: "CANDIDATE_001_CHOCH_FVG_FIB", instrument: "EUR/USD")!
        let c2 = AdaptiveOpportunityAdapters.effectiveConfiguration(
            strategyID: "CANDIDATE_002_AUCTION_FAILURE", instrument: "EUR/USD")!
        #expect(c1.sha256() == "56c548e7f31811537f2078dfd21a454626e640322a027547a34d6f97fe482686")
        #expect(c2.sha256() == "453a16a47a840a717071518a89db0ef50d81945fbeee7cdae371bbd5625c658d")
        let c1DefaultTTL = Candidate001Configuration().resolvedSignalFreshnessSeconds
        let c2DefaultTTL = Candidate002Configuration().resolvedSignalFreshnessSeconds
        #expect(c1DefaultTTL == 300)
        #expect(c2DefaultTTL == 120)
        #expect(c1.numericSettings["signalFreshnessSeconds"] == Double(c1DefaultTTL))
        #expect(c2.numericSettings["signalFreshnessSeconds"] == Double(c2DefaultTTL))
        #expect(Candidate001Configuration(signalFreshnessSeconds: c1DefaultTTL)
            .resolvedSignalFreshnessSeconds == c1DefaultTTL)
        #expect(Candidate002Configuration(signalFreshnessSeconds: c2DefaultTTL)
            .resolvedSignalFreshnessSeconds == c2DefaultTTL)
        var overriddenSettings = c1.numericSettings
        overriddenSettings["signalFreshnessSeconds"] = Double(c1DefaultTTL + 1)
        let overridden = StrategyEffectiveConfiguration(profileID: c1.profileID,
            profileVersion: c1.profileVersion, evaluatorVersion: c1.evaluatorVersion,
            adapterVersion: c1.adapterVersion, instrument: c1.instrument,
            stringSettings: c1.stringSettings, numericSettings: overriddenSettings)
        #expect(overridden.sha256() != c1.sha256())
    }

    @Test func evaluatorAndAdapterSourceDigestsArePinned() {
        let london = AdaptiveOpportunityAdapters.effectiveConfiguration(
            strategyID: GBPJPYLondonBreakRetestV1.strategyID, instrument: "GBP/JPY")!
        #expect(london.profileVersion == "GBPJPY_LONDON_PRACTICE_OBSERVATION_PROVISIONAL_0.1.0")
        #expect(london.stringSettings["atrMethod"] == "SIMPLE_MEAN_TRUE_RANGE_V1")
        #expect(london.numericSettings["maximumQuoteAgeSeconds"] == 3)
        #expect(london.numericSettings["maximumSpreadPips"] == 4.5)
        #expect(StrategyImplementationDigests.adapterCodeSHA256 ==
            "af116791196d95f575f8903bf08d6d64fa187b2402df62066e32a4431c8248c9")
        #expect(StrategyImplementationDigests.selectorCodeSHA256 ==
            "d127d7fc5160213d28df23a6c546401437ccecd7bd7f58fc39b6efaa7419fe08")
        #expect(StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"] ==
            "7199de9171fe9d9e390bf934b0658fec600ded75d4abeb86adf54225c503f304")
        #expect(StrategyImplementationDigests.evaluatorCodeSHA256["CHOCH_FVG_FIB"] ==
            "2cc3dd123c59584d41a42be7a69cd0a0b24ed50a5dddc4fddc2775c01c667236")
        #expect(StrategyImplementationDigests.evaluatorCodeSHA256["AUCTION_FAILURE"] ==
            "3c525e42aa82e09673b9e284b2904b6deb02e022f3ea3f3b44401366d4bc368a")
        #expect(StrategyImplementationDigests.evaluatorCodeSHA256["LONDON_BREAK_RETEST"] ==
            "a883b28bdebd3c672413fb0b0dc79935f1067398c2a68598c9b1d0d32784eb2c")
        #expect(StrategyImplementationDigests.evaluatorCodeSHA256.values.allSatisfy {
            $0.count == 64 && $0.allSatisfy(\.isHexDigit)
        })
    }

    @Test func causalCandidateVersionsAndSourceDigestsMatchRegistry() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func digest(_ relativePath: String) throws -> String {
            let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        let choch = try #require(StrategyResearchRegistry.profiles.first { $0.id == "CHOCH_FVG_FIB" })
        let auction = try #require(StrategyResearchRegistry.profiles.first { $0.id == "AUCTION_FAILURE" })
        #expect(choch.version == Candidate001Analyzer.version)
        #expect(auction.version == Candidate002Analyzer.version)
        #expect(choch.acceptedCandidateIdentities.contains(.init(
            strategyID: "CANDIDATE_001_CHOCH_FVG_FIB", strategyVersion: Candidate001Analyzer.version)))
        #expect(auction.acceptedCandidateIdentities.contains(.init(
            strategyID: "CANDIDATE_002_AUCTION_FAILURE", strategyVersion: Candidate002Analyzer.version)))
        #expect(try digest("Sources/BlazerCore/Research/Candidate001.swift")
            == StrategyImplementationDigests.evaluatorCodeSHA256["CHOCH_FVG_FIB"])
        #expect(try digest("Sources/BlazerCore/Research/Candidate002.swift")
            == StrategyImplementationDigests.evaluatorCodeSHA256["AUCTION_FAILURE"])
        #expect(try digest("Sources/BlazerCore/Research/AdaptiveOpportunityAdapters.swift")
            == StrategyImplementationDigests.adapterCodeSHA256)
    }

    @Test func selectorImplementationDigestMatchesSourceFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Sources/BlazerCore/Research/AdaptiveOpportunitySelector.swift")
        let bytes = try Data(contentsOf: source)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(digest == StrategyImplementationDigests.selectorCodeSHA256)
    }
}
