import CryptoKit
import Foundation

public enum BreakoutAcceptanceDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
}

public enum BreakoutAcceptanceStatus: String, Codable, Sendable, Equatable {
    case watching = "WATCHING"
    case awaitingAcceptance = "AWAITING_ACCEPTANCE"
    case signal = "RESEARCH_SIGNAL"
    case rejected = "REJECTED"
    case expired = "EXPIRED"
}

public struct BreakoutAcceptanceBar: Codable, Sendable, Equatable, Identifiable {
    /// Stable source candle ID, unique within the evaluated input snapshot.
    public let id: String
    public let instrument: String
    public let provider: String
    public let startTime: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(id: String, instrument: String, provider: String, startTime: Date,
                open: Double, high: Double, low: Double,
                close: Double, complete: Bool) {
        self.id = id
        self.instrument = instrument
        self.provider = provider
        self.startTime = startTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.complete = complete
    }

    public func isValid(timeframeSeconds: Int) -> Bool {
        !id.isEmpty && !instrument.isEmpty && !provider.isEmpty
            && startTime.timeIntervalSince1970.isFinite
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
            && timeframeSeconds > 0
    }

    public func endTime(timeframeSeconds: Int) -> Date {
        startTime.addingTimeInterval(TimeInterval(timeframeSeconds))
    }
}

public struct BreakoutAcceptanceFrozenLevel: Codable, Sendable, Equatable {
    public let id: String
    public let price: Double
    public let sourceBarIDs: [String]
    public let frozenAt: Date

    public init(id: String, price: Double, sourceBarIDs: [String], frozenAt: Date) {
        self.id = id
        self.price = price
        self.sourceBarIDs = sourceBarIDs
        self.frozenAt = frozenAt
    }
}

public enum BreakoutAcceptanceStructure: Codable, Sendable, Equatable {
    case keyLevel(level: BreakoutAcceptanceFrozenLevel, direction: BreakoutAcceptanceDirection)
    case range(id: String, high: BreakoutAcceptanceFrozenLevel,
               low: BreakoutAcceptanceFrozenLevel, direction: BreakoutAcceptanceDirection)

    public var direction: BreakoutAcceptanceDirection {
        switch self {
        case .keyLevel(_, let direction), .range(_, _, _, let direction): direction
        }
    }

    public var breakoutLevel: BreakoutAcceptanceFrozenLevel {
        switch self {
        case .keyLevel(let level, _): level
        case .range(_, let high, let low, let direction): direction == .long ? high : low
        }
    }

    public var structureID: String {
        switch self {
        case .keyLevel(let level, _): level.id
        case .range(let id, _, _, _): id
        }
    }

    public var sourceBarIDs: [String] {
        switch self {
        case .keyLevel(let level, _): level.sourceBarIDs
        case .range(_, let high, let low, _): high.sourceBarIDs + low.sourceBarIDs
        }
    }

    public var sourceLevels: [BreakoutAcceptanceFrozenLevel] {
        switch self {
        case .keyLevel(let level, _): [level]
        case .range(_, let high, let low, _): [high, low]
        }
    }

    public var frozenAt: Date {
        switch self {
        case .keyLevel(let level, _): level.frozenAt
        case .range(_, let high, let low, _): max(high.frozenAt, low.frozenAt)
        }
    }

    public func validates() -> Bool {
        switch self {
        case .keyLevel(let level, _): Self.valid(level)
        case .range(let id, let high, let low, _):
            !id.isEmpty && Self.valid(high) && Self.valid(low) && high.price > low.price
                && high.id != low.id
        }
    }

    private static func valid(_ level: BreakoutAcceptanceFrozenLevel) -> Bool {
        !level.id.isEmpty && level.price.isFinite && level.price > 0
            && !level.sourceBarIDs.isEmpty && Set(level.sourceBarIDs).count == level.sourceBarIDs.count
            && level.frozenAt.timeIntervalSince1970.isFinite
    }
}

public enum BreakoutAcceptanceMode: Codable, Sendable, Equatable {
    /// `additionalBars` completed closes after the breakout must clear the configured hold buffer.
    /// The breakout bar itself never counts toward acceptance.
    case sustainedBarsBeyond(additionalBars: Int, holdBufferPips: Double)
    /// Every post-break completed close through the duration must clear the hold buffer.
    case sustainedTimeBeyond(durationSeconds: TimeInterval, holdBufferPips: Double)
    /// After breakout, price must retest the level within the bar bound, hold outside,
    /// then produce a directional close beyond the configured confirmation buffer.
    case boundedRetestHold(maximumRetestBars: Int, tolerancePips: Double,
                           confirmationBufferPips: Double)
}

public enum BreakoutAcceptanceSessionPolicy: Codable, Sendable, Equatable {
    case sessionAgnostic
    /// A single frozen UTC interval. `timeZoneIdentifier` records the zone used
    /// to derive these absolute instants; the caller owns recurring-window/DST conversion.
    case window(id: String, timeZoneIdentifier: String, start: Date, end: Date)
}

/// Each immutable frozen structure may produce only one event. A later attempt
/// requires a newly frozen structure with a new identity, preventing retry loops
/// from silently reusing the same range after a resolved or rejected breakout.
public enum BreakoutAcceptanceRearmPolicy: String, Codable, Sendable, Equatable {
    case newFrozenStructureRequired
}

public struct BreakoutAcceptanceConfiguration: Codable, Sendable, Equatable {
    public let version: String
    public let instrument: String
    public let provider: String
    public let pipSize: Double
    public let timeframeSeconds: Int
    public let structure: BreakoutAcceptanceStructure
    public let regimeDefinitionID: String
    public let regimeDefinitionDigest: String
    public let minimumRegimeValue: Double
    public let maximumRegimeValue: Double
    public let minimumDisplacementPips: Double
    public let acceptanceMode: BreakoutAcceptanceMode
    public let maximumSetupAgeSeconds: TimeInterval
    public let maximumCompletedBarsAfterAcceptance: Int
    public let sessionPolicy: BreakoutAcceptanceSessionPolicy
    public let rearmPolicy: BreakoutAcceptanceRearmPolicy
    public let clusterWindowSeconds: TimeInterval
    public let maximumSpreadPips: Double
    public let maximumQuoteAgeSeconds: TimeInterval
    public let additionalCostsPips: Double
    public let minimumMovementToCostRatio: Double
    public let maximumAdverseEntryDriftPips: Double
    public let stop: BreakoutAcceptanceFrozenLevel
    public let target: BreakoutAcceptanceFrozenLevel

    public init(version: String, instrument: String, provider: String, pipSize: Double,
                timeframeSeconds: Int, structure: BreakoutAcceptanceStructure,
                regimeDefinitionID: String, regimeDefinitionDigest: String,
                minimumRegimeValue: Double,
                maximumRegimeValue: Double, minimumDisplacementPips: Double,
                acceptanceMode: BreakoutAcceptanceMode,
                maximumSetupAgeSeconds: TimeInterval, maximumCompletedBarsAfterAcceptance: Int,
                sessionPolicy: BreakoutAcceptanceSessionPolicy,
                rearmPolicy: BreakoutAcceptanceRearmPolicy, clusterWindowSeconds: TimeInterval,
                maximumSpreadPips: Double, maximumQuoteAgeSeconds: TimeInterval,
                additionalCostsPips: Double, minimumMovementToCostRatio: Double,
                maximumAdverseEntryDriftPips: Double,
                stop: BreakoutAcceptanceFrozenLevel, target: BreakoutAcceptanceFrozenLevel) {
        self.version = version
        self.instrument = instrument
        self.provider = provider
        self.pipSize = pipSize
        self.timeframeSeconds = timeframeSeconds
        self.structure = structure
        self.regimeDefinitionID = regimeDefinitionID
        self.regimeDefinitionDigest = regimeDefinitionDigest
        self.minimumRegimeValue = minimumRegimeValue
        self.maximumRegimeValue = maximumRegimeValue
        self.minimumDisplacementPips = minimumDisplacementPips
        self.acceptanceMode = acceptanceMode
        self.maximumSetupAgeSeconds = maximumSetupAgeSeconds
        self.maximumCompletedBarsAfterAcceptance = maximumCompletedBarsAfterAcceptance
        self.sessionPolicy = sessionPolicy
        self.rearmPolicy = rearmPolicy
        self.clusterWindowSeconds = clusterWindowSeconds
        self.maximumSpreadPips = maximumSpreadPips
        self.maximumQuoteAgeSeconds = maximumQuoteAgeSeconds
        self.additionalCostsPips = additionalCostsPips
        self.minimumMovementToCostRatio = minimumMovementToCostRatio
        self.maximumAdverseEntryDriftPips = maximumAdverseEntryDriftPips
        self.stop = stop
        self.target = target
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("version_missing") }
        if instrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("instrument_missing") }
        if provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("provider_missing") }
        if !pipSize.isFinite || pipSize <= 0 { issues.append("pip_size_invalid") }
        if timeframeSeconds <= 0 { issues.append("timeframe_invalid") }
        if !structure.validates() { issues.append("structure_invalid") }
        if regimeDefinitionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || regimeDefinitionDigest.count != 64
            || !regimeDefinitionDigest.allSatisfy({ $0.isHexDigit })
            || !minimumRegimeValue.isFinite || !maximumRegimeValue.isFinite
            || minimumRegimeValue > maximumRegimeValue { issues.append("regime_rule_invalid") }
        if !minimumDisplacementPips.isFinite || minimumDisplacementPips <= 0 {
            issues.append("minimum_displacement_invalid")
        }
        switch acceptanceMode {
        case .sustainedBarsBeyond(let additionalBars, let holdBufferPips):
            if additionalBars < 1 { issues.append("acceptance_bar_count_invalid") }
            if !holdBufferPips.isFinite || holdBufferPips < 0 { issues.append("acceptance_hold_buffer_invalid") }
        case .sustainedTimeBeyond(let duration, let holdBufferPips):
            if !duration.isFinite || duration < TimeInterval(timeframeSeconds) {
                issues.append("acceptance_duration_invalid")
            }
            if !holdBufferPips.isFinite || holdBufferPips < 0 { issues.append("acceptance_hold_buffer_invalid") }
        case .boundedRetestHold(let maximumBars, let tolerance, let buffer):
            if maximumBars < 1 { issues.append("retest_bar_bound_invalid") }
            if !tolerance.isFinite || tolerance < 0 { issues.append("retest_tolerance_invalid") }
            if !buffer.isFinite || buffer < 0 { issues.append("confirmation_buffer_invalid") }
        }
        if !maximumSetupAgeSeconds.isFinite || maximumSetupAgeSeconds <= 0 { issues.append("setup_age_invalid") }
        if maximumCompletedBarsAfterAcceptance < 0 { issues.append("post_acceptance_bar_expiry_invalid") }
        if case .window(let id, let timeZoneIdentifier, let start, let end) = sessionPolicy {
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || TimeZone(identifier: timeZoneIdentifier) == nil
                || !start.timeIntervalSince1970.isFinite || !end.timeIntervalSince1970.isFinite
                || end <= start {
                issues.append("session_window_invalid")
            }
        }
        if !clusterWindowSeconds.isFinite || clusterWindowSeconds < 0 { issues.append("cluster_window_invalid") }
        if !maximumSpreadPips.isFinite || maximumSpreadPips <= 0 { issues.append("spread_limit_invalid") }
        if !maximumQuoteAgeSeconds.isFinite || maximumQuoteAgeSeconds <= 0 { issues.append("quote_age_invalid") }
        if !additionalCostsPips.isFinite || additionalCostsPips < 0 { issues.append("additional_costs_invalid") }
        if !minimumMovementToCostRatio.isFinite || minimumMovementToCostRatio <= 1 {
            issues.append("movement_cost_ratio_invalid")
        }
        if !maximumAdverseEntryDriftPips.isFinite || maximumAdverseEntryDriftPips < 0 {
            issues.append("adverse_entry_drift_invalid")
        }
        if !Self.validLevel(stop) { issues.append("stop_level_invalid") }
        if !Self.validLevel(target) { issues.append("target_level_invalid") }
        if stop.frozenAt > structure.frozenAt || target.frozenAt > structure.frozenAt {
            issues.append("plan_levels_not_frozen_with_structure")
        }
        let level = structure.breakoutLevel.price
        if structure.direction == .long {
            if !(stop.price < level && target.price > level) { issues.append("frozen_plan_order_invalid") }
        } else if !(target.price < level && stop.price > level) {
            issues.append("frozen_plan_order_invalid")
        }
        return issues.sorted()
    }

    public func digest() -> String { BreakoutAcceptanceDigest.sha256(self) }

    private static func validLevel(_ level: BreakoutAcceptanceFrozenLevel) -> Bool {
        !level.id.isEmpty && level.price.isFinite && level.price > 0
            && !level.sourceBarIDs.isEmpty && Set(level.sourceBarIDs).count == level.sourceBarIDs.count
            && level.frozenAt.timeIntervalSince1970.isFinite
    }
}

public struct BreakoutAcceptanceRegimeMeasurement: Codable, Sendable, Equatable {
    public let definitionID: String
    public let definitionDigest: String
    public let value: Double
    public let measuredAt: Date
    public let sourceBarIDs: [String]

    public init(definitionID: String, definitionDigest: String, value: Double,
                measuredAt: Date, sourceBarIDs: [String]) {
        self.definitionID = definitionID
        self.definitionDigest = definitionDigest
        self.value = value
        self.measuredAt = measuredAt
        self.sourceBarIDs = sourceBarIDs
    }
}

public struct BreakoutAcceptanceQuote: Codable, Sendable, Equatable {
    public let sourceID: String
    public let provider: String
    public let instrument: String
    public let sequence: UInt64
    public let bid: Double
    public let ask: Double
    public let sourceTime: Date
    public let receivedAt: Date

    public init(sourceID: String, provider: String, instrument: String, sequence: UInt64, bid: Double,
                ask: Double, sourceTime: Date, receivedAt: Date) {
        self.sourceID = sourceID
        self.provider = provider
        self.instrument = instrument
        self.sequence = sequence
        self.bid = bid
        self.ask = ask
        self.sourceTime = sourceTime
        self.receivedAt = receivedAt
    }
}

public struct BreakoutAcceptanceEvidence: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let strategyID: String
    public let strategyVersion: String
    public let configurationDigest: String
    public let inputDigest: String
    public let regimeDefinitionID: String
    public let regimeDefinitionDigest: String
    public let regimeValue: Double
    public let sessionID: String?
    public let instrument: String
    public let timeframeSeconds: Int
    public let status: BreakoutAcceptanceStatus
    public let direction: BreakoutAcceptanceDirection?
    public let reasonCodes: [String]
    public let structureID: String
    public let breakoutLevel: Double
    public let breakoutBarID: String?
    public let acceptanceBarID: String?
    public let sourceBarIDs: [String]
    public let quoteSourceID: String
    public let provider: String
    public let quoteSequence: UInt64
    public let quoteSourceTime: Date
    public let quoteReceivedAt: Date
    public let entryReference: Double?
    public let stopReference: Double?
    public let targetReference: Double?
    public let spreadPips: Double?
    public let observedAt: Date

    fileprivate init(configuration: BreakoutAcceptanceConfiguration, configDigest: String,
                     inputDigest: String, status: BreakoutAcceptanceStatus,
                     reasonCodes: [String], breakoutBar: BreakoutAcceptanceBar?,
                     acceptanceBar: BreakoutAcceptanceBar?, sourceBarIDs: [String],
                     regime: BreakoutAcceptanceRegimeMeasurement,
                     quote: BreakoutAcceptanceQuote, observedAt: Date,
                     entry: Double? = nil, spreadPips: Double? = nil) {
        strategyID = "BREAKOUT_ACCEPTANCE_V1"
        strategyVersion = configuration.version
        configurationDigest = configDigest
        self.inputDigest = inputDigest
        regimeDefinitionID = regime.definitionID
        regimeDefinitionDigest = regime.definitionDigest
        regimeValue = regime.value
        if case .window(let id, _, _, _) = configuration.sessionPolicy { sessionID = id }
        else { sessionID = nil }
        instrument = configuration.instrument
        timeframeSeconds = configuration.timeframeSeconds
        self.status = status
        direction = status == .signal ? configuration.structure.direction : nil
        self.reasonCodes = reasonCodes
        structureID = configuration.structure.structureID
        breakoutLevel = configuration.structure.breakoutLevel.price
        breakoutBarID = breakoutBar?.id
        acceptanceBarID = acceptanceBar?.id
        self.sourceBarIDs = Array(Set(sourceBarIDs)).sorted()
        quoteSourceID = quote.sourceID
        provider = quote.provider
        quoteSequence = quote.sequence
        quoteSourceTime = quote.sourceTime
        quoteReceivedAt = quote.receivedAt
        entryReference = entry
        stopReference = entry == nil ? nil : configuration.stop.price
        targetReference = entry == nil ? nil : configuration.target.price
        self.spreadPips = spreadPips
        self.observedAt = observedAt
        id = "breakout-acceptance-\(configuration.instrument)-\(configuration.timeframeSeconds)-\(configuration.structure.structureID)-\(configuration.structure.direction.rawValue)-\(breakoutBar?.id ?? "watch")-\(String(configDigest.prefix(16)))"
    }
}

public enum BreakoutAcceptanceV1 {
    public static func evaluate(configuration: BreakoutAcceptanceConfiguration,
                                 bars: [BreakoutAcceptanceBar],
                                 regime: BreakoutAcceptanceRegimeMeasurement,
                                 quote: BreakoutAcceptanceQuote,
                                 asOf: Date,
                                 previousEventTimes: [Date]) -> BreakoutAcceptanceEvidence {
        let configDigest = configuration.digest()
        let digest = inputDigest(configuration: configuration, bars: bars, regime: regime,
                                 quote: quote, asOf: asOf,
                                 previousEventTimes: previousEventTimes)
        let sortedBars = bars.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        func result(_ status: BreakoutAcceptanceStatus, _ reasons: [String],
                    breakout: BreakoutAcceptanceBar? = nil,
                    accepted: BreakoutAcceptanceBar? = nil,
                    evidenceBars: [BreakoutAcceptanceBar]? = nil,
                    entry: Double? = nil, spread: Double? = nil) -> BreakoutAcceptanceEvidence {
            BreakoutAcceptanceEvidence(configuration: configuration, configDigest: configDigest,
                inputDigest: digest, status: status, reasonCodes: reasons,
                breakoutBar: breakout, acceptanceBar: accepted,
                sourceBarIDs: (evidenceBars ?? sortedBars).map(\.id)
                    + regime.sourceBarIDs + configuration.structure.sourceBarIDs
                    + configuration.stop.sourceBarIDs + configuration.target.sourceBarIDs,
                regime: regime, quote: quote, observedAt: asOf, entry: entry, spreadPips: spread)
        }

        guard configuration.validationIssues().isEmpty else {
            return result(.rejected, ["configuration_invalid"])
        }
        guard asOf.timeIntervalSince1970.isFinite,
              quote.sourceTime.timeIntervalSince1970.isFinite,
              quote.receivedAt.timeIntervalSince1970.isFinite,
              !quote.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !quote.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              quote.instrument == configuration.instrument,
              quote.provider == configuration.provider,
              quote.sequence > 0, quote.bid.isFinite, quote.ask.isFinite, quote.bid > 0, quote.ask > quote.bid,
              quote.sourceTime <= quote.receivedAt, quote.receivedAt <= asOf else {
            return result(.rejected, ["quote_provenance_or_order_invalid"])
        }
        guard !sortedBars.isEmpty else {
            return result(.rejected, ["history_empty"])
        }
        guard sortedBars.allSatisfy({ $0.instrument == configuration.instrument
            && $0.provider == configuration.provider }) else {
            return result(.rejected, ["bar_instrument_or_provider_mismatch"])
        }
        guard
              sortedBars.allSatisfy({ $0.complete && $0.isValid(timeframeSeconds: configuration.timeframeSeconds)
                  && $0.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds)) <= asOf }),
              Set(sortedBars.map(\.id)).count == sortedBars.count,
              Set(sortedBars.map(\.startTime)).count == sortedBars.count,
              zip(sortedBars, sortedBars.dropFirst()).allSatisfy({ left, right in
                  left.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds)) <= right.startTime
              }),
              sortedBars.filter({ $0.startTime >= configuration.structure.frozenAt }).allSatisfy({ bar in
                  let offset = bar.startTime.timeIntervalSince(configuration.structure.frozenAt)
                  return offset >= 0 && abs(offset.truncatingRemainder(dividingBy: TimeInterval(configuration.timeframeSeconds))) < 0.000_001
              }) else {
            return result(.rejected, ["bar_completion_future_duplicate_or_overlap_invalid"])
        }
        guard previousEventTimes.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0 <= asOf }),
              Set(previousEventTimes).count == previousEventTimes.count else {
            return result(.rejected, ["prior_event_provenance_invalid"])
        }
        let barsByID = Dictionary(uniqueKeysWithValues: sortedBars.map { ($0.id, $0) })
        guard configuration.structure.sourceBarIDs.allSatisfy({ barsByID[$0] != nil }),
              configuration.stop.sourceBarIDs.allSatisfy({ barsByID[$0] != nil }),
              configuration.target.sourceBarIDs.allSatisfy({ barsByID[$0] != nil }),
              regime.definitionID == configuration.regimeDefinitionID,
              regime.definitionDigest == configuration.regimeDefinitionDigest,
              regime.value.isFinite,
              regime.sourceBarIDs.allSatisfy({ barsByID[$0] != nil }),
              !regime.sourceBarIDs.isEmpty else {
            return result(.rejected, ["structure_or_regime_provenance_missing"])
        }
        let frozenLevels = configuration.structure.sourceLevels
            + [configuration.stop, configuration.target]
        guard frozenLevels.allSatisfy({ frozenLevel in
            frozenLevel.sourceBarIDs.allSatisfy({ id in
                guard let source = barsByID[id] else { return false }
                return source.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds))
                    <= frozenLevel.frozenAt
            })
        }), regime.sourceBarIDs.allSatisfy({ id in
            guard let source = barsByID[id] else { return false }
            return source.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds))
                <= configuration.structure.frozenAt
        }), regime.measuredAt.timeIntervalSince1970.isFinite,
              regime.sourceBarIDs.allSatisfy({ id in
                  guard let source = barsByID[id] else { return false }
                  return source.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds))
                      <= regime.measuredAt
              }),
              regime.measuredAt <= configuration.structure.frozenAt,
              configuration.structure.frozenAt <= asOf else {
            return result(.rejected, ["structure_not_frozen_from_prior_completed_data"])
        }
        guard regime.value >= configuration.minimumRegimeValue,
              regime.value <= configuration.maximumRegimeValue else {
            return result(.rejected, ["regime_ineligible"])
        }
        guard let latestBar = sortedBars.last,
              quote.sourceTime > latestBar.startTime.addingTimeInterval(TimeInterval(configuration.timeframeSeconds)),
              asOf.timeIntervalSince(quote.sourceTime) <= configuration.maximumQuoteAgeSeconds,
              asOf.timeIntervalSince(quote.receivedAt) <= configuration.maximumQuoteAgeSeconds else {
            return result(.rejected, ["quote_stale_or_not_newer_than_final_bar"])
        }
        if case .window(_, _, _, let sessionEnd) = configuration.sessionPolicy, asOf >= sessionEnd {
            return result(.expired, ["session_end_expired"])
        }

        let direction = configuration.structure.direction
        let level = configuration.structure.breakoutLevel.price
        let spreadPips = (quote.ask - quote.bid) / configuration.pipSize
        guard spreadPips <= configuration.maximumSpreadPips else {
            return result(.rejected, ["spread_exceeds_config"], spread: spreadPips)
        }
        let breakoutBuffer = configuration.minimumDisplacementPips * configuration.pipSize
        guard let breakoutIndex = sortedBars.firstIndex(where: { bar in
            bar.startTime >= configuration.structure.frozenAt
                && (direction == .long ? bar.close >= level + breakoutBuffer
                                      : bar.close <= level - breakoutBuffer)
        }) else {
            let wickOnly = sortedBars.contains { bar in
                bar.startTime >= configuration.structure.frozenAt
                    && (direction == .long ? bar.high > level && bar.close <= level
                                           : bar.low < level && bar.close >= level)
            }
            let undersizedClose = sortedBars.contains { bar in
                bar.startTime >= configuration.structure.frozenAt
                    && (direction == .long
                        ? bar.close > level && bar.close < level + breakoutBuffer
                        : bar.close < level && bar.close > level - breakoutBuffer)
            }
            return result(wickOnly ? .rejected : .watching,
                          [wickOnly ? "wick_only_break_rejected"
                                    : (undersizedClose ? "minimum_displacement_not_met" : "awaiting_initial_break")],
                          spread: spreadPips)
        }
        let breakout = sortedBars[breakoutIndex]
        let postBreakBars = Array(sortedBars.dropFirst(breakoutIndex))
        guard contiguous(postBreakBars, timeframe: configuration.timeframeSeconds) else {
            return result(.rejected, ["setup_data_gap_after_break"], breakout: breakout,
                          evidenceBars: postBreakBars, spread: spreadPips)
        }
        if case .window(_, _, let sessionStart, let sessionEnd) = configuration.sessionPolicy,
           breakout.startTime < sessionStart
                || breakout.endTime(timeframeSeconds: configuration.timeframeSeconds) > sessionEnd {
            return result(.rejected, ["breakout_outside_configured_session"], breakout: breakout,
                          spread: spreadPips)
        }
        if case .range(_, let high, let low, _) = configuration.structure,
           breakout.high >= high.price && breakout.low <= low.price {
            return result(.rejected, ["ambiguous_dual_boundary_break"], breakout: breakout,
                          spread: spreadPips)
        }
        if previousEventTimes.contains(where: { eventTime in
            eventTime.timeIntervalSince1970.isFinite
                && abs(breakout.endTime(timeframeSeconds: configuration.timeframeSeconds)
                    .timeIntervalSince(eventTime)) < configuration.clusterWindowSeconds
        }) {
            return result(.rejected, ["overlapping_event_cluster"], breakout: breakout,
                          spread: spreadPips)
        }
        guard asOf.timeIntervalSince(breakout.endTime(timeframeSeconds: configuration.timeframeSeconds))
                <= configuration.maximumSetupAgeSeconds else {
            return result(.expired, ["setup_expired"], breakout: breakout, spread: spreadPips)
        }

        let afterBreak = postBreakBars
        let acceptance: BreakoutAcceptanceBar?
        switch configuration.acceptanceMode {
        case .sustainedBarsBeyond(let additionalBars, let holdBufferPips):
            let confirmations = Array(afterBreak.dropFirst())
            guard confirmations.count >= additionalBars else {
                return result(.awaitingAcceptance, ["sustained_bars_pending"], breakout: breakout,
                              evidenceBars: afterBreak, spread: spreadPips)
            }
            let selected = Array(confirmations.prefix(additionalBars))
            let acceptanceThreshold = holdBufferPips * configuration.pipSize
            guard selected.allSatisfy({ direction == .long
                ? $0.close > level + acceptanceThreshold
                : $0.close < level - acceptanceThreshold }) else {
                return result(.rejected, ["acceptance_hold_buffer_not_met"], breakout: breakout,
                              evidenceBars: selected, spread: spreadPips)
            }
            guard contiguous(selected, timeframe: configuration.timeframeSeconds) else {
                return result(.rejected, ["acceptance_sequence_gap"], breakout: breakout,
                              evidenceBars: selected, spread: spreadPips)
            }
            acceptance = selected.last
        case .sustainedTimeBeyond(let duration, let holdBufferPips):
            var selected: [BreakoutAcceptanceBar] = []
            let acceptanceThreshold = holdBufferPips * configuration.pipSize
            for bar in afterBreak.dropFirst() {
                if direction == .long ? bar.close <= level + acceptanceThreshold
                                      : bar.close >= level - acceptanceThreshold {
                    let inside = direction == .long ? bar.close <= level : bar.close >= level
                    return result(.rejected, [inside ? "acceptance_failed_back_inside" : "acceptance_hold_buffer_not_met"], breakout: breakout,
                                  evidenceBars: selected + [bar], spread: spreadPips)
                }
                selected.append(bar)
                guard contiguous(selected, timeframe: configuration.timeframeSeconds) else {
                    return result(.rejected, ["acceptance_sequence_gap"], breakout: breakout,
                                  evidenceBars: selected, spread: spreadPips)
                }
                if selected.last!.endTime(timeframeSeconds: configuration.timeframeSeconds)
                    .timeIntervalSince(breakout.endTime(timeframeSeconds: configuration.timeframeSeconds)) >= duration { break }
            }
            guard let last = selected.last,
                  last.endTime(timeframeSeconds: configuration.timeframeSeconds)
                    .timeIntervalSince(breakout.endTime(timeframeSeconds: configuration.timeframeSeconds)) >= duration else {
                return result(.awaitingAcceptance, ["sustained_duration_pending"], breakout: breakout,
                              evidenceBars: selected, spread: spreadPips)
            }
            acceptance = last
        case .boundedRetestHold(let maximumBars, let tolerancePips, let confirmationBufferPips):
            let subsequent = Array(afterBreak.dropFirst())
            let window = Array(subsequent.prefix(maximumBars))
            if window.contains(where: { bar in
                direction == .long
                    ? bar.low < level - tolerancePips * configuration.pipSize
                    : bar.high > level + tolerancePips * configuration.pipSize
            }) {
                return result(.rejected, ["retest_breached_tolerance"], breakout: breakout,
                              evidenceBars: window, spread: spreadPips)
            }
            guard let retestIndex = window.firstIndex(where: { bar in
                direction == .long
                    ? bar.low >= level - tolerancePips * configuration.pipSize
                        && bar.low <= level + tolerancePips * configuration.pipSize
                    : bar.high <= level + tolerancePips * configuration.pipSize
                        && bar.high >= level - tolerancePips * configuration.pipSize
            }) else {
                if subsequent.count >= maximumBars {
                    return result(.expired, ["retest_window_expired"], breakout: breakout,
                                  evidenceBars: window, spread: spreadPips)
                }
                return result(.awaitingAcceptance, ["retest_pending"], breakout: breakout,
                              evidenceBars: window, spread: spreadPips)
            }
            let retest = window[retestIndex]
            let held = direction == .long
                ? retest.close > level && retest.close >= level + confirmationBufferPips * configuration.pipSize
                : retest.close < level && retest.close <= level - confirmationBufferPips * configuration.pipSize
            guard held else {
                return result(.rejected, ["retest_failed_to_hold"], breakout: breakout,
                              evidenceBars: Array(window.prefix(retestIndex + 1)), spread: spreadPips)
            }
            acceptance = retest
        }
        guard let acceptance else {
            return result(.awaitingAcceptance, ["acceptance_pending"], breakout: breakout,
                          spread: spreadPips)
        }
        let eventAge = asOf.timeIntervalSince(acceptance.endTime(timeframeSeconds: configuration.timeframeSeconds))
        guard eventAge >= 0, eventAge <= configuration.maximumSetupAgeSeconds else {
            return result(.expired, ["accepted_setup_expired"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        if case .window(_, _, _, let sessionEnd) = configuration.sessionPolicy,
           asOf >= sessionEnd || acceptance.endTime(timeframeSeconds: configuration.timeframeSeconds) > sessionEnd {
            return result(.expired, ["session_end_expired"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        let acceptanceIndex = sortedBars.firstIndex(of: acceptance)!
        guard sortedBars.dropFirst(acceptanceIndex + 1).count
                <= configuration.maximumCompletedBarsAfterAcceptance else {
            return result(.expired, ["post_acceptance_bar_limit_expired"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        let signalPath = Array(sortedBars[breakoutIndex...])
        for bar in signalPath {
            let stopHit = direction == .long
                ? bar.low <= configuration.stop.price
                : bar.high >= configuration.stop.price
            let targetHit = direction == .long
                ? bar.high >= configuration.target.price
                : bar.low <= configuration.target.price
            if stopHit && targetHit {
                return result(.rejected, ["post_acceptance_barrier_order_ambiguous"], breakout: breakout,
                              accepted: acceptance, evidenceBars: signalPath, spread: spreadPips)
            }
            if stopHit {
                return result(.rejected, ["frozen_stop_already_touched"], breakout: breakout,
                              accepted: acceptance, evidenceBars: signalPath, spread: spreadPips)
            }
            if targetHit {
                return result(.expired, ["frozen_target_already_reached"], breakout: breakout,
                              accepted: acceptance, evidenceBars: signalPath, spread: spreadPips)
            }
        }
        let afterAcceptance = sortedBars.dropFirst(acceptanceIndex + 1)
        if case .range(_, let high, let low, _) = configuration.structure,
           afterAcceptance.contains(where: { $0.high >= high.price && $0.low <= low.price }) {
            return result(.rejected, ["ambiguous_dual_boundary_after_acceptance"], breakout: breakout,
                          accepted: acceptance, evidenceBars: Array(afterAcceptance), spread: spreadPips)
        }
        let invalidated = afterAcceptance.contains { bar in
            direction == .long ? bar.close <= level : bar.close >= level
        }
        guard !invalidated else {
            return result(.rejected, ["setup_invalidated_after_acceptance"], breakout: breakout,
                          accepted: acceptance, evidenceBars: Array(sortedBars[...acceptanceIndex]),
                          spread: spreadPips)
        }

        let entry = direction == .long ? quote.ask : quote.bid
        let adverseDriftPips = direction == .long
            ? max(0, entry - acceptance.close) / configuration.pipSize
            : max(0, acceptance.close - entry) / configuration.pipSize
        guard adverseDriftPips <= configuration.maximumAdverseEntryDriftPips else {
            return result(.rejected, ["adverse_entry_drift_exceeds_config"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        let correctlyOrdered = direction == .long
            ? configuration.stop.price < entry && entry < configuration.target.price
            : configuration.target.price < entry && entry < configuration.stop.price
        guard correctlyOrdered else {
            return result(.rejected, ["entry_stop_target_order_invalid"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        let expectedMovementPips = abs(configuration.target.price - entry) / configuration.pipSize
        let totalCostPips = spreadPips + configuration.additionalCostsPips
        guard totalCostPips > 0,
              expectedMovementPips / totalCostPips >= configuration.minimumMovementToCostRatio else {
            return result(.rejected, ["movement_to_cost_below_config"], breakout: breakout,
                          accepted: acceptance, spread: spreadPips)
        }
        return result(.signal, ["ACCEPTED"], breakout: breakout, accepted: acceptance,
                      evidenceBars: Array(sortedBars[...sortedBars.firstIndex(of: acceptance)!]),
                      entry: entry, spread: spreadPips)
    }

    private static func contiguous(_ bars: [BreakoutAcceptanceBar], timeframe: Int) -> Bool {
        bars.count < 2 || zip(bars, bars.dropFirst()).allSatisfy { left, right in
            right.startTime.timeIntervalSince(left.startTime) == TimeInterval(timeframe)
        }
    }

    private static func inputDigest(configuration: BreakoutAcceptanceConfiguration,
                                     bars: [BreakoutAcceptanceBar],
                                     regime: BreakoutAcceptanceRegimeMeasurement,
                                     quote: BreakoutAcceptanceQuote, asOf: Date,
                                     previousEventTimes: [Date]) -> String {
        struct Input: Encodable {
            let configuration: BreakoutAcceptanceConfiguration
            let bars: [BreakoutAcceptanceBar]
            let regime: BreakoutAcceptanceRegimeMeasurement
            let quote: BreakoutAcceptanceQuote
            let asOf: Date
            let previousEventTimes: [Date]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let sorted = bars.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        let prior = previousEventTimes.sorted()
        guard let data = try? encoder.encode(Input(configuration: configuration, bars: sorted,
            regime: regime, quote: quote, asOf: asOf, previousEventTimes: prior)) else { return "" }
        return BreakoutAcceptanceDigest.hash(data)
    }
}

private enum BreakoutAcceptanceDigest {
    static func sha256<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        guard let data = try? encoder.encode(value) else { return "" }
        return hash(data)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
