import BlazerCore
import CryptoKit
import Foundation

private struct ArchiveFileSummary: Codable {
    let filename: String
    let sha256: String
    let dataUse: String
    let instrument: String
    let granularity: String
    let requestedFrom: Date
    let requestedTo: Date
    let transport: String
    let httpStatus: Int?
    let practiceOnlyRejected: Bool
    let candleCount: Int
    let completeCandles: Int
    let firstSourceTime: Date?
    let lastSourceTime: Date?
}

private struct StructuralPlanSummary: Codable {
    let planID: String
    let sourceIdentity: String
    let instrument: String
    let side: V3SpotSide
    let planEntry: Double
    let stop: Double
    let target: Double
    let stopDistance: Double
    let targetDistance: Double
    let createdAt: Date
    let result: ORBArchiveStructuralResult
}

private struct InstrumentStructuralSummary: Codable {
    let instrument: String
    let distinctM1Candles: Int
    let representedSessionDays: Int
    let openingRangeEligibleSessions: Int
    let fullSetupWindowSessions: Int
    let censoredSetupWindowSessions: Int
    let insufficientOpeningRangeSessions: Int
    let identicalOverlapDuplicateCandles: Int
    let sessionsWithoutPlan: Int
    let repeatedCandidateDecisions: Int
    let uniquePlans: Int
    let statuses: [String: Int]
    let plans: [StructuralPlanSummary]
}

private struct StructuralArchiveReport: Codable {
    let reportKind: String
    let dataUse: String
    let configuration: ORBConfiguration
    let archiveFiles: [ArchiveFileSummary]
    let inputValidation: String
    let instruments: [InstrumentStructuralSummary]
    let limitations: [String]
}

enum ORBArchiveReplayCommand {
    static func run(root: URL, asset: String?) throws {
        // --root must be a scratch root containing historical-bid-ask; the
        // structural report is a sibling output and may never resolve into inputs.
        let safeRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let archive = safeRoot.appendingPathComponent("historical-bid-ask", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let output = safeRoot.appendingPathComponent("structural-replay", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard ORBArchiveFilesystemGuard.outputIsOutsideInputArchive(inputArchive: archive,
                                                                    outputDirectory: output) else {
            throw ScanError.failed("Report output resolves inside historical-bid-ask; use a separate scratch --root")
        }
        let urls = try FileManager.default.contentsOfDirectory(at: archive,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !urls.isEmpty else { throw ScanError.failed("No historical-bid-ask JSON files under --root") }

        let decoder = JSONDecoder()
        var batches: [(URL, OandaHistoricalBidAskBatch)] = []
        var fileSummaries: [ArchiveFileSummary] = []
        var validationSources: [ORBArchiveBatchSource] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            let batch = try decoder.decode(OandaHistoricalBidAskBatch.self, from: data)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            batches.append((url, batch))
            validationSources.append(ORBArchiveBatchSource(filename: url.lastPathComponent, batch: batch))
            fileSummaries.append(ArchiveFileSummary(filename: url.lastPathComponent,
                sha256: digest, dataUse: "RETROSPECTIVE_DEVELOPMENT_ONLY",
                instrument: batch.instrument, granularity: batch.granularity,
                requestedFrom: batch.requestedFrom, requestedTo: batch.requestedTo,
                transport: String(describing: batch.transport), httpStatus: batch.httpStatus,
                practiceOnlyRejected: batch.practiceOnlyRejected,
                candleCount: batch.candles.count,
                completeCandles: batch.candles.filter(\.complete).count,
                firstSourceTime: batch.candles.map(\.sourceTime).min(),
                lastSourceTime: batch.candles.map(\.sourceTime).max()))
        }

        let validationIssues = ORBArchiveBatchValidator.validate(validationSources)
        guard validationIssues.isEmpty else {
            let details = validationIssues.map { "\($0.filename):\($0.reason)" }.joined(separator: ",")
            throw ScanError.failed("Historical bid/ask archive validation failed: \(details)")
        }
        let names = asset.map { [$0.replacingOccurrences(of: "/", with: "_")] }
            ?? Array(Set(batches.map { $0.1.instrument })).sorted()
        var summaries: [InstrumentStructuralSummary] = []
        for name in names {
            let instrument = name.replacingOccurrences(of: "_", with: "/")
            let m1Batches = batches.map(\.1).filter { $0.instrument == name && $0.granularity == "M1" }
            guard !m1Batches.isEmpty else { throw ScanError.failed("No M1 archive for \(instrument)") }
            var byTime: [Date: OandaBidAskCandle] = [:]
            for batch in m1Batches {
                for candle in batch.candles where byTime[candle.sourceTime] == nil {
                    byTime[candle.sourceTime] = candle
                }
            }
            let candles = byTime.values.sorted { $0.sourceTime < $1.sourceTime }
            let originalCandleCount = m1Batches.reduce(0) { $0 + $1.candles.count }
            let bars = candles.map { candle in
                ORBBar(id: "\(instrument)-\(candle.sourceTime.timeIntervalSince1970)",
                    instrument: instrument, sourceTime: candle.sourceTime,
                    endTime: candle.sourceTime.addingTimeInterval(60),
                    open: (candle.bidOpen + candle.askOpen) / 2,
                    high: (candle.bidHigh + candle.askHigh) / 2,
                    low: (candle.bidLow + candle.askLow) / 2,
                    close: (candle.bidClose + candle.askClose) / 2)
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let sessions = Dictionary(grouping: bars) { bar in
                calendar.startOfDay(for: bar.sourceTime)
            }
            var coverageByDay: [Date: ORBArchiveSessionCoverage] = [:]
            for (day, sessionBars) in sessions {
                guard let sessionStart = calendar.date(bySettingHour: 9, minute: 30,
                        second: 0, of: day) else { continue }
                coverageByDay[day] = ORBArchiveSessionCoverageEvaluator.evaluate(
                    sessionStart: sessionStart, bars: sessionBars)
            }
            let openingRangeEligibleDays = Set(coverageByDay.compactMap { day, coverage in
                coverage.openingRangeEligible ? day : nil
            })
            let fullSetupWindowDays = Set(coverageByDay.compactMap { day, coverage in
                coverage.fullSetupWindowCovered ? day : nil
            })
            var plans: [String: V3TradePlan] = [:]
            var rawDecisions = 0
            for (day, sessionBars) in sessions {
                let ordered = sessionBars.sorted { $0.sourceTime < $1.sourceTime }
                guard let sessionStart = calendar.date(bySettingHour: 9, minute: 30,
                        second: 0, of: day) else { continue }
                let first = sessionStart.addingTimeInterval(300)
                let last = first.addingTimeInterval(120 * 60)
                for bar in ordered where bar.endTime >= first && bar.endTime <= last {
                    let decision = ORBBreakRetestV1.evaluate(instrument: instrument,
                        bars: ordered, asOf: bar.endTime)
                    if let candidate = decision.candidate {
                        rawDecisions += 1
                        plans[candidate.plan.id] = candidate.plan
                    }
                }
            }
            let evaluated = plans.values.sorted {
                ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
            }.map { plan -> StructuralPlanSummary in
                let outcome = ORBArchiveStructuralReplay.evaluate(plan: plan, candles: candles)
                return StructuralPlanSummary(planID: plan.id,
                    sourceIdentity: plan.sourceObservationID, instrument: plan.instrument,
                    side: plan.side, planEntry: plan.entryPrice, stop: plan.stopPrice,
                    target: plan.targetPrice, stopDistance: abs(plan.entryPrice - plan.stopPrice),
                    targetDistance: abs(plan.targetPrice - plan.entryPrice),
                    createdAt: plan.createdAt, result: outcome)
            }
            let plannedSessionDays = Set(plans.values.map { calendar.startOfDay(for: $0.createdAt) })
            let sessionsWithoutPlan = fullSetupWindowDays.filter { !plannedSessionDays.contains($0) }.count
            var statuses: [String: Int] = [:]
            for item in evaluated { statuses[item.result.status.rawValue, default: 0] += 1 }
            summaries.append(InstrumentStructuralSummary(instrument: instrument,
                distinctM1Candles: candles.count, representedSessionDays: sessions.count,
                openingRangeEligibleSessions: openingRangeEligibleDays.count,
                fullSetupWindowSessions: fullSetupWindowDays.count,
                censoredSetupWindowSessions: openingRangeEligibleDays.subtracting(fullSetupWindowDays).count,
                insufficientOpeningRangeSessions: sessions.count - openingRangeEligibleDays.count,
                identicalOverlapDuplicateCandles: originalCandleCount - candles.count,
                sessionsWithoutPlan: sessionsWithoutPlan,
                repeatedCandidateDecisions: max(0, rawDecisions - plans.count),
                uniquePlans: plans.count, statuses: statuses, plans: evaluated))
        }
        let report = StructuralArchiveReport(reportKind: "ORB_ARCHIVE_STRUCTURAL_TOUCH_REPLAY",
            dataUse: "RETROSPECTIVE_DEVELOPMENT_ONLY_DESCRIPTIVE_NOT_VALIDATION",
            configuration: ORBBreakRetestV1.configuration, archiveFiles: fileSummaries,
            inputValidation: "PASS_ALL_BATCHES_AND_IDENTICAL_OVERLAPS; CONFLICTS_REJECTED",
            instruments: summaries,
            limitations: [
                "Repeated candidate decisions are deduplicated by generated plan ID; they are not independent trades.",
                "A source-matched entry quote within plan maxSpread is only a quote-feasibility observation; it is not an order, position, or fill.",
                "Per-plan entryQuoteCandleStart/End, entryBidClose, entryAskClose, entrySpread, and entryIndicativeSideClose are archived candle-close quote evidence only; the side reference is ask close for long and bid close for short, not an order, live quote, fill, or guaranteed executable price.",
                "The archive cannot establish quote receive timestamp or quote age. No freshness is inferred and no quote-age threshold is applied; no fallback candle is used when the exact entry candle is unavailable or invalid.",
                "Every source batch must pass transport, HTTP, Practice filename, identity, requested-range, complete-candle, and candle-validation checks before replay.",
                "Identical overlaps are deduplicated and counted; conflicting candles at the same instrument/granularity/time reject the run.",
                "Opening-range eligibility requires the exact contiguous configured opening bars. A no-plan session additionally requires uninterrupted M1 coverage from 09:30 through configured setup expiry (default 11:35 New York); censored windows are reported separately.",
                "Plan-generation OHLC is a synthetic per-field bid/ask side-average. Bid and ask extrema may not be synchronous; this is not an independently supplied authentic midpoint-candle path.",
                "Only historical-bid-ask archive files are read. No streaming quote archive, sibling archive, order, fill, or P&L is used or asserted.",
                "Exit checks chronological complete M1 bid/ask OHLC candles after entry: long bid bounds, short ask bounds.",
                "Same-candle stop and target touches are ambiguous; a single touch records only the candle start/end interval.",
                "No candle path, exact touch time, fill price, P&L, fixed-duration outcome, or post-entry horizon is inferred.",
                "If the available series ends without a touch, outcome remains unresolved; ORB setup expiry applies only before plan generation."
            ])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let destination = output.appendingPathComponent("orb-structural-report.json")
        try encoder.encode(report).write(to: destination, options: .atomic)
        print("ORB_STRUCTURAL_ARCHIVE_REPORT path=\(destination.path) files=\(fileSummaries.count) use=development-only")
    }
}
