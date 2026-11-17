import Foundation

/// V3 setup lifecycle. This is deliberately separate from V1's directional score and
/// from a broker position: a setup can be watched, invalidated, or unresolved without
/// ever becoming a trade.
public enum V3SetupState: String, Codable, Sendable, CaseIterable {
    case noData = "NO_DATA"
    case stale = "STALE"
    case watching = "WATCHING"
    case forming = "FORMING"
    case approaching = "APPROACHING"
    case confirmed = "CONFIRMED"
    case triggered = "TRIGGERED"
    case invalidated = "INVALIDATED"
    case setupExpired = "SETUP_EXPIRED"
    case unresolved = "UNRESOLVED"

    public func canTransition(to next: V3SetupState) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.noData, .stale), (.noData, .watching),
             (.stale, .watching), (.stale, .noData),
             (.stale, .setupExpired),
             (.watching, .forming), (.watching, .stale), (.watching, .invalidated),
             (.watching, .setupExpired),
             (.forming, .approaching), (.forming, .invalidated), (.forming, .stale),
             (.forming, .setupExpired),
             (.approaching, .confirmed), (.approaching, .invalidated), (.approaching, .stale),
             (.approaching, .setupExpired),
             (.confirmed, .triggered), (.confirmed, .invalidated), (.confirmed, .stale),
             (.confirmed, .setupExpired),
             (.triggered, .unresolved), (.triggered, .invalidated),
             (.invalidated, .unresolved), (.setupExpired, .unresolved),
             (.stale, .unresolved), (.watching, .unresolved), (.forming, .unresolved),
             (.approaching, .unresolved), (.confirmed, .unresolved):
            return true
        default:
            return false
        }
    }
}

/// Append-only evidence for a strategy setup as it develops. Setup lifetime is
/// controlled by the strategy's explicit state transition, not by quote freshness
/// or the legacy V1 eight-second action window.
public struct V3SetupLifecycleEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let setupID: String
    public let instrument: String
    public let strategyID: String
    public let strategyVersion: String
    public let provider: String
    public let environment: V3ProviderEnvironment
    public let previousState: V3SetupState?
    public let state: V3SetupState
    public let sourceObservationID: String?
    public let sourceTime: Date?
    public let receivedAt: Date
    public let recordedAt: Date
    public let planID: String?
    public let reason: String
    public let configurationDigest: String?
    public let inputDigest: String?
    public let engineVersion: String?
    public let sourceBarIDs: [String]?
    public let quoteSequence: UInt64?
    public let reasonCodes: [String]?
    public let evidenceSchemaVersion: Int?
    /// Stable structure identity and timeframe used to prevent terminal re-arm.
    /// Optional values preserve decoding of older lifecycle events.
    public let structureID: String?
    public let timeframeSeconds: Int?

    public init(id: String, setupID: String, instrument: String,
                strategyID: String, strategyVersion: String, provider: String,
                environment: V3ProviderEnvironment, previousState: V3SetupState?,
                state: V3SetupState, sourceObservationID: String? = nil,
                sourceTime: Date? = nil, receivedAt: Date, recordedAt: Date,
                planID: String? = nil, reason: String,
                configurationDigest: String? = nil, inputDigest: String? = nil,
                engineVersion: String? = nil, sourceBarIDs: [String]? = nil,
                quoteSequence: UInt64? = nil, reasonCodes: [String]? = nil,
                structureID: String? = nil, timeframeSeconds: Int? = nil,
                evidenceSchemaVersion: Int? = nil) {
        self.id = id
        self.setupID = setupID
        self.instrument = instrument
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.provider = provider
        self.environment = environment
        self.previousState = previousState
        self.state = state
        self.sourceObservationID = sourceObservationID
        self.sourceTime = sourceTime
        self.receivedAt = receivedAt
        self.recordedAt = recordedAt
        self.planID = planID
        self.reason = reason
        self.configurationDigest = configurationDigest
        self.inputDigest = inputDigest
        self.engineVersion = engineVersion
        self.sourceBarIDs = sourceBarIDs
        self.quoteSequence = quoteSequence
        self.reasonCodes = reasonCodes
        self.evidenceSchemaVersion = evidenceSchemaVersion
        self.structureID = structureID
        self.timeframeSeconds = timeframeSeconds
    }

    public var hasCompleteEvaluatorProvenance: Bool {
        guard let configurationDigest, let inputDigest, let engineVersion,
              let sourceBarIDs, let reasonCodes,
              let structureID, let timeframeSeconds, let evidenceSchemaVersion else { return false }
        let sequenceIsValid = strategyID == "ORB_BREAK_RETEST_V1"
            ? quoteSequence == nil : quoteSequence.map { $0 > 0 } ?? false
        return Self.isDigest(configurationDigest) && Self.isDigest(inputDigest)
            && !engineVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceBarIDs.isEmpty && sourceBarIDs.allSatisfy { !$0.isEmpty }
            && Set(sourceBarIDs).count == sourceBarIDs.count && sequenceIsValid
            && !structureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && timeframeSeconds > 0
            && evidenceSchemaVersion == 1
            && reasonCodes.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || setupID.isEmpty || instrument.isEmpty || strategyID.isEmpty
            || strategyVersion.isEmpty || provider.isEmpty || reason.isEmpty {
            issues.append("identity_missing")
        }
        if !id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            || !setupID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            issues.append("identity_invalid")
        }
        if let planID, planID.isEmpty || !planID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            issues.append("plan_identity_invalid")
        }
        for date in [sourceTime, Optional(receivedAt), Optional(recordedAt)].compactMap({ $0 }) {
            if !date.timeIntervalSince1970.isFinite { issues.append("timestamp_invalid") }
        }
        if let sourceTime {
            if sourceTime > recordedAt.addingTimeInterval(1) { issues.append("future_source_time") }
            if sourceTime > receivedAt.addingTimeInterval(1) { issues.append("source_after_receipt") }
        }
        if receivedAt > recordedAt.addingTimeInterval(1) { issues.append("receipt_after_recorded_time") }
        if sourceObservationID?.isEmpty == true { issues.append("observation_identity_invalid") }
        if (sourceObservationID == nil) != (sourceTime == nil) { issues.append("observation_provenance_incomplete") }
        let hasAnyEvaluatorProvenance = configurationDigest != nil || inputDigest != nil
            || engineVersion != nil || sourceBarIDs != nil || quoteSequence != nil || reasonCodes != nil
            || structureID != nil || timeframeSeconds != nil || evidenceSchemaVersion != nil
        if hasAnyEvaluatorProvenance && !hasCompleteEvaluatorProvenance {
            issues.append("evaluator_provenance_incomplete")
        }
        if (structureID == nil) != (timeframeSeconds == nil) {
            issues.append("structure_provenance_incomplete")
        }
        if let structureID, structureID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("structure_identity_invalid")
        }
        if let timeframeSeconds, timeframeSeconds <= 0 { issues.append("timeframe_invalid") }
        if let evidenceSchemaVersion, evidenceSchemaVersion <= 0 { issues.append("evidence_schema_version_invalid") }
        if let quoteSequence, quoteSequence == 0 { issues.append("quote_sequence_invalid") }
        if strategyID == "ORB_BREAK_RETEST_V1" {
            if provider != "OANDA" || environment != .oandaLive || sourceTime == nil
                || sourceObservationID.map({ sourceBarIDs?.contains($0) == true }) != true {
                issues.append("orb_provenance_invalid")
            }
            if state == .confirmed && planID == nil { issues.append("orb_confirmed_plan_missing") }
        }
        if let previousState {
            if !V3SetupLifecycle.transitionAllowed(from: previousState, to: state, event: self) {
                issues.append("invalid_state_transition")
            }
        } else if strategyID == "ORB_BREAK_RETEST_V1" {
            if !hasCompleteEvaluatorProvenance || !Self.isORBObservedState(state) {
                issues.append("initial_state_invalid")
            }
        } else if ![V3SetupState.noData, .watching, .forming].contains(state)
                    && !(hasCompleteEvaluatorProvenance && Self.isAdvancedObservedState(state)) {
            issues.append("initial_state_invalid")
        }
        return Array(Set(issues)).sorted()
    }

    private static func isAdvancedObservedState(_ state: V3SetupState) -> Bool {
        [.stale, .approaching, .confirmed, .invalidated, .setupExpired].contains(state)
    }

    private static func isORBObservedState(_ state: V3SetupState) -> Bool {
        [.watching, .approaching, .confirmed, .invalidated, .setupExpired].contains(state)
    }
}

public enum V3SetupLifecycle {
    /// Validates a replayed setup stream after sorting by durable record time. It
    /// rejects duplicate/conflicting updates and prevents a terminal setup from
    /// silently returning to a tradeable state after restart.
    public static func validationIssues(for events: [V3SetupLifecycleEvent]) -> [String] {
        guard !events.isEmpty else { return [] }
        var issues = events.flatMap { $0.validation() }
        var uniqueEvents: [String: V3SetupLifecycleEvent] = [:]
        for event in events {
            if let existing = uniqueEvents[event.id], existing != event {
                issues.append("event_id_conflict")
            } else {
                uniqueEvents[event.id] = event
            }
        }
        let ordered = uniqueEvents.values.sorted {
            if $0.strategyID == "ORB_BREAK_RETEST_V1", $1.strategyID == "ORB_BREAK_RETEST_V1",
               let left = $0.sourceTime, let right = $1.sourceTime, left != right { return left < right }
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            if let left = $0.quoteSequence, let right = $1.quoteSequence, left != right { return left < right }
            return $0.id < $1.id
        }
        for pair in zip(ordered, ordered.dropFirst())
        where pair.0.recordedAt == pair.1.recordedAt
            && !(pair.0.strategyID == "ORB_BREAK_RETEST_V1"
                 && pair.1.strategyID == "ORB_BREAK_RETEST_V1"
                 && pair.0.sourceTime != nil && pair.1.sourceTime != nil
                 && pair.0.sourceTime != pair.1.sourceTime) {
            guard let leftSequence = pair.0.quoteSequence, let rightSequence = pair.1.quoteSequence,
                  leftSequence != rightSequence else {
                issues.append("ambiguous_recorded_time")
                continue
            }
        }
        guard let first = ordered.first else { return Array(Set(issues)).sorted() }
        var current: V3SetupState?
        var priorRecordedAt: Date?
        var priorSourceTime: Date?
        var priorQuoteSequence: UInt64?
        for event in ordered {
            if event.setupID != first.setupID || event.instrument != first.instrument
                || event.strategyID != first.strategyID || event.strategyVersion != first.strategyVersion
                || event.provider != first.provider || event.environment != first.environment
                || event.configurationDigest != first.configurationDigest
                || event.engineVersion != first.engineVersion || event.structureID != first.structureID
                || event.timeframeSeconds != first.timeframeSeconds
                || event.evidenceSchemaVersion != first.evidenceSchemaVersion {
                issues.append("setup_identity_changed")
            }
            if let priorRecordedAt, event.recordedAt < priorRecordedAt {
                issues.append("recorded_time_out_of_order")
            }
            if event.previousState != current { issues.append("predecessor_state_mismatch") }
            if let current, !transitionAllowed(from: current, to: event.state, event: event) {
                issues.append("invalid_replayed_transition")
            }
            if let sourceTime = event.sourceTime, let priorSourceTime {
                if sourceTime < priorSourceTime { issues.append("source_time_out_of_order") }
                if event.strategyID == "ORB_BREAK_RETEST_V1", sourceTime <= priorSourceTime {
                    issues.append("orb_source_time_not_strictly_increasing")
                }
            }
            if let seq = event.quoteSequence, let priorQuoteSequence {
                if seq < priorQuoteSequence { issues.append("quote_sequence_out_of_order") }
                if event.sourceTime == priorSourceTime && seq <= priorQuoteSequence {
                    issues.append("same_source_sequence_not_increasing")
                }
            }
            current = event.state
            priorRecordedAt = event.recordedAt
            priorSourceTime = event.sourceTime ?? priorSourceTime
            priorQuoteSequence = event.quoteSequence ?? priorQuoteSequence
        }
        return Array(Set(issues)).sorted()
    }

    /// Validates archive-wide ORB structure identity in addition to each setup
    /// stream. A later configuration cannot reopen a structure already terminal.
    public static func archiveValidationIssues(for events: [V3SetupLifecycleEvent]) -> [String] {
        var issues = events.flatMap { $0.validation() }
        for stream in Dictionary(grouping: events, by: \.setupID).values {
            issues += validationIssues(for: stream)
        }
        let orbByStructure = Dictionary(grouping: events.filter {
            $0.strategyID == "ORB_BREAK_RETEST_V1" && $0.structureID != nil
        }, by: { $0.structureID ?? "" })
        for stream in orbByStructure.values {
            let terminalEvents = stream.filter { [.confirmed, .invalidated, .setupExpired].contains($0.state) }
            for terminal in terminalEvents {
                guard let terminalTime = terminal.sourceTime else { continue }
                if stream.contains(where: { event in
                    event.setupID != terminal.setupID
                        && (event.sourceTime.map { $0 >= terminalTime } ?? true)
                }) {
                    issues.append("orb_terminal_structure_rearmed")
                }
            }
        }
        return Array(Set(issues)).sorted()
    }

    fileprivate static func transitionAllowed(from previous: V3SetupState, to next: V3SetupState,
                                                event: V3SetupLifecycleEvent) -> Bool {
        if event.strategyID == "ORB_BREAK_RETEST_V1" {
            guard event.hasCompleteEvaluatorProvenance else { return false }
            switch (previous, next) {
            case (.watching, .approaching), (.watching, .confirmed),
                 (.watching, .invalidated), (.watching, .setupExpired),
                 (.approaching, .confirmed), (.approaching, .invalidated),
                 (.approaching, .setupExpired): return true
            default: return false
            }
        }
        if previous.canTransition(to: next) { return true }
        guard event.strategyID == "BREAKOUT_ACCEPTANCE_V1", event.hasCompleteEvaluatorProvenance else { return false }
        switch (previous, next) {
        case (.watching, .approaching), (.watching, .confirmed),
             (.forming, .confirmed), (.stale, .approaching), (.stale, .confirmed),
             (.stale, .invalidated), (.stale, .setupExpired):
            return true
        default:
            return false
        }
    }
}

public enum V3ProviderEnvironment: String, Codable, Sendable {
    case oandaPractice = "OANDA_PRACTICE"
    case oandaLive = "OANDA_LIVE"
    case tradingView = "TRADINGVIEW"
    case simulated = "SIMULATED"
    case unknown = "UNKNOWN"
}

public enum V3EvidenceKind: String, Codable, Sendable {
    case marketObservation = "MARKET_OBSERVATION"
    case signal = "SIGNAL"
    case plan = "TRADE_PLAN"
    case manualTradeReport = "MANUAL_TRADE_REPORT"
    case manualTradeCloseReport = "MANUAL_TRADE_CLOSE_REPORT"
    case brokerExecution = "BROKER_EXECUTION"
    case exitObservation = "EXIT_OBSERVATION"
    case outcome = "OUTCOME"
}

/// Immutable user assertion that a position was closed outside BlazerOS.
/// This record is not a broker close or a simulated structural outcome.
public struct V3UserReportedPositionClose: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let positionID: String
    public let planID: String
    /// Exact immutable opening revision observed when this close chain began.
    public let openingRecordID: String
    /// Previous close report in this close-correction chain; nil only at its root.
    public let supersedesCloseID: String?
    public let exitPrice: Double?
    /// User-reported effective close time. Nil remains explicitly unknown.
    public let closedAt: Date?
    public let provenance: V3EvidenceKind
    /// Time the user report was durably recorded, distinct from `closedAt`.
    public let recordedAt: Date

    public init(id: String, positionID: String, planID: String, openingRecordID: String,
                supersedesCloseID: String? = nil, exitPrice: Double? = nil,
                closedAt: Date? = nil, provenance: V3EvidenceKind = .manualTradeCloseReport,
                recordedAt: Date) {
        self.id = id
        self.positionID = positionID
        self.planID = planID
        self.openingRecordID = openingRecordID
        self.supersedesCloseID = supersedesCloseID
        self.exitPrice = exitPrice
        self.closedAt = closedAt
        self.provenance = provenance
        self.recordedAt = recordedAt
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || positionID.isEmpty || planID.isEmpty || openingRecordID.isEmpty {
            issues.append("identity_missing")
        }
        if let exitPrice, !exitPrice.isFinite || exitPrice <= 0 {
            issues.append("invalid_user_reported_exit_price")
        }
        if let closedAt, !closedAt.timeIntervalSince1970.isFinite {
            issues.append("invalid_user_reported_close_time")
        }
        if !recordedAt.timeIntervalSince1970.isFinite {
            issues.append("invalid_close_recorded_at")
        }
        if provenance != .manualTradeCloseReport {
            issues.append("user_close_provenance_mismatch")
        }
        if let closedAt, closedAt > recordedAt.addingTimeInterval(1) {
            issues.append("close_time_after_report")
        }
        return issues
    }
}

/// A canonical, bid/ask-aware market observation. It contains no order authority.
public struct V3MarketObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let provider: String
    public let environment: V3ProviderEnvironment
    public let bid: Double
    public let ask: Double
    public let sourceTime: Date
    public let receivedAt: Date
    public let sequence: Int64?

    public init(
        id: String,
        instrument: String,
        provider: String,
        environment: V3ProviderEnvironment,
        bid: Double,
        ask: Double,
        sourceTime: Date,
        receivedAt: Date,
        sequence: Int64? = nil
    ) {
        self.id = id
        self.instrument = instrument
        self.provider = provider
        self.environment = environment
        self.bid = bid
        self.ask = ask
        self.sourceTime = sourceTime
        self.receivedAt = receivedAt
        self.sequence = sequence
    }

    public var spread: Double { ask - bid }
    public var mid: Double { (bid + ask) / 2 }

    public func validation(now: Date, maxAge: TimeInterval = 5) -> [String] {
        var issues: [String] = []
        if instrument.isEmpty { issues.append("instrument_missing") }
        if provider.isEmpty { issues.append("provider_missing") }
        if !bid.isFinite || !ask.isFinite || bid <= 0 || ask <= bid {
            issues.append("invalid_bid_ask")
        }
        if !sourceTime.timeIntervalSince1970.isFinite || !receivedAt.timeIntervalSince1970.isFinite {
            issues.append("invalid_timestamp")
        }
        if sourceTime > now.addingTimeInterval(1) { issues.append("future_source_time") }
        if receivedAt > now.addingTimeInterval(1) { issues.append("future_received_time") }
        if now.timeIntervalSince(sourceTime) > maxAge { issues.append("stale_source") }
        if sourceTime > receivedAt.addingTimeInterval(1) { issues.append("source_after_receipt") }
        return issues
    }
}

public enum V3OutcomeQuality: String, Codable, Sendable {
    case brokerConfirmed = "BROKER_CONFIRMED"
    case manual = "MANUAL"
    case observed = "OBSERVED"
    case simulated = "SIMULATED"
    case proxy = "PROXY"
    case ambiguous = "AMBIGUOUS"
    case unresolved = "UNRESOLVED"
}

/// Evidence quality is explicit so a proxy or missing observation cannot become a broker result.
public struct V3OutcomeRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let quality: V3OutcomeQuality
    public let entryObservationID: String?
    public let exitObservationID: String?
    public let reason: String?
    public let recordedAt: Date

    public init(
        id: String,
        planID: String,
        quality: V3OutcomeQuality,
        entryObservationID: String? = nil,
        exitObservationID: String? = nil,
        reason: String? = nil,
        recordedAt: Date
    ) {
        self.id = id
        self.planID = planID
        self.quality = quality
        self.entryObservationID = entryObservationID
        self.exitObservationID = exitObservationID
        self.reason = reason
        self.recordedAt = recordedAt
    }

    public var canAffectVerifiedPerformance: Bool {
        quality == .brokerConfirmed || quality == .observed
    }
}

public enum V3SpotSide: String, Codable, Sendable {
    case long = "LONG"
    case short = "SHORT"
}

public enum V3SpotEvaluationStatus: String, Codable, Sendable {
    case valid = "VALID"
    case ambiguous = "AMBIGUOUS"
    case unresolved = "UNRESOLVED"
}

/// Cost-aware spot result. Entry and exit are executable sides, not midpoint proxies.
public struct V3SpotEvaluation: Codable, Sendable, Equatable {
    public let status: V3SpotEvaluationStatus
    public let side: V3SpotSide
    public let units: Double
    public let entryPrice: Double?
    public let exitPrice: Double?
    public let netPriceChange: Double?
    public let notionalPnl: Double?
    public let reason: String?

    public init(status: V3SpotEvaluationStatus, side: V3SpotSide, units: Double,
                entryPrice: Double? = nil, exitPrice: Double? = nil,
                netPriceChange: Double? = nil, notionalPnl: Double? = nil,
                reason: String? = nil) {
        self.status = status
        self.side = side
        self.units = units
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.netPriceChange = netPriceChange
        self.notionalPnl = notionalPnl
        self.reason = reason
    }
}

/// Durable V3 result envelope. This is intentionally not `ResearchOutcome`: the latter
/// remains the legacy midpoint/CALL-PUT archive and must not be reinterpreted as spot FX.
public struct V3DurableSpotOutcome: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let instrument: String
    public let provider: String
    public let environment: V3ProviderEnvironment
    public let entryObservation: V3MarketObservation?
    public let exitObservation: V3MarketObservation?
    public let evaluation: V3SpotEvaluation
    public let strategyVersion: String
    public let engineVersion: String
    public let recordedAt: Date

    public init(id: String, planID: String, instrument: String, provider: String,
                environment: V3ProviderEnvironment, entryObservation: V3MarketObservation?,
                exitObservation: V3MarketObservation?, evaluation: V3SpotEvaluation,
                strategyVersion: String, engineVersion: String, recordedAt: Date) {
        self.id = id
        self.planID = planID
        self.instrument = instrument
        self.provider = provider
        self.environment = environment
        self.entryObservation = entryObservation
        self.exitObservation = exitObservation
        self.evaluation = evaluation
        self.strategyVersion = strategyVersion
        self.engineVersion = engineVersion
        self.recordedAt = recordedAt
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty { issues.append("id_missing") }
        if planID.isEmpty { issues.append("plan_missing") }
        if instrument.isEmpty || provider.isEmpty { issues.append("provenance_missing") }
        if strategyVersion.isEmpty || engineVersion.isEmpty { issues.append("version_missing") }
        if let entryObservation {
            if entryObservation.instrument != instrument { issues.append("entry_instrument_mismatch") }
            if entryObservation.environment != environment { issues.append("entry_environment_mismatch") }
        }
        if let exitObservation {
            if exitObservation.instrument != instrument { issues.append("exit_instrument_mismatch") }
            if exitObservation.environment != environment { issues.append("exit_environment_mismatch") }
        }
        if evaluation.status == .valid && (entryObservation == nil || exitObservation == nil) {
            issues.append("valid_result_missing_observation")
        }
        return issues
    }
}

public enum V3StructuralOutcomeStatus: String, Codable, Sendable, Equatable {
    case winner = "WINNER"
    case loser = "LOSER"
    case untriggered = "UNTRIGGERED"
    case ambiguous = "AMBIGUOUS"
    case unresolved = "UNRESOLVED"
}

public enum V3StructuralExitReason: String, Codable, Sendable, Equatable {
    case takeProfit = "TAKE_PROFIT"
    case stopLoss = "STOP_LOSS"
    case noTrigger = "NO_TRIGGER"
    case ambiguousTiming = "AMBIGUOUS_TIMING"
    case missingQuote = "MISSING_QUOTE"
    case staleEvidence = "STALE_EVIDENCE"
    case invalidEvidence = "INVALID_EVIDENCE"
    case instrumentMismatch = "INSTRUMENT_MISMATCH"
}

/// Immutable market evidence for a hypothetical shadow-entry reference. It does
/// not establish user intent, an order, a fill, or a position.
public struct V3PlanEntryEvidence: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let observation: V3MarketObservation
    public let quality: V3OutcomeQuality
    public let recordedAt: Date

    public init(id: String, planID: String, observation: V3MarketObservation,
                quality: V3OutcomeQuality = .simulated, recordedAt: Date) {
        self.id = id
        self.planID = planID
        self.observation = observation
        self.quality = quality
        self.recordedAt = recordedAt
    }
}

/// Cost-adjusted structural evaluation. P&L is always based on executable sides:
/// long ask -> bid and short bid -> ask. Midpoint values are deliberately absent.
public struct V3StructuralOutcome: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let planID: String
    public let instrument: String
    public let strategyVersion: String
    public let engineVersion: String
    public let quality: V3OutcomeQuality
    public let status: V3StructuralOutcomeStatus
    public let exitReason: V3StructuralExitReason
    public let entryObservation: V3MarketObservation?
    public let exitObservation: V3MarketObservation?
    public let entryPrice: Double?
    public let exitPrice: Double?
    public let netPnl: Double?
    public let spreadCost: Double?
    public let additionalCosts: Double?
    public let recordedAt: Date

    public init(id: String, planID: String, instrument: String, strategyVersion: String,
                engineVersion: String, quality: V3OutcomeQuality,
                status: V3StructuralOutcomeStatus, exitReason: V3StructuralExitReason,
                entryObservation: V3MarketObservation?, exitObservation: V3MarketObservation?,
                entryPrice: Double?, exitPrice: Double?, netPnl: Double?,
                spreadCost: Double?, additionalCosts: Double?, recordedAt: Date) {
        self.id = id
        self.planID = planID
        self.instrument = instrument
        self.strategyVersion = strategyVersion
        self.engineVersion = engineVersion
        self.quality = quality
        self.status = status
        self.exitReason = exitReason
        self.entryObservation = entryObservation
        self.exitObservation = exitObservation
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.netPnl = netPnl
        self.spreadCost = spreadCost
        self.additionalCosts = additionalCosts
        self.recordedAt = recordedAt
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || planID.isEmpty || instrument.isEmpty { issues.append("identity_missing") }
        if strategyVersion.isEmpty || engineVersion.isEmpty { issues.append("version_missing") }
        if status == .winner || status == .loser {
            if entryObservation == nil || exitObservation == nil || netPnl == nil {
                issues.append("resolved_outcome_missing_evidence")
            }
        }
        if let entryObservation, entryObservation.instrument != instrument { issues.append("entry_instrument_mismatch") }
        if let exitObservation, exitObservation.instrument != instrument { issues.append("exit_instrument_mismatch") }
        return issues
    }
}

public enum V3StructuralOutcomeEvaluator {
    public static func evaluate(plan: V3TradePlan, entry: V3PlanEntryEvidence?,
                                exitQuotes: [V3MarketObservation], asOf: Date,
                                quality: V3OutcomeQuality = .simulated,
                                additionalCostPerUnit: Double = 0,
                                maximumEvidenceAge: TimeInterval = 10,
                                entryFreshnessAtReceipt: Bool = false) -> V3StructuralOutcome {
        let baseID = "\(plan.id)-structural"
        guard plan.validation().isEmpty else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .invalidEvidence,
                              entry: entry?.observation, recordedAt: asOf)
        }
        guard let entry, entry.planID == plan.id,
              entry.observation.instrument == plan.instrument else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .instrumentMismatch,
                              entry: entry?.observation, recordedAt: asOf)
        }
        guard additionalCostPerUnit.isFinite, additionalCostPerUnit >= 0 else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .invalidEvidence,
                              entry: entry.observation, recordedAt: asOf)
        }
        let entryFreshnessAsOf = entryFreshnessAtReceipt ? entry.observation.receivedAt : asOf
        guard fresh(entry.observation, asOf: entryFreshnessAsOf,
                    maximumAge: maximumEvidenceAge),
              validSpread(entry.observation, maximum: plan.maxSpread) else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .staleEvidence,
                              entry: entry.observation, recordedAt: asOf)
        }
        let ordered = exitQuotes.sorted { ($0.sourceTime, $0.id) < ($1.sourceTime, $1.id) }
        guard !ordered.isEmpty else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .missingQuote,
                              entry: entry.observation, recordedAt: asOf)
        }
        guard ordered.allSatisfy({ fresh($0, asOf: asOf, maximumAge: maximumEvidenceAge) }) else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .staleEvidence,
                              entry: entry.observation, recordedAt: asOf)
        }
        guard ordered.allSatisfy({ $0.instrument == plan.instrument && $0.sourceTime >= entry.observation.sourceTime }) else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .instrumentMismatch,
                              entry: entry.observation, recordedAt: asOf)
        }
        let trigger = ordered.compactMap { quote -> (V3MarketObservation, V3StructuralExitReason)? in
            let executable = plan.side == .long ? quote.bid : quote.ask
            if plan.side == .long, executable >= plan.targetPrice { return (quote, .takeProfit) }
            if plan.side == .long, executable <= plan.stopPrice { return (quote, .stopLoss) }
            if plan.side == .short, executable <= plan.targetPrice { return (quote, .takeProfit) }
            if plan.side == .short, executable >= plan.stopPrice { return (quote, .stopLoss) }
            return nil
        }
        guard let first = trigger.first else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .noTrigger,
                              entry: entry.observation, status: .untriggered, recordedAt: asOf)
        }
        let sameTime = trigger.filter { $0.0.sourceTime == first.0.sourceTime }
        guard Set(sameTime.map(\.1)).count == 1 else {
            return unresolved(id: baseID, plan: plan, quality: quality, reason: .ambiguousTiming,
                              entry: entry.observation, status: .ambiguous, recordedAt: asOf)
        }
        let exit = first.0
        let entryPrice = plan.side == .long ? entry.observation.ask : entry.observation.bid
        let exitPrice = plan.side == .long ? exit.bid : exit.ask
        let direction = plan.side == .long ? 1.0 : -1.0
        let netPnl = (exitPrice - entryPrice) * direction * plan.units
            - additionalCostPerUnit * plan.units
        let spreadCost = (entry.observation.spread + exit.spread) * plan.units
        let reasonID = first.1.rawValue.replacingOccurrences(of: "_", with: "-").lowercased()
        return V3StructuralOutcome(id: "\(baseID)-\(reasonID)", planID: plan.id,
            instrument: plan.instrument, strategyVersion: plan.strategyVersion,
            engineVersion: plan.engineVersion, quality: quality,
            status: first.1 == .takeProfit ? .winner : .loser,
            exitReason: first.1, entryObservation: entry.observation,
            exitObservation: exit, entryPrice: entryPrice, exitPrice: exitPrice,
            netPnl: netPnl, spreadCost: spreadCost,
            additionalCosts: additionalCostPerUnit * plan.units, recordedAt: asOf)
    }

    private static func unresolved(id: String, plan: V3TradePlan, quality: V3OutcomeQuality,
                                  reason: V3StructuralExitReason, entry: V3MarketObservation?,
                                  status: V3StructuralOutcomeStatus = .unresolved,
                                  recordedAt: Date) -> V3StructuralOutcome {
        V3StructuralOutcome(id: id, planID: plan.id, instrument: plan.instrument,
            strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
            quality: quality, status: status, exitReason: reason,
            entryObservation: entry, exitObservation: nil, entryPrice: nil, exitPrice: nil,
            netPnl: nil, spreadCost: nil, additionalCosts: nil, recordedAt: recordedAt)
    }

    private static func fresh(_ observation: V3MarketObservation, asOf: Date,
                              maximumAge: TimeInterval) -> Bool {
        observation.validation(now: asOf, maxAge: maximumAge).isEmpty
    }

    private static func validSpread(_ observation: V3MarketObservation, maximum: Double) -> Bool {
        observation.spread.isFinite && observation.spread >= 0 && observation.spread <= maximum
    }
}

public enum V3SpotOutcomeEvaluator {
    /// Evaluates long ask→bid or short bid→ask. It never infers a fill or resolves
    /// missing/late observations, and has no order authority.
    public static func evaluate(side: V3SpotSide, units: Double,
                                entry: V3MarketObservation?, exit: V3MarketObservation?,
                                expectedExitAt: Date? = nil,
                                maximumExitDelay: TimeInterval = 5) -> V3SpotEvaluation {
        guard units.isFinite, units > 0 else {
            return .init(status: .unresolved, side: side, units: units, reason: "invalid_units")
        }
        guard let entry, let exit else {
            return .init(status: .unresolved, side: side, units: units, reason: "missing_observation")
        }
        guard entry.instrument == exit.instrument, entry.environment == exit.environment else {
            return .init(status: .unresolved, side: side, units: units, reason: "observation_identity_mismatch")
        }
        guard entry.validation(now: entry.receivedAt).isEmpty,
              exit.validation(now: exit.receivedAt).isEmpty else {
            return .init(status: .unresolved, side: side, units: units, reason: "invalid_observation")
        }
        guard exit.sourceTime >= entry.sourceTime else {
            return .init(status: .unresolved, side: side, units: units, reason: "out_of_order_source_time")
        }
        if let expectedExitAt {
            guard exit.sourceTime >= expectedExitAt,
                  exit.sourceTime.timeIntervalSince(expectedExitAt) <= maximumExitDelay else {
                return .init(status: .unresolved, side: side, units: units, reason: "no_timely_exit_observation")
            }
        }
        let entryPrice: Double
        let exitPrice: Double
        let change: Double
        switch side {
        case .long:
            entryPrice = entry.ask
            exitPrice = exit.bid
            change = exitPrice - entryPrice
        case .short:
            entryPrice = entry.bid
            exitPrice = exit.ask
            change = entryPrice - exitPrice
        }
        guard change.isFinite else {
            return .init(status: .unresolved, side: side, units: units, reason: "nonfinite_result")
        }
        return .init(status: .valid, side: side, units: units,
            entryPrice: entryPrice, exitPrice: exitPrice,
            netPriceChange: change, notionalPnl: change * units)
    }
}

public struct V3TradePlan: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let strategyID: String
    public let strategyVersion: String
    public let engineVersion: String
    public let sourceObservationID: String
    public let state: V3TradePlanState
    public let side: V3SpotSide
    public let entryPrice: Double
    public let stopPrice: Double
    public let targetPrice: Double
    public let units: Double
    public let maxSpread: Double
    /// Maximum distance from the planned entry for a shadow market reference.
    /// Nil on older plans, which remain decodable but cannot create this evidence.
    public let maxEntryDeviation: Double?
    public let riskFraction: Double
    public let evidenceIDs: [String]
    public let createdAt: Date

    public init(id: String, instrument: String, strategyID: String, strategyVersion: String,
                engineVersion: String, sourceObservationID: String, state: V3TradePlanState,
                side: V3SpotSide, entryPrice: Double, stopPrice: Double, targetPrice: Double,
                units: Double, maxSpread: Double, riskFraction: Double,
                maxEntryDeviation: Double? = nil, evidenceIDs: [String] = [], createdAt: Date) {
        self.id = id
        self.instrument = instrument
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.engineVersion = engineVersion
        self.sourceObservationID = sourceObservationID
        self.state = state
        self.side = side
        self.entryPrice = entryPrice
        self.stopPrice = stopPrice
        self.targetPrice = targetPrice
        self.units = units
        self.maxSpread = maxSpread
        self.maxEntryDeviation = maxEntryDeviation
        self.riskFraction = riskFraction
        self.evidenceIDs = evidenceIDs
        self.createdAt = createdAt
    }

    public var rewardRisk: Double? {
        let risk = abs(entryPrice - stopPrice)
        guard risk.isFinite, risk > 0 else { return nil }
        let reward = abs(targetPrice - entryPrice)
        return reward.isFinite ? reward / risk : nil
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if instrument.isEmpty { issues.append("instrument_missing") }
        if strategyID.isEmpty || strategyVersion.isEmpty { issues.append("strategy_identity_missing") }
        if engineVersion.isEmpty { issues.append("engine_version_missing") }
        if sourceObservationID.isEmpty { issues.append("source_observation_missing") }
        if ![entryPrice, stopPrice, targetPrice].allSatisfy({ $0.isFinite && $0 > 0 }) {
            issues.append("invalid_price_levels")
        }
        if !units.isFinite || units <= 0 { issues.append("invalid_units") }
        if !maxSpread.isFinite || maxSpread <= 0 { issues.append("invalid_max_spread") }
        if let maxEntryDeviation, !maxEntryDeviation.isFinite || maxEntryDeviation <= 0 {
            issues.append("invalid_max_entry_deviation")
        }
        if !riskFraction.isFinite || riskFraction <= 0 || riskFraction > 1 { issues.append("invalid_risk_fraction") }
        switch side {
        case .long:
            if !(stopPrice < entryPrice && entryPrice < targetPrice) { issues.append("invalid_long_structure") }
        case .short:
            if !(targetPrice < entryPrice && entryPrice < stopPrice) { issues.append("invalid_short_structure") }
        }
        if rewardRisk == nil { issues.append("invalid_reward_risk") }
        return issues
    }
}

public struct V3RiskSizingRequest: Codable, Sendable, Equatable {
    public let accountBalanceUSD: Double
    public let riskFraction: Double
    public let entryPrice: Double
    public let stopPrice: Double
    public let accountRiskPerPriceUnit: Double
    public let estimatedCostPerUnit: Double
    public let minimumUnits: Double
    public let maximumUnits: Double?
    public let availableMarginUSD: Double
    public let marginPerUnitUSD: Double

    public init(accountBalanceUSD: Double, riskFraction: Double, entryPrice: Double,
                stopPrice: Double, accountRiskPerPriceUnit: Double,
                estimatedCostPerUnit: Double, minimumUnits: Double,
                maximumUnits: Double? = nil, availableMarginUSD: Double,
                marginPerUnitUSD: Double) {
        self.accountBalanceUSD = accountBalanceUSD
        self.riskFraction = riskFraction
        self.entryPrice = entryPrice
        self.stopPrice = stopPrice
        self.accountRiskPerPriceUnit = accountRiskPerPriceUnit
        self.estimatedCostPerUnit = estimatedCostPerUnit
        self.minimumUnits = minimumUnits
        self.maximumUnits = maximumUnits
        self.availableMarginUSD = availableMarginUSD
        self.marginPerUnitUSD = marginPerUnitUSD
    }
}

public struct V3RiskSizingResult: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let riskBudgetUSD: Double
    public let units: Double
    public let estimatedWorstCaseLossUSD: Double?
    public let estimatedMarginUSD: Double?
    public let rejectionReason: String?
}

public enum V3RiskSizer {
    public static func size(_ request: V3RiskSizingRequest) -> V3RiskSizingResult {
        let values = [request.accountBalanceUSD, request.riskFraction, request.entryPrice,
            request.stopPrice, request.accountRiskPerPriceUnit, request.estimatedCostPerUnit,
            request.minimumUnits, request.availableMarginUSD, request.marginPerUnitUSD]
        guard values.allSatisfy({ $0.isFinite }), request.accountBalanceUSD > 0,
              request.riskFraction > 0, request.riskFraction <= 1,
              request.entryPrice > 0, request.stopPrice > 0,
              request.accountRiskPerPriceUnit > 0, request.estimatedCostPerUnit >= 0,
              request.minimumUnits > 0, request.availableMarginUSD >= 0,
              request.marginPerUnitUSD >= 0,
              request.maximumUnits.map({ $0 >= request.minimumUnits && $0.isFinite }) ?? true else {
            return .init(accepted: false, riskBudgetUSD: 0, units: 0,
                estimatedWorstCaseLossUSD: nil, estimatedMarginUSD: nil,
                rejectionReason: "invalid_sizing_input")
        }
        let budget = request.accountBalanceUSD * request.riskFraction
        let stopRisk = abs(request.entryPrice - request.stopPrice) * request.accountRiskPerPriceUnit
        let riskPerUnit = stopRisk + request.estimatedCostPerUnit
        guard riskPerUnit.isFinite, riskPerUnit > 0 else {
            return .init(accepted: false, riskBudgetUSD: budget, units: 0,
                estimatedWorstCaseLossUSD: nil, estimatedMarginUSD: nil,
                rejectionReason: "invalid_stop_distance")
        }
        var units = floor(budget / riskPerUnit / request.minimumUnits) * request.minimumUnits
        if let maximumUnits = request.maximumUnits { units = min(units, maximumUnits) }
        let loss = units * riskPerUnit
        let margin = units * request.marginPerUnitUSD
        guard units >= request.minimumUnits else {
            return .init(accepted: false, riskBudgetUSD: budget, units: 0,
                estimatedWorstCaseLossUSD: loss, estimatedMarginUSD: margin,
                rejectionReason: "risk_budget_below_minimum")
        }
        guard margin <= request.availableMarginUSD else {
            return .init(accepted: false, riskBudgetUSD: budget, units: 0,
                estimatedWorstCaseLossUSD: loss, estimatedMarginUSD: margin,
                rejectionReason: "insufficient_margin")
        }
        return .init(accepted: true, riskBudgetUSD: budget, units: units,
            estimatedWorstCaseLossUSD: loss, estimatedMarginUSD: margin, rejectionReason: nil)
    }
}

public enum V3TradePlanState: String, Codable, Sendable, CaseIterable {
    case draft = "DRAFT"
    case validated = "VALIDATED"
    case offered = "OFFERED"
    case triggered = "TRIGGERED"
    case invalidated = "INVALIDATED"
    case expired = "EXPIRED"

    public func canTransition(to next: V3TradePlanState) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.draft, .validated), (.draft, .invalidated),
             (.validated, .offered), (.validated, .invalidated), (.validated, .expired),
             (.offered, .triggered), (.offered, .invalidated), (.offered, .expired):
            return true
        default:
            return false
        }
    }
}

public enum V3PositionState: String, Codable, Sendable, CaseIterable {
    case notOpen = "NOT_OPEN"
    case userReported = "USER_REPORTED"
    case brokerPending = "BROKER_PENDING"
    case unconfirmed = "UNCONFIRMED"
    case brokerOpen = "BROKER_OPEN"
    case exitRequested = "EXIT_REQUESTED"
    case brokerClosed = "BROKER_CLOSED"
    case reconciliationRequired = "RECONCILIATION_REQUIRED"
    case unknown = "UNKNOWN"

    public func canTransition(to next: V3PositionState) -> Bool {
        if self == next { return true }
        switch (self, next) {
        case (.notOpen, .userReported), (.notOpen, .unknown),
             (.userReported, .brokerPending), (.userReported, .unconfirmed),
             (.userReported, .reconciliationRequired), (.userReported, .unknown),
             (.brokerPending, .brokerOpen), (.brokerPending, .unconfirmed),
             (.brokerPending, .reconciliationRequired), (.brokerPending, .unknown),
             (.unconfirmed, .brokerOpen), (.unconfirmed, .reconciliationRequired), (.unconfirmed, .unknown),
             (.brokerOpen, .exitRequested), (.brokerOpen, .reconciliationRequired), (.brokerOpen, .unknown),
             (.exitRequested, .brokerClosed), (.exitRequested, .reconciliationRequired), (.exitRequested, .unknown),
             (.reconciliationRequired, .brokerPending), (.reconciliationRequired, .brokerOpen),
             (.reconciliationRequired, .brokerClosed), (.reconciliationRequired, .unknown),
             (.unknown, .reconciliationRequired):
            return true
        default:
            return false
        }
    }
}

/// A position lifecycle event is deliberately separate from a proposed V3TradePlan.
/// User reports, practice fills, and broker-confirmed fills cannot be conflated.
public struct V3PositionRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// Stable identity for one logical user-reported position. Nil on legacy/broker rows.
    public let positionID: String?
    public let planID: String?
    /// Immutable predecessor record for a manual correction. Nil on each chain root.
    public let supersedesRecordID: String?
    public let instrument: String
    public let state: V3PositionState
    public let side: V3SpotSide
    public let units: Double
    public let broker: String?
    public let brokerPositionID: String?
    public let entryPrice: Double?
    /// User-reported execution time; distinct from `updatedAt` (the report timestamp).
    public let userReportedEnteredAt: Date?
    public let exitPrice: Double?
    public let provenance: V3EvidenceKind
    public let updatedAt: Date

    public init(id: String, positionID: String? = nil, planID: String? = nil,
                supersedesRecordID: String? = nil, instrument: String,
                state: V3PositionState, side: V3SpotSide, units: Double,
                broker: String? = nil, brokerPositionID: String? = nil,
                entryPrice: Double? = nil, userReportedEnteredAt: Date? = nil,
                exitPrice: Double? = nil,
                provenance: V3EvidenceKind, updatedAt: Date) {
        self.id = id
        self.positionID = positionID
        self.planID = planID
        self.supersedesRecordID = supersedesRecordID
        self.instrument = instrument
        self.state = state
        self.side = side
        self.units = units
        self.broker = broker
        self.brokerPositionID = brokerPositionID
        self.entryPrice = entryPrice
        self.userReportedEnteredAt = userReportedEnteredAt
        self.exitPrice = exitPrice
        self.provenance = provenance
        self.updatedAt = updatedAt
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || instrument.isEmpty { issues.append("identity_missing") }
        if !units.isFinite || units <= 0 { issues.append("invalid_units") }
        if let entryPrice, !entryPrice.isFinite || entryPrice <= 0 { issues.append("invalid_entry_price") }
        if let userReportedEnteredAt,
           !userReportedEnteredAt.timeIntervalSince1970.isFinite {
            issues.append("invalid_user_reported_entry_time")
        }
        if state == .userReported {
            if provenance != .manualTradeReport { issues.append("user_report_provenance_mismatch") }
            if broker != nil || brokerPositionID != nil { issues.append("user_report_contains_broker_identity") }
            if exitPrice != nil { issues.append("user_report_contains_exit_price") }
        }
        if positionID != nil {
            if state != .userReported || provenance != .manualTradeReport
                || planID == nil || broker != nil || brokerPositionID != nil || exitPrice != nil {
                issues.append("invalid_user_report_identity")
            }
        }
        if state == .brokerOpen || state == .brokerClosed,
           (broker ?? "").isEmpty || (brokerPositionID ?? "").isEmpty {
            issues.append("broker_identity_missing")
        }
        if state == .brokerClosed && exitPrice == nil { issues.append("closed_exit_missing") }
        return issues
    }
}
