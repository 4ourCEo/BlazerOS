import Foundation
import Testing
import BlazerCore
import BlazerCrypto

private func cryptoBatch(
    spread: Double = 2.0,
    bullish: Bool = true
) -> CryptoCandleBatch {
    var candles: [CryptoCandle] = []
    var price = 100_000.0
    for i in 0..<40 {
        let open = price
        price += bullish ? 80 : -80
        candles.append(
            CryptoCandle(
                time: 1_700_000_000_000 + Double(i) * 60_000,
                open: open,
                high: max(open, price) + 10,
                low: min(open, price) - 10,
                close: price,
                volume: 10 + Double(i) * 0.5,
                quoteVolume: 1_000_000 + Double(i) * 50_000,
                trades: 500 + i * 10
            )
        )
    }
    let mid = candles.last?.close ?? price
    return CryptoCandleBatch(
        candles: candles,
        bid: mid - spread / 2,
        ask: mid + spread / 2,
        asset: "BTC/USDT",
        source: "test"
    )
}

@Test func cryptoAdapterFillsEveryEntryGateField() {
    let batch = cryptoBatch()
    let signal = CryptoDeskSignal.make(asset: "BTC/USDT", batch: batch, now: Date(timeIntervalSince1970: 1_700_000_000))

    #expect(signal.asOfMs != nil)
    #expect(signal.features != nil)
    #expect((signal.features?.atr1m ?? 0) > 0)
    #expect((signal.confidence ?? -1) >= 0 && (signal.confidence ?? 101) <= 100)
    #expect(signal.source?.hasPrefix("crypto:") == true)
}

@Test func cryptoDeskGatesAreEnforced() {
    let batch = cryptoBatch()
    let features = ScanFeatures(
        atr1m: 50, atr5m: 50, efficiency: 0, slopeATR: 0, spreadATR: 0,
        rangeATR: 0, bodyATR: 0, upperWickShare: 0, lowerWickShare: 0,
        twoSidedSweep: false, sweep: nil, structureBreak: nil, regime: "crypto"
    )
    let normal = EngineSignal(
        asset: "BTC/USDT", cabinetSide: "HIGH", call: "CALL", why: "test",
        price: 100_000, entryPrice: 100_000, confidence: 80,
        asOfMs: Date().timeIntervalSince1970 * 1000, features: features
    )
    #expect(CryptoDeskSignal.veto(asset: "BTC/USDT", batch: batch, signal: normal) == nil)

    var weak = normal
    weak.confidence = 60
    #expect(CryptoDeskSignal.veto(asset: "BTC/USDT", batch: batch, signal: weak)?.contains("below") == true)

    var wide = cryptoBatch(spread: 40)
    #expect(CryptoDeskSignal.veto(asset: "BTC/USDT", batch: wide, signal: normal)?.contains("Spread") == true)

    var volatile = features
    volatile.atr1m = 400
    var hot = normal
    hot.features = volatile
    #expect(CryptoDeskSignal.veto(asset: "BTC/USDT", batch: batch, signal: hot)?.contains("ATR") == true)
}

@Test func cryptoShapedSignalPassesEntryQuality() {
    // The exact contract the desk previously failed to populate.
    let now = Date()
    let features = ScanFeatures(
        atr1m: 50, atr5m: 50, efficiency: 0, slopeATR: 0, spreadATR: 0,
        rangeATR: 0, bodyATR: 0, upperWickShare: 0, lowerWickShare: 0,
        twoSidedSweep: false, sweep: nil, structureBreak: nil, regime: "crypto"
    )
    let signal = EngineSignal(
        asset: "BTC/USDT", cabinetSide: "HIGH", call: "CALL", why: "test",
        price: 100_000, entryPrice: 100_000, confidence: 80,
        asOfMs: now.timeIntervalSince1970 * 1000, features: features
    )
    let quote = LiveQuote(
        asset: "BTC/USDT", bid: 99_999, ask: 100_001, mid: 100_000,
        asOfMs: now.timeIntervalSince1970 * 1000, source: "test"
    )
    #expect(EntryQuality.veto(signal: signal, quote: quote, at: now) == nil)
}

@Test func cryptoCommitScoresConvictionNotAFraction() {
    let signal = EngineSignal(
        asset: "BTC/USDT", cabinetSide: "HIGH", call: "CALL", why: "test",
        price: 100_000, entryPrice: 100_000, confidence: 72,
        asOfMs: Date().timeIntervalSince1970 * 1000
    )
    let commit = ScanKernel.commit(from: signal, bars: [], scannedAt: Date())
    #expect(commit.score == 72)
}
