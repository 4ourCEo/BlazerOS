import Foundation
import Testing
@testable import BlazerCore

private let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
private func executionRow(_ id: Int, won: Bool, payout: Double? = 0.88, source: String = "venue-confirmed") -> LedgerRow {
    LedgerRow(timestamp: cutoff.addingTimeInterval(Double(id) - 1000), pair: "EUR/USD", hash: "h\(id)",
        score: 80, side: "CALL", veto: false, drift: 0, outcome: won ? "HIT" : "MISS",
        outcomeEventID: "arm-\(id)", payout: payout, engineSHA: EngineIdentity.pinnedSHA1,
        labelSource: source, horizonSeconds: 60, enteredAt: cutoff.addingTimeInterval(Double(id) * 120 - 100_000))
}

@Test func actualExpectancyMatchesPayoutToWinningRows() throws {
    let rows = [executionRow(0, won: true, payout: 0.1), executionRow(1, won: false, payout: 0.9)]
    let report = try ExecutionIntelligence.report(rows: rows, asOf: cutoff)
    #expect(abs(report.actualExpectancy! + 0.45) < 1e-12)
    let pair = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(abs(pair.expectancy + 0.45) < 1e-12)
    #expect(report.status == "INSUFFICIENT EVIDENCE")
}

@Test func missingPayoutCannotBecomeActualExpectancy() throws {
    let report = try ExecutionIntelligence.report(rows: [executionRow(0, won: true, payout: nil)], asOf: cutoff)
    #expect(report.payoutCoverage == 0)
    #expect(report.actualExpectancy == nil)
    #expect(report.breakEvenAtMinimumPayout == nil)
}

@Test func proxiesDuplicatesAndFutureRowsCannotInflateVenueEvidence() throws {
    let confirmed = executionRow(0, won: true)
    var future = executionRow(2, won: true); future.timestamp = cutoff.addingTimeInterval(1)
    let rows = [confirmed, confirmed, executionRow(1, won: true, source: "synthetic"), future]
    let report = try ExecutionIntelligence.report(rows: rows, asOf: cutoff)
    #expect(report.resolved == 0)
    #expect(report.duplicateOrConflictingIDs == 1)
    #expect(report.excludedUnconfirmed == 1)
    #expect(report.lower95 == nil)
}

@Test func reportIsReproducibleAndDoesNotPromoteNominalSuccess() throws {
    let rows = (0..<300).map { executionRow($0, won: $0 < 250) }
    let first = try ExecutionIntelligence.report(rows: rows, asOf: cutoff)
    let second = try ExecutionIntelligence.report(rows: rows.reversed(), asOf: cutoff)
    #expect(first == second)
    #expect(first.resolved == 300)
    #expect(first.status == "INSUFFICIENT EVIDENCE")
    #expect(!LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows).meetsPromotionCriteria)
}

@Test func unequalClustersAndClockBoundariesDoNotInflateEffectiveN() {
    var samples = (0..<10).map { _ in ClusteredObservation(pair: "EUR/USD", capturedAtMs: 59_999, won: true) }
    samples.append(ClusteredObservation(pair: "GBP/USD", capturedAtMs: 60_001, won: false))
    let one = EvidenceClustering.adjust(samples)
    #expect(one.blocks == 1)
    #expect(one.effectiveSize <= 1.00000001)
    samples.append(ClusteredObservation(pair: "EUR/USD", capturedAtMs: 300_000, won: true))
    let unequal = EvidenceClustering.adjust(samples)
    #expect(unequal.blocks == 2)
    #expect(unequal.effectiveSize < 2)
    let extreme = EvidenceClustering.adjust([.init(pair: "EUR/USD", capturedAtMs: .greatestFiniteMagnitude, won: true)])
    #expect(extreme.effectiveSize == 1)
}

@Test func assistantCountsFullArchiveBeforeBoundingItsContext() {
    let rows = (0..<100).map { executionRow($0, won: $0 < 70) }
    let context = AssistantContextBuilder.make(journal: [], ledgerRows: rows, now: cutoff)
    #expect(context.confirmedEntries.count == 60)
    #expect(context.performance.sampleSize == 100)
    #expect(context.performance.wins == 70)
    #expect(context.research?.status == "INSUFFICIENT EVIDENCE")
    let bounded = context.bounded(maxScans: 0, maxEntries: 4, maxGaps: 0, maxNotes: 0)
    #expect(bounded.performance == context.performance)
}

@Test func executionObservationStoreSurfacesCorruption() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("execution-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("{broken\n".utf8).write(to: root.appendingPathComponent("execution-observations.jsonl"))
    let store = ExecutionObservationStore(root: root)
    do { _ = try await store.load(); Issue.record("Corrupt telemetry must surface") }
    catch { }
}

@Test func conflictingDuplicateOrderHasStableDigest() throws {
    let first = executionRow(0, won: true)
    var conflict = first; conflict.outcome = "MISS"
    let a = try ExecutionIntelligence.report(rows: [first, conflict], asOf: cutoff)
    let b = try ExecutionIntelligence.report(rows: [conflict, first], asOf: cutoff)
    #expect(a == b)
    #expect(a.resolved == 0)
}

@Test func chronologicalReportPurgesOverlappingExpiries() throws {
    let rows = (0..<10).map { executionRow($0, won: $0 < 5) }
    let boundary = rows[5].enteredAt!
    let report = try ExecutionIntelligence.report(rows: rows, splitAt: boundary, asOf: cutoff)
    #expect(report.chronologicalCohorts.count == 2)
    #expect(report.chronologicalCohorts[0].resolved == 5)
    #expect(report.chronologicalCohorts[1].resolved == 5)
    #expect(!report.findings.isEmpty)
}

@Test func referenceAttributionRequiresTimelyProxyAtMatchingExpiry() throws {
    let row = executionRow(0, won: true)
    let expiry = row.enteredAt!.addingTimeInterval(60)
    func reference(_ offset: Double, source: String) -> ResearchOutcome {
        ResearchOutcome(eventID: row.outcomeEventID, horizon: 60, targetExpiry: expiry,
            observedAt: expiry.addingTimeInterval(offset),
            quoteTimeMs: expiry.addingTimeInterval(offset).timeIntervalSince1970 * 1000,
            exitPrice: 1.1, resolution: .miss, reason: nil, labelSource: source)
    }
    let valid = try ExecutionIntelligence.report(rows: [row], references: [reference(1, source: "oanda-midpoint-proxy")], asOf: cutoff)
    #expect(valid.quality.referenceComparisons == 1)
    #expect(valid.quality.referenceDisagreements == 1)
    let invalid = try ExecutionIntelligence.report(rows: [row], references: [reference(10, source: "oanda-midpoint-proxy")], asOf: cutoff)
    #expect(invalid.quality.referenceComparisons == 0)
    let synthetic = try ExecutionIntelligence.report(rows: [row], references: [reference(1, source: "synthetic")], asOf: cutoff)
    #expect(synthetic.quality.referenceComparisons == 0)
}
