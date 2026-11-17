import Foundation
import Testing
@testable import BlazerCore

private func resolution(_ id: String, seconds: Double = 60) throws -> ResearchDataResolution {
    try ResearchDataResolution(id: id, name: id, barDurationSeconds: seconds, minimumCompletedBars: 3)
}

private func strategy() throws -> ResearchStrategyIdentity {
    try ResearchStrategyIdentity(name: "contextual-breakout", version: "2.1")
}

@Test func currentBaselineSelectsM5At30BarsOtherwiseM1AndKeepsM1Trigger() throws {
    let contract = try ResearchRoleContract(
        dataResolutions: [try resolution("M1"), try resolution("M5", seconds: 300)],
        resolutionSelections: [
            try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 30),
            try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 20)
        ],
        featureRoles: [
            try ResearchFeatureRole(name: "context", version: "v1", sourceResolutionID: "M5", lookback: .bars(12)),
            try ResearchFeatureRole(name: "entry", version: "v2", sourceResolutionID: "M1", lookback: .duration(seconds: 90))
        ],
        trigger: .barClose(resolutionID: "M1"),
        exit: .structural(planName: "stop-or-target-v1"),
        strategy: try strategy(),
        engineIdentity: nil
    )

    #expect(contract.dataResolutions.map(\.id) == ["M1", "M5"])
    #expect(contract.featureRoles[0].sourceResolutionID == "M5")
    #expect(contract.resolutionSelections.map(\.resolutionID) == ["M5", "M1"])
    if case .structural = contract.exit {
        // Structural exits deliberately carry no duration or implied horizon.
    } else {
        Issue.record("expected structural exit")
    }
}

@Test func featuresCanUseSeveralStreamsOrASelectionRoleAndPolicyFreshnessIsExplicit() throws {
    let contract = try ResearchRoleContract(
        dataResolutions: [try resolution("M1"), try resolution("M5", seconds: 300)],
        resolutionSelections: [try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 30), try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 20)],
        featureRoles: [
            try ResearchFeatureRole(name: "spread-context", version: "v2", inputs: [
                ResearchFeatureInput(sourceResolutionID: "M1", lookback: .bars(4)),
                ResearchFeatureInput(sourceResolutionID: "M5", lookback: .bars(14))
            ], policyScope: "orb"),
            try ResearchFeatureRole(name: "primary-context", version: "v3", inputs: [
                ResearchFeatureInput(selectionRole: "primary", lookback: .duration(seconds: 900))
            ], policyScope: "orb")
        ],
        freshnessRequirements: [
            try ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "entry-quote", maximumSeconds: 2),
            try ResearchFreshnessRequirement(kind: .futureSkew, sourceRole: "entry-quote", maximumSeconds: 0.5),
            try ResearchFreshnessRequirement(kind: .completedBarTrigger, sourceRole: "M1", maximumSeconds: 300)
        ], declaredInputRoles: ["entry-quote"], trigger: .barClose(resolutionID: "M1"), exit: .structuralWithSetupExpiry(planName: "orb-stop-or-target", maximumSetupDurationSeconds: 1_800), strategy: try strategy(), engineIdentity: nil
    )
    #expect(contract.featureRoles[0].sourceResolutionIDs == ["M1", "M5"])
    #expect(contract.featureRoles[0].inputs.map(\.lookback) == [.bars(4), .bars(14)])
    #expect(contract.freshnessRequirements.map(\.kind) == [.quoteAge, .futureSkew, .completedBarTrigger])
    if case .structuralWithSetupExpiry(_, let expiry) = contract.exit { #expect(expiry == 1_800) } else { Issue.record("expected setup expiry without exit horizon") }
}

@Test func selectionsChooseOrderedFallbacksAndIndependentGroups() throws {
    let rules = [try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 30), try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 20), try ResearchResolutionSelectionRule(selectionRole: "confirmation", resolutionID: "M15", minimumCompletedBars: 10), try ResearchResolutionSelectionRule(selectionRole: "confirmation", resolutionID: "M1", minimumCompletedBars: 5)]
    #expect(rules.selectedResolutionID(selectionRole: "primary", completedBarsByResolution: ["M5": 30, "M1": 52]) == "M5")
    #expect(rules.selectedResolutionID(selectionRole: "primary", completedBarsByResolution: ["M5": 29, "M1": 52]) == "M1")
    #expect(rules.selectedResolutionID(selectionRole: "primary", completedBarsByResolution: ["M5": 29, "M1": 19]) == nil)
    #expect(rules.selectedResolutionID(selectionRole: "confirmation", completedBarsByResolution: ["M15": 9, "M1": 5]) == "M1")
    #expect(throws: ResearchRoleContractError.invalidFallbackOrder) { try ResearchRoleContract(dataResolutions: [try resolution("M1"), try resolution("M5"), try resolution("M15")], resolutionSelections: [try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 30), try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 20), try ResearchResolutionSelectionRule(selectionRole: "confirmation", resolutionID: "M15", minimumCompletedBars: 4), try ResearchResolutionSelectionRule(selectionRole: "confirmation", resolutionID: "M1", minimumCompletedBars: 5)], featureRoles: [], trigger: .barClose(resolutionID: "M1"), exit: .structural(planName: "p"), strategy: try strategy(), engineIdentity: nil) }
}

@Test func anotherResolutionConfigurationAndQuoteTriggerAreIndependent() throws {
    let contract = try ResearchRoleContract(
        dataResolutions: [try resolution("15s", seconds: 15), try resolution("1h", seconds: 3_600)],
        featureRoles: [try ResearchFeatureRole(name: "regime", version: "v3", sourceResolutionID: "1h", lookback: .duration(seconds: 7_200))],
        trigger: .quoteEvent(name: "trusted-quote"),
        exit: .fixedDuration(seconds: 37),
        strategy: try strategy(),
        engineIdentity: "research-engine-v4"
    )

    #expect(contract.dataResolutions[0].barDurationSeconds == 15)
    #expect(contract.engineIdentity == "research-engine-v4")
}

@Test func invalidReferencesAndValuesAreRejected() throws {
    #expect(throws: ResearchRoleContractError.invalidDuration) {
        try ResearchDataResolution(id: "bad", name: "bad", barDurationSeconds: 0, minimumCompletedBars: 1)
    }
    #expect(throws: ResearchRoleContractError.invalidLookback) {
        try ResearchRoleContract(
            dataResolutions: [try resolution("M1")],
            featureRoles: [ResearchFeatureRole(name: "bad", version: "v1", sourceResolutionID: "M1", lookback: .bars(0))],
            trigger: .barClose(resolutionID: "M1"), exit: .structural(planName: "plan"),
            strategy: try strategy(), engineIdentity: nil
        )
    }
    #expect(throws: ResearchRoleContractError.missingResolutionID("M5")) {
        try ResearchRoleContract(
            dataResolutions: [try resolution("M1")], featureRoles: [],
            trigger: .barClose(resolutionID: "M5"), exit: .structural(planName: "plan"),
            strategy: try strategy(), engineIdentity: nil
        )
    }
    #expect(throws: ResearchRoleContractError.invalidFixedHorizon) {
        try ResearchRoleContract(
            dataResolutions: [try resolution("M1")], featureRoles: [],
            trigger: .quoteEvent(name: "quote"), exit: .fixedDuration(seconds: 0),
            strategy: try strategy(), engineIdentity: nil
        )
    }
    #expect(throws: ResearchRoleContractError.invalidFallbackOrder) {
        try ResearchRoleContract(dataResolutions: [try resolution("M1"), try resolution("M5")], resolutionSelections: [try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M5", minimumCompletedBars: 20), try ResearchResolutionSelectionRule(selectionRole: "primary", resolutionID: "M1", minimumCompletedBars: 30)], featureRoles: [], trigger: .barClose(resolutionID: "M1"), exit: .structural(planName: "plan"), strategy: try strategy(), engineIdentity: nil)
    }
    #expect(throws: ResearchRoleContractError.invalidFreshness) {
        try ResearchFreshnessRequirement(kind: .quoteAge, sourceRole: "quote", maximumSeconds: .infinity)
    }
    #expect(throws: ResearchRoleContractError.invalidPolicyScope) {
        try ResearchFeatureRole(name: "f", version: "v1", sourceResolutionID: "M1", lookback: .bars(1), policyScope: " ")
    }
}

@Test func contractJSONRoundTripsAndDecodingRemainsValidated() throws {
    let original = try ResearchRoleContract(
        dataResolutions: [try resolution("M1"), try resolution("M5", seconds: 300)],
        featureRoles: [try ResearchFeatureRole(name: "context", version: "v1", sourceResolutionID: "M5", lookback: .bars(5))],
        trigger: .barClose(resolutionID: "M1"), exit: .structural(planName: "swing-plan"),
        strategy: try strategy(), engineIdentity: nil
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ResearchRoleContract.self, from: data)
    #expect(decoded == original)

    var malformedFeature = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var features = try #require(malformedFeature["featureRoles"] as? [[String: Any]])
    features[0]["version"] = "   "
    malformedFeature["featureRoles"] = features
    let malformedFeatureData = try JSONSerialization.data(withJSONObject: malformedFeature)
    #expect(throws: ResearchRoleContractError.invalidName) {
        try JSONDecoder().decode(ResearchRoleContract.self, from: malformedFeatureData)
    }

    var malformedStrategy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var strategyObject = try #require(malformedStrategy["strategy"] as? [String: Any])
    strategyObject["name"] = ""
    malformedStrategy["strategy"] = strategyObject
    let malformedStrategyData = try JSONSerialization.data(withJSONObject: malformedStrategy)
    #expect(throws: ResearchRoleContractError.invalidName) {
        try JSONDecoder().decode(ResearchRoleContract.self, from: malformedStrategyData)
    }
}

@Test func lookbackDecodesPriorSynthesizedEnumWireFormat() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(ResearchLookback.self, from: Data(#"{"bars":{"_0":12}}"#.utf8)) == .bars(12))
    #expect(try decoder.decode(ResearchLookback.self, from: Data(#"{"duration":{"_0":90}}"#.utf8)) == .duration(seconds: 90))
}
