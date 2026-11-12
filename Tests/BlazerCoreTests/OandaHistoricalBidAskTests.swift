import Foundation
import Testing
@testable import BlazerCore

@Test func historicalBidAskCandleRejectsCrossedOrMalformedPrices() {
    let candle = OandaBidAskCandle(instrument: "EUR_USD", granularity: "M1",
        sourceTime: Date(timeIntervalSince1970: 2_000_000_000), complete: true,
        bidOpen: 1.1, bidHigh: 1.101, bidLow: 1.099, bidClose: 1.1005,
        askOpen: 1.1009, askHigh: 1.1008, askLow: 1.0999, askClose: 1.1004)
    #expect(candle.validation.contains("ohlc_invalid"))
    #expect(candle.intrabarSequenceIsKnown == false)
}

@Test func historicalBidAskAcquisitionRejectsLiveEnvironmentWithoutNetwork() async {
    let from = Date(timeIntervalSince1970: 2_000_000_000)
    let batch = await OandaClient.fetchHistoricalBidAskCandles(
        asset: "EUR/USD", from: from, to: from.addingTimeInterval(60),
        session: OandaSession(token: "token", accountId: "account", environment: .live))
    #expect(batch.candles.isEmpty)
    #expect(batch.practiceOnlyRejected)
    #expect(batch.transport == .network)
}
