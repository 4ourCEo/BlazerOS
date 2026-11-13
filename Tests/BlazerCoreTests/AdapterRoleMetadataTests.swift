import Testing
@testable import BlazerCore

@Test func orbAdapterMetadataMatchesM1StructureExpiryAndFreshness() throws {
    let metadata = try #require(AdapterRoleMetadataCatalog.entry(strategyName: "ORB_BREAK_RETEST_V1"))
    let contract = try #require(metadata.contract)

    #expect(metadata.strategy.version == "ORB_BREAK_RETEST_V1")
    #expect(metadata.availability == .supported)
    #expect(contract.engineIdentity == "V3_ORB_ENGINE_1")
    #expect(contract.dataResolutions.map(\.id) == ["M1"])
    #expect(contract.dataResolutions[0].barDurationSeconds == 60)
    #expect(contract.dataResolutions[0].minimumCompletedBars == 5)
    #expect(contract.featureRoles.map(\.sourceResolutionID) == ["M1", "M1"])
    #expect(contract.trigger == .barClose(resolutionID: "M1"))
    #expect(contract.freshnessRequirements == [
        try ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 10),
        try ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "quote", maximumSeconds: 1)
    ])
    if case .structuralWithSetupExpiry(let name, let expiry) = contract.exit {
        #expect(name == "ORB structural stop-or-target")
        #expect(expiry == 7_200)
    } else {
        Issue.record("ORB requires structural exit semantics and a separate setup expiry")
    }
    #expect(metadata.unavailableReason == nil)
}

@Test func scanPolicyMappingsMatchFallbackDependenciesCadenceFreshnessAndExpiryChoices() throws {
    let baseline = try #require(AdapterRoleMetadataCatalog.entry(strategyName: "baseline"))
    #expect(baseline.availability == .partial)
    #expect(baseline.contract == nil)
    let contract = try #require(baseline.knownContract)
    #expect(baseline.strategy == (try ResearchStrategyIdentity(name: "baseline", version: "JSC_baseline")))
    #expect(contract.dataResolutions.map(\.id) == ["M1", "M5"])
    #expect(contract.dataResolutions.map(\.minimumCompletedBars) == [20, 20])
    #expect(contract.resolutionSelections.map(\.resolutionID) == ["M5", "M1"])
    #expect(contract.resolutionSelections.map(\.minimumCompletedBars) == [30, 20])
    #expect(contract.resolutionSelections.selectedResolutionID(selectionRole: "primary", completedBarsByResolution: ["M5": 29, "M1": 20]) == "M1")
    #expect(contract.resolutionSelections.selectedResolutionID(selectionRole: "primary", completedBarsByResolution: ["M5": 30, "M1": 20]) == "M5")
    #expect(contract.featureRoles.contains { $0.name == "rsi-seven-period" && $0.inputs.map(\.sourceResolutionID) == ["M1"] })
    #expect(contract.featureRoles.first { $0.name == "tap-direction-sweep-and-trigger" }?.lookback == .bars(11))
    #expect(contract.trigger == .barClose(resolutionID: "M1"))
    #expect(contract.freshnessRequirements.isEmpty)
    #expect(contract.exit == .fixedDurationChoices(seconds: [60, 180, 300]))
    #expect(baseline.unavailableReason?.contains("isSpreadOk") == true)
    #expect(baseline.unavailableReason?.contains("no quote-age") == true)

    for policy in ScanPolicy.allCases {
        let metadata = try #require(AdapterRoleMetadataCatalog.entry(strategyName: policy.rawValue))
        #expect(metadata.strategy.version == "JSC_\(policy.rawValue)")
        #expect(metadata.availability == .partial)
        #expect(metadata.contract == nil)
        let policyContract = try #require(metadata.knownContract)
        #expect(policyContract.engineIdentity == "scan-engine.js")
        #expect(policyContract.trigger == .barClose(resolutionID: "M1"))
        #expect(policyContract.exit == .fixedDurationChoices(seconds: [60, 180, 300]))
        #expect(metadata.unavailableReason?.isEmpty == false)
        if policy == .baseline {
            #expect(policyContract.freshnessRequirements.isEmpty)
        } else {
            #expect(policyContract.freshnessRequirements.contains(try ResearchFreshnessRequirement(kind: .completedBarTrigger, sourceRole: "M1", maximumSeconds: 8)))
            #expect(policyContract.freshnessRequirements.contains(try ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 8)))
            #expect(policyContract.freshnessRequirements.contains(try ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "quote", maximumSeconds: 1)))
            #expect(policyContract.featureRoles.allSatisfy { $0.version == "JSC_\(policy.rawValue)" && $0.policyScope == policy.rawValue })
            #expect(metadata.unavailableReason?.contains("trigger age is negative or over 8s") == true)
            #expect(metadata.unavailableReason?.contains("quoteAsOfMs is missing") == true)
        }
    }
}
