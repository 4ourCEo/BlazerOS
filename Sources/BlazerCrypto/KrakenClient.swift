import BlazerCore
import Foundation
import os

private let krakenLog = Logger(subsystem: "com.blazer.ct", category: "KrakenClient")

// MARK: - KrakenClient
// Fallback price feed. Triggered automatically by BinanceClient when Binance
// returns a non-200 or a network error. No API key required.
//
// Kraken OHLC response shape:
//   { "error": [], "result": { "XBTUSDT": [[timeSec, open, high, low, close, vwap, vol, count], ...] } }
//
// Note: Kraken OHLC does not provide separate quoteVolume.
// We derive it as: vol (base) × vwap (price) ≈ quoteVolume.
// This is a valid approximation for BTC/USDT.
//
// Time values are Unix seconds — multiplied by 1000 to match CryptoCandle convention.

public enum KrakenClient {

    public static let pairMap: [String: String] = [
        "BTC/USDT": "XBTUSDT",
        "ETH/USDT": "ETHUSDT",
        "SOL/USDT": "SOLUSDT",
    ]

    // MARK: - fetchCryptoBundle (PRIMARY — returns CryptoCandleBatch)

    public static func fetchCryptoBundle(asset: String) async throws -> CryptoCandleBatch? {
        guard let pair = pairMap[asset] else {
            throw CTFeedError.unsupportedPair(asset)
        }

        let url = URL(string: "https://api.kraken.com/0/public/OHLC?pair=\(pair)&interval=1")!

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url)
        } catch {
            krakenLog.error("Kraken OHLC network error for \(asset): \(error)")
            throw CTFeedError.networkError(error.localizedDescription)
        }

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CTFeedError.httpError(code)
        }

        guard let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let rows   = result[pair] as? [[Any]]
        else {
            throw CTFeedError.decodingError("Kraken OHLC result shape")
        }

        // Kraken includes the current in-progress candle as the last row
        let completedRows = rows.dropLast(1)

        let candles: [CryptoCandle] = completedRows.compactMap { row in
            guard row.count >= 8,
                  let timeSec = (row[0] as? NSNumber).map(\.doubleValue),
                  let open    = Double("\(row[1])"),
                  let high    = Double("\(row[2])"),
                  let low     = Double("\(row[3])"),
                  let close   = Double("\(row[4])"),
                  let vwap    = Double("\(row[5])"),
                  let vol     = Double("\(row[6])"),
                  let count   = (row[7] as? NSNumber).map(\.doubleValue)
            else { return nil }

            // Derive quoteVolume: base vol × vwap price ≈ USDT volume
            let quoteVol = vol * vwap

            return CryptoCandle(
                time:        timeSec * 1000,  // Kraken → ms
                open:        open,
                high:        high,
                low:         low,
                close:       close,
                volume:      vol,
                quoteVolume: quoteVol,
                trades:      Int(count)
            )
        }

        guard candles.count >= 60 else {
            throw CTFeedError.insufficientBars(candles.count, required: 60)
        }

        // Fetch bid/ask from Kraken Ticker endpoint for spread gate
        let last = candles.last?.close ?? 0
        let syntheticSpread = last * 0.0002  // ~0.02% conservative fallback

        var bid = last - syntheticSpread / 2
        var ask = last + syntheticSpread / 2
        var usedSyntheticSpread = true

        if let tickerURL = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)"),
           let (tickerData, _) = try? await URLSession.shared.data(from: tickerURL),
           let tickerJson   = try? JSONSerialization.jsonObject(with: tickerData) as? [String: Any],
           let tickerResult = tickerJson["result"] as? [String: Any],
           let ticker       = tickerResult[pair] as? [String: Any],
           let bidArr       = ticker["b"] as? [Any], let bidStr = bidArr.first as? String,
           let askArr       = ticker["a"] as? [Any], let askStr = askArr.first as? String,
           let realBid      = Double(bidStr),
           let realAsk      = Double(askStr),
           realAsk > realBid
        {
            bid = realBid
            ask = realAsk
            usedSyntheticSpread = false
        }

        krakenLog.info("Kraken fallback successful for \(asset): \(candles.count) candles")

        return CryptoCandleBatch(
            candles: candles,
            bid:     bid,
            ask:     ask,
            asset:   asset,
            source:  usedSyntheticSpread ? "kraken-synthetic-spread" : "kraken"
        )
    }

    // MARK: - fetchQuote (settlement price)

    public static func fetchQuote(asset: String) async -> LiveQuote? {
        guard let pair = pairMap[asset] else { return nil }

        let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pair)")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result     = json["result"] as? [String: Any],
              let ticker     = result[pair] as? [String: Any],
              let bidArr     = ticker["b"] as? [Any], let bidStr = bidArr.first as? String,
              let askArr     = ticker["a"] as? [Any], let askStr = askArr.first as? String,
              let bid        = Double(bidStr),
              let ask        = Double(askStr),
              ask > bid
        else { return nil }

        return LiveQuote(
            asset:  asset,
            bid:    bid,
            ask:    ask,
            mid:    (bid + ask) / 2.0,
            asOfMs: Date().timeIntervalSince1970 * 1000,
            source: "kraken"
        )
    }

    // MARK: - fetchBundle (kept for benchmark compat)

    public static func fetchBundle(asset: String) async throws -> StrategyEngine.MarketInput? {
        guard let batch = try await fetchCryptoBundle(asset: asset) else { return nil }
        let payloads = batch.candles.map {
            StrategyEngine.CandlePayload(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
        return StrategyEngine.MarketInput(
            asset:         asset,
            source:        "kraken",
            candles1m:     payloads,
            candles5m:     payloads,
            lastPrice:     batch.mid,
            bid:           batch.bid,
            ask:           batch.ask,
            spread:        batch.spread,
            expirySeconds: 60
        )
    }
}
