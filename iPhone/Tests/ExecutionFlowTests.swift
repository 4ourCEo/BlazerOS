import BlazerCore
@testable import LightningDesk
import XCTest

@MainActor
final class ExecutionFlowTests: XCTestCase {
    private func root() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-execution-\(UUID().uuidString)", isDirectory: true)
    }

    private func armedFixture(
        signalAge: TimeInterval = 0,
        historical: Bool = false
    ) -> (ScanCommit, EngineSignal, LiveQuote) {
        let now = Date()
        let signal = EngineSignal(
            asset: "EUR/USD",
            cabinetSide: "HIGH",
            call: "CALL",
            why: "test",
            price: 1.1,
            entryPrice: 1.1,
            confidence: 76,
            asOfMs: now.addingTimeInterval(-signalAge).timeIntervalSince1970 * 1000,
            features: ScanFeatures(
                atr1m: 0.0005, atr5m: 0.0005, efficiency: 0, slopeATR: 0,
                spreadATR: 0, rangeATR: 0, bodyATR: 0, upperWickShare: 0,
                lowerWickShare: 0, twoSidedSweep: false, sweep: nil,
                structureBreak: nil, regime: "test"
            )
        )
        let commit = ScanKernel.commit(
            from: signal,
            bars: [Candle(time: 60_000, open: 1.1, high: 1.11, low: 1.09, close: 1.1)],
            m5Bars: [Candle(time: 0, open: 1.08, high: 1.12, low: 1.07, close: 1.1)],
            bid: 1.0999,
            ask: 1.1001,
            spread: 0.0002,
            scannedAt: now
        )
        let quote = LiveQuote(
            asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
            asOfMs: now.timeIntervalSince1970 * 1000, source: "test"
        )
        return (commit, signal, quote)
    }

    func testArmedEntryIsCreatedAndPairSwitchCannotChangeIt() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote)
        _ = await model.rememberForTesting()

        await model.lockInTrade(duration: 60)
        XCTAssertEqual(model.activeTrade?.pair, "EUR/USD")
        XCTAssertEqual(model.activeTrade?.side, "HIGH")
        XCTAssertNotNil(model.activeTrade?.evaluationAgeMs)
        XCTAssertLessThanOrEqual(model.activeTrade?.remainingBeamMs ?? 9_999, 8_000)
        XCTAssertGreaterThanOrEqual(model.activeTrade?.remainingBeamMs ?? -1, 0)

        model.select(pair: "USD/JPY")
        XCTAssertEqual(model.activeTrade?.pair, "EUR/USD")
        XCTAssertEqual(model.pair, "EUR/USD")
        XCTAssertEqual(model.activeTrade?.durationSec, 60)
    }

    func testExpiryRecordsReferenceWithoutTouchingConfirmedStats() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote)
        _ = await model.rememberForTesting()

        await model.lockInTrade(duration: 60)
        let armID = model.activeTrade?.id
        XCTAssertNotNil(armID)

        await model.expireActiveTradeForTesting()

        XCTAssertTrue(model.awaitingOutcome)
        XCTAssertEqual(model.outcomeStats.hits + model.outcomeStats.misses, 0)
        XCTAssertEqual(model.referenceHistory.first?.eventID, armID)
        XCTAssertEqual(model.referenceHistory.first?.horizon, 60)
        XCTAssertTrue(
            ["hit", "miss", "tie"].contains(model.referenceHistory.first?.resolution.rawValue ?? "")
        )
        let referenceFile = root
            .appendingPathComponent("Research/oanda-proxy/outcomes")
            .appendingPathComponent("\(armID ?? "missing")-60.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenceFile.path))
    }

    func testStaleSignalCannotBecomeAnEntry() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture(signalAge: 60)
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote)

        await model.lockInTrade(duration: 60)
        XCTAssertNil(model.activeTrade)
        XCTAssertEqual(model.notice, "Beam expired; scan again")
    }

    func testHistoricalScanCannotBecomeAnEntry() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture(historical: true)
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote, historical: true)

        await model.lockInTrade(duration: 60)
        XCTAssertNil(model.activeTrade)
        XCTAssertEqual(model.notice, "Historical scan; scan again before entry")
    }

    func testLockedEntrySurvivesRelaunch() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        first.installArmedScanForTesting(commit: commit, signal: signal, quote: quote)
        _ = await first.rememberForTesting()
        await first.lockInTrade(duration: 180)
        let armID = first.activeTrade?.id
        XCTAssertNotNil(armID)

        let second = LightningDeskModel(storageRoot: root)
        await second.restoreForTesting()
        XCTAssertEqual(second.activeTrade?.id, armID)
        XCTAssertEqual(second.activeTrade?.pair, "EUR/USD")
        XCTAssertEqual(second.activeTrade?.durationSec, 180)
    }

    func testPendingSiriRequestIsConsumedOnce() {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
        XCTAssertTrue(model.takePendingScanRequest())
        XCTAssertFalse(model.takePendingScanRequest())
    }
}
