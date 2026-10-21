import Foundation
import Testing
@testable import LightningDesk

// Switching market mode must never trap, and the FX path must be safe with no OANDA token.

@MainActor
@Test func switchingMarketModeIsSafe() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-market-test-\(UUID().uuidString)")
    let model = LightningDeskModel(storageRoot: root)

    #expect(model.marketMode == .crypto)
    #expect(model.pairs == ["BTC/USDT"])

    model.marketMode = .fx
    #expect(model.marketMode == .fx)
    #expect(model.pairs.contains("EUR/USD"))
    _ = model.radarLeader
    _ = model.side(for: "EUR/USD")
    _ = model.score(for: "EUR/USD")
    _ = model.strike(for: "EUR/USD")
    _ = model.candles(for: "EUR/USD")

    model.marketMode = .crypto
    #expect(model.pairs == ["BTC/USDT"])
    // Switching modes must not corrupt state; the book refresh happens on scan, not on switch.
    #expect(model.book.isEmpty == false)
}
