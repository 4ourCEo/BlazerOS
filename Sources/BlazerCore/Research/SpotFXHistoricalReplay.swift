import Foundation

/// Explicit assumptions for a fixed-horizon spot-FX replay. This path is
/// deliberately separate from the legacy midpoint `ResearchOutcome` archive.
public struct SpotFXReplayConfiguration: Codable, Sendable, Equatable {
    public let entryDelaySeconds: TimeInterval
    public let horizonSeconds: Int
    public let observationToleranceSeconds: TimeInterval
    public let maximumExitDelaySeconds: TimeInterval
    public let units: Double
    public let additionalCostPerUnit: Double

    public init(entryDelaySeconds: TimeInterval = 3,
                horizonSeconds: Int = 60,
                observationToleranceSeconds: TimeInterval = 2,
                maximumExitDelaySeconds: TimeInterval = 5,
                units: Double = 1,
                additionalCostPerUnit: Double = 0) {
        self.entryDelaySeconds = entryDelaySeconds
        self.horizonSeconds = horizonSeconds
        self.observationToleranceSeconds = observationToleranceSeconds
        self.maximumExitDelaySeconds = maximumExitDelaySeconds
        self.units = units
        self.additionalCostPerUnit = additionalCostPerUnit
    }

    fileprivate var validationError: String? {
        guard entryDelaySeconds.isFinite, entryDelaySeconds >= 0,
              horizonSeconds > 0,
              observationToleranceSeconds.isFinite, observationToleranceSeconds >= 0,
              maximumExitDelaySeconds.isFinite, maximumExitDelaySeconds >= 0,
              units.isFinite, units > 0,
              additionalCostPerUnit.isFinite, additionalCostPerUnit >= 0 else {
            return "Invalid spot-FX replay configuration"
        }
        return nil
    }
}

public enum SpotFXReplayStatus: String, Codable, Sendable, Equatable {
    case valid = "VALID"
    case noSignal = "NO_SIGNAL"
    case unresolved = "UNRESOLVED"
}

/// One source-matched fixed-horizon spot result. A valid result requires
/// executable bid/ask observations at both entry and exit; midpoint-only rows
/// cannot become valid by inference.
public struct SpotFXReplayRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let caseID: String
    public let strategyID: String
    public let instrumentID: String
    public let venueID: String
    public let source: String
    public let signalTimestamp: Date
    public let entryTimestamp: Date?
    public let exitTimestamp: Date?
    public let side: V3SpotSide?
    public let status: SpotFXReplayStatus
    public let entryPrice: Double?
    public let exitPrice: Double?
    public let grossPnl: Double?
    public let transactionCost: Double?
    public let netPnl: Double?
    public let reason: String?

    public init(id: String, caseID: String, strategyID: String, instrumentID: String,
                venueID: String, source: String, signalTimestamp: Date,
                entryTimestamp: Date? = nil, exitTimestamp: Date? = nil,
                side: V3SpotSide? = nil, status: SpotFXReplayStatus,
                entryPrice: Double? = nil, exitPrice: Double? = nil,
                grossPnl: Double? = nil, transactionCost: Double? = nil,
                netPnl: Double? = nil, reason: String? = nil) {
        self.id = id; self.caseID = caseID; self.strategyID = strategyID
        self.instrumentID = instrumentID; self.venueID = venueID; self.source = source
        self.signalTimestamp = signalTimestamp; self.entryTimestamp = entryTimestamp
        self.exitTimestamp = exitTimestamp; self.side = side; self.status = status
        self.entryPrice = entryPrice; self.exitPrice = exitPrice; self.grossPnl = grossPnl
        self.transactionCost = transactionCost; self.netPnl = netPnl; self.reason = reason
    }
}

public enum SpotFXHistoricalReplay {
    public typealias Evaluator = StrategyValidationEngine.Evaluator

    public static func replay(
        cases: [StrategyValidationCase],
        strategyID: String,
        configuration: SpotFXReplayConfiguration = .init(),
        evaluator: @escaping Evaluator = { try await StrategyEngine.evaluate(input: $0).signal }
    ) async throws -> [SpotFXReplayRecord] {
        if let error = configuration.validationError { throw ScanError.failed(error) }
        return try await withThrowingTaskGroup(of: (Int, SpotFXReplayRecord).self,
                                               returning: [SpotFXReplayRecord].self) { group in
            for (index, item) in cases.sorted(by: { $0.signalTimestamp < $1.signalTimestamp }).enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    var input = item.input
                    input.policy = ScanPolicy(rawValue: strategyID)
                    let signal: EngineSignal
                    do {
                        signal = try await evaluator(input)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return (index, unresolved(item, strategyID: strategyID,
                                                  reason: "Engine evaluation failed: \(error.localizedDescription)"))
                    }
                    return (index, evaluate(item, strategyID: strategyID, signal: signal,
                                            configuration: configuration))
                }
            }
            var collected: [(Int, SpotFXReplayRecord)] = []
            for try await value in group { collected.append(value) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func evaluate(_ item: StrategyValidationCase, strategyID: String,
                                 signal: EngineSignal,
                                 configuration: SpotFXReplayConfiguration) -> SpotFXReplayRecord {
        let direction: V3SpotSide?
        switch signal.cabinetSide {
        case "HIGH": direction = .long
        case "LOW": direction = .short
        default: direction = nil
        }
        guard let direction else {
            return unresolved(item, strategyID: strategyID, reason: "Engine returned no directional signal")
        }
        let targetEntry = item.signalTimestamp.addingTimeInterval(configuration.entryDelaySeconds)
        guard let entry = matching(item, target: targetEntry,
                                   tolerance: configuration.observationToleranceSeconds) else {
            return unresolved(item, strategyID: strategyID, side: direction,
                              reason: "Executable bid/ask entry observation missing")
        }
        let targetExit = entry.observedAt.addingTimeInterval(Double(configuration.horizonSeconds))
        guard let exit = matching(item, target: targetExit,
                                  tolerance: configuration.maximumExitDelaySeconds) else {
            return unresolved(item, strategyID: strategyID, side: direction,
                              entry: entry, reason: "Executable bid/ask exit observation missing or late")
        }
        let entryObservation = observation(entry)
        let exitObservation = observation(exit)
        let evaluation = V3SpotOutcomeEvaluator.evaluate(
            side: direction, units: configuration.units,
            entry: entryObservation, exit: exitObservation,
            expectedExitAt: targetExit,
            maximumExitDelay: configuration.maximumExitDelaySeconds)
        guard evaluation.status == .valid, let gross = evaluation.notionalPnl else {
            return unresolved(item, strategyID: strategyID, side: direction,
                              entry: entry, exit: exit, reason: evaluation.reason ?? "Unresolved spot evaluation")
        }
        let cost = configuration.additionalCostPerUnit * configuration.units
        return SpotFXReplayRecord(id: "\(item.id)-\(strategyID)-\(configuration.horizonSeconds)",
            caseID: item.id, strategyID: strategyID, instrumentID: item.instrumentID,
            venueID: item.venueID, source: entry.source, signalTimestamp: item.signalTimestamp,
            entryTimestamp: entry.observedAt, exitTimestamp: exit.observedAt, side: direction,
            status: .valid, entryPrice: evaluation.entryPrice, exitPrice: evaluation.exitPrice,
            grossPnl: gross, transactionCost: cost, netPnl: gross - cost)
    }

    private static func matching(_ item: StrategyValidationCase, target: Date,
                                 tolerance: TimeInterval) -> ValidationPriceObservation? {
        item.observations
            .filter { $0.instrumentID == item.instrumentID && $0.venueID == item.venueID }
            .filter { $0.authority == item.signalPriceAuthority || item.signalPriceAuthority == nil }
            .filter { observation in
                guard let bid = observation.bid, let ask = observation.ask else { return false }
                return observation.price.isFinite && observation.price > 0
                    && bid.isFinite && ask.isFinite && bid > 0 && ask > bid
            }
            .filter { $0.observedAt >= target && $0.observedAt.timeIntervalSince(target) <= tolerance }
            .sorted { $0.observedAt < $1.observedAt }
            .first
    }

    private static func observation(_ value: ValidationPriceObservation) -> V3MarketObservation {
        V3MarketObservation(id: "\(value.venueID)-\(value.observedAt.timeIntervalSince1970)",
            instrument: value.instrumentID, provider: value.venueID,
            environment: .oandaPractice, bid: value.bid!, ask: value.ask!,
            sourceTime: value.observedAt, receivedAt: value.observedAt)
    }

    private static func unresolved(_ item: StrategyValidationCase, strategyID: String,
                                   side: V3SpotSide? = nil,
                                   entry: ValidationPriceObservation? = nil,
                                   exit: ValidationPriceObservation? = nil,
                                   reason: String) -> SpotFXReplayRecord {
        SpotFXReplayRecord(id: "\(item.id)-\(strategyID)-\(item.input.expirySeconds)",
            caseID: item.id, strategyID: strategyID, instrumentID: item.instrumentID,
            venueID: item.venueID, source: item.provenance, signalTimestamp: item.signalTimestamp,
            entryTimestamp: entry?.observedAt, exitTimestamp: exit?.observedAt, side: side,
            status: .unresolved, reason: reason)
    }
}
