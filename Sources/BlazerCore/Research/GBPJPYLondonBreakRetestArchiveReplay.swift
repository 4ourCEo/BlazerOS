import CryptoKit
import Foundation

/// Retrospective archive replay for the existing London Break + Retest evaluator.
/// It consumes an explicit profile/session and never manufactures quote evidence.
public enum GBPJPYLondonBreakRetestArchiveReplay {
    public struct Report: Codable, Sendable, Equatable {
        public let reportKind: String
        public let dataUse: String
        public let interpretation: String
        public let configuration: GBPJPYLondonBreakRetestConfiguration
        public let configurationDigest: String
        public let session: GBPJPYLondonBreakRetestSession
        public let archiveFilenameLabels: [String]
        public let authenticatedPracticeReceipt: String
        public let archiveBatchCount: Int
        public let inputCandleCount: Int
        public let distinctCandleCount: Int
        public let exactDuplicateCount: Int
        public let sessionInputDigest: String
        public let decisions: [GBPJPYLondonBreakRetestDecision]
        public let reportDigest: String
    }

    public enum ReplayError: Error, Equatable, CustomStringConvertible {
        case missingConfiguration
        case missingSession
        case invalidConfiguration([String])
        case invalidArchive([String])
        case noM1Archive
        case sessionCoverage(String)

        public var description: String {
            switch self {
            case .missingConfiguration: "Caller-supplied London Break + Retest configuration is required"
            case .missingSession: "Caller-supplied Europe/London session instants and calendar digest are required"
            case .invalidConfiguration(let issues): "Invalid evaluator configuration: \(issues.joined(separator: ","))"
            case .invalidArchive(let issues): "Invalid archive batches: \(issues.joined(separator: ","))"
            case .noM1Archive: "No GBP/JPY M1 archive batches were supplied"
            case .sessionCoverage(let issue): "Invalid London session M1 coverage: \(issue)"
            }
        }
    }

    /// Batches must already be local archive data. Filename labels are retained as labels;
    /// they are not treated as an authenticated Practice capture receipt.
    public static func replay(
        sources: [ORBArchiveBatchSource],
        configuration: GBPJPYLondonBreakRetestConfiguration?,
        session: GBPJPYLondonBreakRetestSession?,
        provenance: GBPJPYLondonBreakRetestProvenance
    ) throws -> Report {
        guard let configuration else { throw ReplayError.missingConfiguration }
        guard let session else { throw ReplayError.missingSession }
        let configIssues = configuration.validationIssues()
        guard configIssues.isEmpty else { throw ReplayError.invalidConfiguration(configIssues) }
        guard session.timeZoneIdentifier == "Europe/London", !session.id.isEmpty,
              !session.calendarDigest.isEmpty, session.opensAt <= session.rangeStartsAt,
              session.rangeStartsAt < session.rangeEndsAt, session.rangeEndsAt <= session.closesAt,
              session.rangeEndsAt.timeIntervalSince(session.rangeStartsAt) == Double(configuration.rangeDurationSeconds),
              [session.opensAt, session.rangeStartsAt, session.rangeEndsAt, session.closesAt]
                .allSatisfy({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0 }) else {
            throw ReplayError.sessionCoverage("explicit Europe/London session definition is invalid")
        }
        let relevant = sources.filter {
            $0.batch.instrument == "GBP_JPY" && $0.batch.granularity == "M1"
        }
        guard !relevant.isEmpty else { throw ReplayError.noM1Archive }
        let validation = ORBArchiveBatchValidator.validate(relevant)
        guard validation.isEmpty else {
            throw ReplayError.invalidArchive(validation.map { "\($0.filename):\($0.reason)" })
        }

        var byTime: [Date: (OandaBidAskCandle, String)] = [:]
        var exactDuplicates = 0
        for source in relevant.sorted(by: { $0.filename < $1.filename }) {
            for candle in source.batch.candles {
                if let old = byTime[candle.sourceTime] {
                    guard old.0 == candle else {
                        throw ReplayError.invalidArchive(["conflicting_duplicate_candle:\(source.filename)"])
                    }
                    exactDuplicates += 1
                } else {
                    byTime[candle.sourceTime] = (candle, source.filename)
                }
            }
        }
        let all = byTime.values.map(\.0).sorted { $0.sourceTime < $1.sourceTime }
        let expectedStart = session.opensAt
        let expectedEnd = session.closesAt
        let expectedCount = Int(expectedEnd.timeIntervalSince(expectedStart) / 60)
        let selected = all.filter { $0.sourceTime >= expectedStart && $0.sourceTime < expectedEnd }
        guard selected.count == expectedCount else {
            throw ReplayError.sessionCoverage("expected_\(expectedCount)_bars_got_\(selected.count)_missing_partial_or_extra")
        }
        for (index, candle) in selected.enumerated() {
            guard candle.complete else { throw ReplayError.sessionCoverage("partial_candle_at_\(candle.sourceTime.timeIntervalSince1970)") }
            guard candle.sourceTime == expectedStart.addingTimeInterval(Double(index * 60)) else {
                throw ReplayError.sessionCoverage("gap_or_misaligned_minute_at_\(candle.sourceTime.timeIntervalSince1970)")
            }
        }
        let bars = selected.map { candle in
            GBPJPYLondonBreakRetestBar(id: "GBPJPY-M1-\(Int(candle.sourceTime.timeIntervalSince1970))",
                instrument: "GBP/JPY", provider: "OANDA", startTime: candle.sourceTime,
                open: (candle.bidOpen + candle.askOpen) / 2,
                high: (candle.bidHigh + candle.askHigh) / 2,
                low: (candle.bidLow + candle.askLow) / 2,
                close: (candle.bidClose + candle.askClose) / 2, complete: candle.complete)
        }
        let sessionBytes = try canonicalJSON(SessionDigestInput(configuration: configuration,
            session: session, candles: selected))
        let sessionDigest = sha256(sessionBytes)
        // Replay each completed minute and include the explicit close transition.
        var decisions: [GBPJPYLondonBreakRetestDecision] = []
        for bar in bars {
            let asOf = bar.startTime.addingTimeInterval(60)
            decisions.append(GBPJPYLondonBreakRetestV1.evaluate(
                bars: bars.filter { $0.startTime.addingTimeInterval(60) <= asOf },
                session: session, quote: nil, provenance: provenance, asOf: asOf,
                configuration: configuration))
        }
        let labels = relevant.map(\.filename).sorted()
        let unsigned = UnsignedReport(reportKind: "GBPJPY_LONDON_BREAK_RETEST_ARCHIVE_REPLAY",
            dataUse: "RETROSPECTIVE_DEVELOPMENT_ONLY",
            interpretation: "CANDLE_ONLY_SETUP_EVIDENCE_NOT_QUOTE_FRESH_ACTIONABLE_ENTRY",
            configuration: configuration,
            configurationDigest: configuration.digest(), session: session,
            archiveFilenameLabels: labels,
            authenticatedPracticeReceipt: "NOT_PRESENT_FILENAME_LABEL_IS_NOT_AUTHENTICATED_RECEIPT",
            archiveBatchCount: relevant.count, inputCandleCount: relevant.reduce(0) { $0 + $1.batch.candles.count },
            distinctCandleCount: selected.count, exactDuplicateCount: exactDuplicates,
            sessionInputDigest: sessionDigest, decisions: decisions)
        let reportDigest = sha256(try canonicalJSON(unsigned))
        return Report(reportKind: unsigned.reportKind, dataUse: unsigned.dataUse,
            interpretation: unsigned.interpretation,
            configuration: configuration, configurationDigest: unsigned.configurationDigest,
            session: session, archiveFilenameLabels: labels,
            authenticatedPracticeReceipt: unsigned.authenticatedPracticeReceipt,
            archiveBatchCount: unsigned.archiveBatchCount, inputCandleCount: unsigned.inputCandleCount,
            distinctCandleCount: unsigned.distinctCandleCount, exactDuplicateCount: exactDuplicates,
            sessionInputDigest: sessionDigest, decisions: decisions, reportDigest: reportDigest)
    }

    private struct UnsignedReport: Codable {
        let reportKind: String; let dataUse: String; let interpretation: String
        let configuration: GBPJPYLondonBreakRetestConfiguration; let configurationDigest: String
        let session: GBPJPYLondonBreakRetestSession; let archiveFilenameLabels: [String]
        let authenticatedPracticeReceipt: String; let archiveBatchCount: Int
        let inputCandleCount: Int; let distinctCandleCount: Int; let exactDuplicateCount: Int
        let sessionInputDigest: String; let decisions: [GBPJPYLondonBreakRetestDecision]
    }

    private struct SessionDigestInput: Codable {
        let configuration: GBPJPYLondonBreakRetestConfiguration
        let session: GBPJPYLondonBreakRetestSession
        let candles: [OandaBidAskCandle]
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
