import Foundation

/// Candle-level structural observations for retrospective research only. These
/// results never represent fills, execution prices, or P&L.
public enum ORBArchiveStructuralStatus: String, Codable, Sendable, Equatable {
    case stopTouched = "STOP_TOUCHED"
    case targetTouched = "TARGET_TOUCHED"
    case ambiguous = "AMBIGUOUS_SAME_CANDLE_TOUCH"
    case unresolved = "UNRESOLVED_SERIES_ENDED"
    case unresolvedCoverageGap = "UNRESOLVED_COVERAGE_GAP"
    case entryMissingQuote = "ENTRY_MISSING_QUOTE"
    case entrySpreadExceeded = "ENTRY_SPREAD_EXCEEDED"
    case invalidEvidence = "INVALID_EVIDENCE"
}

public struct ORBArchiveStructuralResult: Codable, Sendable, Equatable {
    public let planID: String
    public let sourceIdentity: String
    public let instrument: String
    public let status: ORBArchiveStructuralStatus
    public let entryTime: Date?
    public let entrySpread: Double?
    public let structuralRisk: Double?
    public let spreadToRiskRatio: Double?
    public let firstTouchCandleStart: Date?
    public let firstTouchCandleEnd: Date?
    public let coverageGapFrom: Date?
    public let coverageGapTo: Date?
    public let entryQuoteWithinPlanMaxSpread: Bool?

    public init(planID: String, sourceIdentity: String, instrument: String,
                status: ORBArchiveStructuralStatus, entryTime: Date? = nil,
                entrySpread: Double? = nil, structuralRisk: Double? = nil,
                spreadToRiskRatio: Double? = nil,
                firstTouchCandleStart: Date? = nil, firstTouchCandleEnd: Date? = nil,
                coverageGapFrom: Date? = nil, coverageGapTo: Date? = nil,
                entryQuoteWithinPlanMaxSpread: Bool? = nil) {
        self.planID = planID
        self.sourceIdentity = sourceIdentity
        self.instrument = instrument
        self.status = status
        self.entryTime = entryTime
        self.entrySpread = entrySpread
        self.structuralRisk = structuralRisk
        self.spreadToRiskRatio = spreadToRiskRatio
        self.firstTouchCandleStart = firstTouchCandleStart
        self.firstTouchCandleEnd = firstTouchCandleEnd
        self.coverageGapFrom = coverageGapFrom
        self.coverageGapTo = coverageGapTo
        self.entryQuoteWithinPlanMaxSpread = entryQuoteWithinPlanMaxSpread
    }
}

public enum ORBArchiveStructuralReplay {
    /// Entry is the bid/ask close of the exact completed candle whose end time
    /// matches plan.createdAt. Exits are later complete M1 candles only.
    public static func evaluate(plan: V3TradePlan, candles: [OandaBidAskCandle]) -> ORBArchiveStructuralResult {
        let risk = abs(plan.entryPrice - plan.stopPrice)
        let base = (status: ORBArchiveStructuralStatus.invalidEvidence,
                    entryTime: Optional<Date>.none, spread: Optional<Double>.none)
        guard plan.validation().isEmpty, risk.isFinite, risk > 0,
              candles.allSatisfy({ $0.validation.isEmpty && $0.complete && $0.granularity == "M1" }) else {
            return result(plan, status: base.status, risk: risk)
        }
        let planInstrument = plan.instrument.replacingOccurrences(of: "_", with: "/")
        let ordered = candles.filter { $0.instrument.replacingOccurrences(of: "_", with: "/") == planInstrument }
            .sorted { $0.sourceTime < $1.sourceTime }
        guard let entry = ordered.first(where: { $0.sourceTime.addingTimeInterval(60) == plan.createdAt }) else {
            return result(plan, status: .entryMissingQuote, risk: risk)
        }
        let spread = entry.askClose - entry.bidClose
        guard spread.isFinite, spread >= 0, spread <= plan.maxSpread else {
            return result(plan, status: .entrySpreadExceeded, entryTime: plan.createdAt,
                          spread: spread, risk: risk, quoteFeasible: false)
        }
        var expectedStart = plan.createdAt
        for candle in ordered where candle.sourceTime >= plan.createdAt {
            if candle.sourceTime > expectedStart {
                return result(plan, status: .unresolvedCoverageGap, entryTime: plan.createdAt,
                    spread: spread, risk: risk, gapFrom: expectedStart, gapTo: candle.sourceTime,
                    quoteFeasible: true)
            }
            guard candle.sourceTime == expectedStart else { continue }
            let stopTouched: Bool
            let targetTouched: Bool
            switch plan.side {
            case .long:
                stopTouched = candle.bidLow <= plan.stopPrice
                targetTouched = candle.bidHigh >= plan.targetPrice
            case .short:
                stopTouched = candle.askHigh >= plan.stopPrice
                targetTouched = candle.askLow <= plan.targetPrice
            }
            expectedStart = expectedStart.addingTimeInterval(60)
            guard stopTouched || targetTouched else { continue }
            let status: ORBArchiveStructuralStatus = stopTouched && targetTouched
                ? .ambiguous : (stopTouched ? .stopTouched : .targetTouched)
            return result(plan, status: status, entryTime: plan.createdAt, spread: spread,
                          risk: risk, touchStart: candle.sourceTime,
                          touchEnd: candle.sourceTime.addingTimeInterval(60), quoteFeasible: true)
        }
        return result(plan, status: .unresolved, entryTime: plan.createdAt, spread: spread, risk: risk, quoteFeasible: true)
    }

    private static func result(_ plan: V3TradePlan, status: ORBArchiveStructuralStatus,
                               entryTime: Date? = nil, spread: Double? = nil, risk: Double,
                               touchStart: Date? = nil, touchEnd: Date? = nil,
                               gapFrom: Date? = nil, gapTo: Date? = nil,
                               quoteFeasible: Bool? = nil) -> ORBArchiveStructuralResult {
        let ratio: Double?
        if let spread, risk.isFinite && risk > 0 { ratio = spread / risk } else { ratio = nil }
        return ORBArchiveStructuralResult(planID: plan.id, sourceIdentity: plan.sourceObservationID,
            instrument: plan.instrument, status: status, entryTime: entryTime,
            entrySpread: spread, structuralRisk: risk.isFinite && risk > 0 ? risk : nil,
            spreadToRiskRatio: ratio,
            firstTouchCandleStart: touchStart, firstTouchCandleEnd: touchEnd,
            coverageGapFrom: gapFrom, coverageGapTo: gapTo,
            entryQuoteWithinPlanMaxSpread: quoteFeasible)
    }
}


public struct ORBArchiveBatchSource: Sendable {
    public let filename: String
    public let batch: OandaHistoricalBidAskBatch

    public init(filename: String, batch: OandaHistoricalBidAskBatch) {
        self.filename = filename
        self.batch = batch
    }
}

public struct ORBArchiveBatchIssue: Sendable, Equatable {
    public let filename: String
    public let reason: String

    public init(filename: String, reason: String) {
        self.filename = filename
        self.reason = reason
    }
}

/// Fail-closed provenance, coverage-envelope, candle-integrity, and overlap
/// validation for the narrow archived Practice batches.
public enum ORBArchiveBatchValidator {
    public static func validate(_ sources: [ORBArchiveBatchSource]) -> [ORBArchiveBatchIssue] {
        var issues: [ORBArchiveBatchIssue] = []
        var seen: [String: (OandaBidAskCandle, String)] = [:]
        for source in sources.sorted(by: { $0.filename < $1.filename }) {
            let batch = source.batch
            func issue(_ reason: String) { issues.append(.init(filename: source.filename, reason: reason)) }
            if batch.transport != .ok { issue("transport_not_ok") }
            if batch.httpStatus != 200 { issue("http_status_not_200") }
            if batch.practiceOnlyRejected { issue("practice_only_rejected") }
            if batch.instrument.isEmpty || !["M1", "M5"].contains(batch.granularity) {
                issue("unsupported_batch_identity")
            }
            let expectedPrefix = "oanda-practice-\(batch.instrument)-\(batch.granularity)-"
            let hasExpectedPrefix = source.filename.hasPrefix(expectedPrefix)
                && source.filename.hasSuffix(".json")
            if !hasExpectedPrefix { issue("filename_provenance_mismatch") }
            let from = batch.requestedFrom.timeIntervalSince1970
            let to = batch.requestedTo.timeIntervalSince1970
            let saneRange = from.isFinite && to.isFinite && from > 0 && to > from
                && from < Double(Int.max) && to < Double(Int.max)
            if !saneRange { issue("requested_range_invalid") }
            if hasExpectedPrefix, saneRange {
                let suffixStart = source.filename.index(source.filename.startIndex, offsetBy: expectedPrefix.count)
                let endOfName = source.filename.index(source.filename.endIndex, offsetBy: -5)
                let encoded = source.filename[suffixStart..<endOfName].split(separator: "-")
                let expectedFrom = Int(from)
                let expectedTo = Int(to)
                if encoded.count != 2 || Int(encoded[0]) != expectedFrom || Int(encoded[1]) != expectedTo {
                    issue("filename_requested_range_mismatch")
                }
            }
            let step: TimeInterval = batch.granularity == "M1" ? 60 : 300
            for candle in batch.candles {
                if candle.instrument != batch.instrument || candle.granularity != batch.granularity {
                    issue("candle_batch_identity_mismatch")
                    continue
                }
                if !candle.complete { issue("incomplete_candle") }
                if !candle.validation.isEmpty { issue("candle_validation_failed") }
                let time = candle.sourceTime.timeIntervalSince1970
                if !time.isFinite || (from.isFinite && to.isFinite
                    && (time < from - step || time > to + step)) {
                    issue("candle_outside_requested_range")
                }
                let key = "\(batch.instrument)|\(batch.granularity)|\(time)"
                if let previous = seen[key] {
                    if previous.0 != candle {
                        issues.append(.init(filename: previous.1, reason: "conflicting_duplicate_candle"))
                        issue("conflicting_duplicate_candle")
                    }
                } else {
                    seen[key] = (candle, source.filename)
                }
            }
        }
        return issues.sorted { ($0.filename, $0.reason) < ($1.filename, $1.reason) }
    }
}

public enum ORBArchiveFilesystemGuard {
    /// Report destinations must remain outside the input archive, including
    /// when an existing output path is a symlink into that archive.
    public static func outputIsOutsideInputArchive(inputArchive: URL, outputDirectory: URL) -> Bool {
        let input = inputArchive.standardizedFileURL.resolvingSymlinksInPath()
        let output = outputDirectory.standardizedFileURL.resolvingSymlinksInPath()
        return output.path != input.path && !output.path.hasPrefix(input.path + "/")
    }
}

public struct ORBArchiveSessionCoverage: Sendable, Equatable {
    public let openingRangeEligible: Bool
    public let fullSetupWindowCovered: Bool
}

public enum ORBArchiveSessionCoverageEvaluator {
    /// Requires one-minute bars from the opening-range start through (but not
    /// including) the configured expiry instant. For defaults this is 09:30–11:35.
    public static func evaluate(sessionStart: Date, bars: [ORBBar],
                                configuration: ORBConfiguration = ORBBreakRetestV1.configuration) -> ORBArchiveSessionCoverage {
        let barMinutes = configuration.barMinutes
        guard barMinutes > 0,
              (configuration.openingRangeMinutes + configuration.maximumSetupMinutes) % barMinutes == 0,
              configuration.openingRangeMinutes % barMinutes == 0 else {
            return ORBArchiveSessionCoverage(openingRangeEligible: false, fullSetupWindowCovered: false)
        }
        let expectedWindowBars = (configuration.openingRangeMinutes + configuration.maximumSetupMinutes) / barMinutes
        let openingRangeBars = configuration.openingRangeMinutes / barMinutes
        let interval = TimeInterval(barMinutes * 60)
        let instrument = bars.first?.instrument
        let barsByStart = Dictionary(bars.map { ($0.sourceTime, $0) }, uniquingKeysWith: { first, _ in first })
        func containsContiguousBars(count: Int) -> Bool {
            guard let instrument else { return false }
            return (0..<count).allSatisfy { minute in
                let start = sessionStart.addingTimeInterval(Double(minute) * interval)
                guard let bar = barsByStart[start] else { return false }
                return bar.instrument == instrument && bar.endTime == start.addingTimeInterval(60) && bar.isFinite
            }
        }
        let openingRange = containsContiguousBars(count: openingRangeBars)
        let fullWindow = openingRange && containsContiguousBars(count: expectedWindowBars)
        return ORBArchiveSessionCoverage(openingRangeEligible: openingRange,
            fullSetupWindowCovered: fullWindow)
    }
}
