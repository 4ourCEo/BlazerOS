import Foundation
import BlazerCore

struct Check {
    var name: String
    var pass: Bool
    var detail: String
}

@main
struct ParityCheck {
    static func main() async {
        var rows: [Check] = []
        func check(_ name: String, _ pass: Bool, _ detail: String = "") {
            rows.append(Check(name: name, pass: pass, detail: detail))
        }

        let bars = contractBars()
        let hash = ScanFingerprint.hex(candles: bars)
        check("fingerprint length", hash.count == 8 && hash.allSatisfy(\.isHexDigit), hash)
        check("same bars, same fingerprint", ScanFingerprint.hex(candles: bars) == hash, hash)
        check("golden contract hash", hash == "F9813E3C", hash)

        let strike = 1.17342
        var commit = ScanCommit(
            asset: "EUR/USD",
            engineCall: "TAP HIGH",
            score: 76,
            evidence: "trend",
            strike: strike,
            fingerprint: hash,
            candleCount: bars.count,
            candles: bars,
            scannedAt: Date(timeIntervalSince1970: 1_758_000_000),
            driftPips: 0.2
        )
        commit.driftPips = 0.4
        check("live quote leaves score", commit.score == 76)
        check("live quote leaves hash", commit.fingerprint == hash)
        check("live quote leaves strike", commit.strike == strike)
        check("frozen bars stay frozen", commit.candles.map(\.close) == bars.map(\.close))

        commit.veto = "Slippage"
        commit.driftPips = 1.3
        let highRows = ExecutionGate.rows(
            engineCall: commit.engineCall,
            score: commit.score,
            veto: commit.veto ?? "",
            driftPips: commit.driftPips
        )
        check(
            "veto keeps SIDE",
            highRows.contains { $0.code == "SIDE" && $0.detail == "TAP HIGH" }
        )
        check("veto hero is WAIT", BeamContract.verb(cabinetSide: "HIGH", elapsedMs: 1000, vetoed: true) == "WAIT")
        check("rail expires", BeamContract.verb(cabinetSide: "HIGH", elapsedMs: Timing.liveMs + 1, vetoed: false) == "EXPIRED")
        check("rail armed inside 8s", BeamContract.verb(cabinetSide: "LOW", elapsedMs: 1000, vetoed: false) == "TAP LOW")

        check("incomplete bar fails lift", !MechanicalLifters.verifyLift(barComplete: false, spread: 0.00012))
        check("missing spread fails lift", !MechanicalLifters.verifyLift(barComplete: true, spread: nil))
        check("real spread passes lift", MechanicalLifters.verifyLift(barComplete: true, spread: 0.00012))

        let nowMs = 1_700_000_000_000.0
        check(
            "absurd print is not actionable",
            !QuoteFreshness.isActionable(
                bid: 1.1,
                ask: 1.10012,
                asOfMs: nowMs - Timing.printStaleMs - 1,
                nowMs: nowMs
            )
        )
        check(
            "quiet market print is actionable",
            QuoteFreshness.isActionable(bid: 1.1, ask: 1.10012, asOfMs: nowMs - 60_000, nowMs: nowMs)
        )
        check("beam and stale poll are different clocks", Timing.quoteStaleMs != Timing.liveMs)

        let loaded = EngineIdentity.loadedSHA1()
        check("engine pin", loaded == EngineIdentity.pinnedSHA1, loaded ?? "missing")

        let input = GoldenFixture.market()
        do {
            let first = try await StrategyEngine.evaluate(input: input)
            let second = try await StrategyEngine.evaluate(input: input)
            check("repeat scan, same side", first.signal.cabinetSide == second.signal.cabinetSide, first.signal.cabinetSide)
            check("repeat scan, same call", first.signal.call == second.signal.call, first.signal.call)
            check("repeat scan, same score inputs", first.signal.opportunity == second.signal.opportunity)
            check("verdict is a desk word", ["HIGH", "LOW", "WAIT"].contains(first.signal.cabinetSide))

            let frozen = input.candles1m.map {
                Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }
            let sealed = ScanKernel.commit(from: first.signal, bars: frozen, scannedAt: Date(timeIntervalSince1970: 1_700_000_000))
            let again = ScanKernel.commit(from: second.signal, bars: frozen, scannedAt: Date(timeIntervalSince1970: 1_700_000_000))
            check("repeat commit, same fingerprint", sealed.fingerprint == again.fingerprint, sealed.fingerprint)
            check("golden fixture fingerprint", sealed.fingerprint == "CE239CDB", sealed.fingerprint)
            check("repeat commit, same score", sealed.score == again.score, "\(sealed.score)")
            check("golden fixture score", sealed.score == 68, "\(sealed.score)")
            check("golden fixture call", sealed.engineCall == "WAIT", sealed.engineCall)
            check("golden fixture side", sealed.engineCall == first.signal.cabinetSide, first.signal.cabinetSide)
            check("golden fixture evidence", !sealed.evidence.isEmpty, sealed.evidence)
            check("repeat commit, same strike", sealed.strike == again.strike, String(sealed.strike))
            let seal = ParitySeal.make(commit: sealed, engineSHA1: EngineIdentity.pinnedSHA1)
            check("seal matches local bars", seal.matchesLocalBars(frozen))

            var blocked = input
            blocked.spread = 0
            let envelope = try await ScanKernel.evaluate(input: &blocked, asset: "EUR/USD")
            check("zero spread is WAIT", envelope.signal?.call == "WAIT", envelope.signal?.why ?? "")
        } catch {
            check("engine evaluate", false, error.localizedDescription)
        }

        let armed = DeskFrame.make(commit: commit, feed: .live, cabinetSide: "HIGH", elapsedMs: 1000)
        check("desk frame veto is WAIT and keeps score", armed.verb == "WAIT" && armed.score == 76)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-parity-\(UUID().uuidString)", isDirectory: true)
        let ledger = LedgerFile(root: root)
        let entry = LedgerEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pair: "EUR/USD",
            hash: hash,
            score: 76,
            side: "HIGH",
            veto: true,
            drift: 1.3,
            outcome: "WIN",
            theirPrice: nil,
            outcomeEventID: "arm-1"
        )
        do {
            let wrote = try await ledger.pipe(entry)
            let duplicate = try await ledger.pipe(entry)
            check("ledger writes once", wrote && !duplicate)
            let csv = try String(contentsOf: root.appendingPathComponent(LedgerFile.fileName), encoding: .utf8)
            check("ledger header matches Mac", csv.hasPrefix(LedgerEntry.csvHeader + "\n"))
            check("ledger has no token", !csv.contains("token") && !csv.contains("Bearer"))
        } catch {
            check("ledger write", false, error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: root)

        let local = Set(DeviceLocal.allCases.map(\.rawValue))
        let synced = Set(SyncDomain.allCases.map(\.rawValue))
        check("token feed and live scan stay off CloudKit", local.isDisjoint(with: synced))

        let saturday = Date(timeIntervalSince1970: 1_704_560_400)
        check("Saturday FX is closed", !FxSession.isOpen(saturday), FxSession.label(saturday))
        let freshPoll = Date(timeIntervalSince1970: 1_700_000_000)
        let liveQuote = LiveQuote(
            asset: "EUR/USD",
            bid: 1.1,
            ask: 1.10012,
            mid: 1.10006,
            asOfMs: freshPoll.timeIntervalSince1970 * 1000,
            source: "oanda"
        )
        check(
            "Closed market is not LIVE",
            FeedStatusResolver.resolve(
                marketOpen: false,
                sessionReady: true,
                transport: .ok,
                quote: liveQuote,
                lastFreshPollAt: freshPoll,
                now: freshPoll
            ) == .disconnected
        )
        check(
            "Missing token is ERROR",
            FeedStatusResolver.resolve(
                marketOpen: true,
                sessionReady: false,
                transport: nil,
                quote: nil,
                lastFreshPollAt: nil,
                now: freshPoll
            ) == .error
        )
        check(
            "Fresh poll is LIVE",
            FeedStatusResolver.resolve(
                marketOpen: true,
                sessionReady: true,
                transport: .ok,
                quote: liveQuote,
                lastFreshPollAt: freshPoll,
                now: freshPoll
            ) == .live
        )
        check(
            "Stale poll is STALE",
            FeedStatusResolver.resolve(
                marketOpen: true,
                sessionReady: true,
                transport: .ok,
                quote: liveQuote,
                lastFreshPollAt: freshPoll.addingTimeInterval(-(Timing.quoteStaleMs / 1000) - 1),
                now: freshPoll
            ) == .stale
        )

        let plain = OandaClient.parseTimeMs("2024-01-02T03:04:05Z")
        check(
            "OANDA time parses",
            plain == Date(timeIntervalSince1970: 1_704_164_645).timeIntervalSince1970 * 1000
        )

        var failed = 0
        for row in rows {
            let mark = row.pass ? "PASS" : "FAIL"
            if !row.pass { failed += 1 }
            let detail = row.detail.isEmpty ? "" : "  \(row.detail)"
            print("\(mark)  \(row.name)\(detail)")
        }
        print(failed == 0 ? "parity ok \(rows.count)" : "parity failed \(failed)/\(rows.count)")
        exit(failed == 0 ? 0 : 1)
    }

    private static func contractBars() -> [Candle] {
        var bars: [Candle] = []
        for i in 0..<20 {
            let close = 1.17342 + Double(i) * 0.0001
            bars.append(
                Candle(
                    time: Double(1_700_000_000 + i * 60),
                    open: close - 0.00005,
                    high: close + 0.00008,
                    low: close - 0.00008,
                    close: close
                )
            )
        }
        return bars
    }

}
