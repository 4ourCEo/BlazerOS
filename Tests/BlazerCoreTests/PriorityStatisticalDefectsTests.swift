import Foundation
import Testing
@testable import BlazerCore

private let observed = Date(timeIntervalSince1970: 10_000)
private let digest = String(repeating: "a", count: 64)
private func payoutBook() -> [LedgerRow] {
    (0..<5).map { index in
        LedgerRow(timestamp: observed, pair: "EUR/USD", hash: "s\(index)", score: 80,
            side: "HIGH", veto: false, drift: 0, outcome: index < 3 ? "HIT" : "MISS",
            outcomeEventID: "stat-defect-\(index)", payout: index < 3 ? 0.2 : 2.0,
            stake: Double(index + 1) * 10, labelSource: "venue-confirmed",
            horizonSeconds: 60, enteredAt: observed.addingTimeInterval(-60))
    }
}
private func reviewed(effectiveN: Double = 250, tests: Int = 10, p: Double = 0.001) -> StatisticalEvidenceReview {
    let ids = (0..<tests).map { "policy/expiry/look-\($0)" }
    return StatisticalEvidenceReview(reviewerID: "fixture-independent-reviewer", reviewReference: "fixture-review",
        cohortDigest: digest, verifiedEffectiveSampleSize: effectiveN, dependenceMethod: .validatedClusterModel,
        registrationReference: "fixture-registration", registeredAt: observed.addingTimeInterval(-1),
        registeredTestIDs: ids, rawPValues: Dictionary(uniqueKeysWithValues: ids.map { ($0, p) }),
        selectedTestID: ids[0])
}
private func assess(_ review: StatisticalEvidenceReview? = nil, blocks: Int = 300,
                    trusted: Set<String> = ["fixture-independent-reviewer"]) -> PromotionEvidenceDecision {
    PromotionEvidenceGate.assess(nominalSize: 300, candidateBlocks: blocks,
        cohortDigest: digest, firstObservationAt: observed, review: review, trustedReviewerIDs: trusted)
}

@Test func reproduceMixedPayoutFormulaReversesProfitability() throws {
    let rows = payoutBook()
    let oldMean = rows.compactMap(\.payout).reduce(0, +) / Double(rows.count)
    let oldEV = 0.6 * oldMean - 0.4
    #expect(abs(oldEV - 0.152) < 1e-12)
    let actual = ConfirmedReturnSummary.evaluate(rows)
    #expect(abs(actual.unitExpectancy! - (-0.28)) < 1e-12)
    #expect(actual.netProfit == -78) // Winning cash 2+4+6; actual losses 40+50.
    #expect(abs(actual.meanProfitPerTrade! - (-15.6)) < 1e-12)
    let pair = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(pair.expectancyAvailable)
    #expect(abs(pair.expectancy + 0.28) < 1e-12)
    #expect(abs(pair.actualExpectancy! + 0.28) < 1e-12)
    #expect(ConfirmedReturnSummary.evaluate(Array(rows.reversed())) == actual)
}

@Test func heterogeneousPayoutsWithoutOutcomeAlignmentAreUnavailable() {
    let stats = PairEdgeStats(pair: "EUR/USD", sampleSize: 5, wins: 3, verifiedOutcomes: true,
        perRowPayouts: [0.2, 0.2, 0.2, 2, 2])
    #expect(!stats.expectancyAvailable)
    #expect(stats.actualExpectancy == nil)
    #expect(stats.caveat.contains("alignment missing"))
}

@Test func losingAdvertisedPayoutCannotChangeRealizedProfit() {
    let original = payoutBook()
    var changed = original
    changed[3].payout = nil; changed[4].payout = 99
    #expect(ConfirmedReturnSummary.evaluate(original) == ConfirmedReturnSummary.evaluate(changed))
    #expect(LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: original).actualExpectancy
        == LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: changed).actualExpectancy)
    changed[3].stake = nil
    #expect(ConfirmedReturnSummary.evaluate(changed).netProfit == nil)
    #expect(ConfirmedReturnSummary.evaluate(changed).unitExpectancy != nil)
}

@Test func unconfirmedAndDuplicateCashResultsNeverEnterActualReturns() {
    let rows = payoutBook()
    var proxy = rows[0]; proxy.outcomeEventID = "proxy"; proxy.labelSource = "oanda-midpoint-proxy"
    #expect(ConfirmedReturnSummary.evaluate(rows + [proxy]) == ConfirmedReturnSummary.evaluate(rows))
    let conflict = rows[0]
    #expect(ConfirmedReturnSummary.evaluate(rows + [conflict]).resolved == 4)
    var invalid = rows; invalid[0].stake = .infinity
    #expect(ConfirmedReturnSummary.evaluate(invalid).netProfit == nil)
    invalid = rows; invalid[0].payout = nil
    #expect(ConfirmedReturnSummary.evaluate(invalid).unitExpectancy == nil)
}

@Test func reproduceNominalCountWouldPassButVerifiedEffectiveCountFails() {
    let nominal = EdgeEvidence.wilsonScoreInterval(wins: 280, total: 300)
    #expect(nominal.lower > ExpectancyMath.breakEvenWinRate())
    #expect(!assess().statisticalCriteriaMet)
    #expect(assess().status == "INSUFFICIENT EVIDENCE")
    #expect(!assess(reviewed(effectiveN: 1), blocks: 1).statisticalCriteriaMet)
    #expect(!assess(reviewed(effectiveN: 300), blocks: 1).statisticalCriteriaMet)
    var assumed = reviewed(); assumed.dependenceMethod = .assumedICC
    #expect(!assess(assumed).statisticalCriteriaMet)
}

@Test func uncorrectedSignificanceCannotPassARegisteredFamily() {
    let result = assess(reviewed(tests: 10, p: 0.01))
    #expect(0.01 < PromotionEvidenceGate.familyWiseAlpha)
    #expect(abs(result.familyWiseAdjustedPValue! - 0.1) < 1e-12)
    #expect(!result.statisticalCriteriaMet)
    var incomplete = reviewed(); incomplete.rawPValues.removeValue(forKey: incomplete.registeredTestIDs.last!)
    #expect(!assess(incomplete).statisticalCriteriaMet)
    var duplicate = reviewed(); duplicate.registeredTestIDs.append(duplicate.registeredTestIDs[0])
    #expect(!assess(duplicate).statisticalCriteriaMet)
}

@Test func verificationMustBeTrustedBoundAndProspectivelyRegistered() {
    #expect(!assess(reviewed(), trusted: []).statisticalCriteriaMet)
    var stale = reviewed(); stale.cohortDigest = String(repeating: "b", count: 64)
    #expect(!assess(stale).statisticalCriteriaMet)
    var retrospective = reviewed(); retrospective.registeredAt = observed.addingTimeInterval(1)
    #expect(!assess(retrospective).statisticalCriteriaMet)
    var invalid = reviewed(); invalid.verifiedEffectiveSampleSize = .nan
    #expect(!assess(invalid).statisticalCriteriaMet)
    invalid = reviewed(); invalid.rawPValues[invalid.selectedTestID] = .infinity
    #expect(!assess(invalid).statisticalCriteriaMet)
}

@Test func explicitlyReviewedPositiveControlClearsOnlyStatisticalQualification() {
    let result = assess(reviewed())
    #expect(result.statisticalCriteriaMet)
    #expect(result.verifiedEffectiveSampleSize == 250)
    #expect(abs(result.familyWiseAdjustedPValue! - 0.01) < 1e-12)
    #expect(result.blockers.isEmpty)
    // The live application supplies no trusted reviewers; the same object fails there.
    #expect(!PromotionEvidenceGate.assess(nominalSize: 300, candidateBlocks: 300,
        cohortDigest: digest, firstObservationAt: observed, review: reviewed()).statisticalCriteriaMet)
}

@Test func persistedNominalAcceptanceFlagsCannotBypassEvidenceControls() throws {
    let experiment = ResearchExperiment(name: "legacy", policy: "baseline", engineSHA: EngineIdentity.pinnedSHA1,
        acceptanceCriteria: "legacy nominal", rejectionCriteria: "legacy nominal")
    var report = ResearchEvaluator.evaluate(experiment: experiment, events: [], outcomes: [])
    report.meetsAcceptance = true; report.screeningCriteriaMet = true; report.splitFrozen = true
    report.test.resolved = 1000; report.test.effectiveSampleSize = 1000
    #expect(!report.acceptanceSatisfied)
    #expect(report.evidenceDecision?.status == "INSUFFICIENT EVIDENCE")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
    legacy.removeValue(forKey: "evidenceDecision"); legacy.removeValue(forKey: "heldOutDigest")
    let decoded = try JSONDecoder().decode(ResearchExperimentReport.self,
        from: JSONSerialization.data(withJSONObject: legacy))
    #expect(!decoded.acceptanceSatisfied)
}

@Test func executionReportUsesTheVerifiedReturnPathAfterStatisticalChecks() throws {
    let rows = payoutBook()
    let report = try ExecutionIntelligence.report(rows: rows, asOf: observed)
    #expect(report.schemaVersion == "edge-verification-v2")
    #expect(abs(report.actualExpectancy! + 0.28) < 1e-12)
    #expect(report.netProfit == -78)
    #expect(abs(report.meanProfitPerTrade! + 15.6) < 1e-12)
    #expect(report.cohorts.first?.netProfit == -78)
    #expect(report.evidenceDecision?.status == "INSUFFICIENT EVIDENCE")
    #expect(report.evidenceDecision?.verifiedEffectiveSampleSize == nil)
    #expect(report.evidenceDecision?.familyWiseAdjustedPValue == nil)
}

@Test func missingLosingQuoteTermsDoNotEraseKnownExecutionReturns() throws {
    var rows = payoutBook(); rows[3].payout = nil; rows[4].payout = nil
    let report = try ExecutionIntelligence.report(rows: rows, asOf: observed)
    #expect(report.payoutCoverage == 3)
    let context = AssistantContextBuilder.make(journal: [], ledgerRows: rows, now: observed)
    #expect(abs(context.performance.expectancy! + 0.28) < 1e-12)
    #expect(context.performance.caveat.contains("recorded winning payouts"))
    #expect(abs(report.actualExpectancy! + 0.28) < 1e-12)
    #expect(report.netProfit == -78)
    #expect(report.breakEvenAtMinimumPayout == nil)
    #expect(report.status == "INSUFFICIENT EVIDENCE")
}

@Test func reportExtensionPreservesLedgerBytesAndDecodesLegacyReports() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("statistical-return-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LedgerStore(root: root)
    for row in payoutBook() { _ = try await store.record(row) }
    let url = FileLocations.ledgerCSV(in: root)
    let before = try Data(contentsOf: url)
    let report = try await ExecutionIntelligence.loadReport(root: root, asOf: observed)
    #expect(report.netProfit == -78)
    #expect(try Data(contentsOf: url) == before)
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as! [String: Any]
    legacy["schemaVersion"] = "edge-verification-v1"
    legacy.removeValue(forKey: "netProfit"); legacy.removeValue(forKey: "meanProfitPerTrade")
    legacy.removeValue(forKey: "evidenceDecision")
    let restored = try JSONDecoder().decode(EdgeVerificationReport.self,
        from: JSONSerialization.data(withJSONObject: legacy))
    #expect(restored.netProfit == nil && restored.evidenceDecision == nil)
    #expect(restored.status == "INSUFFICIENT EVIDENCE")
}
