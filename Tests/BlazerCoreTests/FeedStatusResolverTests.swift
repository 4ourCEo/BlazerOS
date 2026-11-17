import Foundation
import Testing
@testable import BlazerCore

@Test func feedStatusRemainsConnectingOnlyBeforeFirstTransportResponse() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(FeedStatusResolver.resolve(marketOpen: true, sessionReady: true,
        transport: nil, quote: nil, lastFreshPollAt: nil, now: now) == .connecting)
}

@Test func successfulTransportWithoutUsableQuoteIsAnError() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(FeedStatusResolver.resolve(marketOpen: true, sessionReady: true,
        transport: .ok, quote: nil, lastFreshPollAt: nil, now: now) == .error)
}

@Test func previouslyLiveFeedWithoutFreshQuoteBecomesStale() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(FeedStatusResolver.resolve(marketOpen: true, sessionReady: true,
        transport: .ok, quote: nil, lastFreshPollAt: now.addingTimeInterval(-10), now: now) == .stale)
}

@Test func freshQuoteAfterSuccessfulPollIsLive() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let quote = LiveQuote(asset: "EUR/USD", bid: 1.1, ask: 1.1001, mid: 1.10005,
                          asOfMs: now.timeIntervalSince1970 * 1000, source: "oanda")
    #expect(FeedStatusResolver.resolve(marketOpen: true, sessionReady: true,
        transport: .ok, quote: quote, lastFreshPollAt: now, now: now) == .live)
}
