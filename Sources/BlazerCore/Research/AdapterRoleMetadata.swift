import Foundation

/// Metadata-only adapter identities. An unavailable entry is deliberately not
/// approximated by a ResearchRoleContract with inaccurate exit/dependency data.
public struct AdapterRoleMetadata: Sendable, Equatable {
    public let strategy: ResearchStrategyIdentity
    public let contract: ResearchRoleContract?
    public let unavailableReason: String?

    fileprivate init(strategy: ResearchStrategyIdentity, contract: ResearchRoleContract?,
                     unavailableReason: String?) {
        self.strategy = strategy
        self.contract = contract
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
                try! ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 5),
                try! ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "quote", maximumSeconds: 1)
            ],
            declaredInputRoles: ["quote"],
            trigger: .barClose(resolutionID: "M1"),
            exit: .structuralWithSetupExpiry(planName: "ORB structural stop-or-target",
                                             maximumSetupDurationSeconds: 7_200),
            strategy: orb,
            engineIdentity: "V3_ORB_ENGINE_1")

        var result = [AdapterRoleMetadata(strategy: orb, contract: orbContract, unavailableReason: nil)]
        let unsupported: [String: String] = [
            "baseline": "Known inputs: validate independently at least 20 completed M1 and M5 bars; select primary M5 when its own count is at least 30, else M1 when its own count is at least 20; use M1 for tap/RSI inputs and the M1 trigger. The engine accepts selectable 60/180/300-second outcome horizons; the contract schema cannot express that choice without asserting a fixed exit.",
            "continuation": "Policy-scoped feature dependencies and exit semantics are not represented as a complete, policy-specific contract.",
            "reversal": "Policy-scoped feature dependencies and exit semantics are not represented as a complete, policy-specific contract.",
            "regime": "Policy-scoped feature dependencies and exit semantics are not represented as a complete, policy-specific contract."
        ]
        for (policy, reason) in unsupported {
            let identity = try! ResearchStrategyIdentity(name: policy, version: "JSC_\(policy)")
            result.append(AdapterRoleMetadata(strategy: identity, contract: nil, unavailableReason: reason))
        }
        return result.sorted { $0.strategy.name < $1.strategy.name }
    }
}
