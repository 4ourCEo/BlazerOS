import Testing
@testable import BlazerCore

// The desk renders drift in "pips". Crypto must not inherit the FX default (0.0001),
// which would print a $20 BTC move as 200,000 pips.

@Test func cryptoPipScaleIsOneDollar() {
    #expect(Assets.pipScale(for: "BTC/USDT") == 1.0)
    #expect(Assets.pipScale(for: "ETH/USDT") == 1.0)
}

@Test func fxPipScalesUnchanged() {
    #expect(Assets.pipScale(for: "EUR/USD") == 0.0001)
    #expect(Assets.pipScale(for: "USD/JPY") == 0.01)
    #expect(Assets.pipScale(for: "XAU/USD") == 0.10)
}
