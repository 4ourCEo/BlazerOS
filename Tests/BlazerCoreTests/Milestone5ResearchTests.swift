import Foundation
import Testing
@testable import BlazerCore

@Test func strategyCompetitionSeparatesCandidatesAndUnresolvedRecords() throws {
    let candidates = [
        ResearchStrategyCandidate(id: "baseline", version: "v1", description: "control"),
        ResearchStrategyCandidate(id: "candidate-001", version: "candidate-001-v1", description: "FVG")
    ]
    let record = StrategyValidationRecord(
        id: "r1", caseID: "c1", stage: .paperTrading, executionKind: .simulated,
        instrumentID: "EUR/USD", venueID: "research", marketKind: .standard,
        signalDirection: "HIGH", signalTimestamp: Date(), entryTimestamp: Date(),
        entryPrice: 1.1, expiryTimestamp: Date(), expiryObservedAt: Date(),
        expiryPrice: 1.2, payoutRatio: 0.8, resolution: .win,
        executionDelaySeconds: 1, engineSHA: "sha", inputDigest: "input",
        caseDigest: "case", configurationDigest: "config", dataSource: "test",
        priceAuthority: .syntheticFixture, signalCategory: "baseline",
        marketRegime: "trend", rejectionReason: nil, isVenueOutcome: false, isSynthetic: true
    )
    let rows = try StrategyCompetition.compare(records: [record], candidates: candidates)
    #expect(rows[0].resolved == 1)
    #expect(rows[0].expectancy == 0.8)
    #expect(rows[1].resolved == 0)
    #expect(rows[1].expectancy == nil)
}

@Test func deteriorationIsResearchOnlyAndDoesNotPromoteOrReplace() throws {
    let candidate = ResearchStrategyCandidate(id: "x", version: "v1", description: "test")
    func row(_ expectancy: Double, _ delay: Double, _ unresolved: Int) -> StrategyCompetitionRow {
        StrategyCompetitionRow(id: "x", candidate: candidate, matchedSignals: 20,
            resolved: 20 - unresolved, wins: 10, unresolved: unresolved,
            expectancy: expectancy, maximumDrawdown: 4, meanExecutionDelaySeconds: delay)
    }
    let alert = try PerformanceDeterioration.inspect(candidateID: "x",
        baseline: row(0.2, 1, 0), recent: row(-0.1, 2, 5))
    #expect(alert.severity == .alert)
    #expect(alert.researchOnly)
}

@Test func capitalScenariosFailClosedForInvalidInputsAndMarkUnsuitableAccounts() throws {
    let scenarios = try CapitalScenarioSimulator.run(
        accounts: [250, 500], returns: [-1, -1, 0.8], minimumPosition: 250,
        slippageShock: 1, transactionCost: 1
    )
    #expect(scenarios[0].trades == 1)
    #expect(!scenarios[0].suitable)
    #expect(scenarios[0].assumption.contains("Hypothetical"))
    #expect(BrokerDecisionEngine.conservativeMatrix.allSatisfy { !$0.liveRecommendation })
}
