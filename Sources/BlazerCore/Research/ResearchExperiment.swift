import Foundation

/// Versioned experiment record for offline engine evaluation. It never modifies the live
/// engine and never activates a candidate.
public struct ResearchExperiment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var policy: String
    public var engineSHA: String
    public var createdAt: Date
    public var splitFraction: Double
    public var evaluationHorizon: Int
    public var acceptanceCriteria: String
    public var rejectionCriteria: String
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        policy: String,
        engineSHA: String,
        createdAt: Date = Date(),
        splitFraction: Double = 0.7,
        evaluationHorizon: Int = 60,
        acceptanceCriteria: String,
        rejectionCriteria: String,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.policy = policy
        self.engineSHA = engineSHA
        self.createdAt = createdAt
        self.splitFraction = min(0.9, max(0.5, splitFraction))
        self.evaluationHorizon = evaluationHorizon
        self.acceptanceCriteria = acceptanceCriteria
        self.rejectionCriteria = rejectionCriteria
        self.notes = notes
    }
}

public struct ExperimentCohortReport: Codable, Sendable, Equatable {
    public var label: String
    public var candidates: Int
    public var acceptedEntries: Int
    public var highSignals: Int
    public var lowSignals: Int
    public var waitSignals: Int
    public var resolved: Int
    public var wins: Int
    public var losses: Int
    public var ties: Int
    public var unresolved: Int
    public var winRate: Double?
    public var wilsonLower: Double?
    public var wilsonUpper: Double?
    public var expectancy: Double?
    public var coverage: Double
    public var caveat: String

    public init(
        label: String, candidates: Int, acceptedEntries: Int,
        highSignals: Int, lowSignals: Int, waitSignals: Int,
        resolved: Int, wins: Int, losses: Int, ties: Int, unresolved: Int,
        winRate: Double?, wilsonLower: Double?, wilsonUpper: Double?,
        expectancy: Double?, coverage: Double, caveat: String
    ) {
        self.label = label
        self.candidates = candidates
        self.acceptedEntries = acceptedEntries
        self.highSignals = highSignals
        self.lowSignals = lowSignals
        self.waitSignals = waitSignals
        self.resolved = resolved
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.unresolved = unresolved
        self.winRate = winRate
        self.wilsonLower = wilsonLower
        self.wilsonUpper = wilsonUpper
        self.expectancy = expectancy
        self.coverage = coverage
        self.caveat = caveat
    }
}

public struct ResearchExperimentReport: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var experimentID: String
    public var generatedAt: Date
    public var train: ExperimentCohortReport
    public var test: ExperimentCohortReport
    public var highLowBalanced: Bool

    public init(
        id: String = UUID().uuidString,
        experimentID: String,
        generatedAt: Date = Date(),
        train: ExperimentCohortReport,
        test: ExperimentCohortReport,
        highLowBalanced: Bool
    ) {
        self.id = id
        self.experimentID = experimentID
        self.generatedAt = generatedAt
        self.train = train
        self.test = test
        self.highLowBalanced = highLowBalanced
    }
}

public enum ResearchEvaluator {
    /// Chronological split, then deterministic counts. The held-out side is never used to
    /// choose or tune the policy.
    public static func evaluate(
        experiment: ResearchExperiment,
        events: [ResearchEvent],
        outcomes: [ResearchOutcome]
    ) -> ResearchExperimentReport {
        let filtered = events
            .filter { ($0.signal.policy ?? ScanPolicy.baseline.rawValue) == experiment.policy }
            .filter { $0.engineSHA == experiment.engineSHA }
            .sorted { $0.capturedAt < $1.capturedAt }
        let splitIndex = Int(Double(filtered.count) * experiment.splitFraction)
        let trainEvents = Array(filtered.prefix(splitIndex))
        let testEvents = Array(filtered.dropFirst(splitIndex))
        let outcomeMap = Dictionary(
            outcomes.filter { $0.horizon == experiment.evaluationHorizon }
                .map { ("\($0.eventID)-\($0.horizon)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        func report(_ label: String, _ cohort: [ResearchEvent]) -> ExperimentCohortReport {
            let accepted = cohort.filter { $0.entryTime != nil }
            let high = cohort.filter { $0.signal.cabinetSide == "HIGH" }.count
            let low = cohort.filter { $0.signal.cabinetSide == "LOW" }.count
            let wait = cohort.filter { $0.signal.cabinetSide == "WAIT" }.count
            var wins = 0, losses = 0, ties = 0, unresolved = 0
            for event in accepted {
                guard let outcome = outcomeMap["\(event.id)-\(experiment.evaluationHorizon)"] else {
                    unresolved += 1
                    continue
                }
                switch outcome.resolution {
                case .hit: wins += 1
                case .miss: losses += 1
                case .tie: ties += 1
                case .unresolved: unresolved += 1
                }
            }
            let resolved = wins + losses
            let winRate = resolved > 0 ? Double(wins) / Double(resolved) : nil
            let interval = EdgeEvidence.wilsonScoreInterval(wins: wins, total: resolved)
            let expectancy = winRate.map { $0 * EntryQuality.assumedPayout - (1 - $0) }
            let caveat: String
            if resolved == 0 {
                caveat = "No resolved outcomes in this cohort. No performance claim is possible."
            } else if resolved < 30 {
                caveat = "Small cohort (n=\(resolved)). Descriptive only; not a promotion decision."
            } else {
                caveat = "Chronological cohort (n=\(resolved)) with assumed \(Int(EntryQuality.assumedPayout * 100))% payout and unverified independence."
            }
            return ExperimentCohortReport(
                label: label,
                candidates: cohort.count,
                acceptedEntries: accepted.count,
                highSignals: high,
                lowSignals: low,
                waitSignals: wait,
                resolved: resolved,
                wins: wins,
                losses: losses,
                ties: ties,
                unresolved: unresolved,
                winRate: winRate,
                wilsonLower: resolved > 0 ? interval.lower : nil,
                wilsonUpper: resolved > 0 ? interval.upper : nil,
                expectancy: expectancy,
                coverage: cohort.isEmpty ? 0 : Double(accepted.count) / Double(cohort.count),
                caveat: caveat
            )
        }
        let train = report("train", trainEvents)
        let test = report("test", testEvents)
        let balanced = train.highSignals > 0 && train.lowSignals > 0
            && test.highSignals > 0 && test.lowSignals > 0
        return ResearchExperimentReport(
            experimentID: experiment.id,
            train: train,
            test: test,
            highLowBalanced: balanced
        )
    }
}
