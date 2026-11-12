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
             (.watching, .forming), (.watching, .stale), (.watching, .invalidated),
             (.forming, .approaching), (.forming, .invalidated), (.forming, .stale),
             (.approaching, .confirmed), (.approaching, .invalidated), (.approaching, .stale),
             (.confirmed, .triggered), (.confirmed, .invalidated), (.confirmed, .stale),
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
    case brokerExecution = "BROKER_EXECUTION"
    case exitObservation = "EXIT_OBSERVATION"
    case outcome = "OUTCOME"
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

/// The immutable evidence that a shadow/manual/broker-confirmed plan had an entry
/// observation. It is separate from a plan because a plan is not a fill.
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
                                maximumEvidenceAge: TimeInterval = 10) -> V3StructuralOutcome {
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
        guard fresh(entry.observation, asOf: asOf, maximumAge: maximumEvidenceAge),
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
    public let riskFraction: Double
    public let evidenceIDs: [String]
    public let createdAt: Date

    public init(id: String, instrument: String, strategyID: String, strategyVersion: String,
                engineVersion: String, sourceObservationID: String, state: V3TradePlanState,
                side: V3SpotSide, entryPrice: Double, stopPrice: Double, targetPrice: Double,
                units: Double, maxSpread: Double, riskFraction: Double,
                evidenceIDs: [String] = [], createdAt: Date) {
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
    public let planID: String?
    public let instrument: String
    public let state: V3PositionState
    public let side: V3SpotSide
    public let units: Double
    public let broker: String?
    public let brokerPositionID: String?
    public let entryPrice: Double?
    public let exitPrice: Double?
    public let provenance: V3EvidenceKind
    public let updatedAt: Date

    public init(id: String, planID: String? = nil, instrument: String,
                state: V3PositionState, side: V3SpotSide, units: Double,
                broker: String? = nil, brokerPositionID: String? = nil,
                entryPrice: Double? = nil, exitPrice: Double? = nil,
                provenance: V3EvidenceKind, updatedAt: Date) {
        self.id = id
        self.planID = planID
        self.instrument = instrument
        self.state = state
        self.side = side
        self.units = units
        self.broker = broker
        self.brokerPositionID = brokerPositionID
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.provenance = provenance
        self.updatedAt = updatedAt
    }

    public func validation() -> [String] {
        var issues: [String] = []
        if id.isEmpty || instrument.isEmpty { issues.append("identity_missing") }
        if !units.isFinite || units <= 0 { issues.append("invalid_units") }
        if state == .brokerOpen || state == .brokerClosed,
           (broker ?? "").isEmpty || (brokerPositionID ?? "").isEmpty {
            issues.append("broker_identity_missing")
        }
        if state == .brokerClosed && exitPrice == nil { issues.append("closed_exit_missing") }
        return issues
    }
}
