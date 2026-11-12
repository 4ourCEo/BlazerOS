import Testing
@testable import BlazerCore

@Test func orbAdapterMetadataMatchesM1StructureExpiryAndFreshness() throws {
    let metadata = try #require(AdapterRoleMetadataCatalog.entry(strategyName: "ORB_BREAK_RETEST_V1"))
    let contract = try #require(metadata.contract)

    #expect(metadata.strategy.version == "ORB_BREAK_RETEST_V1")
    #expect(contract.engineIdentity == "V3_ORB_ENGINE_1")
    #expect(contract.dataResolutions.map(\.id) == ["M1"])
    #expect(contract.dataResolutions[0].barDurationSeconds == 60)
    #expect(contract.dataResolutions[0].minimumCompletedBars == 5)
    #expect(contract.featureRoles.map(\.sourceResolutionID) == ["M1", "M1"])
    #expect(contract.trigger == .barClose(resolutionID: "M1"))
    #expect(contract.freshnessRequirements == [
        try ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: 5),
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

@Test func unsupportedEngineAdapterMappingsAreExplicitAndNeverAssumeSixtySecondExit() throws {
    let baseline = try #require(AdapterRoleMetadataCatalog.entry(strategyName: "baseline"))
    #expect(baseline.contract == nil)
    #expect(baseline.unavailableReason?.contains("M5 when its own count is at least 30") == true)
    #expect(baseline.unavailableReason?.contains("M1 when its own count is at least 20") == true)
    #expect(baseline.unavailableReason?.contains("M1 for tap/RSI inputs and the M1 trigger") == true)

    for policy in ScanPolicy.allCases {
        let metadata = try #require(AdapterRoleMetadataCatalog.entry(strategyName: policy.rawValue))
        #expect(metadata.strategy.version == "JSC_\(policy.rawValue)")
        #expect(metadata.contract == nil)
        #expect(metadata.unavailableReason?.isEmpty == false)
    }
}
