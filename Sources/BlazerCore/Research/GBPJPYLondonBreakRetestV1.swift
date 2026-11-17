import CryptoKit
import Foundation

/// A provider bar retained with its native M1 identity. This candidate deliberately
/// accepts M1 only; callers must not pass unlabeled synthesized M3/M5 bars.
public struct GBPJPYLondonBreakRetestBar: Codable, Sendable, Equatable {
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
                open: Double, high: Double, low: Double, close: Double,
                complete: Bool = true) {
        self.id = id; self.instrument = instrument; self.provider = provider
        self.startTime = startTime; self.open = open; self.high = high
        self.low = low; self.close = close; self.complete = complete
    }

    fileprivate var valid: Bool {
        !id.isEmpty && !instrument.isEmpty && !provider.isEmpty
            && startTime.timeIntervalSince1970.isFinite
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
    }
}

/// Explicit absolute instants resolved by the caller's versioned London calendar.
/// The candidate stores the calendar digest and never reconstructs DST-sensitive
/// wall-clock boundaries itself.
public struct GBPJPYLondonBreakRetestSession: Codable, Sendable, Equatable {
    public let id: String
    public let timeZoneIdentifier: String
    public let calendarDigest: String
    public let opensAt: Date
    public let rangeStartsAt: Date
    public let rangeEndsAt: Date
    public let closesAt: Date

    public init(id: String, timeZoneIdentifier: String, calendarDigest: String,
                opensAt: Date, rangeStartsAt: Date, rangeEndsAt: Date, closesAt: Date) {
        self.id = id; self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarDigest = calendarDigest; self.opensAt = opensAt
        self.rangeStartsAt = rangeStartsAt; self.rangeEndsAt = rangeEndsAt
        self.closesAt = closesAt
    }
}

public struct GBPJPYLondonBreakRetestQuote: Codable, Sendable, Equatable {
    public let sourceID: String
    public let bid: Double
    public let ask: Double
    public let observedAt: Date

    public init(sourceID: String, bid: Double, ask: Double, observedAt: Date) {
        self.sourceID = sourceID; self.bid = bid; self.ask = ask; self.observedAt = observedAt
    }
}

public struct GBPJPYLondonBreakRetestProvenance: Codable, Sendable, Equatable {
    public let provider: String
    public let environment: String
    public let buildID: String
    public let codeDigest: String
    public let snapshotDigest: String
    public let lineageIsProviderNative: Bool

    public init(provider: String, environment: String, buildID: String, codeDigest: String,
                snapshotDigest: String, lineageIsProviderNative: Bool) {
        self.provider = provider; self.environment = environment; self.buildID = buildID
        self.codeDigest = codeDigest; self.snapshotDigest = snapshotDigest
        self.lineageIsProviderNative = lineageIsProviderNative
    }
}

/// Versioned ATR definitions prevent configuration from silently selecting a
/// volatility calculation. Unknown future methods decode as unsupported and fail closed.
public enum GBPJPYLondonBreakRetestATRMethod: Sendable, Equatable, Codable {
    case simpleMeanTrueRangeV1
    case unsupported(String)

    private var identifier: String {
        switch self {
        case .simpleMeanTrueRangeV1: "SIMPLE_MEAN_TRUE_RANGE_V1"
        case .unsupported(let value): value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = value == "SIMPLE_MEAN_TRUE_RANGE_V1"
            ? .simpleMeanTrueRangeV1 : .unsupported(value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}

/// All strategy thresholds are mandatory and expressed in explicit price/pip units.
/// There is intentionally no default or built-in production profile.
public struct GBPJPYLondonBreakRetestConfiguration: Codable, Sendable, Equatable {
    public let version: String
    public let pipSize: Double
    public let rangeDurationSeconds: Int
    public let minimumRangePips: Double
    public let maximumRangePips: Double
    public let minimumBreakoutPips: Double
    public let retestTolerancePips: Double
    public let maximumRetestBars: Int
    public let atrMethod: GBPJPYLondonBreakRetestATRMethod
    public let atrLookbackBars: Int
    public let stopBufferATRMultiple: Double
    public let targetRMultiple: Double
    public let maximumSpreadPips: Double
    public let maximumQuoteAgeSeconds: TimeInterval
    public let maximumSetupAgeSeconds: TimeInterval
    public let cooldownSeconds: TimeInterval

    public init(version: String, pipSize: Double, rangeDurationSeconds: Int,
                minimumRangePips: Double, maximumRangePips: Double,
                minimumBreakoutPips: Double, retestTolerancePips: Double,
                maximumRetestBars: Int, atrMethod: GBPJPYLondonBreakRetestATRMethod,
                atrLookbackBars: Int,
                stopBufferATRMultiple: Double, targetRMultiple: Double,
                maximumSpreadPips: Double, maximumQuoteAgeSeconds: TimeInterval,
                maximumSetupAgeSeconds: TimeInterval, cooldownSeconds: TimeInterval) {
        self.version = version; self.pipSize = pipSize
        self.rangeDurationSeconds = rangeDurationSeconds
        self.minimumRangePips = minimumRangePips; self.maximumRangePips = maximumRangePips
        self.minimumBreakoutPips = minimumBreakoutPips
        self.retestTolerancePips = retestTolerancePips
        self.maximumRetestBars = maximumRetestBars; self.atrMethod = atrMethod
        self.atrLookbackBars = atrLookbackBars
        self.stopBufferATRMultiple = stopBufferATRMultiple; self.targetRMultiple = targetRMultiple
        self.maximumSpreadPips = maximumSpreadPips
        self.maximumQuoteAgeSeconds = maximumQuoteAgeSeconds
        self.maximumSetupAgeSeconds = maximumSetupAgeSeconds
        self.cooldownSeconds = cooldownSeconds
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        if version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("version_missing") }
        if !pipSize.isFinite || pipSize <= 0 { issues.append("pip_size_invalid") }
        if rangeDurationSeconds < 60 || rangeDurationSeconds % 60 != 0 { issues.append("range_duration_invalid") }
        if !minimumRangePips.isFinite || minimumRangePips <= 0
            || !maximumRangePips.isFinite || maximumRangePips < minimumRangePips {
            issues.append("range_width_invalid")
        }
        if !minimumBreakoutPips.isFinite || minimumBreakoutPips <= 0 { issues.append("breakout_distance_invalid") }
        if !retestTolerancePips.isFinite || retestTolerancePips <= 0 { issues.append("retest_tolerance_invalid") }
        if maximumRetestBars < 1 { issues.append("maximum_retest_bars_invalid") }
        if atrMethod != .simpleMeanTrueRangeV1 { issues.append("atr_method_unsupported") }
        if atrLookbackBars < 2 { issues.append("atr_lookback_invalid") }
        if !stopBufferATRMultiple.isFinite || stopBufferATRMultiple <= 0 { issues.append("stop_buffer_invalid") }
        if !targetRMultiple.isFinite || targetRMultiple <= 0 { issues.append("target_r_invalid") }
        if !maximumSpreadPips.isFinite || maximumSpreadPips <= 0 { issues.append("spread_limit_invalid") }
        if !maximumQuoteAgeSeconds.isFinite || maximumQuoteAgeSeconds <= 0 { issues.append("quote_age_invalid") }
        if !maximumSetupAgeSeconds.isFinite || maximumSetupAgeSeconds <= 0 { issues.append("setup_age_invalid") }
        if !cooldownSeconds.isFinite || cooldownSeconds < 0 { issues.append("cooldown_invalid") }
        return Array(Set(issues)).sorted()
    }

    public func digest() -> String { GBPJPYLondonBreakRetestV1.digest(self) }
}

public enum GBPJPYLondonBreakRetestDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
    case wait = "WAIT"
}

public enum GBPJPYLondonBreakRetestState: String, Codable, Sendable, Equatable {
    case wait = "WAIT"
    case signal = "RESEARCH_CANDIDATE"
    case rejected = "REJECTED"
    case expired = "EXPIRED"
}

public enum GBPJPYLondonBreakRetestReason: String, Codable, Sendable, Equatable {
    case configurationInvalid = "CONFIGURATION_INVALID"
    case sessionInvalid = "SESSION_INVALID"
    case provenanceInvalid = "PROVENANCE_INVALID"
    case waitingForRange = "WAITING_FOR_RANGE"
    case rangeDataInvalid = "RANGE_DATA_INVALID"
    case rangeTooNarrow = "RANGE_TOO_NARROW"
    case rangeTooWide = "RANGE_TOO_WIDE"
    case waitingForBreakout = "WAITING_FOR_BREAKOUT"
    case breakoutAmbiguous = "BREAKOUT_AMBIGUOUS"
    case waitingForRetest = "WAITING_FOR_RETEST"
    case retestFailed = "RETEST_FAILED"
    case retestExpired = "RETEST_EXPIRED"
    case sessionClosed = "SESSION_CLOSED"
    case setupTooOld = "SETUP_TOO_OLD"
    case cooldownActive = "COOLDOWN_ACTIVE"
    case quoteMissing = "QUOTE_MISSING"
    case quoteInvalid = "QUOTE_INVALID"
    case quoteNotAfterRetest = "QUOTE_NOT_AFTER_RETEST"
    case quoteStale = "QUOTE_STALE"
    case spreadTooWide = "SPREAD_TOO_WIDE"
    case stopInvalid = "STOP_INVALID"
    case targetInvalid = "TARGET_INVALID"
    case setupReady = "SETUP_READY"
}

/// Research structure only. No account sizing, fill, or order semantics are represented.
public struct GBPJPYLondonBreakRetestDecision: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let strategyID: String
    public let version: String
    public let configurationDigest: String
    public let inputDigest: String
    public let state: GBPJPYLondonBreakRetestState
    public let direction: GBPJPYLondonBreakRetestDirection
    public let reason: GBPJPYLondonBreakRetestReason
    public let sessionID: String?
    public let calendarDigest: String?
    public let provider: String
    public let environment: String
    public let buildID: String
    public let codeDigest: String
    public let sourceSnapshotDigest: String
    public let rangeStart: Date?
    public let rangeEnd: Date?
    public let rangeHigh: Double?
    public let rangeLow: Double?
    public let breakoutBarID: String?
    public let retestBarID: String?
    public let sourceBarIDs: [String]
    public let quoteSourceID: String?
    public let quoteObservedAt: Date?
    public let entryReference: Double?
    public let stopReference: Double?
    public let targetReference: Double?
    public let spreadPips: Double?
    public let asOf: Date

    fileprivate init(inputDigest: String, configurationDigest: String,
        state: GBPJPYLondonBreakRetestState, direction: GBPJPYLondonBreakRetestDirection,
        reason: GBPJPYLondonBreakRetestReason, session: GBPJPYLondonBreakRetestSession?,
        provenance: GBPJPYLondonBreakRetestProvenance,
        rangeHigh: Double? = nil, rangeLow: Double? = nil,
        breakoutBarID: String? = nil, retestBarID: String? = nil,
        sourceBarIDs: [String] = [], quote: GBPJPYLondonBreakRetestQuote? = nil,
        entryReference: Double? = nil, stopReference: Double? = nil,
        targetReference: Double? = nil, spreadPips: Double? = nil, asOf: Date) {
        self.strategyID = GBPJPYLondonBreakRetestV1.strategyID
        self.version = "GBPJPY_LONDON_RANGE_BREAK_RETEST_V1"
        self.configurationDigest = configurationDigest; self.inputDigest = inputDigest
        self.state = state; self.direction = direction; self.reason = reason
        self.sessionID = session?.id; self.calendarDigest = session?.calendarDigest
        self.provider = provenance.provider; self.environment = provenance.environment
        self.buildID = provenance.buildID; self.codeDigest = provenance.codeDigest
        self.sourceSnapshotDigest = provenance.snapshotDigest
        self.rangeStart = session?.rangeStartsAt
        self.rangeEnd = session?.rangeEndsAt; self.rangeHigh = rangeHigh; self.rangeLow = rangeLow
        self.breakoutBarID = breakoutBarID; self.retestBarID = retestBarID
        self.sourceBarIDs = sourceBarIDs; self.quoteSourceID = quote?.sourceID
        self.quoteObservedAt = quote?.observedAt; self.entryReference = entryReference
        self.stopReference = stopReference; self.targetReference = targetReference
        self.spreadPips = spreadPips; self.asOf = asOf
        if let breakoutBarID, let retestBarID, let sessionID = session?.id {
            id = "gbpjpy-london-break-retest-\(sessionID)-\(breakoutBarID)-\(retestBarID)-\(String(configurationDigest.prefix(12)))"
        } else {
            id = "gbpjpy-london-break-retest-\(session?.id ?? "unknown")-\(String(inputDigest.prefix(16)))"
        }
    }
}

public enum GBPJPYLondonBreakRetestV1 {
    public static let strategyID = "GBPJPY_LONDON_RANGE_BREAK_RETEST"
    private static let barSeconds: TimeInterval = 60

    public static func evaluate(bars: [GBPJPYLondonBreakRetestBar],
        session: GBPJPYLondonBreakRetestSession,
        quote: GBPJPYLondonBreakRetestQuote?, provenance: GBPJPYLondonBreakRetestProvenance,
        asOf: Date, configuration: GBPJPYLondonBreakRetestConfiguration,
        lastSignalAt: Date? = nil) -> GBPJPYLondonBreakRetestDecision {
        let inputDigest = digest(Input(bars: bars, session: session, quote: quote,
            provenance: provenance, asOf: asOf, lastSignalAt: lastSignalAt,
            configurationDigest: configuration.digest()))
        let configDigest = configuration.digest()
        func result(_ state: GBPJPYLondonBreakRetestState, _ direction: GBPJPYLondonBreakRetestDirection,
                    _ reason: GBPJPYLondonBreakRetestReason,
                    rangeHigh: Double? = nil, rangeLow: Double? = nil,
                    breakout: String? = nil, retest: String? = nil, ids: [String] = [],
                    entry: Double? = nil, stop: Double? = nil, target: Double? = nil,
                    spread: Double? = nil) -> GBPJPYLondonBreakRetestDecision {
            GBPJPYLondonBreakRetestDecision(inputDigest: inputDigest, configurationDigest: configDigest,
                state: state, direction: direction, reason: reason, session: session,
                provenance: provenance,
                rangeHigh: rangeHigh, rangeLow: rangeLow, breakoutBarID: breakout,
                retestBarID: retest, sourceBarIDs: ids, quote: quote,
                entryReference: entry, stopReference: stop, targetReference: target,
                spreadPips: spread, asOf: asOf)
        }

        guard configuration.validationIssues().isEmpty else {
            return result(.rejected, .wait, .configurationInvalid)
        }
        guard asOf.timeIntervalSince1970.isFinite,
              session.opensAt.timeIntervalSince1970.isFinite,
              session.rangeStartsAt.timeIntervalSince1970.isFinite,
              session.rangeEndsAt.timeIntervalSince1970.isFinite,
              session.closesAt.timeIntervalSince1970.isFinite,
              !session.id.isEmpty, !session.calendarDigest.isEmpty,
              session.timeZoneIdentifier == "Europe/London",
              let zone = TimeZone(identifier: session.timeZoneIdentifier),
              session.opensAt <= session.rangeStartsAt,
              session.rangeStartsAt < session.rangeEndsAt,
              session.rangeEndsAt <= session.closesAt,
              session.closesAt.timeIntervalSince(session.rangeStartsAt)
                >= Double(configuration.rangeDurationSeconds),
              session.rangeEndsAt.timeIntervalSince(session.rangeStartsAt)
                == Double(configuration.rangeDurationSeconds),
              aligned(session.opensAt), aligned(session.rangeStartsAt),
              aligned(session.rangeEndsAt), aligned(session.closesAt) else {
            return result(.rejected, .wait, .sessionInvalid)
        }
        // The absolute instants are authoritative; checking the local date boundary
        // catches accidental cross-date session definitions without guessing DST.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let openDay = calendar.dateComponents([.era, .year, .month, .day], from: session.opensAt)
        let closeDay = calendar.dateComponents([.era, .year, .month, .day], from: session.closesAt)
        guard openDay == closeDay else { return result(.rejected, .wait, .sessionInvalid) }
        guard !provenance.provider.isEmpty, !provenance.environment.isEmpty,
              !provenance.buildID.isEmpty, validDigest(provenance.codeDigest),
              validDigest(provenance.snapshotDigest), provenance.lineageIsProviderNative,
              bars.allSatisfy({ $0.instrument == "GBP/JPY" && $0.provider == provenance.provider }) else {
            return result(.rejected, .wait, .provenanceInvalid)
        }
        guard asOf >= session.opensAt else { return result(.wait, .wait, .waitingForRange) }
        guard asOf < session.closesAt else { return result(.expired, .wait, .sessionClosed) }
        if let lastSignalAt {
            guard lastSignalAt.timeIntervalSince1970.isFinite, lastSignalAt <= asOf else {
                return result(.rejected, .wait, .configurationInvalid)
            }
            if asOf.timeIntervalSince(lastSignalAt) < configuration.cooldownSeconds {
                return result(.wait, .wait, .cooldownActive)
            }
        }

        guard !bars.isEmpty else { return result(.wait, .wait, .waitingForRange) }
        var seenIDs = Set<String>(), seenTimes = Set<Date>()
        var previousStart: Date?
        for bar in bars {
            guard bar.valid, seenIDs.insert(bar.id).inserted, seenTimes.insert(bar.startTime).inserted,
                  bar.startTime >= session.opensAt, bar.startTime < session.closesAt,
                  aligned(bar.startTime) else { return result(.rejected, .wait, .rangeDataInvalid) }
            if let previousStart,
               bar.startTime.timeIntervalSince(previousStart) != barSeconds {
                return result(.rejected, .wait, .rangeDataInvalid)
            }
            if bar.complete && bar.startTime.addingTimeInterval(barSeconds) > asOf {
                return result(.rejected, .wait, .rangeDataInvalid)
            }
            previousStart = bar.startTime
        }
        let completed = bars.filter { $0.complete && $0.startTime.addingTimeInterval(barSeconds) <= asOf }
        guard asOf >= session.rangeEndsAt else {
            return result(.wait, .wait, .waitingForRange, ids: completed.map(\.id))
        }
        let rangeBars = completed.filter {
            $0.startTime >= session.rangeStartsAt
                && $0.startTime.addingTimeInterval(barSeconds) <= session.rangeEndsAt
        }
        let expectedRangeBars = configuration.rangeDurationSeconds / 60
        guard rangeBars.count == expectedRangeBars,
              rangeBars.first?.startTime == session.rangeStartsAt,
              rangeBars.last?.startTime.addingTimeInterval(barSeconds) == session.rangeEndsAt else {
            return result(.rejected, .wait, .rangeDataInvalid, ids: completed.map(\.id))
        }
        let rangeHigh = rangeBars.map(\.high).max()!
        let rangeLow = rangeBars.map(\.low).min()!
        let rangePips = (rangeHigh - rangeLow) / configuration.pipSize
        guard rangePips.isFinite else { return result(.rejected, .wait, .rangeDataInvalid) }
        if rangePips < configuration.minimumRangePips {
            return result(.rejected, .wait, .rangeTooNarrow, rangeHigh: rangeHigh,
                rangeLow: rangeLow, ids: rangeBars.map(\.id))
        }
        if rangePips > configuration.maximumRangePips {
            return result(.rejected, .wait, .rangeTooWide, rangeHigh: rangeHigh,
                rangeLow: rangeLow, ids: rangeBars.map(\.id))
        }
        let afterRange = completed.filter { $0.startTime >= session.rangeEndsAt }
        guard !afterRange.isEmpty else {
            return result(.wait, .wait, .waitingForBreakout,
                rangeHigh: rangeHigh, rangeLow: rangeLow, ids: completed.map(\.id))
        }
        let breakoutDistance = configuration.minimumBreakoutPips * configuration.pipSize
        var breakoutIndex: Int?, direction: GBPJPYLondonBreakRetestDirection = .wait
        for (index, bar) in afterRange.enumerated() {
            let brokeUp = bar.close >= rangeHigh + breakoutDistance
            let brokeDown = bar.close <= rangeLow - breakoutDistance
            if brokeUp && brokeDown {
                return result(.rejected, .wait, .breakoutAmbiguous,
                    rangeHigh: rangeHigh, rangeLow: rangeLow)
            }
            if brokeUp || brokeDown {
                breakoutIndex = index; direction = brokeUp ? .long : .short; break
            }
        }
        guard let breakoutIndex else {
            return result(.wait, .wait, .waitingForBreakout, rangeHigh: rangeHigh,
                rangeLow: rangeLow, ids: rangeBars.map(\.id) + afterRange.map(\.id))
        }
        let breakout = afterRange[breakoutIndex]
        let age = asOf.timeIntervalSince(breakout.startTime.addingTimeInterval(barSeconds))
        guard age <= configuration.maximumSetupAgeSeconds else {
            return result(.expired, direction, .setupTooOld, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, ids: completed.map(\.id))
        }
        let retestEnd = min(afterRange.count - 1, breakoutIndex + configuration.maximumRetestBars)
        var retest: GBPJPYLondonBreakRetestBar?
        if breakoutIndex < retestEnd {
            for bar in afterRange[(breakoutIndex + 1)...retestEnd] {
                let tolerance = configuration.retestTolerancePips * configuration.pipSize
                let touchedAndHeld: Bool
                let touchedAndFailed: Bool
                if direction == .long {
                    touchedAndHeld = abs(bar.low - rangeHigh) <= tolerance && bar.close > rangeHigh
                    touchedAndFailed = bar.close <= rangeHigh
                } else {
                    touchedAndHeld = abs(bar.high - rangeLow) <= tolerance && bar.close < rangeLow
                    touchedAndFailed = bar.close >= rangeLow
                }
                if touchedAndFailed {
                    return result(.rejected, direction, .retestFailed, rangeHigh: rangeHigh,
                        rangeLow: rangeLow, breakout: breakout.id, retest: bar.id,
                        ids: completed.map(\.id))
                }
                if touchedAndHeld { retest = bar; break }
            }
        }
        guard let retest else {
            let barsSinceBreak = max(0, afterRange.count - 1 - breakoutIndex)
            if barsSinceBreak >= configuration.maximumRetestBars {
                return result(.expired, direction, .retestExpired, rangeHigh: rangeHigh,
                    rangeLow: rangeLow, breakout: breakout.id, ids: completed.map(\.id))
            }
            return result(.wait, direction, .waitingForRetest, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, ids: completed.map(\.id))
        }
        guard asOf.timeIntervalSince(retest.startTime.addingTimeInterval(barSeconds))
                <= configuration.maximumSetupAgeSeconds else {
            return result(.expired, direction, .setupTooOld, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        guard let quote else {
            return result(.wait, direction, .quoteMissing, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        guard !quote.sourceID.isEmpty, quote.bid.isFinite, quote.ask.isFinite,
              quote.bid > 0, quote.ask > quote.bid,
              quote.observedAt.timeIntervalSince1970.isFinite else {
            return result(.rejected, direction, .quoteInvalid, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        let retestCloseTime = retest.startTime.addingTimeInterval(barSeconds)
        guard quote.observedAt > retestCloseTime else {
            return result(.rejected, direction, .quoteNotAfterRetest, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        guard quote.observedAt <= asOf else {
            return result(.rejected, direction, .quoteInvalid, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        guard asOf.timeIntervalSince(quote.observedAt) <= configuration.maximumQuoteAgeSeconds else {
            return result(.wait, direction, .quoteStale, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id))
        }
        let spreadPips = (quote.ask - quote.bid) / configuration.pipSize
        guard spreadPips.isFinite, spreadPips <= configuration.maximumSpreadPips else {
            return result(.rejected, direction, .spreadTooWide, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id), spread: spreadPips)
        }
        let throughRetest = completed.filter { $0.startTime <= retest.startTime }
        guard throughRetest.count >= configuration.atrLookbackBars + 1 else {
            return result(.wait, direction, .rangeDataInvalid, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id), spread: spreadPips)
        }
        let recent = Array(throughRetest.suffix(configuration.atrLookbackBars + 1))
        let trueRanges = zip(recent.dropFirst(), recent).map { current, prior in
            max(current.high - current.low, abs(current.high - prior.close), abs(current.low - prior.close))
        }
        let atr: Double
        switch configuration.atrMethod {
        case .simpleMeanTrueRangeV1:
            atr = trueRanges.reduce(0, +) / Double(trueRanges.count)
        case .unsupported:
            return result(.rejected, direction, .configurationInvalid, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id), spread: spreadPips)
        }
        guard atr.isFinite, atr > 0 else {
            return result(.rejected, direction, .rangeDataInvalid, rangeHigh: rangeHigh,
                rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                ids: completed.map(\.id), spread: spreadPips)
        }
        let entry = direction == .long ? quote.ask : quote.bid
        let stop: Double
        let target: Double
        if direction == .long {
            stop = rangeHigh - atr * configuration.stopBufferATRMultiple
            guard stop > 0, stop < entry else {
                return result(.rejected, direction, .stopInvalid, rangeHigh: rangeHigh,
                    rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                    ids: completed.map(\.id), entry: entry, spread: spreadPips)
            }
            target = entry + (entry - stop) * configuration.targetRMultiple
            guard target > entry else {
                return result(.rejected, direction, .targetInvalid, rangeHigh: rangeHigh,
                    rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                    ids: completed.map(\.id), entry: entry, stop: stop, spread: spreadPips)
            }
        } else {
            stop = rangeLow + atr * configuration.stopBufferATRMultiple
            guard stop > entry else {
                return result(.rejected, direction, .stopInvalid, rangeHigh: rangeHigh,
                    rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                    ids: completed.map(\.id), entry: entry, spread: spreadPips)
            }
            target = entry - (stop - entry) * configuration.targetRMultiple
            guard target > 0, target < entry else {
                return result(.rejected, direction, .targetInvalid, rangeHigh: rangeHigh,
                    rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
                    ids: completed.map(\.id), entry: entry, stop: stop, spread: spreadPips)
            }
        }
        return result(.signal, direction, .setupReady, rangeHigh: rangeHigh,
            rangeLow: rangeLow, breakout: breakout.id, retest: retest.id,
            ids: completed.map(\.id), entry: entry, stop: stop, target: target, spread: spreadPips)
    }

    private struct Input: Encodable {
        let bars: [GBPJPYLondonBreakRetestBar]
        let session: GBPJPYLondonBreakRetestSession
        let quote: GBPJPYLondonBreakRetestQuote?
        let provenance: GBPJPYLondonBreakRetestProvenance
        let asOf: Date
        let lastSignalAt: Date?
        let configurationDigest: String
    }

    fileprivate static func aligned(_ date: Date) -> Bool {
        abs(date.timeIntervalSince1970.truncatingRemainder(dividingBy: barSeconds)) < 0.000_001
    }

    fileprivate static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    fileprivate static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "__POSITIVE_INFINITY__",
            negativeInfinity: "__NEGATIVE_INFINITY__",
            nan: "__NAN__")
        let data = (try? encoder.encode(value)) ?? Data("encoding-failed".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
