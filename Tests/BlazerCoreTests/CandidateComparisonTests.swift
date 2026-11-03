import Foundation
import Testing
@testable import BlazerCore

private func comparisonRecord(_ id: String, _ candidate: String,
                              _ resolution: ResearchResolution,
                              quality: SignalQualityClass = .supported,
                              payout: Double? = 0.88,
                              cost: Double? = 0.02) -> CandidateComparisonObservation {
    CandidateComparisonObservation(observationID: id, candidateID: candidate,
        instrumentID: "EUR/USD", sourceKind: "oanda-proxy",
        observedAt: Date(timeIntervalSince1970: 1_800_000_000), quality: quality,
        resolution: resolution, payoutRatio: payout, transactionCost: cost,
        entryDelaySeconds: 2)
}

@Test func candidateComparisonRequiresMatchedIdentityAndKeepsPromotionDisabled() {
    let records = [
        comparisonRecord("a", "baseline", .hit), comparisonRecord("a", "candidate-001", .miss),
        comparisonRecord("b", "baseline", .miss), comparisonRecord("b", "candidate-001", .unresolved,
            quality: .conditional), comparisonRecord("unmatched", "candidate-001", .hit)
    ]
    let report = CandidateComparisonEvaluator.compare(baselineID: "baseline",
        candidateID: "candidate-001", observations: records,
        asOf: Date(timeIntervalSince1970: 1_800_000_001))
    #expect(report.matchedObservationIDs == ["a", "b"])
    #expect(report.baseline.resolved == 2)
    #expect(report.candidate.resolved == 1)
    #expect(report.candidate.retained == 1)
    #expect(report.promotionEligible == false)
}

@Test func candidateComparisonWithholdsCostExpectancyWhenCostOrPayoutMissing() {
    let records = [
        comparisonRecord("a", "baseline", .hit, payout: nil, cost: 0.02),
        comparisonRecord("a", "candidate-002", .hit, payout: 0.88, cost: nil)
    ]
    let report = CandidateComparisonEvaluator.compare(baselineID: "baseline",
        candidateID: "candidate-002", observations: records)
    #expect(report.baseline.netExpectancyAfterCost == nil)
    #expect(report.candidate.netExpectancyAfterCost == nil)
    #expect(report.candidate.costCoverage == 0)
}
