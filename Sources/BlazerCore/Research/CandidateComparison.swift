import Foundation

/// One frozen research observation for comparing independent candidates on the same market event.
/// `observationID` is the matching key; it is never an order or ledger identity.
public struct CandidateComparisonObservation: Codable, Sendable, Equatable, Identifiable {
    public let observationID: String
    public let candidateID: String
    public let instrumentID: String
    public let sourceKind: String
    public let observedAt: Date
    public let quality: SignalQualityClass
    public let resolution: ResearchResolution
    public let payoutRatio: Double?
    public let transactionCost: Double?
    public let entryDelaySeconds: Double?

    public var id: String { "\(candidateID):\(observationID)" }

    public init(observationID: String, candidateID: String, instrumentID: String,
                sourceKind: String, observedAt: Date,
                quality: SignalQualityClass, resolution: ResearchResolution,
                payoutRatio: Double? = nil, transactionCost: Double? = nil,
                entryDelaySeconds: Double? = nil) {
        self.observationID = observationID
        self.candidateID = candidateID
        self.instrumentID = instrumentID
        self.sourceKind = sourceKind
        self.observedAt = observedAt
        self.quality = quality
        self.resolution = resolution
        self.payoutRatio = payoutRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.transactionCost = transactionCost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.entryDelaySeconds = entryDelaySeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
}

public struct CandidateComparisonCohort: Codable, Sendable, Equatable {
    public let candidateID: String
    public let observations: Int
    public let retained: Int
    public let resolved: Int
    public let wins: Int
    public let losses: Int
    public let unresolved: Int
    public let netExpectancyAfterCost: Double?
    public let meanEntryDelaySeconds: Double?
    public let costCoverage: Int
}

public struct CandidateComparisonReport: Codable, Sendable, Equatable {
    public static let version = "candidate-comparison-v1"
    public let version: String
    public let baseline: CandidateComparisonCohort
    public let candidate: CandidateComparisonCohort
    public let matchedObservationIDs: [String]
    public let limitations: [String]
    public let promotionEligible: Bool
}

public enum CandidateComparisonEvaluator {
    public static func compare(
        baselineID: String,
        candidateID: String,
        observations: [CandidateComparisonObservation],
        asOf: Date = Date()
    ) -> CandidateComparisonReport {
        let eligible = observations.filter { $0.observedAt <= asOf }
        let baseline = eligible.filter { $0.candidateID == baselineID }
        let candidate = eligible.filter { $0.candidateID == candidateID }
        let baselineByID = Dictionary(grouping: baseline, by: \.observationID)
        let candidateByID = Dictionary(grouping: candidate, by: \.observationID)
        let matched = Set(baselineByID.keys).intersection(candidateByID.keys).filter { id in
            guard baselineByID[id]?.count == 1, candidateByID[id]?.count == 1,
                  let b = baselineByID[id]?.first, let c = candidateByID[id]?.first else { return false }
            return b.instrumentID == c.instrumentID && b.sourceKind == c.sourceKind
        }.sorted()

        func cohort(_ id: String, _ records: [CandidateComparisonObservation], retained: Int)
            -> CandidateComparisonCohort {
            let resolved = records.filter { $0.resolution == .hit || $0.resolution == .miss }
            let wins = resolved.filter { $0.resolution == .hit }.count
            let losses = resolved.count - wins
            let returns = resolved.compactMap { record -> Double? in
                guard let cost = record.transactionCost,
                      record.resolution == .miss || record.payoutRatio != nil else { return nil }
                let reward = record.resolution == .hit ? (record.payoutRatio ?? 0) : -1
                return reward - cost
            }
            let expectancy = returns.count == resolved.count && !returns.isEmpty
                ? returns.reduce(0, +) / Double(returns.count) : nil
            let delays = records.compactMap(\.entryDelaySeconds)
            return CandidateComparisonCohort(candidateID: id, observations: records.count,
                retained: retained, resolved: resolved.count, wins: wins, losses: losses,
                unresolved: records.count - resolved.count, netExpectancyAfterCost: expectancy,
                meanEntryDelaySeconds: delays.isEmpty ? nil : delays.reduce(0, +) / Double(delays.count),
                costCoverage: returns.count)
        }

        let matchedBaseline = matched.compactMap { baselineByID[$0]?.first }
        let matchedCandidate = matched.compactMap { candidateByID[$0]?.first }
        return CandidateComparisonReport(version: CandidateComparisonReport.version,
            baseline: cohort(baselineID, matchedBaseline, retained: matchedBaseline.count),
            candidate: cohort(candidateID, matchedCandidate,
                retained: matchedCandidate.filter { $0.quality == .supported }.count),
            matchedObservationIDs: matched,
            limitations: [
                "Matched observations are descriptive and do not establish an edge.",
                "Cost and payout are unavailable when not explicitly recorded.",
                "Latency sensitivity requires prospective observations; delay is not imputed.",
                "Promotion requires the existing independent review and evidence gate."
            ], promotionEligible: false)
    }
}
