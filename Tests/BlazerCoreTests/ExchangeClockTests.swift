import Foundation
import Testing
@testable import BlazerCore

// Tier 1 clock sync. Strike contracts settle to the second, so local-vs-exchange skew must be
// measurable and bounded.

@Test func symmetricSampleHasNoSkew() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let t3 = t0.addingTimeInterval(0.1)              // 100 ms round trip
    let serverTime = t0.addingTimeInterval(0.05)     // exactly the midpoint
    let offset = ExchangeClock.offset(sentAt: t0, serverTime: serverTime, receivedAt: t3, source: "ntp")
    #expect(abs(offset.skewMs) < 0.01)
    #expect(abs(offset.roundTripMs - 100) < 0.01)
}

@Test func detectsServerAheadAndBehind() {
    let t0 = Date(timeIntervalSince1970: 2_000)
    let t3 = t0.addingTimeInterval(0.1)

    let ahead = ExchangeClock.offset(
        sentAt: t0, serverTime: t0.addingTimeInterval(0.07), receivedAt: t3, source: "exchange"
    )
    #expect(abs(ahead.skewMs - 20) < 0.01) // server 20 ms ahead of midpoint

    let behind = ExchangeClock.offset(
        sentAt: t0, serverTime: t0.addingTimeInterval(0.03), receivedAt: t3, source: "exchange"
    )
    #expect(abs(behind.skewMs + 20) < 0.01) // server 20 ms behind
}

@Test func correctedNowAppliesSkew() {
    let t0 = Date(timeIntervalSince1970: 3_000)
    let t3 = t0.addingTimeInterval(0.1)
    let offset = ExchangeClock.offset(
        sentAt: t0, serverTime: t0.addingTimeInterval(0.55), receivedAt: t3, source: "exchange"
    )
    // server is 0.5 s ahead of midpoint
    let corrected = ExchangeClock.correctedNow(localNow: t0, offset: offset)
    #expect(abs(corrected.timeIntervalSince(t0) - 0.5) < 0.01)
}

@Test func driftClassifiesSkew() {
    let now = Date()
    #expect(ExchangeClock.drift(of: ClockOffset(skewMs: 100, roundTripMs: 20, measuredAt: now, source: "ntp")) == .ok)
    #expect(ExchangeClock.drift(of: ClockOffset(skewMs: -800, roundTripMs: 20, measuredAt: now, source: "ntp")) == .warn)
    #expect(ExchangeClock.drift(of: ClockOffset(skewMs: 3_000, roundTripMs: 20, measuredAt: now, source: "ntp")) == .critical)
}

@Test func staleSampleIsDetected() {
    let now = Date()
    let fresh = ClockOffset(skewMs: 10, roundTripMs: 20, measuredAt: now.addingTimeInterval(-60), source: "ntp")
    let old = ClockOffset(skewMs: 10, roundTripMs: 20, measuredAt: now.addingTimeInterval(-1_000), source: "ntp")
    #expect(ExchangeClock.isSampleStale(offset: fresh, now: now) == false)
    #expect(ExchangeClock.isSampleStale(offset: old, now: now) == true)
}
