import Foundation

public enum ResearchSplitAssignment: String, Codable, Sendable, CaseIterable {
    case development
    case validation
    case holdout
}

public enum ResearchAttemptDecision: String, Codable, Sendable, CaseIterable {
    case pending
    case acceptedForFurtherResearch
    case rejected
}

public struct ResearchArchiveReference: Codable, Sendable, Equatable {
    public let sourceIdentity: String
    public let archiveSHA256: String

    public init(sourceIdentity: String, archiveSHA256: String) {
        self.sourceIdentity = sourceIdentity
        self.archiveSHA256 = archiveSHA256.lowercased()
    }
}

/// Costs are recorded as declared assumptions, not inferred transaction facts.
public struct ResearchExecutionAssumptions: Codable, Sendable, Equatable {
    public let spread: String
    public let slippage: String
    public let entryDelay: String
    public let financing: String
    public let fillModel: String

    public init(spread: String, slippage: String, entryDelay: String,
                financing: String, fillModel: String) {
        self.spread = spread
        self.slippage = slippage
        self.entryDelay = entryDelay
        self.financing = financing
        self.fillModel = fillModel
    }
}

public struct ResearchAttemptOutcomeEvidence: Codable, Sendable, Equatable {
    public let independentEligibleSetups: Int
    public let resolved: Int
    public let ambiguous: Int
    public let unresolved: Int
    public let netExpectancyR: Double?
    public let uncertaintyLowerR: Double?
    public let uncertaintyUpperR: Double?
    public let uncertaintyMethod: String?
    public let evidenceReference: String?

    public init(independentEligibleSetups: Int, resolved: Int, ambiguous: Int,
                unresolved: Int, netExpectancyR: Double? = nil,
                uncertaintyLowerR: Double? = nil, uncertaintyUpperR: Double? = nil,
                uncertaintyMethod: String? = nil,
                evidenceReference: String? = nil) {
        self.independentEligibleSetups = independentEligibleSetups
        self.resolved = resolved
        self.ambiguous = ambiguous
        self.unresolved = unresolved
        self.netExpectancyR = netExpectancyR
        self.uncertaintyLowerR = uncertaintyLowerR
        self.uncertaintyUpperR = uncertaintyUpperR
        self.uncertaintyMethod = uncertaintyMethod
        self.evidenceReference = evidenceReference
    }
}

/// Append-only protocol and result for one research attempt. A failed or superseded
/// hypothesis is a first-class record; it is never overwritten by its successor.
public struct ResearchExperimentAttempt: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let experimentID: String
    /// One-based, contiguous within an experiment; sequence is enforced by ResearchStore.
    public let attemptNumber: Int
    public let strategyID: String
    public let strategyVersion: String
    public let hypothesis: String
    public let dataArchives: [ResearchArchiveReference]
    public let instrumentID: String
    /// Explicit roles such as ["trigger": "M1", "context": "M5"].
    public let timeframeRoles: [String: String]
    public let exitContract: String
    public let splitAssignment: ResearchSplitAssignment
    /// Parameter name to all values tested in this attempt.
    public let parameterVariations: [String: [String]]
    public let benchmark: String
    public let executionAssumptions: ResearchExecutionAssumptions
    public let outcomeEvidence: ResearchAttemptOutcomeEvidence
    public let decision: ResearchAttemptDecision
    public let decisionRationale: String
    public let supersedesAttemptID: String?
    public let createdAt: Date

    public init(id: String = UUID().uuidString, experimentID: String, attemptNumber: Int,
                strategyID: String, strategyVersion: String, hypothesis: String,
                dataArchives: [ResearchArchiveReference], instrumentID: String,
                timeframeRoles: [String: String], exitContract: String,
                splitAssignment: ResearchSplitAssignment,
                parameterVariations: [String: [String]], benchmark: String,
                executionAssumptions: ResearchExecutionAssumptions,
                outcomeEvidence: ResearchAttemptOutcomeEvidence,
                decision: ResearchAttemptDecision, decisionRationale: String,
                supersedesAttemptID: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.experimentID = experimentID
        self.attemptNumber = attemptNumber
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.hypothesis = hypothesis
        self.dataArchives = dataArchives
        self.instrumentID = instrumentID
        self.timeframeRoles = timeframeRoles
        self.exitContract = exitContract
        self.splitAssignment = splitAssignment
        self.parameterVariations = parameterVariations
        self.benchmark = benchmark
        self.executionAssumptions = executionAssumptions
        self.outcomeEvidence = outcomeEvidence
        self.decision = decision
        self.decisionRationale = decisionRationale
        self.supersedesAttemptID = supersedesAttemptID
        self.createdAt = createdAt
    }
}
