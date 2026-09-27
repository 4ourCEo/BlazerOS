import Foundation

/// The completed-bar fixture both desks seal. Same bars must yield the same fingerprint, score, side, strike, and evidence.
public enum GoldenFixture {
    public static func market() -> StrategyEngine.MarketInput {
        var candles: [StrategyEngine.CandlePayload] = []
        var price = 1.08500
        let base = 1_700_000_000_000.0
        for i in 0..<80 {
            let open = price
            let close = price + (i % 5 == 4 ? -0.00020 : 0.00008)
            candles.append(
                StrategyEngine.CandlePayload(
                    time: base + Double(i) * 60_000,
                    open: open,
                    high: max(open, close) + 0.00004,
                    low: min(open, close) - 0.00004,
                    close: close
                )
            )
            price = close
        }
        let last = candles[candles.count - 1].close
        return StrategyEngine.MarketInput(
            asset: "EUR/USD",
            source: "oanda",
            candles1m: candles,
            candles5m: candles,
            lastPrice: last,
            bid: last - 0.00006,
            ask: last + 0.00006,
            spread: 0.00012,
            expirySeconds: 60
        )
    }

    public static func frozenBars(from input: StrategyEngine.MarketInput) -> [Candle] {
        input.candles1m.map {
            Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
    }
}
