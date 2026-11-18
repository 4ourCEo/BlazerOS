import Foundation
import Testing
@testable import BlazerCore

struct GBPJPYLondonBreakRetestArchiveReplayTests {
    private let start = Date(timeIntervalSince1970: 1_794_816_000) // explicit test instant

    private var config: GBPJPYLondonBreakRetestConfiguration {
        GBPJPYLondonBreakRetestConfiguration(version: "test-profile-v1", pipSize: 0.01,
            rangeDurationSeconds: 300, minimumRangePips: 5, maximumRangePips: 40,
            minimumBreakoutPips: 5, retestTolerancePips: 1, maximumRetestBars: 3,
            atrMethod: .simpleMeanTrueRangeV1, atrLookbackBars: 3,
            stopBufferATRMultiple: 0.2, targetRMultiple: 2, maximumSpreadPips: 3,
            maximumQuoteAgeSeconds: 5, maximumSetupAgeSeconds: 600, cooldownSeconds: 0)
    }

    private var session: GBPJPYLondonBreakRetestSession {
        GBPJPYLondonBreakRetestSession(id: "explicit-london-test-session",
            timeZoneIdentifier: "Europe/London", calendarDigest: String(repeating: "c", count: 64),
            opensAt: start, rangeStartsAt: start.addingTimeInterval(300),
            rangeEndsAt: start.addingTimeInterval(600), closesAt: start.addingTimeInterval(900))
    }

    private var provenance: GBPJPYLondonBreakRetestProvenance {
        GBPJPYLondonBreakRetestProvenance(provider: "OANDA", environment: "archive-label-only",
            buildID: "test-build", codeDigest: String(repeating: "a", count: 64),
            snapshotDigest: String(repeating: "b", count: 64), lineageIsProviderNative: true)
    }

    private func candle(_ index: Int, _ tuple: (Double, Double, Double, Double)? = nil,
                        complete: Bool = true) -> OandaBidAskCandle {
        let values = tuple ?? (150.00, 150.08, 149.96, 150.02)
        let t = start.addingTimeInterval(Double(index * 60))
        return OandaBidAskCandle(instrument: "GBP_JPY", granularity: "M1", sourceTime: t,
            complete: complete, bidOpen: values.0, bidHigh: values.1, bidLow: values.2, bidClose: values.3,
            askOpen: values.0 + 0.01, askHigh: values.1 + 0.01, askLow: values.2 + 0.01, askClose: values.3 + 0.01)
    }

    private func source(_ candles: [OandaBidAskCandle], filename: String = "oanda-practice-GBP_JPY-M1-1794816000-1794816900.json") -> ORBArchiveBatchSource {
        let batch = OandaHistoricalBidAskBatch(instrument: "GBP_JPY", granularity: "M1",
            requestedFrom: start, requestedTo: start.addingTimeInterval(900), candles: candles,
            transport: .ok, httpStatus: 200)
        return ORBArchiveBatchSource(filename: filename, batch: batch)
    }

    private func fullCandles() -> [OandaBidAskCandle] {
        (0..<15).map { index in
            switch index {
            case 10: candle(index, (150.10, 150.30, 150.09, 150.25))
            case 11: candle(index, (150.20, 150.22, 150.08, 150.15))
            default: candle(index)
            }
        }
    }

    @Test func requiresExplicitConfigurationAndSession() throws {
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.missingConfiguration) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(fullCandles())],
                configuration: nil, session: session, provenance: provenance)
        }
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.missingSession) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(fullCandles())],
                configuration: config, session: nil, provenance: provenance)
        }
        let result = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(fullCandles())],
            configuration: config, session: session, provenance: provenance)
        #expect(result.configuration == config)
        #expect(result.session == session)
        #expect(result.configurationDigest == config.digest())
    }

    @Test func permitsOpeningRangeToBeginAtLondonSessionOpen() throws {
        let sessionAtOpen = GBPJPYLondonBreakRetestSession(id: session.id,
            timeZoneIdentifier: session.timeZoneIdentifier, calendarDigest: session.calendarDigest,
            opensAt: start, rangeStartsAt: start, rangeEndsAt: start.addingTimeInterval(300),
            closesAt: start.addingTimeInterval(900))
        let result = try GBPJPYLondonBreakRetestArchiveReplay.replay(
            sources: [source(fullCandles())], configuration: config,
            session: sessionAtOpen, provenance: provenance)
        #expect(result.session == sessionAtOpen)
    }

    @Test func exactDuplicatesAreCountedAndConflictsRejected() throws {
        let candles = fullCandles()
        let duplicateSource = source([candles[0]], filename: "oanda-practice-GBP_JPY-M1-1794816000-1794816900-copy.json")
        // The archive validator checks the filename envelope; use the same valid filename label.
        let repeated = ORBArchiveBatchSource(filename: "oanda-practice-GBP_JPY-M1-1794816000-1794816900.json",
            batch: duplicateSource.batch)
        let report = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(candles), repeated],
            configuration: config, session: session, provenance: provenance)
        #expect(report.exactDuplicateCount == 1)
        #expect(report.inputCandleCount == 16)

        let conflict = candle(0, (150.01, 150.09, 149.97, 150.03))
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.self) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(candles), source([conflict])],
                configuration: config, session: session, provenance: provenance)
        }
    }

    @Test func missingPartialAndGappedSessionInputAreRejected() {
        let candles = fullCandles()
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.self) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(Array(candles.dropLast()))],
                configuration: config, session: session, provenance: provenance)
        }
        var gap = candles; gap.remove(at: 4)
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.self) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(gap)],
                configuration: config, session: session, provenance: provenance)
        }
        var partial = candles; partial[14] = candle(14, complete: false)
        #expect(throws: GBPJPYLondonBreakRetestArchiveReplay.ReplayError.self) {
            try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(partial)],
                configuration: config, session: session, provenance: provenance)
        }
    }

    @Test func reportIsDeterministicAndSeparatesFilenameFromReceipt() throws {
        let args = (sources: [source(fullCandles())], configuration: config, session: session, provenance: provenance)
        let first = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: args.sources,
            configuration: args.configuration, session: args.session, provenance: args.provenance)
        let second = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: args.sources,
            configuration: args.configuration, session: args.session, provenance: args.provenance)
        #expect(first.reportDigest == second.reportDigest)
        #expect(first.sessionInputDigest == second.sessionInputDigest)
        #expect(first.archiveFilenameLabels == ["oanda-practice-GBP_JPY-M1-1794816000-1794816900.json"])
        #expect(first.authenticatedPracticeReceipt == "NOT_PRESENT_FILENAME_LABEL_IS_NOT_AUTHENTICATED_RECEIPT")
        #expect(first.interpretation.contains("NOT_QUOTE_FRESH_ACTIONABLE_ENTRY"))
    }

    @Test func historicalCandidateNeverBecomesActionableWithoutTimestampedQuote() throws {
        let report = try GBPJPYLondonBreakRetestArchiveReplay.replay(sources: [source(fullCandles())],
            configuration: config, session: session, provenance: provenance)
        let setupEvidence = report.decisions.first { $0.reason == .quoteMissing }
        #expect(setupEvidence != nil)
        #expect(setupEvidence?.state == .wait)
        #expect(setupEvidence?.quoteSourceID == nil)
        #expect(setupEvidence?.entryReference == nil)
        #expect(report.decisions.allSatisfy { $0.reason != .setupReady })
    }
}
