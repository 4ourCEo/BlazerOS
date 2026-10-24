import Foundation
import Testing
@testable import BlazerCrypto
@testable import BlazerCore

private func safeCandle(_ index: Int, price: Double = 100, volume: Double = 10, trades: Int = 10) -> CryptoCandle {
    CryptoCandle(time: Double(index) * 60_000, open: price, high: price * 1.01,
                 low: price * 0.99, close: price, volume: volume, quoteVolume: volume, trades: trades)
}

@Test func invalidCryptoDomainsAlwaysWait() {
    for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude, -1, 0] {
        var bars = (0..<65).map { safeCandle($0) }
        bars[30] = CryptoCandle(time: 1_800_000, open: value, high: value, low: value,
                               close: value, volume: 1, quoteVolume: 1, trades: 1)
        let batch = CryptoCandleBatch(candles: bars, bid: 99, ask: 101, asset: "BTC/USDT", source: "test")
        let signal = CryptoEngine.evaluate(batch: batch)
        #expect(signal.side == "WAIT")
        #expect(signal.conviction == 0)
        #expect(signal.atrPips.isFinite && signal.volumeSurge.isFinite)
    }
}

@Test func extremeButSupportedValuesDoNotTrapScoreConversion() {
    var bars = (0..<65).map { safeCandle($0, price: 1e90, volume: 1e-90) }
    bars[64] = safeCandle(64, price: 1e90, volume: 1e90, trades: Int.max)
    let batch = CryptoCandleBatch(candles: bars, bid: 1e90, ask: 1.01e90, asset: "BTC/USDT", source: "test")
    let result = CryptoEngine.evaluate(batch: batch)
    #expect(result.atrPips.isFinite && result.volumeSurge.isFinite)
    #expect((0...97).contains(result.conviction))
}

@Test func candleValidationRejectsMalformedRelationsAndNegativeData() {
    let invalid = [
        CryptoCandle(time: 0, open: 1, high: 2, low: 3, close: 1, volume: 1, quoteVolume: 1, trades: 1),
        CryptoCandle(time: 0, open: 4, high: 3, low: 1, close: 2, volume: 1, quoteVolume: 1, trades: 1),
        safeCandle(0, volume: -1), safeCandle(0, trades: -1)
    ]
    #expect(invalid.allSatisfy { !$0.isValidMarketInput })
}

@Test func bothProviderParsersRejectFractionalAndOverflowingTradeCounts() {
    for count in ["nan", "inf", "1e300", "-1", "1.5", String(Double(Int.max))] {
        let binance: [BinanceKlineField] = ["0", "100", "101", "99", "100", "10", "0", "1000", count, "0", "0", "0"].map { .string($0) }
        #expect(CryptoCandle.from(row: binance) == nil)
        #expect(CryptoCandle.fromKraken(row: [0, "100", "101", "99", "100", "100", "10", count]) == nil)
    }
    #expect(CryptoCandle.fromKraken(row: [0, "100", "101", "99", "100", "1e100", "1e100", 1]) == nil)
}

@Test func invalidCryptoQuoteAndChronologyFailClosed() {
    let bars = (0..<65).map { safeCandle($0) }
    for (bid, ask) in [(Double.nan, 101.0), (100.0, Double.infinity), (-1.0, 1.0), (100.0, 99.0), (100.0, 100.0)] {
        let batch = CryptoCandleBatch(candles: bars, bid: bid, ask: ask, asset: "BTC/USDT", source: "test")
        #expect(CryptoDeskSignal.make(asset: "BTC/USDT", batch: batch).cabinetSide == "WAIT")
    }
    let reversed = CryptoCandleBatch(candles: bars.reversed(), bid: 99, ask: 101, asset: "BTC/USDT", source: "test")
    #expect(CryptoEngine.evaluate(batch: reversed).side == "WAIT")
}

@Test func invalidSizingAndWilsonInputsFailClosed() {
    #expect(ExpectancyMath.recommendedStake(bankroll: .infinity, winRate: 0.9) == 0)
    #expect(ExpectancyMath.recommendedStake(bankroll: 1000, winRate: 0.9, fraction: -1) == 0)
    #expect(ExpectancyMath.breakEvenWinRate(payoutRatio: .infinity) == 1)
    #expect(ExpectancyMath.expectedValue(winRate: 1, payoutRatio: 1e300, stake: 1e300) == 0)
    #expect(EdgeEvidence.wilsonScoreInterval(wins: -1, total: 10).lower == 0)
    #expect(EdgeEvidence.wilsonScoreInterval(wins: 11, total: 10).lower == 0)
}

@Test func scanCommitRejectsInvalidOpportunityWithoutConversionTrap() {
    for value in [Double.nan, .infinity, .greatestFiniteMagnitude, -1, 101] {
        let signal = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH",
            why: "invalid fixture", price: 1.1, confidence: 80, opportunity: value)
        let commit = ScanKernel.commit(from: signal, bars: [])
        #expect(commit.engineCall == "WAIT")
        #expect(commit.score == 0)
        #expect(commit.veto != nil)
        let confidenceSignal = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH",
            why: "invalid confidence fixture", price: 1.1, confidence: value, opportunity: 80)
        #expect(ScanKernel.commit(from: confidenceSignal, bars: []).engineCall == "WAIT")
    }
}
