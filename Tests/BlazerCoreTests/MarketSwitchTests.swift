import Foundation
import Testing
@testable import LightningDesk

// Switching market mode must never trap, and the FX path must be safe with no OANDA token.

@MainActor
@Test func switchingMarketModeIsSafe() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-market-test-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)

    #expect(model.marketMode == .fx)
    #expect(model.pairs.contains("EUR/USD"))

    model.marketMode = .crypto
    #expect(model.marketMode == .crypto)
    #expect(model.pairs == ["BTC/USDT"])
    _ = model.radarLeader
    _ = model.side(for: "BTC/USDT")
    _ = model.score(for: "BTC/USDT")
    _ = model.strike(for: "BTC/USDT")
    _ = model.candles(for: "BTC/USDT")

    model.marketMode = .fx
    #expect(model.pairs.contains("EUR/USD"))
    // Switching modes must not corrupt state; the book refresh happens on scan, not on switch.
    #expect(model.book.isEmpty == false)
}
