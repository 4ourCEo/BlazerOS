import Foundation
import Testing
@testable import BlazerCore

private func resolution(_ id: String, seconds: Double = 60) throws -> ResearchDataResolution {
    try ResearchDataResolution(id: id, name: id, barDurationSeconds: seconds, minimumCompletedBars: 3)
}

private func strategy() throws -> ResearchStrategyIdentity {
    try ResearchStrategyIdentity(name: "contextual-breakout", version: "2.1")
}

@Test func m5ContextM1TriggerCanUseStructuralExitWithoutHorizon() throws {
    let contract = try ResearchRoleContract(
        dataResolutions: [try resolution("M1"), try resolution("M5", seconds: 300)],
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
    if case .structural = contract.exit {
        // Structural exits deliberately carry no duration or implied horizon.
    } else {
        Issue.record("expected structural exit")
    }
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
