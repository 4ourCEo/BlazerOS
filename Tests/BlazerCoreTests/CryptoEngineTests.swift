import Foundation
import Testing
import BlazerCore
import BlazerCrypto

// The crypto engine is compiled Swift, so it has no runtime hash to verify. Its identity is
// protected the same way the JS seal protects the JS engine: sealed decisions. If any of these
// change, the behaviour changed — bump `CryptoDeskSignal.engineIdentity` deliberately.

private func candle(_ open: Double, _ close: Double, high: Double, low: Double, i: Int) -> CryptoCandle {
    CryptoCandle(
        time: 1_700_000_000_000 + Double(i) * 60_000,
        open: open, high: high, low: low, close: close,
        volume: 10 + Double(i) * 0.5,
        quoteVolume: 1_000_000 + Double(i) * 50_000,
        trades: 500 + i * 10
    )
}

private func batch(bullish: Bool = true, last: ((CryptoCandle) -> CryptoCandle)? = nil) -> CryptoCandleBatch {
    var candles: [CryptoCandle] = []
    var price = 100_000.0
    for i in 0..<40 {
        let open = price
        price += bullish ? 80 : -80
        candles.append(candle(open, price, high: max(open, price) + 10, low: min(open, price) - 10, i: i))
    }
    if let last, let previous = candles.popLast() {
        candles.append(last(previous))
    }
    let mid = candles.last?.close ?? price
    return CryptoCandleBatch(candles: candles, bid: mid - 1, ask: mid + 1, asset: "BTC/USDT", source: "test")
}

@Test func cryptoIdentityIsStable() {
    #expect(CryptoDeskSignal.engineIdentity == "crypto-engine-v1")
    #expect(CryptoDeskSignal.policy == "crypto-v1")
}

@Test func cryptoDecisionsAreSealed() {
    let up = CryptoEngine.evaluate(batch: batch(), asset: "BTC/USDT")
    #expect(up.side == "HIGH")
    #expect(up.conviction == 55)
    #expect(up.highScore == 44)
    #expect(up.lowScore == 4)
    #expect(up.why.contains("Bullish 3-candle"))

    let down = CryptoEngine.evaluate(batch: batch(bullish: false), asset: "BTC/USDT")
    #expect(down.side == "LOW")
    #expect(down.lowScore == 44)
    #expect(down.highScore == 4)
}

@Test func cryptoVetoBranchesAreSealed() {
    let sweep = batch { _ in
        let priorHigh: Double = 100_000 + 39 * 80 + 10
        return candle(priorHigh - 200, priorHigh - 40, high: priorHigh + 200, low: priorHigh - 210, i: 39)
    }
    let sweepSignal = CryptoEngine.evaluate(batch: sweep, asset: "BTC/USDT")
    #expect(sweepSignal.side == "WAIT")
    #expect(sweepSignal.why.contains("Liquidity sweep veto"))

    let climax = batch { c in
        candle(c.open, c.open + 480, high: c.open + 500, low: c.open - 10, i: 39)
    }
    let climaxSignal = CryptoEngine.evaluate(batch: climax, asset: "BTC/USDT")
    #expect(climaxSignal.side == "WAIT")
    #expect(climaxSignal.why.contains("Exhaustion veto"))

    let conflict = batch(bullish: false) { c in
        candle(c.close - 400, c.close, high: c.close + 10, low: c.close - 410, i: 39)
    }
    let conflictSignal = CryptoEngine.evaluate(batch: conflict, asset: "BTC/USDT")
    #expect(conflictSignal.side == "WAIT")
    #expect(conflictSignal.why.contains("Trend conflict"))
}

@Test func cryptoDirectionAndStrengthStayInsideTheContract() {
    for feed in [batch(), batch(bullish: false)] {
        let signal = CryptoDeskSignal.make(
            asset: "BTC/USDT",
            batch: feed,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let direction = signal.directionScore ?? -1
        let strength = signal.strength ?? -1

        #expect((0.0...100.0).contains(direction), "directionScore \(direction) left 0...100")
        #expect((0.0...100.0).contains(strength), "strength \(strength) left 0...100")
        #expect(abs(abs(direction - 50) * 2 - strength) < 0.001)

        if signal.cabinetSide == "HIGH" {
            #expect(direction > 50)
        } else if signal.cabinetSide == "LOW" {
            #expect(direction < 50)
        } else {
            #expect(direction == 50)
            #expect(strength == 0)
        }
    }
}
