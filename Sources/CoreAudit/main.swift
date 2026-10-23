import BlazerCore
import BlazerCrypto
import Foundation

/// Macro-free deterministic regressions for restricted tooling hosts. Not a full test suite.
@main
struct CoreAudit {
    static func main() async {
        var passed = 0, failed = 0
        func check(_ name: String, _ value: Bool) {
            if value { passed += 1 } else { failed += 1 }
            print("\(value ? "PASS" : "FAIL") \(name)")
        }
        func candle(_ index: Int, price: Double = 100, volume: Double = 10, trades: Int = 10) -> CryptoCandle {
            CryptoCandle(time: Double(index) * 60_000, open: price, high: price * 1.01,
                         low: price * 0.99, close: price, volume: volume, quoteVolume: volume, trades: trades)
        }
        let bars = (0..<65).map { candle($0) }
        for (index, value) in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude, -1, 0].enumerated() {
            var invalid = bars
            invalid[30] = candle(30, price: value)
            let result = CryptoEngine.evaluate(batch: CryptoCandleBatch(candles: invalid, bid: 99, ask: 101, asset: "BTC/USDT", source: "test"))
            check("invalid candle \(index) fails closed", result.side == "WAIT" && result.conviction == 0 && result.atrPips.isFinite)
        }
        for (index, count) in ["nan", "inf", "1e300", "-1", "1.5", String(Double(Int.max))].enumerated() {
            let row: [BinanceKlineField] = ["0", "100", "101", "99", "100", "10", "0", "1000", count, "0", "0", "0"].map { .string($0) }
            check("invalid trade count \(index) rejected", CryptoCandle.from(row: row) == nil)
        }
        for (index, pair) in [(Double.nan, 101.0), (100.0, .infinity), (-1.0, 1.0), (100.0, 99.0), (100.0, 100.0)].enumerated() {
            let batch = CryptoCandleBatch(candles: bars, bid: pair.0, ask: pair.1, asset: "BTC/USDT", source: "test")
            check("invalid quote \(index) fails closed", CryptoEngine.evaluate(batch: batch).side == "WAIT")
        }
        var extreme = (0..<65).map { candle($0, price: 1e90, volume: 1e-90) }
        extreme[64] = candle(64, price: 1e90, volume: 1e90, trades: Int.max)
        let extremeResult = CryptoEngine.evaluate(batch: .init(candles: extreme, bid: 1e90, ask: 1.01e90, asset: "BTC/USDT", source: "test"))
        check("finite extreme arithmetic survives", extremeResult.atrPips.isFinite && extremeResult.volumeSurge.isFinite && (0...97).contains(extremeResult.conviction))
        for (index, value) in [Double.nan, .infinity, .greatestFiniteMagnitude, -1, 101].enumerated() {
            let signal = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH", why: "fixture",
                price: 1.1, confidence: 80, opportunity: value)
            let commit = ScanKernel.commit(from: signal, bars: [])
            let invalidConfidence = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH",
                why: "fixture", price: 1.1, confidence: value, opportunity: 80)
            let confidenceCommit = ScanKernel.commit(from: invalidConfidence, bars: [])
            check("invalid commit score \(index) cannot trap or arm", commit.engineCall == "WAIT" && commit.score == 0 && commit.veto != nil
                && confidenceCommit.engineCall == "WAIT" && confidenceCommit.veto != nil)
        }
        let ring = CompletedBarRing()
        let ringOK = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for index in 1...100 {
                group.addTask {
                    let input = (0..<64).map { CompletedBar(time: Double($0) * 60_000, open: Double(index), high: Double(index) + 1, low: Double(index) - 1, close: Double(index)) }
                    return await ring.loadAndFetch(input) == input
                }
            }
            var ok = true
            for await value in group { ok = ok && value }
            return ok
        }
        check("100 concurrent ring scans isolated", ringOK)
        let small = CompletedBarRing(capacity: 1)
        let pair = [CompletedBar(time: 1, open: 1, high: 2, low: 0, close: 1), CompletedBar(time: 2, open: 1, high: 2, low: 0, close: 1)]
        check("ring rejects truncation", await small.loadAndFetch(pair).isEmpty)
        check("ring rejects reordering", await ring.loadAndFetch(pair.reversed()).isEmpty)
        let block = EvidenceClustering.adjust([.init(pair: "EUR/USD", capturedAtMs: 59_999, won: true), .init(pair: "GBP/USD", capturedAtMs: 60_001, won: true)])
        check("clock boundary does not split correlated block", block.blocks == 1 && block.effectiveSize == 1)
        check("extreme clustering timestamp does not trap", EvidenceClustering.adjust([.init(pair: "EUR/USD", capturedAtMs: .greatestFiniteMagnitude, won: true)]).effectiveSize == 1)
        check("infinite bankroll fails closed", ExpectancyMath.recommendedStake(bankroll: .infinity, winRate: 0.9) == 0)
        check("numeric guards preserve configured risk ceiling", ExpectancyMath.recommendedStake(bankroll: 10_000,
            winRate: 0.65, payoutRatio: 0.88, fraction: 0.25, maxRiskCeiling: 0.05) == 500)
        check("sizing arithmetic overflow fails closed", ExpectancyMath.recommendedStake(bankroll: 1e300,
            winRate: 1, payoutRatio: 0.88, fraction: 1e300, maxRiskCeiling: 1e300) == 0)
        check("invalid Wilson wins fail closed", EdgeEvidence.wilsonScoreInterval(wins: 11, total: 10).lower == 0)
        do {
            let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
            func row(_ id: Int, won: Bool, payout: Double?) -> LedgerRow {
                LedgerRow(timestamp: cutoff.addingTimeInterval(-1000 + Double(id)), pair: "EUR/USD", hash: "h\(id)", score: 80,
                    side: "CALL", veto: false, drift: 0, outcome: won ? "HIT" : "MISS", outcomeEventID: "arm-\(id)", payout: payout,
                    labelSource: "venue-confirmed", horizonSeconds: 60, enteredAt: cutoff.addingTimeInterval(-100_000 + Double(id) * 120))
            }
            let rows = [row(0, won: true, payout: 0.1), row(1, won: false, payout: 0.9)]
            let report = try ExecutionIntelligence.report(rows: rows, asOf: cutoff)
            check("payout follows actual winning row", abs((report.actualExpectancy ?? 1) + 0.45) < 1e-12)
            check("ledger payout matches actual winning row", abs(LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows).expectancy + 0.45) < 1e-12)
            let aboveOne = [row(0, won: true, payout: 1.2), row(1, won: false, payout: 1.2)]
            let aboveOneReport = try ExecutionIntelligence.report(rows: aboveOne, asOf: cutoff)
            check("recorded net payouts above one remain supported", abs((aboveOneReport.actualExpectancy ?? -1) - 0.1) < 1e-12
                && abs(LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: aboveOne).expectancy - 0.1) < 1e-12)
            check("missing payout never imputed as actual", try ExecutionIntelligence.report(rows: [row(0, won: true, payout: nil)], asOf: cutoff).actualExpectancy == nil)
            check("report input order is reproducible", report == (try ExecutionIntelligence.report(rows: rows.reversed(), asOf: cutoff)))
            check("duplicate arms excluded", try ExecutionIntelligence.report(rows: [rows[0], rows[0]], asOf: cutoff).resolved == 0)
            let book = (0..<300).map { row($0, won: $0 < 250, payout: 0.88) }
            check("nominal success cannot promote", !LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: book).isProvenEdge)
            let context = AssistantContextBuilder.make(journal: [], ledgerRows: book, now: cutoff)
            check("assistant statistics use complete archive", context.performance.sampleSize == 300 && context.confirmedEntries.count == 60)
            check("assistant retains insufficient evidence", context.research?.status == "INSUFFICIENT EVIDENCE")
            let split = cutoff.addingTimeInterval(-99_760)
            let chronological = try ExecutionIntelligence.report(rows: book, splitAt: split, asOf: cutoff)
            check("chronological cutoff purges overlapping training expiry", chronological.chronologicalCohorts.count == 2 && chronological.chronologicalCohorts[0].resolved == 2)
            var conflicting = rows[0]; conflicting.outcome = "MISS"
            let conflictA = try ExecutionIntelligence.report(rows: [rows[0], conflicting], asOf: cutoff)
            let conflictB = try ExecutionIntelligence.report(rows: [conflicting, rows[0]], asOf: cutoff)
            check("conflicting row ordering preserves digest", conflictA == conflictB)
            let expiry = rows[0].enteredAt!.addingTimeInterval(60)
            func proxy(_ delay: Double, source: String) -> ResearchOutcome {
                ResearchOutcome.resolve(eventID: rows[0].outcomeEventID, horizon: 60,
                    entryTime: rows[0].enteredAt!, strike: 1.1, side: "HIGH",
                    quote: LiveQuote(asset: "EUR/USD", bid: 1.0998, ask: 1.1, mid: 1.0999,
                        asOfMs: expiry.addingTimeInterval(delay).timeIntervalSince1970 * 1000, source: "fixture"),
                    observedAt: expiry.addingTimeInterval(delay), labelSource: source)
            }
            check("reference attribution matches timely proxy", try ExecutionIntelligence.report(rows: rows,
                references: [proxy(1, source: "oanda-midpoint-proxy")], asOf: cutoff).quality.referenceDisagreements == 1)
            check("late proxy excluded from attribution", try ExecutionIntelligence.report(rows: rows,
                references: [proxy(10, source: "oanda-midpoint-proxy")], asOf: cutoff).quality.referenceComparisons == 0)
            check("synthetic proxy excluded from attribution", try ExecutionIntelligence.report(rows: rows,
                references: [proxy(1, source: "synthetic")], asOf: cutoff).quality.referenceComparisons == 0)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("core-audit-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let corruptURL = root.appendingPathComponent("execution-observations.jsonl")
            let corruptBytes = Data("{broken\n".utf8)
            try corruptBytes.write(to: corruptURL)
            do {
                _ = try await ExecutionObservationStore(root: root).load()
                check("corrupt telemetry is surfaced", false)
            } catch { check("corrupt telemetry is surfaced", true) }
            check("corrupt telemetry preserved", try Data(contentsOf: corruptURL) == corruptBytes)
            let signal = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "CALL", why: "fixture", price: 1.1, confidence: 80)
            let commit = ScanKernel.commit(from: signal, bars: [], scannedAt: cutoff.addingTimeInterval(-2))
            let quote = LiveQuote(asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
                asOfMs: cutoff.timeIntervalSince1970 * 1000 - 100, source: "test")
            let observation = ExecutionObservation(armID: "arm-0", commit: commit, quote: quote, kind: "manual-entry", now: cutoff)
            check("execution timing comes from frozen scan", observation.scanToRecordMs == 2000 && observation.quoteAgeMs == 100)
            let cleanRoot = root.appendingPathComponent("clean")
            let store = ExecutionObservationStore(root: cleanRoot)
            try await store.record(observation)
            try await store.record(observation)
            let loaded = try await store.load()
            check("execution observations persist once", loaded == [observation])
            check("telemetry cannot create ledger", !FileManager.default.fileExists(atPath: FileLocations.ledgerCSV(in: cleanRoot).path))
        } catch { check("research checks completed: \(error)", false) }
        print("CoreAudit: \(passed)/\(passed + failed) PASS; \(failed) FAIL. Foundation Models and UI are not exercised.")
        if failed > 0 { exit(1) }
    }
}
