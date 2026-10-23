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
    /// Frozen boundary between train and held-out cohorts. Captured once from the archive
    /// that existed when the experiment was created. When nil (legacy records) the evaluator
    /// falls back to a recomputed index split and marks the report as unfrozen.
    public var splitAt: Date?
    public var evaluationHorizon: Int
    /// Payout used for break-even when an event carries no payout of its own.
    public var payoutRatio: Double?
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
        splitAt: Date? = nil,
        evaluationHorizon: Int = 60,
        payoutRatio: Double? = nil,
        acceptanceCriteria: String,
        rejectionCriteria: String,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.policy = policy
        self.engineSHA = engineSHA
        self.createdAt = createdAt
        self.splitFraction = splitFraction.isFinite ? min(0.9, max(0.5, splitFraction)) : 0.7
        self.splitAt = splitAt
        self.evaluationHorizon = evaluationHorizon
        self.payoutRatio = payoutRatio
        self.acceptanceCriteria = acceptanceCriteria
        self.rejectionCriteria = rejectionCriteria
        self.notes = notes
    }

    /// True when the held-out boundary was captured at creation and cannot drift.
    public var hasFrozenHoldout: Bool { splitAt != nil }
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
    /// Reported interval. Cluster-adjusted when concurrent correlated observations exist;
    /// otherwise equal to the nominal Wilson interval.
    public var wilsonLower: Double?
    public var wilsonUpper: Double?
    /// Unadjusted Wilson interval, retained for transparency.
    public var nominalWilsonLower: Double?
    public var nominalWilsonUpper: Double?
    /// Distinct (correlation group, time bucket) blocks and the design-effect sample size.
    public var blocks: Int?
    public var effectiveSampleSize: Double?
    public var expectancy: Double?
    /// Mean payout over resolved entries, and the lowest payout in the cohort.
    public var payoutRatio: Double?
    public var minimumPayoutRatio: Double?
    public var breakEvenWinRate: Double?
    public var coverage: Double
    public var caveat: String

    public init(
        label: String, candidates: Int, acceptedEntries: Int,
        highSignals: Int, lowSignals: Int, waitSignals: Int,
        resolved: Int, wins: Int, losses: Int, ties: Int, unresolved: Int,
        winRate: Double?, wilsonLower: Double?, wilsonUpper: Double?,
        nominalWilsonLower: Double? = nil, nominalWilsonUpper: Double? = nil,
        blocks: Int? = nil, effectiveSampleSize: Double? = nil,
        expectancy: Double?, payoutRatio: Double? = nil,
        minimumPayoutRatio: Double? = nil, breakEvenWinRate: Double? = nil,
        coverage: Double, caveat: String
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
        self.nominalWilsonLower = nominalWilsonLower
        self.nominalWilsonUpper = nominalWilsonUpper
        self.blocks = blocks
        self.effectiveSampleSize = effectiveSampleSize
        self.expectancy = expectancy
        self.payoutRatio = payoutRatio
        self.minimumPayoutRatio = minimumPayoutRatio
        self.breakEvenWinRate = breakEvenWinRate
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
    /// True when the held-out boundary came from the stored experiment, not a recomputation.
    public var splitFrozen: Bool?
    public var payoutRatio: Double?
    /// Conservative break-even: based on the lowest payout in the held-out cohort.
    public var breakEvenWinRate: Double?
    /// True only when the held-out cohort clears the conservative break-even with its
    /// cluster-adjusted lower bound and has at least 250 independent clustered events.
    public var meetsAcceptance: Bool?
    /// Mathematical screening only; not independent validation or live authorization.
    public var screeningCriteriaMet: Bool?

    public init(
        id: String = UUID().uuidString,
        experimentID: String,
        generatedAt: Date = Date(),
        train: ExperimentCohortReport,
        test: ExperimentCohortReport,
        highLowBalanced: Bool,
        splitFrozen: Bool? = nil,
        payoutRatio: Double? = nil,
        breakEvenWinRate: Double? = nil,
        meetsAcceptance: Bool? = nil,
        screeningCriteriaMet: Bool? = nil
    ) {
        self.id = id
        self.experimentID = experimentID
        self.generatedAt = generatedAt
        self.train = train
        self.test = test
        self.highLowBalanced = highLowBalanced
        self.splitFrozen = splitFrozen
        self.payoutRatio = payoutRatio
        self.breakEvenWinRate = breakEvenWinRate
        self.meetsAcceptance = meetsAcceptance
        self.screeningCriteriaMet = screeningCriteriaMet
    }

    /// Non-optional convenience view for callers and tests.
    public var acceptanceSatisfied: Bool { meetsAcceptance ?? false }
    public var isHoldoutFrozen: Bool { splitFrozen ?? false }
}

public enum ResearchEvaluator {
    /// Boundary that a new experiment should freeze. Uses the same filter the evaluator
    /// applies, so the stored boundary and the evaluated cohorts agree.
    public static func splitDate(
        events: [ResearchEvent],
        policy: String,
        engineSHA: String,
        splitFraction: Double
    ) -> Date? {
        let filtered = events
            .filter { ($0.signal.policy ?? ScanPolicy.baseline.rawValue) == policy }
            .filter { $0.engineSHA == engineSHA }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard !filtered.isEmpty else { return nil }
        let fraction = splitFraction.isFinite ? min(0.9, max(0.5, splitFraction)) : 0.7
        let index = Int(Double(filtered.count) * fraction)
        guard index > 0, index < filtered.count else { return nil }
        return filtered[index].capturedAt
    }

    /// Chronological split, then deterministic counts. The held-out side is never used to
    /// choose or tune the policy.
    ///
    /// When `experiment.splitAt` is stored, the boundary is fixed: adding later events
    /// cannot move an earlier cohort or re-use the holdout. Without it, the split index is
    /// recomputed over the current archive and the report is marked `splitFrozen == false`.
    public static func evaluate(
        experiment: ResearchExperiment,
        events: [ResearchEvent],
        outcomes: [ResearchOutcome]
    ) -> ResearchExperimentReport {
        let filtered = events
            .filter { ($0.signal.policy ?? ScanPolicy.baseline.rawValue) == experiment.policy }
            .filter { $0.engineSHA == experiment.engineSHA }
            .sorted { $0.capturedAt < $1.capturedAt }

        let trainEvents: [ResearchEvent]
        let testEvents: [ResearchEvent]
        let splitFrozen: Bool
        if let splitAt = experiment.splitAt {
            trainEvents = filtered.filter { $0.capturedAt < splitAt }
            testEvents = filtered.filter { $0.capturedAt >= splitAt }
            splitFrozen = true
        } else {
            let fraction = experiment.splitFraction.isFinite ? min(0.9, max(0.5, experiment.splitFraction)) : 0.7
            let splitIndex = Int(Double(filtered.count) * fraction)
            trainEvents = Array(filtered.prefix(splitIndex))
            testEvents = Array(filtered.dropFirst(splitIndex))
            splitFrozen = false
        }

        let outcomeMap = Dictionary(
            outcomes.filter { $0.horizon == experiment.evaluationHorizon }
                .map { ("\($0.eventID)-\($0.horizon)", $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let fallbackPayout = experiment.payoutRatio ?? EntryQuality.assumedPayout

        func report(_ label: String, _ cohort: [ResearchEvent]) -> ExperimentCohortReport {
            let accepted = cohort.filter { $0.entryTime != nil }
            let high = cohort.filter { $0.signal.cabinetSide == "HIGH" }.count
            let low = cohort.filter { $0.signal.cabinetSide == "LOW" }.count
            let wait = cohort.filter { $0.signal.cabinetSide == "WAIT" }.count
            var wins = 0, losses = 0, ties = 0, unresolved = 0
            var resolvedPayouts: [Double] = []
            var netReturn = 0.0
            var observations: [ClusteredObservation] = []
            for event in accepted {
                guard let outcome = outcomeMap["\(event.id)-\(experiment.evaluationHorizon)"] else {
                    unresolved += 1
                    continue
                }
                let payout = event.assumedPayout.isFinite && event.assumedPayout > 0
                    ? event.assumedPayout : fallbackPayout
                switch outcome.resolution {
                case .hit:
                    netReturn += payout
                    wins += 1
                    resolvedPayouts.append(payout)
                    observations.append(.init(
                        pair: event.input.asset,
                        capturedAtMs: event.capturedAt.timeIntervalSince1970 * 1000,
                        won: true
                    ))
                case .miss:
                    netReturn -= 1
                    losses += 1
                    resolvedPayouts.append(payout)
                    observations.append(.init(
                        pair: event.input.asset,
                        capturedAtMs: event.capturedAt.timeIntervalSince1970 * 1000,
                        won: false
                    ))
                case .tie:
                    ties += 1
                case .unresolved:
                    unresolved += 1
                }
            }

            let resolved = wins + losses
            let meanPayout = resolvedPayouts.isEmpty
                ? fallbackPayout
                : resolvedPayouts.reduce(0, +) / Double(resolvedPayouts.count)
            let minimumPayout = resolvedPayouts.min() ?? fallbackPayout
            let breakEven = 1.0 / (1.0 + meanPayout)
            let winRate = resolved > 0 ? Double(wins) / Double(resolved) : nil
            let nominal = EdgeEvidence.wilsonScoreInterval(wins: wins, total: resolved)
            let clustered = EvidenceClustering.adjust(observations, bucketMs: Double(max(60, experiment.evaluationHorizon)) * 1000)
            let expectancy = resolved > 0 ? netReturn / Double(resolved) : nil

            var caveatParts: [String] = []
            if resolved == 0 {
                caveatParts.append("No resolved outcomes in this cohort. No performance claim is possible.")
            } else if resolved < 30 {
                caveatParts.append("Small cohort (n=\(resolved)). Descriptive only; not a promotion decision.")
            } else {
                caveatParts.append(
                    "Chronological cohort (n=\(resolved)) at \(String(format: "%.1f", meanPayout * 100))% "
                    + "mean payout; break-even \(String(format: "%.2f", breakEven * 100))%. "
                    + "Independence is adjusted, not proven."
                )
            }
            if resolved > 0 {
                caveatParts.append(clustered.caveat)
            }
            caveatParts.append("Exploratory analysis; assumed payouts and proxy/synthetic labels cannot establish venue edge. Repeated evaluation is not an independent holdout. Independent validation and explicit authorization are required.")
            let caveat = caveatParts.joined(separator: " ")

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
                wilsonLower: resolved > 0 ? clustered.lower95 : nil,
                wilsonUpper: resolved > 0 ? clustered.upper95 : nil,
                nominalWilsonLower: resolved > 0 ? nominal.lower : nil,
                nominalWilsonUpper: resolved > 0 ? nominal.upper : nil,
                blocks: resolved > 0 ? clustered.blocks : nil,
                effectiveSampleSize: resolved > 0 ? clustered.effectiveSize : nil,
                expectancy: expectancy,
                payoutRatio: resolved > 0 ? meanPayout : nil,
                minimumPayoutRatio: resolved > 0 ? minimumPayout : nil,
                breakEvenWinRate: resolved > 0 ? breakEven : nil,
                coverage: cohort.isEmpty ? 0 : Double(accepted.count) / Double(cohort.count),
                caveat: caveat
            )
        }

        // Purge training entries whose evaluation horizon reaches the holdout boundary.
        let boundary = testEvents.first?.capturedAt
        let purgedTrain = trainEvents.filter { event in
            guard let boundary, let entry = event.entryTime else { return true }
            return entry.addingTimeInterval(Double(experiment.evaluationHorizon)) < boundary
        }
        let train = report("train", purgedTrain)
        let test = report("test", testEvents)
        let balanced = train.highSignals > 0 && train.lowSignals > 0
            && test.highSignals > 0 && test.lowSignals > 0

        // Promotion is gated on the conservative break-even: the lowest payout actually
        // observed in the held-out cohort, never a flat 50% threshold.
        let testMinPayout = test.minimumPayoutRatio ?? fallbackPayout
        let conservativeBreakEven = 1.0 / (1.0 + testMinPayout)
        let testIDs = Set(testEvents.map(\.id))
        let testOutcomes = outcomes.filter { testIDs.contains($0.eventID) && $0.horizon == experiment.evaluationHorizon }
        let prospective = experiment.splitAt.map { $0 >= experiment.createdAt } ?? false
        let meets = splitFrozen && prospective && balanced
            && Set(testEvents.map { $0.input.asset }) == Set(Assets.watchlist)
            && testEvents.allSatisfy { MarketEdgeWindow.current(at: $0.capturedAt).isPrime }
            && Set(testEvents.map(\.id)).count == testEvents.count
            && Set(testOutcomes.map { "\($0.eventID)-\($0.horizon)" }).count == testOutcomes.count
            && Set(testEvents.map(\.sourceKind)) == ["venue-confirmed"]
            && Set(testEvents.map(\.policyVersion)).count == 1
            && testOutcomes.allSatisfy { $0.labelSource == "venue-confirmed" }
            && test.unresolved == 0 && test.ties == 0
            && (test.effectiveSampleSize ?? 0) >= 250 && (test.blocks ?? 0) >= 250
            && (test.expectancy ?? -1) > 0
            && (test.wilsonLower ?? 0) > conservativeBreakEven


        return ResearchExperimentReport(
            experimentID: experiment.id,
            train: train,
            test: test,
            highLowBalanced: balanced,
            splitFrozen: splitFrozen,
            payoutRatio: test.payoutRatio ?? fallbackPayout,
            breakEvenWinRate: conservativeBreakEven,
            // No independently validated stopping rule/test-family record or live
            // authorization exists in this research schema. Repeated report inspection
            // must never turn mathematical screening into accepted strategy evidence.
            meetsAcceptance: false,
            screeningCriteriaMet: meets
        )
    }
}
