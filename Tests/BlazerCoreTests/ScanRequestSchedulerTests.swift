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

private actor CancellationIgnoringGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false

    func wait() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Test func scanCoordinatorRejectsCancellationIgnoringObsoleteResult() async {
    let coordinator = ScanOperationCoordinator()
    let gate = CancellationIgnoringGate()
    var published: [String] = []

    let operation: ScanOperationCoordinator.Operation = { request in
        if request.asset == "first" {
            await gate.wait() // CheckedContinuation deliberately ignores task cancellation.
        }
        if coordinator.isCurrent(request), let asset = request.asset {
            published.append(asset)
        }
    }

    let first = Task { @MainActor in
        await coordinator.submit(market: .crypto, asset: "first", assets: ["first"], operation: operation)
    }
    while await !gate.waiting { await Task.yield() }

    let second = Task { @MainActor in
        await coordinator.submit(market: .crypto, asset: "second", assets: ["second"], operation: operation)
    }
    while coordinator.currentGeneration < 2 { await Task.yield() }
    await gate.open()

    _ = await first.value
    _ = await second.value
    #expect(published == ["second"])
    #expect(coordinator.isIdle)
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
