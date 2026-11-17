import Foundation

public enum AdaptiveMarketAvailability: String, Codable, Sendable, Equatable {
    case ready = "READY"
    case credentialsMissing = "CREDENTIALS_MISSING"
    case practiceRequired = "PRACTICE_REQUIRED"
    case marketClosed = "MARKET_CLOSED"
    case unsupportedInstrument = "UNSUPPORTED_INSTRUMENT"
    case observationUnavailable = "OBSERVATION_UNAVAILABLE"
    case providerError = "PROVIDER_ERROR"
}

public enum AdaptiveMarketDecisionState: String, Codable, Sendable, Equatable {
    case noOpportunity = "NO_OPPORTUNITY"
    case opportunityForming = "OPPORTUNITY_FORMING"
    case actionableOpportunity = "ACTIONABLE_OPPORTUNITY"
    case unavailable = "UNAVAILABLE"
}

public enum AdaptiveHorizonEvidenceState: String, Codable, Sendable, Equatable {
    case supportedByResearch = "SUPPORTED_BY_RESEARCH"
    case structurallyDefined = "STRUCTURALLY_DEFINED"
    case awaitingEvidence = "AWAITING_EVIDENCE"
    case unsupported = "UNSUPPORTED"
}

/// Result of invoking one configured research evaluator on a Practice/replay
/// snapshot. An empty candidate list with `.completed` means the evaluator ran
/// successfully and found no setup; `.failed` and `.dataUnavailable` remain
/// distinct, machine-readable outcomes.
public struct AdaptiveStrategyEvaluationOutcome: Codable, Sendable, Equatable, Identifiable {
    public enum State: String, Codable, Sendable, Equatable {
        case completed = "COMPLETED"
        case failed = "FAILED"
        case dataUnavailable = "DATA_UNAVAILABLE"
    }

    public let evaluatorID: String
    public let strategyID: String
    public let strategyVersion: String
    public let timeframe: String
    public let state: State
    public let candidateIDs: [String]
    public let reasonCode: String?
    public var id: String { "\(evaluatorID):\(timeframe)" }

    public init(evaluatorID: String, strategyID: String, strategyVersion: String,
                timeframe: String, state: State, candidateIDs: [String] = [],
                reasonCode: String? = nil) {
        self.evaluatorID = evaluatorID
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.timeframe = timeframe
        self.state = state
        self.candidateIDs = candidateIDs
        self.reasonCode = reasonCode
    }
}

public struct AdaptiveRehearsalTiming: Codable, Sendable, Equatable {
    public let brokerMs: Double
    public let validationMs: Double
    public let candidateEvaluationMs: Double
    public let selectionMs: Double
    public let persistenceMs: Double
    public let totalMs: Double

    public init(brokerMs: Double, validationMs: Double, candidateEvaluationMs: Double,
                selectionMs: Double, persistenceMs: Double, totalMs: Double) {
        self.brokerMs = brokerMs
        self.validationMs = validationMs
        self.candidateEvaluationMs = candidateEvaluationMs
        self.selectionMs = selectionMs
        self.persistenceMs = persistenceMs
        self.totalMs = totalMs
    }
}

public struct AdaptiveMarketRehearsalResult: Codable, Sendable {
    public let record: AdaptiveMarketRehearsalRecord
    public let timing: AdaptiveRehearsalTiming

    public init(record: AdaptiveMarketRehearsalRecord, timing: AdaptiveRehearsalTiming) {
        self.record = record
        self.timing = timing
    }
}

public enum AdaptiveDiagnosticState: String, Codable, Sendable, Equatable {
    case success = "SUCCESS"
    case credentialsMissing = "CREDENTIALS_MISSING"
    case authenticationFailure = "AUTHENTICATION_FAILURE"
    case timeout = "TIMEOUT"
    case networkFailure = "NETWORK_FAILURE"
    case rateLimited = "RATE_LIMITED"
    case marketDataUnavailable = "MARKET_DATA_UNAVAILABLE"
    case internalFailure = "INTERNAL_FAILURE"
}

public struct AdaptiveMarketDiagnostic: Codable, Sendable {
    public let state: AdaptiveDiagnosticState
    public let message: String
    public let timing: AdaptiveRehearsalTiming?
    public let result: AdaptiveMarketRehearsalResult?

    public init(state: AdaptiveDiagnosticState, message: String,
                timing: AdaptiveRehearsalTiming? = nil,
                result: AdaptiveMarketRehearsalResult? = nil) {
        self.state = state
        self.message = message
        self.timing = timing
        self.result = result
    }
}

public struct AdaptiveHorizonEvidence: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateID: String
    public let horizonSeconds: Int?
    public let state: AdaptiveHorizonEvidenceState
    public let evidenceReferences: [String]
    public let reason: String

    public init(candidateID: String, horizonSeconds: Int?, state: AdaptiveHorizonEvidenceState,
                evidenceReferences: [String] = [], reason: String) {
        self.candidateID = candidateID
        self.horizonSeconds = horizonSeconds
        self.state = state
        self.evidenceReferences = evidenceReferences
        self.reason = reason
        id = "\(candidateID)-\(horizonSeconds.map(String.init) ?? "structural")-\(state.rawValue)"
    }
}

/// Practice signal presentation model. It carries usable review details without
/// granting order authority and converts expired candidates to non-actionable state.
public struct AdaptiveResearchProjection: Codable, Sendable, Equatable {
    public let decisionState: AdaptiveMarketDecisionState
    public let instrument: String
    public let provider: String
    public let candidateID: String?
    public let strategyID: String?
    public let timeframe: String?
    public let direction: AdaptiveDirection?
    public let entryPrice: Double?
    public let stopPrice: Double?
    public let targetPrice: Double?
    public let remainingReasons: [String]?
    public let unavailableFields: [String]?
    public let horizonSeconds: Int?
    public let freshness: AdaptiveFreshnessState?
    public let observedAt: Date?
    public let decisionAgeSeconds: TimeInterval?
    public let invalidationReason: String?
    /// Candidate review always requires the user's own broker action.
    public var requiresManualExecution: Bool { true }

    public init(record: AdaptiveMarketRehearsalRecord, now: Date,
                maximumAge: TimeInterval = 8) {
        let selected = record.decision.selectedCandidateID.flatMap { id in
            record.candidates.first { $0.id == id }
        }
        let selectedOutcome = selected.flatMap { candidate in
            record.evaluatorOutcomes?.first {
                $0.candidateIDs.contains(candidate.id)
            }
        }
        let age = record.observedAt <= now ? now.timeIntervalSince(record.observedAt) : nil
        let expired = selected.map { $0.freshness != .fresh || (age ?? .greatestFiniteMagnitude) > maximumAge } ?? false
        decisionState = expired ? .noOpportunity : record.decisionState
        instrument = record.instrument
        provider = record.provider
        candidateID = selected?.id
        strategyID = selected?.strategyID
        timeframe = expired ? nil : selectedOutcome?.timeframe
        direction = selected?.direction
        entryPrice = expired ? nil : selected?.plan?.entryPrice ?? selected?.entryReference
        stopPrice = expired ? nil : selected?.plan?.stopPrice
        targetPrice = expired ? nil : selected?.plan?.targetPrice
        remainingReasons = expired ? [] : (selected?.rejectionReasons ?? [])
        var missing: [String] = []
        if selectedOutcome?.timeframe == nil { missing.append("timeframe") }
        if selected?.plan?.entryPrice == nil && selected?.entryReference == nil { missing.append("entry") }
        if selected?.plan?.stopPrice == nil { missing.append("stop") }
        if selected?.plan?.targetPrice == nil { missing.append("target") }
        unavailableFields = expired ? ["timeframe", "entry", "stop", "target"] : missing
        horizonSeconds = expired ? nil : record.selectedHorizonSeconds
        freshness = selected?.freshness
        observedAt = record.observedAt
        decisionAgeSeconds = age
        invalidationReason = expired ? "decision_expired_or_stale" : record.errorReason
    }
}

public struct AdaptiveMarketRehearsalRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let inputDigest: String
    public let instrument: String
    public let provider: String
    public let environment: V3ProviderEnvironment
    public let observedAt: Date
    public let receivedAt: Date
    public let input: StrategyEngine.MarketInput
    public let candidates: [AdaptiveOpportunityCandidate]
    public let decision: AdaptiveOpportunityDecision
    public let decisionState: AdaptiveMarketDecisionState
    public let horizonEvidence: [AdaptiveHorizonEvidence]
    public let availability: AdaptiveMarketAvailability
    public let errorReason: String?
    /// Optional for compatibility with previously persisted rehearsal records.
    public let evaluatorOutcomes: [AdaptiveStrategyEvaluationOutcome]?

    public init(input: StrategyEngine.MarketInput, observedAt: Date, receivedAt: Date,
                candidates: [AdaptiveOpportunityCandidate], decision: AdaptiveOpportunityDecision,
                decisionState: AdaptiveMarketDecisionState,
                horizonEvidence: [AdaptiveHorizonEvidence],
                availability: AdaptiveMarketAvailability = .ready, errorReason: String? = nil,
                evaluatorOutcomes: [AdaptiveStrategyEvaluationOutcome]? = nil) throws {
        inputDigest = try ResearchEvent.digest(of: input)
        id = "adaptive-\(inputDigest)"
        instrument = input.asset
        provider = input.source
        environment = .oandaPractice
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.input = input
        self.candidates = candidates
        self.decision = decision
        self.decisionState = decisionState
        self.horizonEvidence = horizonEvidence
        self.availability = availability
        self.errorReason = errorReason
        self.evaluatorOutcomes = evaluatorOutcomes
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || instrument.isEmpty || provider.isEmpty { issues.append("identity_missing") }
        if environment != .oandaPractice { issues.append("practice_environment_required") }
        if input.source != provider || input.asset != instrument { issues.append("input_identity_mismatch") }
        if inputDigest != (try? ResearchEvent.digest(of: input)) { issues.append("input_digest_mismatch") }
        if observedAt > receivedAt.addingTimeInterval(1) { issues.append("future_observation") }
        if decisionState == .actionableOpportunity && decision.selectedCandidateID == nil {
            issues.append("actionable_decision_missing_candidate")
        }
        return issues
    }

    /// The horizon selected for the winning candidate, when research actually
    /// supports one. Structural plans intentionally return nil because a
    /// stop/target plan is not evidence of a fixed holding duration.
    public var selectedHorizonSeconds: Int? {
        guard let selectedCandidateID = decision.selectedCandidateID else { return nil }
        return horizonEvidence.first {
            $0.candidateID == selectedCandidateID && $0.state == .supportedByResearch
        }?.horizonSeconds
    }

    public var selectedHorizonEvidenceState: AdaptiveHorizonEvidenceState? {
        guard let selectedCandidateID = decision.selectedCandidateID else { return nil }
        return horizonEvidence.first { $0.candidateID == selectedCandidateID }?.state
    }
}

/// One-shot Practice rehearsal. It is intentionally not connected to the desk or order APIs.
public enum AdaptiveMarketRehearsal {
    /// Maps selector output to the user-facing market state without treating
    /// stale or unsafe data as a developing setup.
    public static func decisionState(for decision: AdaptiveOpportunityDecision) -> AdaptiveMarketDecisionState {
        if decision.selectedCandidateID != nil { return .actionableOpportunity }
        if decision.candidates.contains(where: { $0.state == .unavailable }) { return .unavailable }

        let hardRejectionReasons: Set<String> = [
            "non_directional", "stale_or_missing_observation",
            "observation_expired", "spread_not_accepted", "conflicting_direction",
            "quote_stale", "quote_missing", "quote_future"
        ]
        let forming = decision.candidates.contains { candidate in
            guard candidate.direction != .wait, candidate.state == .rejected else { return false }
            return Set(candidate.rejectionReasons).isDisjoint(with: hardRejectionReasons)
        }
        return forming ? .opportunityForming : .noOpportunity
    }

    public static func run(asset: String, session: OandaSession, store: ResearchStore? = nil,
                           now: Date = Date()) async throws -> AdaptiveMarketRehearsalRecord {
        try await runMeasured(asset: asset, session: session, store: store, now: now).record
    }

    /// Evaluates an already captured scan snapshot. Callers that already own a
    /// broker observation use this entry point so adaptive research never
    /// performs a second network fetch or changes the executable scan result.
    public static func evaluateSnapshot(_ input: StrategyEngine.MarketInput,
                                         observedAt: Date,
                                         receivedAt: Date = Date(),
                                         store: ResearchStore? = nil) async throws
        -> AdaptiveMarketRehearsalResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let candidateStart = DispatchTime.now().uptimeNanoseconds
        var candidates: [AdaptiveOpportunityCandidate] = []
        for policy in ScanPolicy.allCases {
            let candidateStart = Date()
            candidates.append(try await AdaptiveOpportunityAdapters.evaluateEngine(
                input, policy: policy, at: candidateStart))
        }
        let researchBatch = evaluateConfiguredResearchStrategies(input, asOf: receivedAt)
        candidates.append(contentsOf: researchBatch.candidates)
        candidates.append(AdaptiveOpportunityAdapters.evaluateORB(input, asOf: receivedAt,
                                                                   startedAt: receivedAt))
        let candidateEvaluationMs = elapsedMs(since: candidateStart)
        let selectionStart = DispatchTime.now().uptimeNanoseconds
        let decision = AdaptiveOpportunitySelector.select(candidates, now: receivedAt,
                                                           decisionAt: Date())
        let selectionMs = elapsedMs(since: selectionStart)
        let horizonEvidence = candidates.flatMap { candidate -> [AdaptiveHorizonEvidence] in
            if let plan = candidate.plan {
                return [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                    state: .structurallyDefined, evidenceReferences: plan.evidenceIDs,
                    reason: "V3 stop/target-first structural evaluation")]
            }
            guard !candidate.horizonsSeconds.isEmpty, !candidate.evidenceReferences.isEmpty else {
                return [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                    state: .awaitingEvidence,
                    reason: "No completed research horizon evidence")]
            }
            return candidate.horizonsSeconds.map {
                AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: $0,
                    state: .supportedByResearch, evidenceReferences: candidate.evidenceReferences,
                    reason: "Existing research horizon; not an optimality claim")
            }
        }
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: observedAt,
            receivedAt: receivedAt, candidates: candidates, decision: decision,
            decisionState: decisionState(for: decision), horizonEvidence: horizonEvidence,
            evaluatorOutcomes: researchBatch.outcomes)
        let persistenceStart = DispatchTime.now().uptimeNanoseconds
        if let store { try await store.record(record) }
        let persistenceMs = elapsedMs(since: persistenceStart)
        return AdaptiveMarketRehearsalResult(record: record,
             timing: AdaptiveRehearsalTiming(brokerMs: 0, validationMs: 0,
                 candidateEvaluationMs: candidateEvaluationMs,
                 selectionMs: selectionMs, persistenceMs: persistenceMs,
                 totalMs: elapsedMs(since: started)))
    }

    public static func runMeasured(asset: String, session: OandaSession, store: ResearchStore? = nil,
                                   now: Date = Date()) async throws -> AdaptiveMarketRehearsalResult {
        let totalStart = DispatchTime.now().uptimeNanoseconds
        guard session.isConfigured else { throw ScanError.failed("OANDA credentials missing") }
        guard session.environment == .practice else { throw ScanError.failed("OANDA Practice required") }
        guard OandaClient.instrument(for: asset) != nil else {
            throw ScanError.failed("Unsupported instrument: \(asset)")
        }
        guard FxSession.isOpen(now) else { throw ScanError.failed("FX market closed") }
        let brokerStart = DispatchTime.now().uptimeNanoseconds
        guard let input = try await OandaClient.fetchBundle(asset: asset, session: session) else {
            throw ScanError.failed("OANDA observation unavailable")
        }
        // Receipt is measured after the provider response, not before the
        // network request. This keeps freshness and latency evidence honest.
        let receivedAt = Date()
        let brokerMs = elapsedMs(since: brokerStart)
        let validationStart = DispatchTime.now().uptimeNanoseconds
        guard input.source == "oanda", input.candles1m.count >= 20, input.candles5m.count >= 20,
              input.bid.isFinite, input.ask.isFinite, input.ask > input.bid,
              let quoteMs = input.quoteAsOfMs else {
            throw ScanError.failed("OANDA observation incomplete")
        }
        let observedAt = Date(timeIntervalSince1970: quoteMs / 1_000)
        guard observedAt <= receivedAt.addingTimeInterval(1),
              receivedAt.timeIntervalSince(observedAt) <= 8 else {
            throw ScanError.failed("OANDA observation stale")
        }
        let validationMs = elapsedMs(since: validationStart)

        let candidateStart = DispatchTime.now().uptimeNanoseconds
        var candidates: [AdaptiveOpportunityCandidate] = []
        for policy in ScanPolicy.allCases {
            let started = Date()
            candidates.append(try await AdaptiveOpportunityAdapters.evaluateEngine(input, policy: policy,
                                                                                   at: started))
        }
        let researchBatch = evaluateConfiguredResearchStrategies(input, asOf: receivedAt)
        candidates.append(contentsOf: researchBatch.candidates)
        candidates.append(AdaptiveOpportunityAdapters.evaluateORB(input, asOf: receivedAt,
                                                                  startedAt: receivedAt))
        let candidateEvaluationMs = elapsedMs(since: candidateStart)
        let selectionStart = DispatchTime.now().uptimeNanoseconds
        let decision = AdaptiveOpportunitySelector.select(candidates, now: receivedAt)
        let selectionMs = elapsedMs(since: selectionStart)
        let state = decisionState(for: decision)
        let horizonEvidence = candidates.flatMap { candidate -> [AdaptiveHorizonEvidence] in
            if let plan = candidate.plan {
                return [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                    state: .structurallyDefined, evidenceReferences: plan.evidenceIDs,
                    reason: "V3 stop/target-first structural evaluation")]
            }
            if candidate.horizonsSeconds.isEmpty {
                return [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                    state: .awaitingEvidence, reason: "No structural horizon or completed research outcome")]
            }
            guard !candidate.evidenceReferences.isEmpty else {
                return [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                    state: .awaitingEvidence,
                    reason: "Candidate has no completed research evidence references")]
            }
            return candidate.horizonsSeconds.map {
                AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: $0,
                    state: .supportedByResearch,
                    evidenceReferences: candidate.evidenceReferences,
                    reason: "Existing research horizon; not an optimality claim")
            }
        }
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: observedAt,
            receivedAt: receivedAt, candidates: candidates, decision: decision,
            decisionState: state, horizonEvidence: horizonEvidence,
            evaluatorOutcomes: researchBatch.outcomes)
        let persistenceStart = DispatchTime.now().uptimeNanoseconds
        if let store { try await store.record(record) }
        let persistenceMs = elapsedMs(since: persistenceStart)
        let timing = AdaptiveRehearsalTiming(brokerMs: brokerMs, validationMs: validationMs,
            candidateEvaluationMs: candidateEvaluationMs, selectionMs: selectionMs,
            persistenceMs: persistenceMs, totalMs: elapsedMs(since: totalStart))
        return AdaptiveMarketRehearsalResult(record: record, timing: timing)
    }

    public static func runBounded(asset: String, session: OandaSession,
                                  store: ResearchStore? = nil,
                                  now: Date = Date(),
                                  timeout: Duration = .seconds(45)) async -> AdaptiveMarketDiagnostic {
        do {
            let result = try await withThrowingTaskGroup(of: AdaptiveMarketRehearsalResult.self) { group in
                group.addTask {
                    try await runMeasured(asset: asset, session: session, store: store, now: now)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ScanError.failed("bounded diagnostic deadline exceeded")
                }
                guard let result = try await group.next() else {
                    throw ScanError.failed("bounded diagnostic produced no result")
                }
                group.cancelAll()
                return result
            }
            return AdaptiveMarketDiagnostic(state: .success, message: "Adaptive Practice rehearsal completed",
                                            timing: result.timing, result: result)
        } catch {
            let message = error.localizedDescription
            let state: AdaptiveDiagnosticState
            switch message {
            case let value where value.localizedCaseInsensitiveContains("credential") || value.localizedCaseInsensitiveContains("token missing"):
                state = .credentialsMissing
            case let value where value.localizedCaseInsensitiveContains("unauthorized") || value.localizedCaseInsensitiveContains("practice required"):
                state = .authenticationFailure
            case let value where value.localizedCaseInsensitiveContains("timeout") || value.localizedCaseInsensitiveContains("deadline"):
                state = .timeout
            case let value where value.localizedCaseInsensitiveContains("rate limit"):
                state = .rateLimited
            case let value where value.localizedCaseInsensitiveContains("observation") || value.localizedCaseInsensitiveContains("incomplete") || value.localizedCaseInsensitiveContains("stale"):
                state = .marketDataUnavailable
            default:
                state = .networkFailure
            }
            return AdaptiveMarketDiagnostic(state: state, message: message)
        }
    }

    /// Runs the existing GBP/JPY research evaluators against the same captured
    /// snapshot as the rest of Practice rehearsal. No strategy promotion registry
    /// participates in candidate generation. Each evaluator reports successful
    /// no-setup separately from incomplete data and analyzer failure.
    private static func evaluateConfiguredResearchStrategies(
        _ input: StrategyEngine.MarketInput, asOf: Date
    ) -> (candidates: [AdaptiveOpportunityCandidate], outcomes: [AdaptiveStrategyEvaluationOutcome]) {
        let instrument = input.asset.uppercased().replacingOccurrences(of: "_", with: "/")
        guard instrument == "GBP/JPY" else { return ([], []) }

        let m15 = AdaptiveOpportunityAdapters.aggregateM15(input.candles5m)
        let m1Count = input.candles1m.count
        let hasM15Context = !m15.isEmpty
        let startedAt = Date()
        var candidates: [AdaptiveOpportunityCandidate] = []
        var outcomes: [AdaptiveStrategyEvaluationOutcome] = []

        let candidate001Configuration = Candidate001Configuration(requireM15Confirmation: true,
                                                                   signalFreshnessSeconds: 300)
        let candidate002Configuration = Candidate002Configuration(signalFreshnessSeconds: 120)
        let evaluatorSpecs: [(id: String, strategy: String, version: String, minimumM1: Int)] = [
            ("candidate001", "CANDIDATE_001_CHOCH_FVG_FIB", Candidate001Analyzer.version,
             candidate001Configuration.swingLeftBars + candidate001Configuration.swingRightBars + 1),
            ("candidate002", "CANDIDATE_002_AUCTION_FAILURE", Candidate002Analyzer.version,
             candidate002Configuration.lookbackBars + 2)
        ]
        for spec in evaluatorSpecs {
            // Both existing adapters use M1 bars with a deterministically
            // aggregated M15 context. Three aligned M5 bars form one completed
            // M15 bar; incomplete context cannot be reported as NO_SETUP.
            guard m1Count >= spec.minimumM1, hasM15Context else {
                outcomes.append(AdaptiveStrategyEvaluationOutcome(
                    evaluatorID: spec.id, strategyID: spec.strategy,
                    strategyVersion: spec.version, timeframe: "M1+M15",
                    state: .dataUnavailable,
                    reasonCode: m1Count < spec.minimumM1
                        ? "candle_history_insufficient" : "m15_context_unavailable"))
                continue
            }

            let batch: AdaptiveCandidateEvaluationBatch
            switch spec.id {
            case "candidate001":
                batch = AdaptiveOpportunityAdapters.evaluateCandidate001Result(
                    input, asOf: asOf, startedAt: startedAt)
            case "candidate002":
                batch = AdaptiveOpportunityAdapters.evaluateCandidate002Result(
                    input, asOf: asOf, startedAt: startedAt)
            default:
                continue
            }

            switch batch {
            case .completed(let values):
                candidates.append(contentsOf: values)
                outcomes.append(AdaptiveStrategyEvaluationOutcome(
                    evaluatorID: spec.id, strategyID: spec.strategy,
                    strategyVersion: spec.version, timeframe: "M1+M15",
                    state: .completed, candidateIDs: values.map(\.id),
                    reasonCode: values.isEmpty ? "no_candidate" : nil))
            case .failed(let reason):
                // Adapter errors are already normalized to stable codes; never
                // persist localized exception messages or provider payloads.
                outcomes.append(AdaptiveStrategyEvaluationOutcome(
                    evaluatorID: spec.id, strategyID: spec.strategy,
                    strategyVersion: spec.version, timeframe: "M1+M15",
                    state: .failed, reasonCode: reason))
            }
        }
        return (candidates, outcomes)
    }

    private static func elapsedMs(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}
