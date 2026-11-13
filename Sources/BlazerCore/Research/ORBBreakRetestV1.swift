import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A completed bar used by ORB_BREAK_RETEST_V1. The engine never consumes a bar
/// whose end time is after the evaluation cutoff.
public struct ORBBar: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let sourceTime: Date
    public let endTime: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(id: String, instrument: String, sourceTime: Date, endTime: Date,
                open: Double, high: Double, low: Double, close: Double) {
        self.id = id
        self.instrument = instrument
        self.sourceTime = sourceTime
        self.endTime = endTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    public var isFinite: Bool {
        [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
    }
}

public enum ORBStage: String, Codable, Sendable, Equatable {
    case noData = "NO_DATA"
    case rangeForming = "RANGE_FORMING"
    case rangeSealed = "RANGE_SEALED"
    case boundaryApproaching = "BOUNDARY_APPROACHING"
    case breakoutConfirmed = "BREAKOUT_CONFIRMED"
    case retestPending = "RETEST_PENDING"
    case retestInProgress = "RETEST_IN_PROGRESS"
    case setupConfirmed = "SETUP_CONFIRMED"
    case invalidated = "INVALIDATED"
    case expired = "EXPIRED"
    case unavailable = "UNAVAILABLE"
}

public enum ORBDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
}

public struct ORBConfiguration: Codable, Sendable, Equatable {
    public let strategyVersion: String
    public let engineVersion: String
    public let timeZoneIdentifier: String
    public let openingHour: Int
    public let openingMinute: Int
    public let openingRangeMinutes: Int
    public let barMinutes: Int
    public let minimumBreakoutThreshold: Double
    public let retestTolerance: Double
    public let confirmationBuffer: Double
    public let stopBuffer: Double
    public let rewardRisk: Double
    public let maximumSetupMinutes: Int
    public let maximumSpread: Double
    public let riskFraction: Double
    public let plannedUnits: Double

    public init(strategyVersion: String = "ORB_BREAK_RETEST_V1",
                engineVersion: String = "V3_ORB_ENGINE_1",
                timeZoneIdentifier: String = "America/New_York",
                openingHour: Int = 9, openingMinute: Int = 30,
                openingRangeMinutes: Int = 5, barMinutes: Int = 1,
                minimumBreakoutThreshold: Double = 0,
                retestTolerance: Double = 0.0001,
                confirmationBuffer: Double = 0,
                stopBuffer: Double = 0,
                rewardRisk: Double = 2,
                maximumSetupMinutes: Int = 120,
                maximumSpread: Double = 0.0003,
                riskFraction: Double = 0.01,
                plannedUnits: Double = 1) {
        self.strategyVersion = strategyVersion
        self.engineVersion = engineVersion
        self.timeZoneIdentifier = timeZoneIdentifier
        self.openingHour = openingHour
        self.openingMinute = openingMinute
        self.openingRangeMinutes = openingRangeMinutes
        self.barMinutes = barMinutes
        self.minimumBreakoutThreshold = minimumBreakoutThreshold
        self.retestTolerance = retestTolerance
        self.confirmationBuffer = confirmationBuffer
        self.stopBuffer = stopBuffer
        self.rewardRisk = rewardRisk
        self.maximumSetupMinutes = maximumSetupMinutes
        self.maximumSpread = maximumSpread
        self.riskFraction = riskFraction
        self.plannedUnits = plannedUnits
    }
}

public struct ORBTradePlanCandidate: Codable, Sendable, Equatable {
    public let direction: ORBDirection
    public let breakoutBarID: String
    public let retestBarID: String
    public let confirmationBarID: String
    public let rangeHigh: Double
    public let rangeLow: Double
    public let plan: V3TradePlan
}

public struct ORBDecision: Codable, Sendable, Equatable {
    public let stage: ORBStage
    public let setupState: V3SetupState
    public let sessionStart: Date?
    public let rangeHigh: Double?
    public let rangeLow: Double?
    public let direction: ORBDirection?
    public let reason: String
    public let candidate: ORBTradePlanCandidate?

    public init(stage: ORBStage, setupState: V3SetupState, sessionStart: Date?,
                rangeHigh: Double? = nil, rangeLow: Double? = nil,
                direction: ORBDirection? = nil, reason: String,
                candidate: ORBTradePlanCandidate? = nil) {
        self.stage = stage
        self.setupState = setupState
        self.sessionStart = sessionStart
        self.rangeHigh = rangeHigh
        self.rangeLow = rangeLow
        self.direction = direction
        self.reason = reason
        self.candidate = candidate
    }
}

public struct ORBNotification: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let strategyVersion: String
    public let stage: ORBStage
    public let sourceTime: Date
    public let deepLink: String

    public init(instrument: String, strategyVersion: String, stage: ORBStage,
                sourceTime: Date) {
        self.instrument = instrument
        self.strategyVersion = strategyVersion
        self.stage = stage
        self.sourceTime = sourceTime
        id = "orb-\(instrument)-\(strategyVersion)-\(stage.rawValue)-\(sourceTime.timeIntervalSince1970)"
        var components = URLComponents()
        components.scheme = "blazer"
        components.host = "trade"
        components.queryItems = [URLQueryItem(name: "instrument", value: instrument),
                                 URLQueryItem(name: "strategy", value: strategyVersion)]
        deepLink = components.url?.absoluteString ?? "blazer://trade"
    }
}

public enum ORBNotificationPlanner {
    /// Plans are source-evidence notifications only. Delivery is owned by the app's
    /// notification service; this layer performs stage filtering and deduplication.
    public static func plan(for decision: ORBDecision, instrument: String,
                            sourceTime: Date, strategyVersion: String = "ORB_BREAK_RETEST_V1",
                            previouslyDelivered: Set<String> = []) -> ORBNotification? {
        let alertStages: Set<ORBStage> = [
            .rangeForming, .rangeSealed, .boundaryApproaching, .breakoutConfirmed,
            .retestPending, .retestInProgress, .setupConfirmed, .invalidated, .expired
        ]
        guard alertStages.contains(decision.stage) else { return nil }
        let notification = ORBNotification(instrument: instrument, strategyVersion: strategyVersion,
                                           stage: decision.stage, sourceTime: sourceTime)
        return previouslyDelivered.contains(notification.id) ? nil : notification
    }
}

/// APNs/webhook envelope contract. The server must authenticate `signature` with
/// its managed key; the client only accepts a fresh, strategy-matched envelope.
public struct ORBRemoteNotificationEnvelope: Codable, Sendable, Equatable {
    public let eventID: String
    public let planID: String
    public let instrument: String
    public let strategyVersion: String
    public let stage: ORBStage
    public let sourceTime: Date
    public let issuedAt: Date
    public let expiresAt: Date
    public let deepLink: String
    public let keyID: String
    public let signature: String

    public init(eventID: String, planID: String, instrument: String,
                strategyVersion: String, stage: ORBStage, sourceTime: Date,
                issuedAt: Date, expiresAt: Date, deepLink: String,
                keyID: String, signature: String) {
        self.eventID = eventID
        self.planID = planID
        self.instrument = instrument
        self.strategyVersion = strategyVersion
        self.stage = stage
        self.sourceTime = sourceTime
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.deepLink = deepLink
        self.keyID = keyID
        self.signature = signature
    }

    public func validation(now: Date, maximumAge: TimeInterval = 120) -> [String] {
        var issues: [String] = []
        if eventID.isEmpty || planID.isEmpty || instrument.isEmpty { issues.append("identity_missing") }
        if strategyVersion != "ORB_BREAK_RETEST_V1" { issues.append("strategy_mismatch") }
        if keyID.isEmpty || signature.isEmpty { issues.append("authentication_missing") }
        if expiresAt <= issuedAt || now < issuedAt.addingTimeInterval(-5) { issues.append("invalid_time_window") }
        if now > expiresAt || now.timeIntervalSince(issuedAt) > maximumAge { issues.append("stale_alert") }
        guard let url = URL(string: deepLink), url.scheme == "blazer", url.host == "trade" else {
            issues.append("invalid_deep_link")
            return issues
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.first(where: { $0.name == "instrument" })?.value != instrument
            || items.first(where: { $0.name == "strategy" })?.value != strategyVersion {
            issues.append("deep_link_mismatch")
        }
        return issues
    }

    public var signingPayload: Data {
        Data([
            eventID, planID, instrument, strategyVersion, stage.rawValue,
            String(format: "%.3f", sourceTime.timeIntervalSince1970),
            String(format: "%.3f", issuedAt.timeIntervalSince1970),
            String(format: "%.3f", expiresAt.timeIntervalSince1970), deepLink, keyID
        ].joined(separator: "|").utf8)
    }
}

public enum ORBRemoteNotificationAuthenticator {
    public static func verify(_ envelope: ORBRemoteNotificationEnvelope, key: Data) -> Bool {
        guard !key.isEmpty, let signature = Data(base64Encoded: envelope.signature) else { return false }
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(for: envelope.signingPayload, using: SymmetricKey(data: key))
        return Data(mac) == signature
        #else
        return false
        #endif
    }
}

public enum ORBBreakRetestV1 {
    public static let configuration = ORBConfiguration()

    /// Adapts the existing ForwardTest/iPhone market payload without changing the
    /// pinned V1 engine. Only completed one-minute payloads are considered.
    public static func evaluate(input: StrategyEngine.MarketInput, asOf: Date? = nil,
                                configuration: ORBConfiguration = configuration) -> ORBDecision {
        let bars = input.candles1m.map {
            let start = Date(timeIntervalSince1970: $0.time / 1_000)
            return ORBBar(id: "\(input.asset)-\($0.time)", instrument: input.asset,
                          sourceTime: start, endTime: start.addingTimeInterval(60),
                          open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
        let cutoff = asOf ?? Date(timeIntervalSince1970:
            (input.evaluatedAtMs ?? input.quoteAsOfMs ?? bars.last.map { $0.endTime.timeIntervalSince1970 * 1_000 } ?? 0) / 1_000)
        return evaluate(instrument: input.asset, bars: bars, asOf: cutoff, configuration: configuration)
    }

    public static func evaluate(instrument: String, bars: [ORBBar], asOf: Date,
                                configuration: ORBConfiguration = configuration) -> ORBDecision {
        guard !instrument.isEmpty, asOf.timeIntervalSince1970.isFinite else {
            return .init(stage: .unavailable, setupState: .unresolved, sessionStart: nil,
                         reason: "invalid_evaluation_input")
        }
        guard let timeZone = TimeZone(identifier: configuration.timeZoneIdentifier) else {
            return .init(stage: .unavailable, setupState: .unresolved, sessionStart: nil,
                         reason: "invalid_session_timezone")
        }
        let calendar = sessionCalendar(timeZone)
        let sessionStart = calendar.date(bySettingHour: configuration.openingHour,
                                         minute: configuration.openingMinute,
                                         second: 0, of: asOf)
        guard let sessionStart else {
            return .init(stage: .unavailable, setupState: .unresolved, sessionStart: nil,
                         reason: "session_start_unavailable")
        }
        let rangeEnd = sessionStart.addingTimeInterval(TimeInterval(configuration.openingRangeMinutes * 60))
        let expiry = rangeEnd.addingTimeInterval(TimeInterval(configuration.maximumSetupMinutes * 60))
        guard asOf >= sessionStart else {
            return .init(stage: .noData, setupState: .watching, sessionStart: sessionStart,
                         reason: "before_opening_range")
        }

        let eligible = bars.filter {
            $0.instrument == instrument && $0.endTime <= asOf && $0.isFinite
        }.sorted { ($0.endTime, $0.id) < ($1.endTime, $1.id) }
        let rangeBars = eligible.filter { $0.sourceTime >= sessionStart && $0.endTime <= rangeEnd }
        let expectedCount = configuration.openingRangeMinutes / configuration.barMinutes
        guard rangeBars.count >= expectedCount else {
            if asOf >= rangeEnd {
                return .init(stage: .unavailable, setupState: .unresolved, sessionStart: sessionStart,
                             reason: "opening_range_missing_or_out_of_order")
            }
            return .init(stage: .rangeForming, setupState: .forming, sessionStart: sessionStart,
                         reason: "opening_range_incomplete")
        }
        guard rangeBars.count == expectedCount,
              contiguous(rangeBars, minutes: configuration.barMinutes),
              rangeBars.first?.sourceTime == sessionStart else {
            return .init(stage: .unavailable, setupState: .unresolved, sessionStart: sessionStart,
                         reason: "opening_range_missing_or_out_of_order")
        }
        let rangeHigh = rangeBars.map(\.high).max()!
        let rangeLow = rangeBars.map(\.low).min()!
        guard asOf >= rangeEnd else {
            return .init(stage: .rangeForming, setupState: .forming, sessionStart: sessionStart,
                         rangeHigh: rangeHigh, rangeLow: rangeLow, reason: "opening_range_forming")
        }
        let postRange = eligible.filter { $0.sourceTime >= rangeEnd }
        guard let breakoutIndex = postRange.firstIndex(where: {
            $0.close > rangeHigh + configuration.minimumBreakoutThreshold
                || $0.close < rangeLow - configuration.minimumBreakoutThreshold
        }) else {
            if asOf > expiry {
                return .init(stage: .expired, setupState: .setupExpired, sessionStart: sessionStart,
                             rangeHigh: rangeHigh, rangeLow: rangeLow, reason: "setup_expired_without_breakout")
            }
            let nearBoundary = postRange.last.map {
                min(abs($0.close - rangeHigh), abs($0.close - rangeLow)) <= configuration.retestTolerance
            } ?? false
            return .init(stage: nearBoundary ? .boundaryApproaching : .rangeSealed,
                         setupState: nearBoundary ? .approaching : .watching,
                         sessionStart: sessionStart, rangeHigh: rangeHigh, rangeLow: rangeLow,
                         reason: nearBoundary ? "boundary_approaching" : "range_sealed")
        }

        let breakout = postRange[breakoutIndex]
        let direction: ORBDirection = breakout.close > rangeHigh ? .long : .short
        let boundary = direction == .long ? rangeHigh : rangeLow
        let subsequent = Array(postRange.dropFirst(breakoutIndex + 1))
        guard let retestIndex = subsequent.firstIndex(where: { bar in
            direction == .long
                ? bar.low <= boundary + configuration.retestTolerance
                : bar.high >= boundary - configuration.retestTolerance
        }) else {
            if asOf > expiry {
                return .init(stage: .expired, setupState: .setupExpired, sessionStart: sessionStart,
                             rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                             reason: "setup_expired_waiting_for_retest")
            }
            return .init(stage: .retestPending, setupState: .confirmed, sessionStart: sessionStart,
                         rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                         reason: "breakout_confirmed_retest_pending")
        }
        let retest = subsequent[retestIndex]
        if direction == .long && retest.close < boundary - configuration.retestTolerance
            || direction == .short && retest.close > boundary + configuration.retestTolerance {
            return .init(stage: .invalidated, setupState: .invalidated, sessionStart: sessionStart,
                         rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                         reason: "retest_failed_boundary")
        }
        let afterRetest = Array(subsequent.dropFirst(retestIndex + 1))
        guard let confirmation = afterRetest.first(where: {
            direction == .long
                ? ($0.close > $0.open && $0.close > boundary + configuration.confirmationBuffer)
                : ($0.close < $0.open && $0.close < boundary - configuration.confirmationBuffer)
        }) else {
            return .init(stage: .retestInProgress, setupState: .approaching,
                         sessionStart: sessionStart, rangeHigh: rangeHigh, rangeLow: rangeLow,
                         direction: direction, reason: "retest_confirmation_pending")
        }
        let entry = confirmation.close
        let stop = direction == .long
            ? min(rangeLow, retest.low) - configuration.stopBuffer
            : max(rangeHigh, retest.high) + configuration.stopBuffer
        let risk = abs(entry - stop)
        guard risk.isFinite, risk > 0, configuration.rewardRisk >= 2 else {
            return .init(stage: .invalidated, setupState: .invalidated, sessionStart: sessionStart,
                         rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                         reason: "invalid_structural_risk")
        }
        let target = direction == .long
            ? entry + risk * configuration.rewardRisk
            : entry - risk * configuration.rewardRisk
        let side: V3SpotSide = direction == .long ? .long : .short
        let planIdentity = "orb-\(instrument)-\(confirmation.id)"
            .map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
        let plan = V3TradePlan(
            id: planIdentity,
            instrument: instrument, strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: configuration.strategyVersion, engineVersion: configuration.engineVersion,
            sourceObservationID: confirmation.id, state: .validated, side: side,
            entryPrice: entry, stopPrice: stop, targetPrice: target,
            units: configuration.plannedUnits, maxSpread: configuration.maximumSpread,
            riskFraction: configuration.riskFraction,
            evidenceIDs: [rangeBars.map(\.id).joined(separator: ","), breakout.id, retest.id, confirmation.id],
            createdAt: confirmation.endTime)
        guard plan.validation().isEmpty else {
            return .init(stage: .invalidated, setupState: .invalidated, sessionStart: sessionStart,
                         rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                         reason: "generated_plan_validation_failed")
        }
        let candidate = ORBTradePlanCandidate(direction: direction, breakoutBarID: breakout.id,
            retestBarID: retest.id, confirmationBarID: confirmation.id,
            rangeHigh: rangeHigh, rangeLow: rangeLow, plan: plan)
        return .init(stage: .setupConfirmed, setupState: .confirmed, sessionStart: sessionStart,
                     rangeHigh: rangeHigh, rangeLow: rangeLow, direction: direction,
                     reason: "orb_break_retest_confirmed", candidate: candidate)
    }

    private static func sessionCalendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func contiguous(_ bars: [ORBBar], minutes: Int) -> Bool {
        guard let first = bars.first else { return false }
        return bars.enumerated().allSatisfy { index, bar in
            let expectedStart = first.sourceTime.addingTimeInterval(TimeInterval(index * minutes * 60))
            return bar.sourceTime == expectedStart
                && bar.endTime.timeIntervalSince(bar.sourceTime) == TimeInterval(minutes * 60)
        }
    }
}
