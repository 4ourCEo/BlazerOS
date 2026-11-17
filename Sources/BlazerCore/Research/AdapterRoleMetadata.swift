import Foundation

/// Metadata-only adapter identities. An unavailable entry is deliberately not
/// approximated by a ResearchRoleContract with inaccurate exit/dependency data.
public enum AdapterRoleAvailability: String, Sendable, Equatable {
    case supported, partial, unavailable
}

public struct AdapterRoleMetadata: Sendable, Equatable {
    public let strategy: ResearchStrategyIdentity
    /// Present only when all material behavior is represented.
    public let contract: ResearchRoleContract?
    /// Known metadata retained for a partial mapping; never treated as complete.
    public let knownContract: ResearchRoleContract?
    public let availability: AdapterRoleAvailability
    public let unavailableReason: String?

    fileprivate init(strategy: ResearchStrategyIdentity, contract: ResearchRoleContract?,
                     knownContract: ResearchRoleContract? = nil,
                     availability: AdapterRoleAvailability, unavailableReason: String?) {
        self.strategy = strategy
        self.contract = contract
        self.knownContract = knownContract
        self.availability = availability
        self.unavailableReason = unavailableReason
    }
}

public enum AdapterRoleMetadataCatalog {
    public static let entries: [AdapterRoleMetadata] = makeEntries()

    public static func entry(strategyName: String) -> AdapterRoleMetadata? {
        entries.first { $0.strategy.name == strategyName }
    }

    private static func makeEntries() -> [AdapterRoleMetadata] {
        let orb = try! ResearchStrategyIdentity(name: "ORB_BREAK_RETEST_V1", version: "ORB_BREAK_RETEST_V1")
        let orbContract = try! ResearchRoleContract(
            dataResolutions: [try! ResearchDataResolution(
                id: "M1", name: "completed one-minute bars", barDurationSeconds: 60,
                minimumCompletedBars: 5)],
            featureRoles: [
                try! ResearchFeatureRole(name: "opening-range-structure", version: "V3_ORB_ENGINE_1",
                                         sourceResolutionID: "M1", lookback: .bars(5)),
                try! ResearchFeatureRole(name: "break-retest-confirmation", version: "V3_ORB_ENGINE_1",
                                         sourceResolutionID: "M1", lookback: .bars(1))
            ],
            freshnessRequirements: [
                try! ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 10),
                try! ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "quote", maximumSeconds: 1)
            ],
            declaredInputRoles: ["quote"],
            trigger: .barClose(resolutionID: "M1"),
            exit: .structuralWithSetupExpiry(planName: "ORB structural stop-or-target",
                                             maximumSetupDurationSeconds: 7_200),
            strategy: orb,
            engineIdentity: "V3_ORB_ENGINE_1")

        var result = [AdapterRoleMetadata(strategy: orb, contract: orbContract, availability: .supported, unavailableReason: nil)]
        let baselineFeatures = [
            try! ResearchFeatureRole(name: "ema-fast-21-and-slow-55-context", version: "JSC_baseline", sourceResolutionIDs: [], selectionRole: "primary", lookback: .bars(55), policyScope: "baseline"),
            try! ResearchFeatureRole(name: "atr-14-and-primary-timeframe-levels", version: "JSC_baseline", sourceResolutionIDs: [], selectionRole: "primary", lookback: .bars(55), policyScope: "baseline"),
            try! ResearchFeatureRole(name: "tap-direction-sweep-and-trigger", version: "JSC_baseline", sourceResolutionID: "M1", lookback: .bars(11), policyScope: "baseline"),
            try! ResearchFeatureRole(name: "rsi-seven-period", version: "JSC_baseline", sourceResolutionID: "M1", lookback: .bars(20), policyScope: "baseline")
        ]
        let adaptiveFeatures = [
            try! ResearchFeatureRole(name: "baseline-signal-context", version: "JSC_baseline", inputs: [try! ResearchFeatureInput(selectionRole: "primary", lookback: .bars(55)), try! ResearchFeatureInput(sourceResolutionID: "M1", lookback: .bars(20))]),
            try! ResearchFeatureRole(name: "adaptive-volatility-efficiency-and-trigger", version: "JSC_POLICY", inputs: [try! ResearchFeatureInput(sourceResolutionID: "M1", lookback: .bars(14)), try! ResearchFeatureInput(sourceResolutionID: "M5", lookback: .bars(14)), try! ResearchFeatureInput(sourceResolutionID: "M1", lookback: .bars(8))]),
            try! ResearchFeatureRole(name: "adaptive-slow-ema-slope", version: "JSC_POLICY", sourceResolutionID: "M5", lookback: .bars(58))
        ]
        for policy in ScanPolicy.allCases {
            let identity = try! ResearchStrategyIdentity(name: policy.rawValue, version: "JSC_\(policy.rawValue)")
            let adaptive = policy != .baseline
            let features = adaptive ? adaptiveFeatures.map {
                try! ResearchFeatureRole(name: $0.name, version: identity.version, inputs: $0.inputs, policyScope: policy.rawValue)
            } : baselineFeatures
            var freshness: [ResearchFreshnessRequirement] = []
            if adaptive {
                freshness = [
                    try! ResearchFreshnessRequirement(kind: .completedBarTrigger, sourceRole: "M1", maximumSeconds: 8),
                    try! ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 8),
                    try! ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "quote", maximumSeconds: 1)
                ]
            }
            let contract = try! ResearchRoleContract(
                dataResolutions: [
                    try! ResearchDataResolution(id: "M1", name: "completed one-minute bars", barDurationSeconds: 60, minimumCompletedBars: 20),
                    try! ResearchDataResolution(id: "M5", name: "completed five-minute bars", barDurationSeconds: 300, minimumCompletedBars: 20)
                ],
                resolutionSelections: [
                    try! ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 30),
                    try! ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 20)
                ],
                featureRoles: features,
                freshnessRequirements: freshness,
                declaredInputRoles: ["quote"],
                trigger: .barClose(resolutionID: "M1"),
                exit: .fixedDurationChoices(seconds: [60, 180, 300]),
                strategy: identity,
                engineIdentity: "scan-engine.js")
            let reason = "Partial mapping only: the knownContract records declared streams, selection, selected feature inputs, trigger, and outcome durations, but not the complete signal predicates or eligibility behavior. Engine inputs require at least 20 completed M1 and M5 bars and valid bid/ask/spread/horizon; ScanKernel additionally removes forming/future bars, requires at least 20 on each stream, and applies MechanicalLifters.verifyLift. Baseline has no quote-age, future-skew, or trigger-age freshness veto in applyResearchPolicy (which baseline does not call); it does apply isSpreadOk, whose instrument-specific thresholds are not represented here. Adaptive policies additionally veto when the M1 trigger age is negative or over 8s, quoteAsOfMs is missing or more than 8s old, or more than 1s in the future; they also apply spread/ATR, chase-distance, volatility, and regime predicates not fully expressible by this contract."
            result.append(AdapterRoleMetadata(strategy: identity, contract: nil, knownContract: contract,
                availability: .partial, unavailableReason: reason))
        }
        return result.sorted { $0.strategy.name < $1.strategy.name }
    }
}
