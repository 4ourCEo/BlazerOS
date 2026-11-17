import Foundation
import Testing
@testable import BlazerCore

private func attemptFixture(
    number: Int,
    id: String? = nil,
    decision: ResearchAttemptDecision = .rejected,
    supersedes: String? = nil,
    archiveHash: String = String(repeating: "a", count: 64)
) -> ResearchExperimentAttempt {
    ResearchExperimentAttempt(
        id: id ?? "attempt-\(number)", experimentID: "experiment-1", attemptNumber: number,
        strategyID: "eurusd-continuation", strategyVersion: "v1",
        hypothesis: "Continuation after a completed M5 trend should outperform no-trade.",
        dataArchives: [.init(sourceIdentity: "OANDA/EUR_USD", archiveSHA256: archiveHash)],
        instrumentID: "EUR_USD", timeframeRoles: ["trigger": "M1", "context": "M5"],
        exitContract: "structural stop at prior swing; invalidate on close through level",
        splitAssignment: .development,
        parameterVariations: ["trendLookback": ["12", "16"]],
        benchmark: "NO_TRADE and pinned baseline",
        executionAssumptions: .init(spread: "recorded bid/ask", slippage: "0.2R sensitivity",
            entryDelay: "3s observed", financing: "not applicable for intraday replay",
            fillModel: "conservative next quote; no assumed exact candle fill"),
        outcomeEvidence: .init(independentEligibleSetups: 20, resolved: 15, ambiguous: 2,
            unresolved: 3, netExpectancyR: -0.12, uncertaintyLowerR: -0.45,
            uncertaintyUpperR: 0.21, uncertaintyMethod: "cluster bootstrap",
            evidenceReference: "validation cohort digest"),
        decision: decision, decisionRationale: "Development attempt rejected; retain for audit.",
        supersedesAttemptID: supersedes,
        createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(number)))
}

private func seedExperiment(in store: ResearchStore) async throws {
    try await store.record(ResearchExperiment(
        id: "experiment-1", name: "EURUSD continuation protocol", policy: "continuation",
        engineSHA: EngineIdentity.pinnedSHA1, acceptanceCriteria: "Predeclared criteria",
        rejectionCriteria: "Predeclared rejection criteria"))
}

@Test func researchStoreAppendsFailedAndSupersedingAttemptsWithoutOverwriting() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("research-attempts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResearchStore(root: root)
    try await seedExperiment(in: store)
    let first = attemptFixture(number: 1, decision: .rejected)
    let second = attemptFixture(number: 2, decision: .acceptedForFurtherResearch,
                                supersedes: first.id)

    try await store.record(first)
    try await store.record(second)
    let loaded = try await store.attempts(experimentID: "experiment-1")

    #expect(loaded == [first, second])
    #expect(loaded[0].decision == .rejected)
    #expect(loaded[1].supersedesAttemptID == first.id)
    #expect(loaded.map(\.attemptNumber) == [1, 2])
}

@Test func researchStoreRejectsSkippedAttemptNumbersAndInvalidArchiveHashes() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("research-attempt-invalid-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResearchStore(root: root)
    try await seedExperiment(in: store)

    await #expect(throws: (any Error).self) {
        try await store.record(attemptFixture(number: 2))
    }
    await #expect(throws: (any Error).self) {
        try await store.record(attemptFixture(number: 1, archiveHash: "not-a-sha256"))
    }
    #expect(try await store.attempts().isEmpty)
}

@Test func researchStoreMakesAttemptIDIdempotentButRejectsContentReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("research-attempt-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ResearchStore(root: root)
    try await seedExperiment(in: store)
    let first = attemptFixture(number: 1)
    try await store.record(first)
    try await store.record(first)

    let changed = attemptFixture(number: 1, decision: .pending)
    await #expect(throws: (any Error).self) { try await store.record(changed) }
    #expect(try await store.attempts() == [first])
}
