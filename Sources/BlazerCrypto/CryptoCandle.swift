import Foundation

// MARK: - CryptoCandle
// Full 1-minute candle from Binance klines.
// Unlike BlazerCore's Candle, this carries volume and quote volume —
// the primary additional signal that FX does not have.

public struct CryptoCandle: Sendable, Equatable {
    public let time: Double         // Open time in Unix milliseconds
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double       // Base asset volume (e.g., BTC)
    public let quoteVolume: Double  // Quote volume in USDT — more stable for cross-asset comparison
    public let trades: Int          // Number of individual trades in this candle

    public init(
        time: Double, open: Double, high: Double, low: Double, close: Double,
        volume: Double, quoteVolume: Double, trades: Int
    ) {
        self.time        = time
        self.open        = open
        self.high        = high
        self.low         = low
        self.close       = close
        self.volume      = volume
        self.quoteVolume = quoteVolume
        self.trades      = trades
    }

    /// Validity boundary for untrusted candle data before scoring.
    public var isValidMarketInput: Bool {
        [time, open, high, low, close, volume, quoteVolume].allSatisfy { $0.isFinite }
            && time >= 0 && low >= 0 && high >= low
            && open >= low && open <= high && close >= low && close <= high
            && volume >= 0 && quoteVolume >= 0 && trades >= 0
    }

    // MARK: - Derived Properties

    /// Absolute body size (close - open, signed positive if bullish)
    public var bodySize: Double { abs(close - open) }

    /// True range — accounts for gaps
    public var trueRange: Double { high - low }

    /// Bullish if close ≥ open
    public var isBullish: Bool { close >= open }

    /// Upper wick from body top to candle high
    public var upperWick: Double { high - Swift.max(open, close) }

    /// Lower wick from body bottom to candle low
    public var lowerWick: Double { Swift.min(open, close) - low }

    /// Body-to-range ratio: 1.0 = pure marubozu, ~0 = doji
    public var bodyRatio: Double {
        guard trueRange > 0 else { return 0 }
        return bodySize / trueRange
    }

    /// Factory from a parsed Binance kline row (array of BinanceKlineField)
    public static func from(row: [BinanceKlineField]) -> CryptoCandle? {
        guard row.count >= 12,
              let time        = row[0].doubleValue,
              let open        = row[1].doubleValue,
              let high        = row[2].doubleValue,
              let low         = row[3].doubleValue,
              let close       = row[4].doubleValue,
              let vol         = row[5].doubleValue,
              let quoteVol    = row[7].doubleValue,
              let tradesVal   = row[8].doubleValue
        else { return nil }

        guard tradesVal.isFinite, tradesVal >= 0, tradesVal < Double(Int.max) else { return nil }
        let candle = CryptoCandle(
            time:        time,
            open:        open,
            high:        high,
            low:         low,
            close:       close,
            volume:      vol,
            quoteVolume: quoteVol,
            trades:      Int(tradesVal)
        )
        return candle.isValidMarketInput ? candle : nil
    }
}

// MARK: - CryptoCandleBatch
// Returned by BinanceClient.fetchCryptoBundle — includes bid/ask for spread gate.

public struct CryptoCandleBatch: Sendable {
    public let candles: [CryptoCandle]  // Completed candles (last in-progress dropped)
    public let bid:     Double
    public let ask:     Double
    public let spread:  Double
    public let mid:     Double
    public let asset:   String
    public let source:  String          // "binance" or "kraken"

    public init(
        candles: [CryptoCandle], bid: Double, ask: Double,
        asset: String, source: String
    ) {
        self.candles = candles
        self.bid     = bid
        self.ask     = ask
        self.spread  = ask - bid
        self.mid     = (bid + ask) / 2.0
        self.asset   = asset
        self.source  = source
    }
}
