import Testing
import BlazerCore
@testable import LightningDesk

@Test func candleLabelDoesNotCallCachedBarsLiveWhenQuoteFeedIsDisconnected() {
    #expect(CandleStatusLabel.make(feed: .disconnected, isStale: false, count: 120)
        == "OANDA candles · last received · 120 bars")
}

@Test func candleLabelMarksStaleSavedBarsEvenWhenFeedHasRecovered() {
    #expect(CandleStatusLabel.make(feed: .live, isStale: true, count: 80)
        == "Saved OANDA candles · stale · 80 bars")
}

@Test func candleLabelCallsBarsLiveOnlyWithLiveFeedAndFreshCandles() {
    #expect(CandleStatusLabel.make(feed: .live, isStale: false, count: 80)
        == "Live OANDA candles · 80 bars")
}

@Test func candleLabelExplainsAnEmptyChart() {
    #expect(CandleStatusLabel.make(feed: .error, isStale: true, count: 0)
        == "No OANDA candles loaded")
}
