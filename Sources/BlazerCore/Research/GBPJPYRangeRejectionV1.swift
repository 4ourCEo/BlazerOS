import CryptoKit
import Foundation

/// Completed source bar for the GBP/JPY range-rejection research candidate.
public struct GBPJPYRangeRejectionBar: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let startTime: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(id: String, startTime: Date, open: Double, high: Double,
                low: Double, close: Double, complete: Bool) {
        self.id = id
        self.startTime = startTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.complete = complete
    }

    public var isValid: Bool {
        !id.isEmpty && startTime.timeIntervalSince1970.isFinite
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
    }
}

public struct GBPJPYRangeRejectionQuote: Codable, Sendable, Equatable {
    public let sourceID: String
    public let bid: Double
    public let ask: Double
    public let observedAt: Date

    public init(sourceID: String, bid: Double, ask: Double, observedAt: Date) {
        self.sourceID = sourceID
        self.bid = bid
        self.ask = ask
        self.observedAt = observedAt
    }
}

public enum GBPJPYRangeRejectionTargetPolicy: Codable, Sendable, Equatable {
    case rangeMidpoint
    case fixedRMultiple(Double)
}

/// All thresholds and session rules are explicit. The evaluator has no implicit
/// defaults: an experiment must freeze this complete configuration before scoring.
public struct GBPJPYRangeRejectionConfiguration: Codable, Sendable, Equatable {
    public let version: String
    public let timeZoneIdentifier: String
    public let rangeStartHour: Int
    public let rangeStartMinute: Int
    public let rangeCutoffHour: Int
    public let rangeCutoffMinute: Int
    public let timeframeSeconds: Int
    public let minimumRangePips: Double
    public let maximumRangePips: Double
    public let touchTolerancePips: Double
    public let atrLookbackBars: Int
    public let maximumEventRangeATR: Double
    public let stopBufferATRMultiple: Double
    public let targetPolicy: GBPJPYRangeRejectionTargetPolicy
    public let maximumSpreadPips: Double
    public let maximumEventAgeSeconds: TimeInterval
    public let maximumQuoteAgeSeconds: TimeInterval
    public let cooldownSeconds: TimeInterval

    public init(version: String, timeZoneIdentifier: String,
                rangeStartHour: Int, rangeStartMinute: Int,
                rangeCutoffHour: Int, rangeCutoffMinute: Int,
                timeframeSeconds: Int, minimumRangePips: Double,
                maximumRangePips: Double, touchTolerancePips: Double,
                atrLookbackBars: Int, maximumEventRangeATR: Double,
                stopBufferATRMultiple: Double, targetPolicy: GBPJPYRangeRejectionTargetPolicy,
                maximumSpreadPips: Double, maximumEventAgeSeconds: TimeInterval,
                maximumQuoteAgeSeconds: TimeInterval, cooldownSeconds: TimeInterval) {
        self.version = version
        self.timeZoneIdentifier = timeZoneIdentifier
        self.rangeStartHour = rangeStartHour
        self.rangeStartMinute = rangeStartMinute
        self.rangeCutoffHour = rangeCutoffHour
        self.rangeCutoffMinute = rangeCutoffMinute
        self.timeframeSeconds = timeframeSeconds
        self.minimumRangePips = minimumRangePips
        self.maximumRangePips = maximumRangePips
        self.touchTolerancePips = touchTolerancePips
        self.atrLookbackBars = atrLookbackBars
        self.maximumEventRangeATR = maximumEventRangeATR
        self.stopBufferATRMultiple = stopBufferATRMultiple
        self.targetPolicy = targetPolicy
        self.maximumSpreadPips = maximumSpreadPips
        self.maximumEventAgeSeconds = maximumEventAgeSeconds
        self.maximumQuoteAgeSeconds = maximumQuoteAgeSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if version.isEmpty { issues.append("strategy_version_missing") }
        if TimeZone(identifier: timeZoneIdentifier) == nil { issues.append("timezone_invalid") }
        let startMinute = rangeStartHour * 60 + rangeStartMinute
        let cutoffMinute = rangeCutoffHour * 60 + rangeCutoffMinute
        if !(0..<24).contains(rangeStartHour) || !(0..<60).contains(rangeStartMinute)
            || !(0..<24).contains(rangeCutoffHour) || !(0..<60).contains(rangeCutoffMinute)
            || cutoffMinute <= startMinute {
            issues.append("session_range_invalid")
        }
        let rangeSeconds = (cutoffMinute - startMinute) * 60
        if timeframeSeconds <= 0 || rangeSeconds <= 0 || rangeSeconds % timeframeSeconds != 0 {
            issues.append("timeframe_does_not_tile_range")
        }
        if !minimumRangePips.isFinite || minimumRangePips <= 0
            || !maximumRangePips.isFinite || maximumRangePips < minimumRangePips {
            issues.append("range_width_invalid")
        }
        if !touchTolerancePips.isFinite || touchTolerancePips < 0 { issues.append("touch_tolerance_invalid") }
        if atrLookbackBars < 2 { issues.append("atr_lookback_invalid") }
        if !maximumEventRangeATR.isFinite || maximumEventRangeATR <= 0 { issues.append("atr_expansion_limit_invalid") }
        if !stopBufferATRMultiple.isFinite || stopBufferATRMultiple <= 0 { issues.append("stop_buffer_atr_multiple_invalid") }
        if case .fixedRMultiple(let multiple) = targetPolicy,
           !multiple.isFinite || multiple <= 0 { issues.append("target_r_multiple_invalid") }
        if !maximumSpreadPips.isFinite || maximumSpreadPips <= 0 { issues.append("spread_limit_invalid") }
        if !maximumEventAgeSeconds.isFinite || maximumEventAgeSeconds <= 0 { issues.append("event_age_invalid") }
        if !maximumQuoteAgeSeconds.isFinite || maximumQuoteAgeSeconds <= 0 { issues.append("quote_age_invalid") }
        if !cooldownSeconds.isFinite || cooldownSeconds < 0 { issues.append("cooldown_invalid") }
        return issues.sorted()
    }

    public func digest() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum GBPJPYRangeRejectionDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
    case wait = "WAIT"
}

public enum GBPJPYRangeRejectionState: String, Codable, Sendable, Equatable {
    case signal = "SIGNAL"
    case wait = "WAIT"
    case rejected = "REJECTED"
}

/// Research evidence only. It is not an order, account-sized position, or fill.
public struct GBPJPYRangeRejectionDecision: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let strategyID: String
    public let strategyVersion: String
    public let configurationDigest: String
    public let inputDigest: String
    public let instrument: String
    public let timeframeSeconds: Int
    public let state: GBPJPYRangeRejectionState
    public let direction: GBPJPYRangeRejectionDirection
    public let reasonCodes: [String]
    public let rangeStart: Date?
    public let rangeCutoff: Date?
    public let rangeHigh: Double?
    public let rangeLow: Double?
    public let eventBarID: String?
    public let sourceBarIDs: [String]
    public let quoteSourceID: String?
    public let quoteObservedAt: Date?
    public let entryPrice: Double?
    public let stopPrice: Double?
    public let targetPrice: Double?
    public let spreadPips: Double?
    public let observedAt: Date

    fileprivate init(strategyVersion: String, configurationDigest: String,
                     inputDigest: String, state: GBPJPYRangeRejectionState,
                     direction: GBPJPYRangeRejectionDirection, reasonCodes: [String],
                     timeframeSeconds: Int,
                     rangeStart: Date?, rangeCutoff: Date?, rangeHigh: Double?, rangeLow: Double?,
                     eventBarID: String?, sourceBarIDs: [String], quoteSourceID: String?, quoteObservedAt: Date?,
                     entryPrice: Double?, stopPrice: Double?, targetPrice: Double?,
                     spreadPips: Double?, observedAt: Date) {
        self.strategyID = "GBPJPY_RANGE_REJECTION"
        self.strategyVersion = strategyVersion
        self.configurationDigest = configurationDigest
        self.inputDigest = inputDigest
        self.instrument = "GBP/JPY"
        self.timeframeSeconds = timeframeSeconds
        self.state = state
        self.direction = direction
        self.reasonCodes = reasonCodes
        self.rangeStart = rangeStart
        self.rangeCutoff = rangeCutoff
        self.rangeHigh = rangeHigh
        self.rangeLow = rangeLow
        self.eventBarID = eventBarID
        self.sourceBarIDs = sourceBarIDs
        self.quoteSourceID = quoteSourceID
        self.quoteObservedAt = quoteObservedAt
        self.entryPrice = entryPrice
        self.stopPrice = stopPrice
        self.targetPrice = targetPrice
        self.spreadPips = spreadPips
        self.observedAt = observedAt
        id = "range-rejection-\(eventBarID ?? "wait")-\(String(inputDigest.prefix(16)))"
    }
}

public enum GBPJPYRangeRejectionV1 {
    public static let strategyID = "GBPJPY_RANGE_REJECTION"

    public static func evaluate(bars: [GBPJPYRangeRejectionBar],
                                quote: GBPJPYRangeRejectionQuote?,
                                asOf: Date,
                                configuration: GBPJPYRangeRejectionConfiguration,
                                lastSignalAt: Date? = nil) -> GBPJPYRangeRejectionDecision {
        let digest = inputDigest(bars: bars, quote: quote, asOf: asOf,
                                 configuration: configuration, lastSignalAt: lastSignalAt)
        let configDigest = configuration.digest()
        guard configuration.validationIssues().isEmpty else {
            return decision(.rejected, .wait, ["configuration_invalid"], bars: [], quote: quote,
                            asOf: asOf, configuration: configuration, configDigest: configDigest,
                            inputDigest: digest)
        }
        guard asOf.timeIntervalSince1970.isFinite,
              let timeZone = TimeZone(identifier: configuration.timeZoneIdentifier) else {
            return decision(.rejected, .wait, ["evaluation_time_invalid"], bars: [], quote: quote,
                            asOf: asOf, configuration: configuration, configDigest: configDigest,
                            inputDigest: digest)
        }
        let timeframe = TimeInterval(configuration.timeframeSeconds)
        let validBars = bars.filter { bar in
            bar.complete && bar.isValid
                && bar.startTime.addingTimeInterval(timeframe) <= asOf
                && bar.startTime.addingTimeInterval(timeframe).timeIntervalSince1970.isFinite
        }.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        if bars.contains(where: { bar in
            bar.complete && bar.startTime.timeIntervalSince1970.isFinite
                && bar.startTime.addingTimeInterval(timeframe) <= asOf && !bar.isValid
        }) {
            return decision(.rejected, .wait, ["completed_bar_invalid"], bars: [],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest)
        }
        guard Set(validBars.map(\.id)).count == validBars.count,
              Set(validBars.map(\.startTime)).count == validBars.count else {
            return decision(.rejected, .wait, ["duplicate_bar_identity_or_time"], bars: validBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let rangeStart = calendar.date(bySettingHour: configuration.rangeStartHour,
                minute: configuration.rangeStartMinute, second: 0, of: asOf),
              let rangeCutoff = calendar.date(bySettingHour: configuration.rangeCutoffHour,
                minute: configuration.rangeCutoffMinute, second: 0, of: asOf) else {
            return decision(.rejected, .wait, ["session_boundary_unavailable"], bars: validBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest)
        }
        let configuredRangeSeconds = TimeInterval(((configuration.rangeCutoffHour * 60
            + configuration.rangeCutoffMinute) - (configuration.rangeStartHour * 60
            + configuration.rangeStartMinute)) * 60)
        guard rangeCutoff.timeIntervalSince(rangeStart) == configuredRangeSeconds else {
            return decision(.rejected, .wait, ["session_boundary_elapsed_duration_mismatch"], bars: validBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff)
        }
        guard asOf >= rangeCutoff else {
            return decision(.wait, .wait, ["session_range_not_closed"], bars: validBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff)
        }
        let rangeBars = validBars.filter {
            $0.startTime >= rangeStart && $0.startTime.addingTimeInterval(timeframe) <= rangeCutoff
        }
        let expectedCount = Int(rangeCutoff.timeIntervalSince(rangeStart) / timeframe)
        guard expectedCount > 0, rangeBars.count == expectedCount,
              rangeBars.first?.startTime == rangeStart,
              rangeBars.enumerated().allSatisfy({ index, bar in
                  bar.startTime == rangeStart.addingTimeInterval(Double(index) * timeframe)
              }) else {
            return decision(.wait, .wait, ["session_range_incomplete_or_gapped"], bars: rangeBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff)
        }
        let rangeHigh = rangeBars.map(\.high).max()!
        let rangeLow = rangeBars.map(\.low).min()!
        let pip = Assets.pipScale(for: "GBP/JPY")
        let rangeWidthPips = (rangeHigh - rangeLow) / pip
        guard rangeWidthPips >= configuration.minimumRangePips,
              rangeWidthPips <= configuration.maximumRangePips else {
            return decision(.rejected, .wait, ["session_range_width_outside_config"], bars: rangeBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow)
        }

        let postRangeBars = validBars.filter { $0.startTime >= rangeCutoff }
        guard postRangeBars.allSatisfy({ bar in
            let offset = bar.startTime.timeIntervalSince(rangeCutoff)
            return offset >= 0 && abs(offset.truncatingRemainder(dividingBy: timeframe)) < 0.000_001
        }) else {
            return decision(.rejected, .wait, ["post_range_bar_off_timeframe_grid"], bars: rangeBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow)
        }
        let touchedBars = postRangeBars.filter {
            $0.high >= rangeHigh - configuration.touchTolerancePips * pip
                || $0.low <= rangeLow + configuration.touchTolerancePips * pip
        }
        guard let eventBar = touchedBars.last else {
            return decision(.wait, .wait, ["post_range_event_bar_missing"], bars: rangeBars,
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow)
        }
        let eventEnd = eventBar.startTime.addingTimeInterval(timeframe)
        let tolerance = configuration.touchTolerancePips * pip
        let upperTouch = eventBar.high >= rangeHigh - tolerance
        let lowerTouch = eventBar.low <= rangeLow + tolerance
        guard eventBar.close >= rangeLow, eventBar.close <= rangeHigh else {
            return decision(.rejected, .wait, ["rejection_close_outside_range"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let upperRejected = upperTouch && eventBar.close >= rangeLow && eventBar.close < rangeHigh
        let lowerRejected = lowerTouch && eventBar.close > rangeLow && eventBar.close <= rangeHigh
        guard upperRejected || lowerRejected else {
            return decision(.wait, .wait, ["range_boundary_rejection_not_confirmed"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        guard upperRejected != lowerRejected else {
            return decision(.rejected, .wait, ["ambiguous_two_boundary_rejection"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let direction: GBPJPYRangeRejectionDirection = lowerRejected ? .long : .short
        let age = asOf.timeIntervalSince(eventEnd)
        guard age >= 0, age <= configuration.maximumEventAgeSeconds else {
            return decision(.rejected, direction, ["event_stale"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        if let lastSignalAt, asOf.timeIntervalSince(lastSignalAt) < configuration.cooldownSeconds {
            return decision(.wait, .wait, ["signal_cooldown_active"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let preEventBars = validBars.filter { $0.startTime.addingTimeInterval(timeframe) <= eventBar.startTime }
        guard let atr = averageTrueRange(preEventBars, count: configuration.atrLookbackBars,
                                         timeframe: timeframe), atr > 0 else {
            return decision(.wait, .wait, ["atr_history_incomplete"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let previousClose = preEventBars.last!.close
        let eventTrueRange = max(eventBar.high - eventBar.low,
                                 max(abs(eventBar.high - previousClose), abs(eventBar.low - previousClose)))
        guard eventTrueRange / atr <= configuration.maximumEventRangeATR else {
            return decision(.rejected, .wait, ["atr_expansion_veto"], bars: rangeBars + preEventBars.suffix(configuration.atrLookbackBars + 1) + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        guard let quote,
              !quote.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              quote.bid.isFinite, quote.ask.isFinite, quote.bid > 0, quote.ask > quote.bid,
              quote.observedAt.timeIntervalSince1970.isFinite,
              quote.observedAt >= eventEnd, quote.observedAt <= asOf,
              asOf.timeIntervalSince(quote.observedAt) <= configuration.maximumQuoteAgeSeconds else {
            return decision(.rejected, .wait, ["fresh_post_confirmation_quote_required"], bars: rangeBars + [eventBar],
                            quote: quote, asOf: asOf, configuration: configuration,
                            configDigest: configDigest, inputDigest: digest,
                            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let spreadPips = (quote.ask - quote.bid) / pip
        guard spreadPips <= configuration.maximumSpreadPips else {
            return decision(.rejected, .wait, ["spread_exceeds_config"], bars: rangeBars + [eventBar],
                            quote: quote, spreadPips: spreadPips, asOf: asOf,
                            configuration: configuration, configDigest: configDigest,
                            inputDigest: digest, rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        let entry = direction == .long ? quote.ask : quote.bid
        let stop = direction == .long
            ? min(rangeLow, eventBar.low) - configuration.stopBufferATRMultiple * atr
            : max(rangeHigh, eventBar.high) + configuration.stopBufferATRMultiple * atr
        let midpoint = (rangeHigh + rangeLow) / 2
        let target: Double
        switch configuration.targetPolicy {
        case .rangeMidpoint: target = midpoint
        case .fixedRMultiple(let multiple):
            let risk = abs(entry - stop)
            target = direction == .long ? entry + risk * multiple : entry - risk * multiple
        }
        let correctlyOrdered = direction == .long
            ? stop < entry && entry < target
            : target < entry && entry < stop
        guard [entry, stop, target].allSatisfy({ $0.isFinite && $0 > 0 }), correctlyOrdered else {
            return decision(.rejected, .wait, ["entry_stop_target_order_invalid"], bars: rangeBars + [eventBar],
                            quote: quote, spreadPips: spreadPips, asOf: asOf,
                            configuration: configuration, configDigest: configDigest,
                            inputDigest: digest, rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                            rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar)
        }
        return decision(.signal, direction, [], bars: rangeBars + preEventBars.suffix(configuration.atrLookbackBars + 1) + [eventBar],
                        quote: quote, spreadPips: spreadPips, asOf: asOf,
                        configuration: configuration, configDigest: configDigest,
                        inputDigest: digest, rangeStart: rangeStart, rangeCutoff: rangeCutoff,
                        rangeHigh: rangeHigh, rangeLow: rangeLow, eventBar: eventBar,
                        entry: entry, stop: stop, target: target)
    }

    private static func averageTrueRange(_ bars: [GBPJPYRangeRejectionBar], count: Int,
                                         timeframe: TimeInterval) -> Double? {
        guard bars.count >= count + 1 else { return nil }
        let selected = Array(bars.suffix(count + 1))
        guard selected.enumerated().dropFirst().allSatisfy({ index, bar in
            bar.startTime == selected[index - 1].startTime.addingTimeInterval(timeframe)
        }) else { return nil }
        let ranges = selected.indices.dropFirst().map { index -> Double in
            let bar = selected[index]
            let priorClose = selected[index - 1].close
            return max(bar.high - bar.low,
                       max(abs(bar.high - priorClose), abs(bar.low - priorClose)))
        }
        return ranges.reduce(0, +) / Double(ranges.count)
    }

    private static func decision(_ state: GBPJPYRangeRejectionState,
                                 _ direction: GBPJPYRangeRejectionDirection,
                                 _ reasons: [String],
                                 bars: [GBPJPYRangeRejectionBar],
                                 quote: GBPJPYRangeRejectionQuote?,
                                 spreadPips: Double? = nil,
                                 asOf: Date,
                                 configuration: GBPJPYRangeRejectionConfiguration,
                                 configDigest: String,
                                 inputDigest: String,
                                 rangeStart: Date? = nil,
                                 rangeCutoff: Date? = nil,
                                 rangeHigh: Double? = nil,
                                 rangeLow: Double? = nil,
                                 eventBar: GBPJPYRangeRejectionBar? = nil,
                                 entry: Double? = nil,
                                 stop: Double? = nil,
                                 target: Double? = nil) -> GBPJPYRangeRejectionDecision {
        GBPJPYRangeRejectionDecision(strategyVersion: configuration.version,
            configurationDigest: configDigest, inputDigest: inputDigest,
            state: state, direction: direction, reasonCodes: reasons,
            timeframeSeconds: configuration.timeframeSeconds,
            rangeStart: rangeStart, rangeCutoff: rangeCutoff,
            rangeHigh: rangeHigh, rangeLow: rangeLow,
            eventBarID: eventBar?.id, sourceBarIDs: Array(Set(bars.map(\.id))).sorted(),
            quoteSourceID: quote?.sourceID,
            quoteObservedAt: quote?.observedAt, entryPrice: entry,
            stopPrice: stop, targetPrice: target, spreadPips: spreadPips,
            observedAt: asOf)
    }

    private static func inputDigest(bars: [GBPJPYRangeRejectionBar],
                                    quote: GBPJPYRangeRejectionQuote?, asOf: Date,
                                    configuration: GBPJPYRangeRejectionConfiguration,
                                    lastSignalAt: Date?) -> String {
        struct Input: Encodable {
            let bars: [GBPJPYRangeRejectionBar]
            let quote: GBPJPYRangeRejectionQuote?
            let asOf: Date
            let configuration: GBPJPYRangeRejectionConfiguration
            let lastSignalAt: Date?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let timeframe = TimeInterval(configuration.timeframeSeconds)
        let completedBars = bars.filter {
            $0.complete && $0.startTime.timeIntervalSince1970.isFinite
                && $0.startTime.addingTimeInterval(timeframe) <= asOf
        }.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        guard let data = try? encoder.encode(Input(bars: completedBars, quote: quote, asOf: asOf,
                                                  configuration: configuration,
                                                  lastSignalAt: lastSignalAt)) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
