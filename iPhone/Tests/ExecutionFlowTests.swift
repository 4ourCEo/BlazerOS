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
            .appendingPathComponent("Research/oanda-proxy")
            .appendingPathComponent(ReferenceOutcomeStore.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenceFile.path))
        let contents = (try? String(contentsOf: referenceFile, encoding: .utf8)) ?? ""
        XCTAssertTrue(contents.contains(armID ?? "missing"))
    }

    func testStaleSignalCannotBecomeAnEntry() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture(signalAge: 60)
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote)

        await model.lockInTrade(duration: 60)
        XCTAssertNil(model.activeTrade)
        XCTAssertEqual(model.entryIssue, "Beam expired; scan again")
    }

    func testHistoricalScanCannotBecomeAnEntry() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture(historical: true)
        model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote, historical: true)

        await model.lockInTrade(duration: 60)
        XCTAssertNil(model.activeTrade)
        XCTAssertEqual(model.entryIssue, "Historical scan; scan again before entry")
    }

    func testExpiredUnenteredSignalDoesNotBecomeAwaitingOutcome() {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(
            commit: commit, signal: signal, quote: quote,
            armedAt: Date().addingTimeInterval(-9))

        XCTAssertEqual(model.frame?.verb, "EXPIRED")
        XCTAssertFalse(model.awaitingOutcome)
        XCTAssertNil(model.activeTrade)
        XCTAssertTrue(model.canLogLateEntry)
    }

    func testDemoDeskCannotReuseExpiredDirectionalSignalForLateEntry() {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(
            commit: commit, signal: signal, quote: quote,
            armedAt: Date().addingTimeInterval(-9))
        XCTAssertTrue(model.canLogLateEntry)

        model.loadDemoDesk()
        XCTAssertFalse(model.canLogLateEntry)
        XCTAssertEqual(model.frame?.verb, "HISTORICAL")
        XCTAssertFalse(model.awaitingOutcome)
    }

    func testLateEntryRequiresAndPreservesActualBrokerTime() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(
            commit: commit, signal: signal, quote: quote,
            armedAt: Date().addingTimeInterval(-9))
        _ = await model.rememberForTesting()

        await model.lockInTrade(late: true)
        XCTAssertNil(model.activeTrade)
        XCTAssertEqual(model.entryIssue, "Actual broker entry time is required for late logging")

        let actual = Date()
        await model.lockInTrade(duration: 180, late: true, actualEntryTime: actual)
        guard let activeTrade = model.activeTrade else {
            XCTFail("Late entry should create an active trade")
            return
        }
        XCTAssertEqual(activeTrade.enteredAt.timeIntervalSince1970,
                       actual.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(activeTrade.expiresAt.timeIntervalSince1970,
                       actual.addingTimeInterval(180).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(model.activeTrade?.brokerEntryPrice)
    }

    func testUnknownLateEntryTimeCreatesOnlyIncompleteResearchObservation() async {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LightningDeskModel(storageRoot: root)
        let (commit, signal, quote) = armedFixture()
        model.installArmedScanForTesting(
            commit: commit, signal: signal, quote: quote,
            armedAt: Date().addingTimeInterval(-9))
        _ = await model.rememberForTesting()

        await model.recordUnknownLateEntryTime()
        XCTAssertNil(model.activeTrade)
        XCTAssertFalse(model.awaitingOutcome)
        XCTAssertEqual(model.executionObservations.last?.kind, "late-entry-unknown-time")
    }

    func testExpiredPositionRestoredAfterRelaunchCanBeSettled() async throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let (commit, _, _) = armedFixture()
        let armID = "restored-expired-arm"
        let trade = ActiveTrade(
            id: armID, pair: commit.asset, side: "HIGH", strike: commit.strike,
            score: commit.score, enteredAt: Date().addingTimeInterval(-120),
            durationSec: 60, fingerprint: commit.fingerprint)
        let persistence = PersistenceCoordinator(root: root)
        try await persistence.recordScan(
            JournalEntry(
                id: armID, fingerprint: commit.fingerprint, pair: commit.asset,
                score: commit.score, side: "HIGH", verb: "TAP HIGH", why: "test",
                strike: commit.strike, veto: nil, scannedAt: commit.scannedAt),
            snapshot: SnapshotRecord(
                hash: commit.fingerprint, fullFingerprint: commit.fullFingerprint,
                pair: commit.asset, bars: commit.candles, strike: commit.strike,
                score: commit.score, side: commit.engineCall))
        try await persistence.saveOpenPosition(ActivePositionRecord(
            armID: armID, trade: trade, fullFingerprint: commit.fullFingerprint,
            scanInput: commit.inputSnapshot))

        let model = LightningDeskModel(storageRoot: root)
        await model.restoreForTesting()
        XCTAssertTrue(model.awaitingOutcome)
        XCTAssertNil(model.activeTrade)
        await model.settle(.hit)
        XCTAssertEqual(model.journal.first(where: { $0.id == armID })?.outcome, "HIT")
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
