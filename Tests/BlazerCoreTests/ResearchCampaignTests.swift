import Foundation
import Testing
@testable import BlazerCore

@Test func campaignFreezesSixtySecondRulesAndVersions() throws {
    let campaign = try ForwardValidationCampaign(
        id: "campaign-2026-11", version: "v1",
        strategies: [ResearchStrategyCandidate(id: "baseline", version: "engine-v1", description: "control")],
        instruments: ["EUR/USD"], sources: ["oanda-proxy"],
        evaluationCriteria: ["resolved expectancy", "latency sensitivity"]
    )
    #expect(campaign.expirySeconds == 60)
    #expect(throws: Milestone5ResearchError.invalidInput) {
        try ForwardValidationCampaign(
            id: "bad", version: "v1",
            strategies: campaign.strategies, instruments: campaign.instruments,
            sources: campaign.sources, expirySeconds: 180,
            evaluationCriteria: campaign.evaluationCriteria
        )
    }
}

@Test func researchStorePersistsCampaignsAndGapRegister() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("research-\(UUID().uuidString)", isDirectory: true)
    let store = ResearchStore(root: root)
    let gap = ResearchGap(id: "P1-webhook-replay", component: "Pine webhook",
        severity: .p1, evidence: "restart replay risk", owner: "engineering",
        requiredFix: "persist consumed IDs", regressionTest: "restart replay test",
        independentQA: "confirmed", status: .verified)
    try await store.record(gap)
    #expect((try await store.gaps()).first?.status == .verified)
}
