import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

@MainActor
@Test func scanSchedulerKeepsOneLatestPendingRequest() {
    let scheduler = ScanRequestScheduler()
    let obsolete = scheduler.submit(market: .fx, assets: ["EUR/USD", "GBP/USD"])
    let current = scheduler.submit(market: .crypto, asset: "BTC/USDT", assets: ["BTC/USDT"])

    #expect(!scheduler.isCurrent(obsolete))
    #expect(scheduler.isCurrent(current))
    #expect(scheduler.pending == current)
    #expect(scheduler.takePending() == current)
    #expect(scheduler.takePending() == nil)

    scheduler.invalidate()
    #expect(!scheduler.isCurrent(current))
    #expect(scheduler.pending == nil)
}

@MainActor
@Test func backgroundingExpiresActionableDeskStateWithoutRearming() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-background-expiry-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)
    let scanTime = Date()
    let signal = EngineSignal(
        asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH", why: "fixture",
        price: 1.1, entryPrice: 1.1, confidence: 80, asOfMs: scanTime.timeIntervalSince1970 * 1000
    )
    let candle = Candle(time: scanTime.timeIntervalSince1970 * 1000, open: 1.1, high: 1.101, low: 1.099, close: 1.1)
    let commit = ScanKernel.commit(from: signal, bars: [candle], scannedAt: scanTime)
    let quote = LiveQuote(
        asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
        asOfMs: scanTime.timeIntervalSince1970 * 1000, source: "test"
    )
    model.installArmedScanForTesting(commit: commit, signal: signal, quote: quote, armedAt: scanTime.addingTimeInterval(-1))
    #expect(model.frame?.isActionable == true)

    model.handleAppBackgrounded(now: scanTime.addingTimeInterval(2))
    #expect(model.frame?.isActionable == false)
    #expect(model.frame?.verb == "EXPIRED")
    #expect(model.awaitingOutcome)

    model.handleAppForegrounded(now: scanTime.addingTimeInterval(20))
    #expect(model.frame?.isActionable == false)
}
