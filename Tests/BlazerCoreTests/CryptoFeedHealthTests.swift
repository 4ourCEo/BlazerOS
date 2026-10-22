import Foundation
import Testing
@testable import BlazerCore

// Tier 1 crypto feed health. Session-free: crypto is judged on connectivity + tick recency,
// never on FX market hours or weekend closure.

@Test func cryptoFeedIsLiveWhenTickIsFresh() {
    let now = Date()
    let state = CryptoFeedHealth.state(
        connected: true, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-1.0), now: now
    )
    #expect(state == .live)
}

@Test func cryptoFeedGoesStaleThenNoFeed() {
    let now = Date()
    // 5s old -> STALE (between the 2s live window and the 8s stale ceiling).
    #expect(CryptoFeedHealth.state(
        connected: true, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-5), now: now
    ) == .stale)
    // 12s old -> NO FEED.
    #expect(CryptoFeedHealth.state(
        connected: true, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-12), now: now
    ) == .noFeed)
}

@Test func cryptoFeedConnectingBeforeFirstTick() {
    let now = Date()
    #expect(CryptoFeedHealth.state(
        connected: true, everReceivedTick: false, lastTickAt: nil, now: now
    ) == .connecting)
    #expect(CryptoFeedHealth.state(
        connected: false, everReceivedTick: false, lastTickAt: nil, now: now
    ) == .connecting)
}

@Test func cryptoFeedNoFeedAfterDisconnectWithHistory() {
    let now = Date()
    #expect(CryptoFeedHealth.state(
        connected: false, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-3), now: now
    ) == .noFeed)
}

@Test func cryptoFeedDoesNotDependOnFxSessions() {
    // There is no marketOpen/session parameter. A weekend timestamp still reads LIVE when
    // the feed is ticking — crypto is 24/7.
    let weekend = Date(timeIntervalSince1970: 1_771_000_000)
    let state = CryptoFeedHealth.state(
        connected: true, everReceivedTick: true, lastTickAt: weekend, now: weekend
    )
    #expect(state == .live)
}

@Test func cryptoFeedRequestsReconnectWhenNoTick() {
    let now = Date()
    #expect(CryptoFeedHealth.shouldReconnect(
        connected: true, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-9), now: now
    ) == true)
    #expect(CryptoFeedHealth.shouldReconnect(
        connected: true, everReceivedTick: true,
        lastTickAt: now.addingTimeInterval(-1), now: now
    ) == false)
    #expect(CryptoFeedHealth.shouldReconnect(
        connected: false, everReceivedTick: true, lastTickAt: now, now: now
    ) == true)
}

@Test func reconnectBackoffIsExponentialAndCapped() {
    let p = FeedHealthPolicy.cryptoDefault
    #expect(CryptoFeedHealth.reconnectDelayMs(attempt: 0, policy: p) == p.reconnectBaseMs)
    #expect(CryptoFeedHealth.reconnectDelayMs(attempt: 1, policy: p) == p.reconnectBaseMs * 2)
    #expect(CryptoFeedHealth.reconnectDelayMs(attempt: 2, policy: p) == p.reconnectBaseMs * 4)
    #expect(CryptoFeedHealth.reconnectDelayMs(attempt: 50, policy: p) == p.reconnectMaxMs)
}

@Test func heartbeatOverdueDetection() {
    let now = Date()
    #expect(CryptoFeedHealth.isHeartbeatOverdue(lastTickAt: nil, now: now) == true)
    #expect(CryptoFeedHealth.isHeartbeatOverdue(lastTickAt: now.addingTimeInterval(-0.5), now: now) == false)
    #expect(CryptoFeedHealth.isHeartbeatOverdue(lastTickAt: now.addingTimeInterval(-3), now: now) == true)
}

@Test func cryptoFeedStateMapsToDeskFeedStatus() {
    #expect(CryptoFeedHealth.feedStatus(for: .live) == .live)
    #expect(CryptoFeedHealth.feedStatus(for: .stale) == .stale)
    #expect(CryptoFeedHealth.feedStatus(for: .noFeed) == .disconnected)
    #expect(CryptoFeedHealth.feedStatus(for: .connecting) == .connecting)
}
