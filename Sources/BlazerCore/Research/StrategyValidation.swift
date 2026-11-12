import CryptoKit
import Foundation

/// The three evidence stages remain distinct. Moving a record between stages is not a
/// promotion decision and this type has no execution authority.
public enum ValidationStage: String, Codable, Sendable, CaseIterable {
    case historicalReplay
    case paperTrading
    case liveObservation
}

public enum ValidationExecutionKind: String, Codable, Sendable {
    case simulated
    case recordedManual
}

/// Describes what a price can prove. In particular, an OANDA print can never settle a
/// Pocket Option OTC contract.
public enum ValidationPriceAuthority: String, Codable, Sendable {
    case directBroker
    case independentProvider
    case oandaReference
    case manualBrokerObservation
    case syntheticFixture
}

public enum ValidationResolution: String, Codable, Sendable {
    case win, loss, tie, unresolved
}

public enum ValidationTiePolicy: String, Codable, Sendable {
    /// Venue behavior has not been verified. Any tie withholds expectancy/drawdown.
    case unknown
    /// Stake is returned and the tie contributes zero return.
    case refund
    /// Venue scores an unchanged expiry price as a full loss.
    case loss
}

public struct ValidationPriceObservation: Codable, Sendable, Equatable {
    public let instrumentID: String
    public let venueID: String
    public let observedAt: Date
    public let bid: Double?
    public let ask: Double?
    public let price: Double
    public let source: String
    public let authority: ValidationPriceAuthority

    public init(
        instrumentID: String,
        venueID: String,
        observedAt: Date,
        price: Double,
        bid: Double? = nil,
        ask: Double? = nil,
        source: String,
        authority: ValidationPriceAuthority
    ) {
        self.instrumentID = instrumentID
        self.venueID = venueID
        self.observedAt = observedAt
        self.bid = bid
        self.ask = ask
        self.price = price
        self.source = source
        self.authority = authority
    }
}

public struct RecordedValidationExecution: Codable, Sendable, Equatable {
    public let enteredAt: Date
    public let entryPrice: Double
    public let expiryObservedAt: Date?
    public let expiryPrice: Double?
    public let confirmedResolution: ValidationResolution?
    public let venueEventID: String?

    public init(
        enteredAt: Date,
        entryPrice: Double,
        expiryObservedAt: Date? = nil,
        expiryPrice: Double? = nil,
        confirmedResolution: ValidationResolution? = nil,
        venueEventID: String? = nil
    ) {
        self.enteredAt = enteredAt
        self.entryPrice = entryPrice
        self.expiryObservedAt = expiryObservedAt
        self.expiryPrice = expiryPrice
        self.confirmedResolution = confirmedResolution
        self.venueEventID = venueEventID
    }
}

/// A frozen historical decision point. `input` contains only information that was available
/// at `signalTimestamp`; later observations are used solely for simulated execution/settlement.
public struct StrategyValidationCase: Codable, Sendable {
    public let id: String
    public let stage: ValidationStage
    public let instrumentID: String
    public let engineAsset: String
    public let venueID: String
    public let marketKind: ShadowMarketKind
    public let signalTimestamp: Date
    public let engineSHA: String
    public let input: StrategyEngine.MarketInput
    /// Source-declared maximum age for the quote that produced the historical signal.
    /// Nil is retained for decoding old records, but historical replay fails closed.
    public let maximumSignalQuoteAgeSeconds: TimeInterval?
    /// Authority of the quote/history used to create the signal input. Optional only for
    /// archives written before signal-input authority was recorded.
    public let signalPriceAuthority: ValidationPriceAuthority?
    public let observations: [ValidationPriceObservation]
    public let recordedExecution: RecordedValidationExecution?
    public let payoutRatio: Double?
    public let signalCategory: String?
    public let marketRegime: String?
    public let provenance: String

    public init(
        id: String = UUID().uuidString,
        stage: ValidationStage,
        instrumentID: String,
        engineAsset: String,
        venueID: String,
        marketKind: ShadowMarketKind,
        signalTimestamp: Date,
        engineSHA: String,
        input: StrategyEngine.MarketInput,
        maximumSignalQuoteAgeSeconds: TimeInterval? = nil,
        signalPriceAuthority: ValidationPriceAuthority? = nil,
        observations: [ValidationPriceObservation],
        recordedExecution: RecordedValidationExecution? = nil,
        payoutRatio: Double? = nil,
        signalCategory: String? = nil,
        marketRegime: String? = nil,
        provenance: String
    ) {
        self.id = id
        self.stage = stage
        self.instrumentID = instrumentID
        self.engineAsset = engineAsset
        self.venueID = venueID
        self.marketKind = marketKind
        self.signalTimestamp = signalTimestamp
        self.engineSHA = engineSHA
        self.input = input
        self.maximumSignalQuoteAgeSeconds = maximumSignalQuoteAgeSeconds
        self.signalPriceAuthority = signalPriceAuthority
        self.observations = observations
        self.recordedExecution = recordedExecution
        self.payoutRatio = payoutRatio
        self.signalCategory = signalCategory
        self.marketRegime = marketRegime
        self.provenance = provenance
    }
}

public struct StrategyValidationConfiguration: Codable, Sendable, Equatable {
    public let entryDelaySeconds: TimeInterval
    public let expirySeconds: Int
    public let observationToleranceSeconds: TimeInterval
    public let tiePolicy: ValidationTiePolicy

    public init(
        entryDelaySeconds: TimeInterval = 0,
        expirySeconds: Int = 60,
        observationToleranceSeconds: TimeInterval = 2,
        tiePolicy: ValidationTiePolicy = .unknown
    ) {
        self.entryDelaySeconds = entryDelaySeconds
        self.expirySeconds = expirySeconds
        self.observationToleranceSeconds = observationToleranceSeconds
        self.tiePolicy = tiePolicy
    }

    public static let sixtySecond = StrategyValidationConfiguration()
}

public struct StrategyValidationRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let caseID: String
    public let stage: ValidationStage
    public let executionKind: ValidationExecutionKind
    public let instrumentID: String
    public let venueID: String
    public let marketKind: ShadowMarketKind
    public let signalDirection: String
    public let signalTimestamp: Date
    public let entryTimestamp: Date?
    public let entryPrice: Double?
    public let expiryTimestamp: Date?
    public let expiryObservedAt: Date?
    public let expiryPrice: Double?
    public let payoutRatio: Double?
    public let resolution: ValidationResolution
    public let executionDelaySeconds: TimeInterval?
    public let engineSHA: String
    public let inputDigest: String
    public let caseDigest: String
    public let configurationDigest: String
    /// Full replay configuration for reproducibility. Optional for legacy archives.
    public let configuration: StrategyValidationConfiguration?
    /// Optional for backward compatibility with validation archives written before tie
    /// settlement policy was recorded. A missing value is treated as unverified.
    public let tiePolicy: ValidationTiePolicy?
    public let signalPriceAuthority: ValidationPriceAuthority?
    public let venueEventID: String?
    public let dataSource: String
    public let priceAuthority: ValidationPriceAuthority?
    public let signalCategory: String?
    public let marketRegime: String?
    public let rejectionReason: String?
    public let isVenueOutcome: Bool
    public let isSynthetic: Bool
}

public struct StrategyValidationCohort: Codable, Sendable, Equatable {
    public let key: String
    public let resolved: Int
    public let wins: Int
    public let losses: Int
    public let ties: Int
    public let unresolved: Int
    public let winRate: Double?
    public let lower95: Double?
    public let upper95: Double?
    public let candidateBlocks: Int
    public let effectiveSampleSize: Double
    public let payoutAdjustedExpectancy: Double?
    public let breakEvenWinRate: Double?
    public let maximumConsecutiveLosses: Int?
    public let maximumUnitDrawdown: Double?
}

public struct StrategyValidationReport: Codable, Sendable, Equatable {
    public let stage: ValidationStage
    public let total: Int
    public let performanceEligible: Int
    public let excludedDuplicateCases: Int
    public let excludedReferenceOutcomes: Int
    public let syntheticRecords: Int
    public let overall: StrategyValidationCohort
    public let byRegime: [StrategyValidationCohort]
    public let byTimeOfDayUTC: [StrategyValidationCohort]
    public let bySignalCategory: [StrategyValidationCohort]
    public let byExecutionDelay: [StrategyValidationCohort]
    public let sampleWarning: String?
    public var status: String { "INSUFFICIENT EVIDENCE" }
}

/// Compact deterministic facts suitable for the bounded on-device assistant context.
/// The assistant receives no raw price stream and cannot mutate this report.
public struct StrategyValidationSummary: Codable, Sendable, Equatable {
    public let stage: ValidationStage
    public let total: Int
    public let resolved: Int
    public let effectiveSampleSize: Double
    public let payoutAdjustedExpectancy: Double?
    public let breakEvenWinRate: Double?
    public let sampleWarning: String?
    public let status: String

    public init(_ report: StrategyValidationReport) {
        stage = report.stage
        total = report.total
        resolved = report.overall.resolved
        effectiveSampleSize = report.overall.effectiveSampleSize
        payoutAdjustedExpectancy = report.overall.payoutAdjustedExpectancy
        breakEvenWinRate = report.overall.breakEvenWinRate
        sampleWarning = report.sampleWarning
        status = report.status
    }
}

/// Legitimately obtained historical observations used to construct frozen decision points.
/// The builder exposes only candles and the latest quote available at each evaluation time.
public struct HistoricalValidationSeries: Codable, Sendable {
    public let instrumentID: String
    public let engineAsset: String
    public let venueID: String
    public let marketKind: ShadowMarketKind
    public let source: String
    public let authority: ValidationPriceAuthority
    public let candles1m: [StrategyEngine.CandlePayload]
    public let candles5m: [StrategyEngine.CandlePayload]
    public let prices: [ValidationPriceObservation]
    public let evaluationTimes: [Date]
    /// Source-specific quote freshness contract. Historical construction is rejected if
    /// the source does not supply a finite, non-negative limit.
    public let maximumSignalQuoteAgeSeconds: TimeInterval?
    public let payoutRatio: Double?
    public let signalCategory: String?
    public let marketRegime: String?
    public let provenance: String

    public init(
        instrumentID: String, engineAsset: String, venueID: String,
        marketKind: ShadowMarketKind, source: String,
        authority: ValidationPriceAuthority,
        candles1m: [StrategyEngine.CandlePayload],
        candles5m: [StrategyEngine.CandlePayload],
        prices: [ValidationPriceObservation], evaluationTimes: [Date],
        maximumSignalQuoteAgeSeconds: TimeInterval? = nil,
        payoutRatio: Double? = nil, signalCategory: String? = nil,
        marketRegime: String? = nil, provenance: String
    ) {
        self.instrumentID = instrumentID
        self.engineAsset = engineAsset
        self.venueID = venueID
        self.marketKind = marketKind
        self.source = source
        self.authority = authority
        self.candles1m = candles1m
        self.candles5m = candles5m
        self.prices = prices
        self.evaluationTimes = evaluationTimes
        self.maximumSignalQuoteAgeSeconds = maximumSignalQuoteAgeSeconds
        self.payoutRatio = payoutRatio
        self.signalCategory = signalCategory
        self.marketRegime = marketRegime
        self.provenance = provenance
    }
}

public struct HistoricalValidationBuildRejection: Codable, Sendable, Equatable {
    public let evaluationTime: Date
    public let reason: String
}

public struct HistoricalValidationBuildResult: Codable, Sendable {
    public let cases: [StrategyValidationCase]
    public let rejections: [HistoricalValidationBuildRejection]
}

public enum HistoricalValidationCaseBuilder {
    /// Builds rolling snapshots without exposing future candles or quotes to the engine input.
    /// Later prices remain attached only for the settlement phase.
    public static func build(
        series: HistoricalValidationSeries,
        stage: ValidationStage = .historicalReplay,
        minimumM1: Int = 52,
        minimumM5: Int = 12,
        maximumBars: Int = 200
    ) -> HistoricalValidationBuildResult {
        guard stage != .liveObservation, minimumM1 > 0, minimumM5 > 0,
              maximumBars >= max(minimumM1, minimumM5) else {
            return HistoricalValidationBuildResult(
                cases: [], rejections: series.evaluationTimes.map {
                    HistoricalValidationBuildRejection(
                        evaluationTime: $0, reason: "Invalid historical builder configuration")
                })
        }
        guard let maxQuoteAge = series.maximumSignalQuoteAgeSeconds,
              maxQuoteAge.isFinite, maxQuoteAge >= 0 else {
            return HistoricalValidationBuildResult(
                cases: [], rejections: series.evaluationTimes.map {
                    HistoricalValidationBuildRejection(
                        evaluationTime: $0,
                        reason: "Source-specific signal quote freshness contract unavailable")
                })
        }
        var output: [StrategyValidationCase] = []
        var rejected: [HistoricalValidationBuildRejection] = []
        let times = Array(Set(series.evaluationTimes)).sorted()
        for evaluationTime in times {
            guard evaluationTime.timeIntervalSince1970.isFinite else {
                rejected.append(.init(evaluationTime: evaluationTime, reason: "Invalid evaluation time"))
                continue
            }
            let cutoffMs = evaluationTime.timeIntervalSince1970 * 1_000
            let m1 = series.candles1m.filter { $0.time + 60_000 <= cutoffMs + 1 }
                .sorted { $0.time < $1.time }.suffix(maximumBars)
            let m5 = series.candles5m.filter { $0.time + 300_000 <= cutoffMs + 1 }
                .sorted { $0.time < $1.time }.suffix(maximumBars)
            guard m1.count >= minimumM1, m5.count >= minimumM5 else {
                rejected.append(.init(
                    evaluationTime: evaluationTime, reason: "Insufficient completed candle history"))
                continue
            }
            let quote = series.prices
                .filter { $0.instrumentID == series.instrumentID && $0.venueID == series.venueID }
                .filter { $0.observedAt <= evaluationTime && $0.authority == series.authority }
                .filter { $0.price.isFinite && $0.price > 0 }
                .max { $0.observedAt < $1.observedAt }
            guard let quote, let bid = quote.bid, let ask = quote.ask,
                  bid.isFinite, ask.isFinite, bid > 0, ask > bid else {
                rejected.append(.init(
                    evaluationTime: evaluationTime, reason: "Historical bid/ask quote unavailable"))
                continue
            }
            let quoteAge = evaluationTime.timeIntervalSince(quote.observedAt)
            guard quoteAge.isFinite, quoteAge >= 0, quoteAge <= maxQuoteAge else {
                rejected.append(.init(
                    evaluationTime: evaluationTime,
                    reason: "Historical signal quote exceeds source freshness contract"))
                continue
            }
            let input = StrategyEngine.MarketInput(
                asset: series.engineAsset, source: series.source,
                candles1m: Array(m1), candles5m: Array(m5),
                lastPrice: quote.price, bid: bid, ask: ask, spread: ask - bid,
                expirySeconds: 60,
                quoteAsOfMs: quote.observedAt.timeIntervalSince1970 * 1_000,
                evaluatedAtMs: cutoffMs, policy: .baseline)
            output.append(StrategyValidationCase(
                id: "\(series.instrumentID)-"
                    + String(evaluationTime.timeIntervalSince1970.bitPattern, radix: 16),
                stage: stage, instrumentID: series.instrumentID,
                engineAsset: series.engineAsset, venueID: series.venueID,
                marketKind: series.marketKind, signalTimestamp: evaluationTime,
                engineSHA: EngineIdentity.pinnedSHA1, input: input,
                maximumSignalQuoteAgeSeconds: maxQuoteAge,
                signalPriceAuthority: series.authority,
                observations: series.prices, payoutRatio: series.payoutRatio,
                signalCategory: series.signalCategory, marketRegime: series.marketRegime,
                provenance: series.provenance))
        }
        return HistoricalValidationBuildResult(cases: output, rejections: rejected)
    }
}

public enum StrategyValidationEngine {
    public typealias Evaluator = @Sendable (StrategyEngine.MarketInput) async throws -> EngineSignal

    /// Replays frozen decision points with the pinned engine. Invalid cases become unresolved
    /// records instead of disappearing from coverage.
    public static func replay(
        cases: [StrategyValidationCase],
        configuration: StrategyValidationConfiguration,
        evaluator: Evaluator = { try await StrategyEngine.evaluate(input: $0).signal }
    ) async throws -> [StrategyValidationRecord] {
        var records: [StrategyValidationRecord] = []
        for item in cases.sorted(by: { $0.signalTimestamp < $1.signalTimestamp }) {
            try Task.checkCancellation()
            if let reason = validationFailure(item, configuration: configuration) {
                records.append(unresolved(item, configuration: configuration, reason: reason))
                continue
            }
            do {
                let signal = try await evaluator(item.input)
                try Task.checkCancellation()
                records.append(resolve(item, signal: signal, configuration: configuration))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                records.append(unresolved(item, configuration: configuration,
                                          reason: "Engine evaluation failed: \(error.localizedDescription)"))
            }
        }
        return records
    }

    public static func digest(of item: StrategyValidationCase) -> String {
        canonicalDigest(item)
    }

    public static func digest(of configuration: StrategyValidationConfiguration) -> String {
        canonicalDigest(configuration)
    }

    public static func recordID(caseDigest: String, configurationDigest: String) -> String {
        canonicalDigest([caseDigest, configurationDigest])
    }

    public static func report(records: [StrategyValidationRecord], stage: ValidationStage) -> StrategyValidationReport {
        let stageRecords = records.filter { $0.stage == stage }
        let byCase = Dictionary(grouping: stageRecords, by: \.caseID)
        let uniqueCases = byCase.values.filter { $0.count == 1 }.compactMap(\.first)
        let byVenueEvent = Dictionary(grouping: uniqueCases.compactMap { record in
            record.venueEventID.map { ($0, record) }
        }, by: { $0.0 })
        let duplicateVenueCaseIDs = Set(byVenueEvent.values.filter { $0.count != 1 }
            .flatMap { $0.map { $0.1.caseID } })
        // Reference and synthetic prices remain visible for comparison but cannot establish
        // venue performance. Paper/replay provider results are research evidence only.
        let eligible = uniqueCases.filter {
            !duplicateVenueCaseIDs.contains($0.caseID)
                &&
            !$0.isSynthetic && ($0.isVenueOutcome || stage != .liveObservation)
                && !($0.marketKind == .otc && $0.priceAuthority == .oandaReference)
        }
        let resolvedEligible = eligible.filter {
            $0.resolution == .win || $0.resolution == .loss
                || ($0.resolution == .tie && ($0.tiePolicy ?? .unknown) == .loss)
        }
        func grouped(_ key: (StrategyValidationRecord) -> String) -> [StrategyValidationCohort] {
            Dictionary(grouping: eligible, by: key).keys.sorted().map {
                cohort(key: $0, records: Dictionary(grouping: eligible, by: key)[$0, default: []])
            }
        }
        let overall = cohort(key: "all", records: eligible)
        return StrategyValidationReport(
            stage: stage,
            total: stageRecords.count,
            performanceEligible: resolvedEligible.count,
            excludedDuplicateCases: byCase.values.filter { $0.count != 1 }
                .reduce(0) { $0 + $1.count } + duplicateVenueCaseIDs.count,
            excludedReferenceOutcomes: stageRecords.filter {
                $0.marketKind == .otc && $0.priceAuthority == .oandaReference
            }.count,
            syntheticRecords: stageRecords.filter(\.isSynthetic).count,
            overall: overall,
            byRegime: grouped { $0.marketRegime ?? "unknown" },
            byTimeOfDayUTC: grouped { String(format: "%02d:00", Calendar.utc.component(.hour, from: $0.signalTimestamp)) },
            bySignalCategory: grouped { $0.signalCategory ?? "unknown" },
            byExecutionDelay: grouped { record in
                guard let delay = record.executionDelaySeconds else { return "unknown" }
                switch delay { case ..<3: return "0-2s"; case ..<6: return "3-5s"; case ..<9: return "6-8s"; default: return "9s+" }
            },
            sampleWarning: overall.effectiveSampleSize < 30
                ? "Small or dependent sample: effective N is below 30 resolved observations."
                : nil
        )
    }

    private static func validationFailure(
        _ item: StrategyValidationCase,
        configuration: StrategyValidationConfiguration
    ) -> String? {
        guard item.engineSHA == EngineIdentity.pinnedSHA1 else { return "Historical engine version is not the pinned engine" }
        guard configuration.entryDelaySeconds.isFinite, configuration.entryDelaySeconds >= 0,
              configuration.expirySeconds == 60,
              configuration.observationToleranceSeconds.isFinite,
              configuration.observationToleranceSeconds >= 0,
              configuration.observationToleranceSeconds <= 5 else { return "Invalid 60-second replay configuration" }
        guard item.signalTimestamp.timeIntervalSince1970.isFinite,
              item.input.expirySeconds == 60,
              let evaluatedAt = item.input.evaluatedAtMs, evaluatedAt.isFinite,
              abs(evaluatedAt / 1_000 - item.signalTimestamp.timeIntervalSince1970) <= 0.001 else {
            return "Signal timestamp is missing or changed"
        }
        guard !item.instrumentID.isEmpty, !item.venueID.isEmpty,
              item.input.asset == item.engineAsset, !item.engineAsset.isEmpty else {
            return "Wrong instrument mapping"
        }
        guard item.input.lastPrice.isFinite, item.input.lastPrice > 0,
              item.input.bid.isFinite, item.input.bid > 0,
              item.input.ask.isFinite, item.input.ask > item.input.bid,
              item.input.spread.isFinite, item.input.spread > 0 else {
            return "Invalid historical evaluation quote"
        }
        guard let quoteAt = item.input.quoteAsOfMs, quoteAt.isFinite else {
            return "Historical quote timestamp is missing"
        }
        if quoteAt / 1_000 > item.signalTimestamp.timeIntervalSince1970 + 0.001 {
            return "Future quote leaked into the signal"
        }
        if item.stage == .historicalReplay {
            guard let maximumAge = item.maximumSignalQuoteAgeSeconds,
                  maximumAge.isFinite, maximumAge >= 0 else {
                return "Source-specific signal quote freshness contract unavailable"
            }
            let quoteAge = item.signalTimestamp.timeIntervalSince1970 - quoteAt / 1_000
            guard quoteAge.isFinite, quoteAge >= 0, quoteAge <= maximumAge else {
                return "Historical signal quote exceeds source freshness contract"
            }
        }
        guard validCompleted(item.input.candles1m, interval: 60, at: item.signalTimestamp),
              validCompleted(item.input.candles5m, interval: 300, at: item.signalTimestamp) else {
            return "Incomplete, invalid, or future candle in historical input"
        }
        if item.stage == .liveObservation && item.recordedExecution == nil {
            return "Live observation requires a recorded manual execution"
        }
        if item.stage != .liveObservation && item.recordedExecution != nil {
            return "Recorded execution cannot be relabeled as simulated"
        }
        if let execution = item.recordedExecution {
            guard execution.enteredAt.timeIntervalSince1970.isFinite,
                  execution.enteredAt >= item.signalTimestamp,
                  execution.entryPrice.isFinite, execution.entryPrice > 0 else {
                return "Invalid recorded manual entry"
            }
            if execution.expiryObservedAt != nil || execution.expiryPrice != nil
                || execution.confirmedResolution != nil {
                guard let observedAt = execution.expiryObservedAt,
                      observedAt.timeIntervalSince1970.isFinite,
                      let price = execution.expiryPrice, price.isFinite, price > 0 else {
                    return "Invalid recorded manual expiry"
                }
            }
        }
        return nil
    }

    private static func validCompleted(
        _ candles: [StrategyEngine.CandlePayload], interval: TimeInterval, at signalTime: Date
    ) -> Bool {
        guard !candles.isEmpty else { return false }
        var previous = -Double.infinity
        for candle in candles {
            guard candle.time.isFinite, candle.time > previous,
                  candle.open.isFinite, candle.high.isFinite, candle.low.isFinite, candle.close.isFinite,
                  candle.open > 0, candle.close > 0,
                  candle.high >= max(candle.open, candle.close),
                  candle.low <= min(candle.open, candle.close), candle.low > 0,
                  candle.time / 1_000 + interval <= signalTime.timeIntervalSince1970 + 0.001 else { return false }
            previous = candle.time
        }
        return true
    }

    private static func resolve(
        _ item: StrategyValidationCase, signal: EngineSignal,
        configuration: StrategyValidationConfiguration
    ) -> StrategyValidationRecord {
        let direction = signal.cabinetSide
        guard direction == "HIGH" || direction == "LOW" else {
            return unresolved(item, configuration: configuration, direction: direction,
                              reason: "Engine returned no actionable signal")
        }
        let executionKind: ValidationExecutionKind = item.stage == .liveObservation ? .recordedManual : .simulated
        let entry: (Date, Double, ValidationPriceAuthority, String)?
        if let actual = item.recordedExecution {
            entry = (actual.enteredAt, actual.entryPrice, .manualBrokerObservation, "manual broker observation")
        } else {
            let target = item.signalTimestamp.addingTimeInterval(configuration.entryDelaySeconds)
            entry = matchingObservation(item, target: target, tolerance: configuration.observationToleranceSeconds)
                .map { ($0.observedAt, $0.price, $0.authority, $0.source) }
        }
        guard let entry, entry.0 >= item.signalTimestamp else {
            return unresolved(item, configuration: configuration, direction: direction,
                              reason: "Entry observation missing")
        }
        let expiry = entry.0.addingTimeInterval(TimeInterval(configuration.expirySeconds))
        let expiryObservation: (Date, Double, ValidationPriceAuthority, String)?
        let confirmed: ValidationResolution?
        if let actual = item.recordedExecution {
            confirmed = actual.confirmedResolution
            if let at = actual.expiryObservedAt, let price = actual.expiryPrice {
                expiryObservation = (at, price, .manualBrokerObservation, "manual broker observation")
            } else { expiryObservation = nil }
        } else {
            confirmed = nil
            expiryObservation = matchingObservation(item, target: expiry,
                tolerance: configuration.observationToleranceSeconds).map {
                    ($0.observedAt, $0.price, $0.authority, $0.source)
                }
        }
        guard let expiryObservation, expiryObservation.0 >= expiry,
              expiryObservation.0.timeIntervalSince(expiry) <= configuration.observationToleranceSeconds else {
            return record(item, configuration: configuration, direction: direction,
                          executionKind: executionKind, entry: entry, expiry: expiry,
                          expiryObservation: nil, resolution: .unresolved,
                          reason: "Timely expiry observation missing", isVenueOutcome: false)
        }
        guard item.stage == .liveObservation
                || (expiryObservation.2 == entry.2 && expiryObservation.3 == entry.3) else {
            return record(item, configuration: configuration, direction: direction,
                          executionKind: executionKind, entry: entry, expiry: expiry,
                          expiryObservation: expiryObservation, resolution: .unresolved,
                          reason: "Entry and expiry price provenance changed", isVenueOutcome: false)
        }
        let calculated: ValidationResolution
        if expiryObservation.1 == entry.1 { calculated = .tie }
        else {
            let win = direction == "HIGH" ? expiryObservation.1 > entry.1 : expiryObservation.1 < entry.1
            calculated = win ? .win : .loss
        }
        let resolution = confirmed ?? calculated
        let venueOutcome = item.stage == .liveObservation
            && confirmed != nil
            && !(item.recordedExecution?.venueEventID ?? "").isEmpty
        return record(item, configuration: configuration, direction: direction,
                      executionKind: executionKind, entry: entry, expiry: expiry,
                      expiryObservation: expiryObservation, resolution: resolution,
                      reason: nil, isVenueOutcome: venueOutcome)
    }

    private static func matchingObservation(
        _ item: StrategyValidationCase, target: Date, tolerance: TimeInterval
    ) -> ValidationPriceObservation? {
        item.observations
            .filter { $0.instrumentID == item.instrumentID && $0.venueID == item.venueID }
            .filter { observation in
                guard !observation.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                if observation.authority == .oandaReference {
                    return item.marketKind == .standard
                        && item.venueID.localizedCaseInsensitiveContains("oanda")
                }
                return true
            }
            .filter { $0.price.isFinite && $0.price > 0 && $0.observedAt >= target
                && $0.observedAt.timeIntervalSince(target) <= tolerance }
            .sorted { $0.observedAt < $1.observedAt }
            .first
    }

    private static func unresolved(
        _ item: StrategyValidationCase,
        configuration: StrategyValidationConfiguration,
        direction: String = "UNKNOWN",
        reason: String
    ) -> StrategyValidationRecord {
        record(item, configuration: configuration, direction: direction,
               executionKind: item.stage == .liveObservation ? .recordedManual : .simulated,
               entry: nil, expiry: nil, expiryObservation: nil, resolution: .unresolved,
               reason: reason, isVenueOutcome: false)
    }

    private static func record(
        _ item: StrategyValidationCase,
        configuration: StrategyValidationConfiguration,
        direction: String,
        executionKind: ValidationExecutionKind,
        entry: (Date, Double, ValidationPriceAuthority, String)?,
        expiry: Date?,
        expiryObservation: (Date, Double, ValidationPriceAuthority, String)?,
        resolution: ValidationResolution,
        reason: String?,
        isVenueOutcome: Bool
    ) -> StrategyValidationRecord {
        let authority = expiryObservation?.2 ?? entry?.2
        return StrategyValidationRecord(
            id: recordID(caseDigest: digest(of: item),
                         configurationDigest: canonicalDigest(configuration)),
            caseID: item.id, stage: item.stage, executionKind: executionKind,
            instrumentID: item.instrumentID, venueID: item.venueID, marketKind: item.marketKind,
            signalDirection: direction, signalTimestamp: item.signalTimestamp,
            entryTimestamp: entry?.0, entryPrice: entry?.1, expiryTimestamp: expiry,
            expiryObservedAt: expiryObservation?.0, expiryPrice: expiryObservation?.1,
            payoutRatio: validPayout(item.payoutRatio),
            resolution: resolution,
            executionDelaySeconds: entry.map { $0.0.timeIntervalSince(item.signalTimestamp) },
            engineSHA: item.engineSHA,
            inputDigest: canonicalDigest(item.input),
            caseDigest: digest(of: item),
            configurationDigest: canonicalDigest(configuration),
            configuration: configuration,
            tiePolicy: configuration.tiePolicy,
            signalPriceAuthority: item.signalPriceAuthority,
            venueEventID: item.recordedExecution?.venueEventID,
            dataSource: [item.provenance, expiryObservation?.3 ?? entry?.3]
                .compactMap { $0 }.joined(separator: " | "),
            priceAuthority: authority,
            signalCategory: item.signalCategory, marketRegime: item.marketRegime,
            rejectionReason: reason, isVenueOutcome: isVenueOutcome,
            isSynthetic: item.signalPriceAuthority == .syntheticFixture
                || entry?.2 == .syntheticFixture
                || expiryObservation?.2 == .syntheticFixture
                || authority == .syntheticFixture
                || item.provenance.localizedCaseInsensitiveContains("synthetic")
        )
    }

    private static func cohort(key: String, records: [StrategyValidationRecord]) -> StrategyValidationCohort {
        let directional = records.filter {
            $0.resolution == .win || $0.resolution == .loss
                || ($0.resolution == .tie && ($0.tiePolicy ?? .unknown) == .loss)
        }
        let wins = directional.filter { $0.resolution == .win }.count
        let losses = directional.count - wins
        let clustered = EvidenceClustering.adjust(directional.map {
            ClusteredObservation(
                pair: $0.instrumentID,
                capturedAtMs: ($0.entryTimestamp ?? $0.signalTimestamp).timeIntervalSince1970 * 1_000,
                won: $0.resolution == .win)
        }, bucketMs: 60_000)
        let ties = records.filter { $0.resolution == .tie }
        let refundableOrUnknownTies = ties.filter { ($0.tiePolicy ?? .unknown) != .loss }
        let payoutRows = directional + refundableOrUnknownTies
        let payouts = payoutRows.compactMap(\.payoutRatio)
        let tiePolicies = Set(refundableOrUnknownTies.map { $0.tiePolicy ?? .unknown })
        let tiesAreScorable = refundableOrUnknownTies.isEmpty
            || (tiePolicies.count == 1 && tiePolicies.first != .unknown)
        let expectancy: Double? = !directional.isEmpty && tiesAreScorable
            && payouts.count == payoutRows.count
            ? payoutRows.map { record in
                switch record.resolution {
                case .win: return record.payoutRatio ?? 0
                case .loss: return -1
                case .tie: return (record.tiePolicy ?? .unknown) == .loss ? -1 : 0
                case .unresolved: return 0
                }
            }.reduce(0, +) / Double(payoutRows.count)
            : nil
        let minimumPayout = payouts.min()
        let pathCoverageComplete = !records.contains {
            $0.entryTimestamp != nil && $0.resolution == .unresolved
        }
        var streak = 0, maximumStreak = 0
        var balance = 0.0, peak = 0.0, drawdown = 0.0
        let sequenced = (directional + refundableOrUnknownTies).sorted {
            let left = $0.entryTimestamp ?? $0.signalTimestamp
            let right = $1.entryTimestamp ?? $1.signalTimestamp
            return left == right ? $0.id < $1.id : left < right
        }
        for record in sequenced {
            if record.resolution == .loss
                || (record.resolution == .tie && (record.tiePolicy ?? .unknown) == .loss) {
                streak += 1; balance -= 1
            } else if record.resolution == .win {
                streak = 0; balance += record.payoutRatio ?? 0
            } else {
                streak = 0
            }
            maximumStreak = max(maximumStreak, streak)
            peak = max(peak, balance)
            drawdown = max(drawdown, peak - balance)
        }
        return StrategyValidationCohort(
            key: key, resolved: directional.count,
            wins: wins, losses: losses,
            ties: ties.count,
            unresolved: records.filter { $0.resolution == .unresolved }.count,
            winRate: directional.isEmpty ? nil : Double(wins) / Double(directional.count),
            lower95: directional.isEmpty ? nil : clustered.lower95,
            upper95: directional.isEmpty ? nil : clustered.upper95,
            candidateBlocks: clustered.blocks,
            effectiveSampleSize: clustered.effectiveSize,
            payoutAdjustedExpectancy: expectancy,
            breakEvenWinRate: minimumPayout.map { 1 / (1 + $0) },
            maximumConsecutiveLosses: pathCoverageComplete ? maximumStreak : nil,
            maximumUnitDrawdown: pathCoverageComplete && !directional.isEmpty && tiesAreScorable
                && payouts.count == payoutRows.count ? drawdown : nil
        )
    }

    private static func validPayout(_ payout: Double?) -> Double? {
        guard let payout, payout.isFinite, payout > 0, payout <= 1 else { return nil }
        return payout
    }

    private static func canonicalDigest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let data = (try? encoder.encode(value)) ?? Data(String(describing: value).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
