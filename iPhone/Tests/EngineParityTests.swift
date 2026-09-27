import BlazerCore
import XCTest

final class EngineParityTests: XCTestCase {
    func testSameCompletedBarsMatchTheMacSeal() async throws {
        let input = GoldenFixture.market()
        let first = try await StrategyEngine.evaluate(input: input)
        let second = try await StrategyEngine.evaluate(input: input)
        let bars = GoldenFixture.frozenBars(from: input)
        let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let commit = ScanKernel.commit(from: first.signal, bars: bars, scannedAt: scannedAt)
        let again = ScanKernel.commit(from: second.signal, bars: bars, scannedAt: scannedAt)

        XCTAssertEqual(EngineIdentity.loadedSHA1(), EngineIdentity.pinnedSHA1)
        XCTAssertEqual(commit.fingerprint, "CE239CDB")
        XCTAssertEqual(commit.fingerprint, again.fingerprint)
        XCTAssertEqual(commit.fingerprint, ScanFingerprint.hex(candles: bars))
        XCTAssertEqual(commit.score, 68)
        XCTAssertEqual(commit.score, again.score)
        XCTAssertEqual(commit.engineCall, "WAIT")
        XCTAssertEqual(first.signal.cabinetSide, "WAIT")
        XCTAssertEqual(commit.engineCall, again.engineCall)
        XCTAssertEqual(commit.evidence, "Trend is up (+18)")
        XCTAssertEqual(commit.evidence, again.evidence)
        XCTAssertEqual(commit.strike, again.strike)
        XCTAssertEqual(commit.strike, 1.0869200000000054, accuracy: 0.000000000001)
        XCTAssertEqual(Timing.liveMs, 8000)
        XCTAssertEqual(BeamContract.verb(cabinetSide: "HIGH", elapsedMs: 1_000, vetoed: false), "TAP HIGH")
        XCTAssertEqual(BeamContract.verb(cabinetSide: "LOW", elapsedMs: 1_000, vetoed: false), "TAP LOW")
        XCTAssertEqual(BeamContract.verb(cabinetSide: "HIGH", elapsedMs: Timing.liveMs + 1, vetoed: false), "EXPIRED")
        XCTAssertEqual(BeamContract.verb(cabinetSide: "HIGH", elapsedMs: 1_000, vetoed: true), "WAIT")
    }

    func testClosedMarketIsOffline() {
        let saturday = Date(timeIntervalSince1970: 1_704_560_400)
        XCTAssertFalse(FxSession.isOpen(saturday))
        XCTAssertEqual(FxSession.label(saturday), "FX closed — SKIP")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let quote = LiveQuote(
            asset: "EUR/USD",
            bid: 1.1,
            ask: 1.10012,
            mid: 1.10006,
            asOfMs: now.timeIntervalSince1970 * 1000,
            source: "oanda"
        )
        XCTAssertEqual(
            FeedStatusResolver.resolve(
                marketOpen: false,
                sessionReady: true,
                transport: .ok,
                quote: quote,
                lastFreshPollAt: now,
                now: now
            ),
            .disconnected
        )
    }

    func testHitWritesOnceAndReplayKeepsTheSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-iphone-\(UUID().uuidString)", isDirectory: true)
        let store = PersistenceCoordinator(root: root)
        let bar = Candle(time: 60, open: 1.1, high: 1.2, low: 1.0, close: 1.15)
        let snapshot = SnapshotRecord(
            hash: "CE239CDB",
            pair: "EUR/USD",
            bars: [bar],
            strike: 1.08692,
            score: 68,
            side: "WAIT"
        )
        let entry = JournalEntry(
            id: "arm-1",
            fingerprint: "CE239CDB",
            pair: "EUR/USD",
            score: 68,
            side: "WAIT",
            verb: "WAIT",
            why: "Trend is up (+18)",
            strike: 1.08692,
            veto: nil,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await store.recordScan(entry, snapshot: snapshot)
        let row = LedgerRow(
            timestamp: entry.scannedAt,
            pair: entry.pair,
            hash: entry.fingerprint,
            score: entry.score,
            side: entry.side,
            veto: false,
            drift: 0,
            outcome: DeskOutcome.hit.rawValue,
            outcomeEventID: entry.id
        )
        let first = try await store.settle(armID: entry.id, row: row, snapshot: snapshot)
        let second = try await store.settle(armID: entry.id, row: row, snapshot: snapshot)
        let restored = await store.restore()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(restored.stats.hits, 1)
        XCTAssertEqual(restored.stats.misses, 0)
        XCTAssertEqual(restored.entries.first?.outcome, "HIT")
        XCTAssertEqual(restored.bars(for: "CE239CDB").map(\.close), [1.15])
        try? FileManager.default.removeItem(at: root)
    }
}
