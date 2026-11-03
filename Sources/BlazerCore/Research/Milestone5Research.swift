import Foundation

public struct ResearchStrategyCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let description: String

    public init(id: String, version: String, description: String) {
        self.id = id
        self.version = version
        self.description = description
    }
}

public struct StrategyCompetitionRow: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidate: ResearchStrategyCandidate
    public let matchedSignals: Int
    public let resolved: Int
    public let wins: Int
    public let unresolved: Int
    public let expectancy: Double?
    public let maximumDrawdown: Double?
    public let meanExecutionDelaySeconds: Double?
}

public enum Milestone5ResearchError: Error, Equatable, Sendable {
    case invalidInput
    case insufficientEvidence
}

public enum StrategyCompetition {
    public static func compare(
        records: [StrategyValidationRecord],
        candidates: [ResearchStrategyCandidate]
    ) throws -> [StrategyCompetitionRow] {
        guard !candidates.isEmpty, candidates.map(\.id).count == Set(candidates.map(\.id)).count else {
            throw Milestone5ResearchError.invalidInput
        }
        let valid = records.filter { $0.stage == .paperTrading || $0.stage == .liveObservation }
        let grouped = Dictionary(grouping: valid, by: { $0.signalCategory ?? "" })
        return candidates.map { candidate in
            let rows = grouped[candidate.id] ?? []
            let resolved = rows.filter { [.win, .loss, .tie].contains($0.resolution) }
            let wins = resolved.filter { $0.resolution == .win }.count
            let returns = resolved.compactMap { record -> Double? in
                guard let payout = record.payoutRatio, payout.isFinite, payout > 0 else { return nil }
                switch record.resolution {
                case .win: return payout
                case .loss: return -1
                case .tie, .unresolved: return 0
                }
            }
            let expectancy = returns.isEmpty ? nil : returns.reduce(0, +) / Double(returns.count)
            var balance = 0.0
            var peak = 0.0
            var drawdown = 0.0
            for value in returns {
                balance += value
                peak = max(peak, balance)
                drawdown = max(drawdown, peak - balance)
            }
            let delays = resolved.compactMap(\.executionDelaySeconds).filter(\.isFinite)
            return StrategyCompetitionRow(
                id: candidate.id,
                candidate: candidate,
                matchedSignals: rows.count,
                resolved: resolved.count,
                wins: wins,
                unresolved: rows.count - resolved.count,
                expectancy: expectancy,
                maximumDrawdown: returns.isEmpty ? nil : drawdown,
                meanExecutionDelaySeconds: delays.isEmpty ? nil : delays.reduce(0, +) / Double(delays.count)
            )
        }
    }
}

public enum DeteriorationSeverity: String, Codable, Sendable {
    case none, watch, alert
}

public struct StrategyDeteriorationAlert: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateID: String
    public let severity: DeteriorationSeverity
    public let reasons: [String]
    public let researchOnly: Bool
}

public enum PerformanceDeterioration {
    public static func inspect(
        candidateID: String,
        baseline: StrategyCompetitionRow,
        recent: StrategyCompetitionRow,
        minimumResolved: Int = 10
    ) throws -> StrategyDeteriorationAlert {
        guard minimumResolved > 0 else { throw Milestone5ResearchError.invalidInput }
        var reasons: [String] = []
        if recent.resolved >= minimumResolved, let old = baseline.expectancy, let current = recent.expectancy,
           current < old { reasons.append("recent expectancy declined") }
        if let old = baseline.meanExecutionDelaySeconds, let current = recent.meanExecutionDelaySeconds,
           current > old * 1.25 { reasons.append("execution latency increased") }
        if recent.unresolved > baseline.unresolved, recent.matchedSignals >= minimumResolved {
            reasons.append("unresolved-outcome rate increased")
        }
        let severity: DeteriorationSeverity
        if reasons.count >= 2 { severity = .alert }
        else if reasons.count == 1 { severity = .watch }
        else { severity = .none }
        return StrategyDeteriorationAlert(
            id: "\(candidateID)-\(severity.rawValue)",
            candidateID: candidateID,
            severity: severity,
            reasons: reasons,
            researchOnly: true
        )
    }
}

public struct CapitalScenario: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let account: Double
    public let trades: Int
    public let endingBalance: Double
    public let maximumDrawdown: Double
    public let depleted: Bool
    public let suitable: Bool
    public let assumption: String
}

public enum CapitalScenarioSimulator {
    public static func run(
        accounts: [Double] = [250, 500, 1_000, 2_500],
        returns: [Double],
        minimumPosition: Double,
        slippageShock: Double = 0,
        transactionCost: Double = 0
    ) throws -> [CapitalScenario] {
        guard !accounts.isEmpty, accounts.allSatisfy({ $0.isFinite && $0 > 0 }),
              !returns.isEmpty, returns.allSatisfy(\.isFinite),
              minimumPosition.isFinite, minimumPosition > 0,
              slippageShock.isFinite, slippageShock >= 0,
              transactionCost.isFinite, transactionCost >= 0 else {
            throw Milestone5ResearchError.invalidInput
        }
        return accounts.map { account in
            var balance = account
            var peak = account
            var drawdown = 0.0
            var trades = 0
            for value in returns where balance >= minimumPosition {
                let risk = min(minimumPosition, balance)
                balance += risk * value - transactionCost - slippageShock
                trades += 1
                peak = max(peak, balance)
                drawdown = max(drawdown, peak - balance)
                if balance <= 0 { balance = 0; break }
            }
            return CapitalScenario(
                id: "USD-\(account)",
                account: account,
                trades: trades,
                endingBalance: balance,
                maximumDrawdown: drawdown,
                depleted: balance <= 0,
                suitable: trades == returns.count && balance > 0,
                assumption: "Hypothetical research only; fixed minimum position, costs and slippage shock are not broker guarantees."
            )
        }
    }
}

public enum BrokerEvidenceState: String, Codable, Sendable {
    case verified, pendingVerification, unsuitable, unknown
}

public struct BrokerDecisionEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let broker: String
    public let instrument: String
    public let eligibility: BrokerEvidenceState
    public let dataAccess: BrokerEvidenceState
    public let execution: BrokerEvidenceState
    public let limitations: [String]
    public let liveRecommendation: Bool
}

public enum BrokerDecisionEngine {
    public static let conservativeMatrix = [
        BrokerDecisionEntry(
            id: "oanda-us-forex", broker: "OANDA", instrument: "U.S. retail forex",
            eligibility: .pendingVerification, dataAccess: .pendingVerification,
            execution: .pendingVerification,
            limitations: ["Verify current NFA/CFTC status, account terms, spreads, API limits, and Washington eligibility from official sources."],
            liveRecommendation: false
        ),
        BrokerDecisionEntry(
            id: "us-micro-futures", broker: "U.S. futures broker", instrument: "CME micro-futures",
            eligibility: .pendingVerification, dataAccess: .pendingVerification,
            execution: .pendingVerification,
            limitations: ["Broker, contract, margin, commission, data entitlement, and manual execution must be selected and verified."],
            liveRecommendation: false
        ),
        BrokerDecisionEntry(
            id: "fixed-expiry-unverified", broker: "Unverified fixed-expiry venue", instrument: "Fixed-expiry contract",
            eligibility: .unknown, dataAccess: .unknown, execution: .unknown,
            limitations: ["No live recommendation without current legal, venue, settlement, and customer-eligibility evidence."],
            liveRecommendation: false
        )
    ]
}

public enum ResearchGapSeverity: String, Codable, Sendable, CaseIterable {
    case p0, p1, p2, p3
}

public enum ResearchGapStatus: String, Codable, Sendable, CaseIterable {
    case open, blocked, fixed, verified, closed
}

public struct ResearchGap: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let component: String
    public let severity: ResearchGapSeverity
    public let evidence: String
    public let rootCause: String?
    public let owner: String
    public let requiredFix: String
    public let regressionTest: String
    public let independentQA: String?
    public let disposition: String?
    public let relatedReference: String?
    public let status: ResearchGapStatus
    public let updatedAt: Date

    public init(id: String, component: String, severity: ResearchGapSeverity, evidence: String,
                rootCause: String? = nil, owner: String, requiredFix: String,
                regressionTest: String, independentQA: String? = nil,
                disposition: String? = nil, relatedReference: String? = nil,
                status: ResearchGapStatus = .open, updatedAt: Date = Date()) {
        self.id = id
        self.component = component
        self.severity = severity
        self.evidence = evidence
        self.rootCause = rootCause
        self.owner = owner
        self.requiredFix = requiredFix
        self.regressionTest = regressionTest
        self.independentQA = independentQA
        self.disposition = disposition
        self.relatedReference = relatedReference
        self.status = status
        self.updatedAt = updatedAt
    }
}

public struct ForwardValidationCampaign: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let strategies: [ResearchStrategyCandidate]
    public let instruments: [String]
    public let sources: [String]
    public let expirySeconds: Int
    public let evaluationCriteria: [String]
    public let createdAt: Date

    public init(id: String, version: String, strategies: [ResearchStrategyCandidate],
                instruments: [String], sources: [String], expirySeconds: Int = 60,
                evaluationCriteria: [String], createdAt: Date = Date()) throws {
        guard !id.isEmpty, !version.isEmpty, !strategies.isEmpty,
              !instruments.isEmpty, !sources.isEmpty, expirySeconds == 60,
              !evaluationCriteria.isEmpty else {
            throw Milestone5ResearchError.invalidInput
        }
        self.id = id
        self.version = version
        self.strategies = strategies
        self.instruments = instruments
        self.sources = sources
        self.expirySeconds = expirySeconds
        self.evaluationCriteria = evaluationCriteria
        self.createdAt = createdAt
    }
}
