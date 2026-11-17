import CryptoKit
import Foundation

public enum StrategyResearchStatus: String, Codable, Sendable, Equatable {
    case controlOnly = "CONTROL_ONLY"
    case researchCandidate = "RESEARCH_CANDIDATE"
    case partialResearch = "PARTIAL_RESEARCH"
    case hypothesisNeedsContract = "HYPOTHESIS_NEEDS_CONTRACT"
}

/// Runtime role is independent of research maturity and broker-order authority.
public enum StrategyDecisionRole: String, Codable, Sendable, Equatable {
    case control
    case shadow
    case liveSignal
}

public struct StrategyCandidateIdentity: Codable, Hashable, Sendable, Equatable {
    public let strategyID: String
    public let strategyVersion: String

    public init(strategyID: String, strategyVersion: String) {
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
    }
}

/// Canonical, instrument-specific settings actually passed through the evaluator
/// adapter. Sorted-key JSON and millisecond dates make the digest reproducible.
public struct StrategyEffectiveConfiguration: Codable, Sendable, Equatable {
    public let domain: String
    public let schemaVersion: Int
    public let profileID: String
    public let profileVersion: String
    public let evaluatorVersion: String
    public let adapterVersion: String
    public let instrument: String
    public let stringSettings: [String: String]
    public let numericSettings: [String: Double]
    public let dateSettingsMilliseconds: [String: Int64]

    public init(profileID: String, profileVersion: String, evaluatorVersion: String,
                adapterVersion: String, instrument: String,
                stringSettings: [String: String], numericSettings: [String: Double] = [:],
                dateSettingsMilliseconds: [String: Int64] = [:]) {
        domain = "com.4ource.blazeros.strategy-effective-configuration"
        schemaVersion = 1
        self.profileID = profileID; self.profileVersion = profileVersion
        self.evaluatorVersion = evaluatorVersion; self.adapterVersion = adapterVersion
        self.instrument = instrument
        self.stringSettings = stringSettings; self.numericSettings = numericSettings
        self.dateSettingsMilliseconds = dateSettingsMilliseconds
    }

    public func sha256() -> String? {
        guard numericSettings.values.allSatisfy(\.isFinite) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let json = try? encoder.encode(self),
              let canonical = String(data: json, encoding: .utf8) else { return nil }
        let bytes = Data((domain + "\u{0}" + canonical).utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

public struct StrategyResearchProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let family: String
    public let status: StrategyResearchStatus
    public let sourceReferences: [String]
    public let mayAuthorizeOrder: Bool
    public let decisionRole: StrategyDecisionRole
    public let acceptedCandidateIdentities: [StrategyCandidateIdentity]
    /// Legacy single-config archive field. Live selection requires the instrument map below.
    public let configurationSHA256: String?
    /// Frozen effective configuration digests indexed by exact instrument.
    /// A liveSignal profile must have the exact candidate instrument entry.
    public let configurationSHA256ByInstrument: [String: String]?
    /// Nil means there is no approved selector policy bound to this profile.
    public let selectorPolicySHA256: String?
    public let evaluatorCodeSHA256: String?
    public let adapterCodeSHA256: String?
    public let selectorCodeSHA256: String?

    public init(id: String, version: String, family: String,
                status: StrategyResearchStatus, sourceReferences: [String],
                mayAuthorizeOrder: Bool = false,
                decisionRole: StrategyDecisionRole = .shadow,
                acceptedCandidateIdentities: [StrategyCandidateIdentity] = [],
                configurationSHA256: String? = nil,
                configurationSHA256ByInstrument: [String: String]? = nil,
                selectorPolicySHA256: String? = nil,
                evaluatorCodeSHA256: String? = nil,
                adapterCodeSHA256: String? = nil,
                selectorCodeSHA256: String? = nil) {
        self.id = id
        self.version = version
        self.family = family
        self.status = status
        self.sourceReferences = sourceReferences
        self.mayAuthorizeOrder = mayAuthorizeOrder
        self.decisionRole = decisionRole
        let canonical = StrategyCandidateIdentity(strategyID: id, strategyVersion: version)
        self.acceptedCandidateIdentities = Array(Set([canonical] + acceptedCandidateIdentities))
            .sorted {
                if $0.strategyID != $1.strategyID { return $0.strategyID < $1.strategyID }
                return $0.strategyVersion < $1.strategyVersion
            }
        self.configurationSHA256 = configurationSHA256.map { $0.lowercased() }
        self.configurationSHA256ByInstrument = configurationSHA256ByInstrument?.mapValues { $0.lowercased() }
        self.selectorPolicySHA256 = selectorPolicySHA256.map { $0.lowercased() }
        self.evaluatorCodeSHA256 = evaluatorCodeSHA256?.lowercased()
        self.adapterCodeSHA256 = adapterCodeSHA256?.lowercased()
        self.selectorCodeSHA256 = selectorCodeSHA256?.lowercased()
    }
}

public enum StrategyCandidateResolution: Sendable, Equatable {
    case matched(StrategyResearchProfile)
    case versionMismatch(StrategyResearchProfile)
    case ambiguous
    case unknown
}

public enum StrategyCampaignCompletion: String, Codable, Sendable, Equatable {
    case completed
    case incomplete
}

public enum StrategyCampaignVerdict: String, Codable, Sendable, Equatable {
    case passed
    case failed
}

/// A profile can enter Live selection only when every exact evidence and approval
/// reference is populated and the held-out criteria passed. The Mac resource loader
/// is responsible for verifying these digests against the signed bundled manifest.
public struct StrategyPromotionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let profileID: String
    public let profileVersion: String
    public let hypothesisID: String
    public let configurationSHA256: String
    public let instrument: String
    public let evaluatorCodeSHA256: String
    public let adapterCodeSHA256: String
    public let selectorCodeSHA256: String?
    public let selectorPolicySHA256: String
    public let campaignID: String
    public let campaignManifestSHA256: String
    public let heldOutArtifactSHA256: String
    public let campaignCompletion: StrategyCampaignCompletion
    public let campaignVerdict: StrategyCampaignVerdict
    public let preregistered: Bool
    public let protectedHoldout: Bool
    public let costModelSHA256: String
    public let ownerApprovalID: String
    public let ownerApprovalSHA256: String

    public init(id: String, profileID: String, profileVersion: String,
                hypothesisID: String, configurationSHA256: String,
                instrument: String = "", evaluatorCodeSHA256: String = "",
                adapterCodeSHA256: String = "",
                selectorCodeSHA256: String? = nil,
                selectorPolicySHA256: String, campaignID: String,
                campaignManifestSHA256: String, heldOutArtifactSHA256: String,
                campaignCompletion: StrategyCampaignCompletion,
                campaignVerdict: StrategyCampaignVerdict,
                preregistered: Bool, protectedHoldout: Bool,
                costModelSHA256: String, ownerApprovalID: String,
                ownerApprovalSHA256: String) {
        self.id = id
        self.profileID = profileID
        self.profileVersion = profileVersion
        self.hypothesisID = hypothesisID
        self.configurationSHA256 = configurationSHA256.lowercased()
        self.instrument = instrument
        self.evaluatorCodeSHA256 = evaluatorCodeSHA256.lowercased()
        self.adapterCodeSHA256 = adapterCodeSHA256.lowercased()
        self.selectorCodeSHA256 = selectorCodeSHA256?.lowercased()
        self.selectorPolicySHA256 = selectorPolicySHA256.lowercased()
        self.campaignID = campaignID
        self.campaignManifestSHA256 = campaignManifestSHA256.lowercased()
        self.heldOutArtifactSHA256 = heldOutArtifactSHA256.lowercased()
        self.campaignCompletion = campaignCompletion
        self.campaignVerdict = campaignVerdict
        self.preregistered = preregistered
        self.protectedHoldout = protectedHoldout
        self.costModelSHA256 = costModelSHA256.lowercased()
        self.ownerApprovalID = ownerApprovalID
        self.ownerApprovalSHA256 = ownerApprovalSHA256.lowercased()
    }

    public func validationErrors(for profile: StrategyResearchProfile,
                                 candidate: AdaptiveOpportunityCandidate? = nil) -> [String] {
        var errors: [String] = []
        guard profile.decisionRole == .liveSignal else { errors.append("profile_not_live_signal") ; return errors }
        if profile.mayAuthorizeOrder { errors.append("profile_has_order_authority") }
        guard profile.id == profileID, profile.version == profileVersion else {
            errors.append("promotion_profile_identity_mismatch")
            return errors
        }
        if !Self.isSHA256(configurationSHA256) { errors.append("promotion_configuration_digest_invalid") }
        let instrumentConfiguration = profile.configurationSHA256ByInstrument?[instrument]
        if instrument.isEmpty || profile.configurationSHA256ByInstrument?.isEmpty != false
            || instrumentConfiguration == nil {
            errors.append("profile_instrument_configuration_missing")
        } else if instrumentConfiguration != configurationSHA256 {
            errors.append("promotion_configuration_digest_mismatch")
        }
        if let legacyConfiguration = profile.configurationSHA256,
           legacyConfiguration != instrumentConfiguration {
            errors.append("legacy_profile_configuration_digest_mismatch")
        }
        if !Self.isSHA256(evaluatorCodeSHA256) { errors.append("promotion_evaluator_code_digest_invalid") }
        if !Self.isSHA256(adapterCodeSHA256) { errors.append("promotion_adapter_code_digest_invalid") }
        if profile.evaluatorCodeSHA256 != evaluatorCodeSHA256
            || profile.adapterCodeSHA256 != adapterCodeSHA256 {
            errors.append("promotion_code_digest_mismatch")
        }
        if !Self.isSHA256(selectorCodeSHA256 ?? "")
            || profile.selectorCodeSHA256 != selectorCodeSHA256
            || selectorCodeSHA256 != StrategyImplementationDigests.selectorCodeSHA256 {
            errors.append("promotion_selector_code_digest_mismatch")
        }
        if let candidate {
            if candidate.instrument != instrument
                || candidate.effectiveConfigurationSHA256 != configurationSHA256
                || candidate.evaluatorCodeSHA256 != evaluatorCodeSHA256
                || candidate.adapterCodeSHA256 != adapterCodeSHA256
                || candidate.selectorCodeSHA256 != selectorCodeSHA256 {
                errors.append("promotion_candidate_provenance_mismatch")
            }
            if instrumentConfiguration != candidate.effectiveConfigurationSHA256 {
                errors.append("profile_candidate_configuration_mismatch")
            }
        }
        if profile.selectorPolicySHA256 != selectorPolicySHA256
            || selectorPolicySHA256 != LiveStrategySelectorPolicy.sha256
            || !Self.isSHA256(selectorPolicySHA256) {
            errors.append("promotion_selector_policy_digest_mismatch")
        }
        if id.isEmpty || hypothesisID.isEmpty || campaignID.isEmpty || ownerApprovalID.isEmpty {
            errors.append("promotion_reference_missing")
        }
        for (value, code) in [
            (campaignManifestSHA256, "campaign_manifest_digest_invalid"),
            (heldOutArtifactSHA256, "held_out_digest_invalid"),
            (costModelSHA256, "cost_model_digest_invalid"),
            (ownerApprovalSHA256, "owner_approval_digest_invalid")
        ] where !Self.isSHA256(value) {
            errors.append(code)
        }
        if campaignCompletion != .completed { errors.append("campaign_incomplete") }
        if campaignVerdict != .passed { errors.append("held_out_criteria_not_passed") }
        if !preregistered { errors.append("hypothesis_not_preregistered") }
        if !protectedHoldout { errors.append("held_out_set_not_protected") }
        return errors
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}

public enum LiveStrategySelectorPolicy {
    public static let version = "LIVE_UNIQUE_PLAN_LEGACY_4OF4_V1"
    /// Canonical policy statement hashed into promotion records. Any policy change
    /// requires a new version and a newly evaluated promotion artifact.
    public static let canonicalDefinition = """
    one-unique-validated-plan; exact-profile-version; promotion-proof-required;
    opposing-promoted-direction-vetoes; legacy-control-veto-only-if-all-four-
    baseline-continuation-reversal-regime-are-fresh-eligible-directional-and-
    unanimous; legacy-never-supplies-plan-or-support; no-rank-score-arbitration
    """
    public static let sha256 = SHA256.hash(data: Data(canonicalDefinition.utf8))
        .map { String(format: "%02x", $0) }.joined()
}

/// Source and evidence boundaries available to the decision engine. Book-derived
/// principles guide testing and risk controls; book chapter topics are never
/// substituted for a fully specified, validated entry rule.
public enum StrategyResearchRegistry {
    /// Research standards the laboratory uses for evaluation. These references are
    /// not presented as the source of any signal rule.
    public static let researchMethodReferences = [
        "ARONSON_EBTA_2007:CH3-6",
        "CHAN_ALGORITHMIC_TRADING_2013:CH1-8",
        "CHAN_QUANTITATIVE_TRADING_2E:CH2-3,CH6-7",
        "CARVER_SYSTEMATIC_TRADING:CH2-4,CH7-11",
        "DUARTE_TRADING_FUTURES_FOR_DUMMIES_2008:CH7-8,CH11,CH17-21"
    ]

    private static func identity(_ id: String, _ version: String) -> StrategyCandidateIdentity {
        StrategyCandidateIdentity(strategyID: id, strategyVersion: version)
    }

    public static func duplicateIdentityErrors(in profiles: [StrategyResearchProfile]) -> [String] {
        var owners: [StrategyCandidateIdentity: [String]] = [:]
        for profile in profiles {
            for accepted in profile.acceptedCandidateIdentities {
                owners[accepted, default: []].append(profile.id)
            }
        }
        return owners.filter { $0.value.count > 1 }.keys
            .map { "duplicate_strategy_identity:\($0.strategyID):\($0.strategyVersion)" }.sorted()
    }

    public static let profiles: [StrategyResearchProfile] = [
        .init(id: "LEGACY_V1", version: "pinned-control",
              family: "Legacy V1 directional control", status: .controlOnly,
              sourceReferences: ["Sources/BlazerCore/Research/scan-engine-control.js"],
              decisionRole: .control,
              acceptedCandidateIdentities: [
                identity("baseline", "JSC_baseline"),
                identity("continuation", "JSC_continuation"),
                identity("reversal", "JSC_reversal"),
                identity("regime", "JSC_regime")
              ], evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["LEGACY_V1"],
              adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
              selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256),
        .init(id: "ORB_BREAK_RETEST", version: "ORB_BREAK_RETEST_V1",
              family: "Opening range breakout + retest", status: .researchCandidate,
              sourceReferences: ["Sources/BlazerCore/Research/ORBBreakRetestV1.swift"],
              acceptedCandidateIdentities: [identity("ORB_BREAK_RETEST_V1", "ORB_BREAK_RETEST_V1")],
              evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"],
              adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
              selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256),
        .init(id: "CHOCH_FVG_FIB", version: "candidate-001-v2",
              family: "CHoCH + FVG + Fibonacci", status: .researchCandidate,
              sourceReferences: ["Sources/BlazerCore/Research/Candidate001.swift"],
              acceptedCandidateIdentities: [identity("CANDIDATE_001_CHOCH_FVG_FIB", "candidate-001-v2")],
              evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["CHOCH_FVG_FIB"],
              adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
              selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256),
        .init(id: "AUCTION_FAILURE", version: "candidate-002-auction-failure-v2",
              family: "Auction failure reversal", status: .researchCandidate,
              sourceReferences: ["Sources/BlazerCore/Research/Candidate002.swift"],
              acceptedCandidateIdentities: [identity("CANDIDATE_002_AUCTION_FAILURE", "candidate-002-auction-failure-v2")],
              evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["AUCTION_FAILURE"],
              adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
              selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256),
        .init(id: "BREAKOUT_ACCEPTANCE", version: "BREAKOUT_ACCEPTANCE_V1",
              family: "Breakout + acceptance", status: .partialResearch,
              sourceReferences: ["Sources/BlazerCore/Research/BreakoutAcceptanceV1.swift",
                                "reports/STRAT_BREAKOUT_ACCEPTANCE_CONTRACT_PRD_2026-11-13.md",
                                "reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md",
                                "reports/source/BlazerOS_STRIKE_V3_Product_Engineering_PRD.md",
                                "reports/BLAZEROS_BOOK_HYPOTHESIS_REGISTER_2026-11-13.md"]),
        .init(id: "TREND_PULLBACK", version: "STRAT-GBPJPY-TREND-PULLBACK-V1",
              family: "Trend pullback continuation", status: .partialResearch,
              sourceReferences: ["Sources/BlazerCore/Research/GBPJPYTrendPullbackV1.swift",
                                "reports/STRAT_GBPJPY_TREND_PULLBACK_PLAN_2026-11-13.md",
                                "reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md",
                                "reports/source/BlazerOS_STRIKE_V3_REBUILT_PRD.md",
                                "reports/source/BlazerOS_STRIKE_V3_Product_Engineering_PRD.md",
                                "reports/BLAZEROS_BOOK_HYPOTHESIS_REGISTER_2026-11-13.md"]),
        .init(id: "RANGE_REJECTION", version: "GBPJPY_RANGE_REJECTION_V1",
              family: "GBP/JPY range rejection / mean reversion", status: .researchCandidate,
              sourceReferences: ["Sources/BlazerCore/Research/GBPJPYRangeRejectionV1.swift",
                                "reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md"]),
        .init(id: "LONDON_BREAK_RETEST", version: "GBPJPY_LONDON_RANGE_BREAK_RETEST_V1",
              family: "London GBP/JPY breakout + retest", status: .researchCandidate,
              sourceReferences: ["Sources/BlazerCore/Research/GBPJPYLondonBreakRetestV1.swift",
                                "reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md",
                                "reports/STRAT_GBPJPY_LONDON_BREAK_RETEST_PLAN_2026-11-14.md"],
              acceptedCandidateIdentities: [identity("GBPJPY_LONDON_RANGE_BREAK_RETEST",
                                                       "GBPJPY_LONDON_RANGE_BREAK_RETEST_V1")]),
        .init(id: "LIQUIDITY_SWEEP", version: "v1-features-only",
              family: "Liquidity sweep + reversal", status: .partialResearch,
              sourceReferences: ["Sources/BlazerCore/Research/scan-engine-control.js"]),
        .init(id: "MARKET_REGIME_ROUTER", version: "partial-v1-policy",
              family: "Market regime router", status: .partialResearch,
              sourceReferences: ["Sources/BlazerCore/Research/scan-engine-control.js"]),
        .init(id: "MULTI_TIMEFRAME_SELECTION", version: "uncontracted",
              family: "Adaptive multi-timeframe selection", status: .hypothesisNeedsContract,
              sourceReferences: ["reports/GBPJPY_STRATEGY_VALIDATION_PRD_2026-11-10.md"]),
        .init(id: "TOKYO_SESSION_SWEEP", version: "unvalidated-hypothesis",
              family: "Tokyo / Asian session sweep", status: .hypothesisNeedsContract,
              sourceReferences: ["reports/BLAZEROS_BOOK_HYPOTHESIS_REGISTER_2026-11-13.md"]),
        .init(id: "LATE_NIGHT_TACTICAL_SCALP", version: "schedule-only",
              family: "Late-night tactical scalp", status: .partialResearch,
              sourceReferences: ["Sources/LightningDesk/Modals/PrimeScheduleSheet.swift"]),
        .init(id: "MORNING_PRIME_NEW_YORK", version: "session-priority-only",
              family: "Morning prime / New York focus", status: .partialResearch,
              sourceReferences: ["Sources/LightningDesk/Modals/PrimeScheduleSheet.swift"]),
        .init(id: "FX_INTRADAY_MOMENTUM", version: "unregistered",
              family: "FX intraday momentum hypothesis", status: .hypothesisNeedsContract,
              sourceReferences: ["CHAN_ALGORITHMIC_TRADING_2013:CH7"]),
        .init(id: "FX_MEAN_REVERSION", version: "unregistered",
              family: "FX mean-reversion hypothesis", status: .hypothesisNeedsContract,
              sourceReferences: ["CHAN_ALGORITHMIC_TRADING_2013:CH2,CH5"]),
        .init(id: "FIXED_HORIZON_COMPARISON", version: "research-arm",
              family: "Fixed-horizon comparisons", status: .partialResearch,
              sourceReferences: ["Sources/BlazerCore/Research/ResearchExperiment.swift",
                                "Sources/BlazerCore/Research/SpotFXHistoricalReplay.swift"])
    ]

    /// Deliberately empty: code and synthetic fixtures never imply evidence or owner approval.
    public static let productionPromotionRecords: [StrategyPromotionRecord] = []

    public static func resolve(strategyID: String,
                               strategyVersion: String) -> StrategyCandidateResolution {
        let identity = StrategyCandidateIdentity(strategyID: strategyID, strategyVersion: strategyVersion)
        let exactProfiles = profiles.filter { $0.acceptedCandidateIdentities.contains(identity) }
        if exactProfiles.count > 1 { return .ambiguous }
        if let exact = exactProfiles.first {
            return .matched(exact)
        }
        if let sameID = profiles.first(where: { profile in
            profile.acceptedCandidateIdentities.contains { $0.strategyID == strategyID }
        }) {
            return .versionMismatch(sameID)
        }
        return .unknown
    }

    /// Display family mapping only. Unknown IDs remain explicitly unregistered.
    public static func family(for strategyID: String) -> String? {
        let matches = profiles.filter { profile in
            profile.acceptedCandidateIdentities.contains { $0.strategyID == strategyID }
        }
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    public static func sourceReferences(for families: [String]) -> [String] {
        let familySources = profiles.filter { families.contains($0.id) }
            .flatMap(\.sourceReferences)
        return Array(Set(familySources)).sorted()
    }
}
