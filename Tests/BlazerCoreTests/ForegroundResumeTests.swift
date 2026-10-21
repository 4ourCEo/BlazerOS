import Foundation
import Testing
@testable import BlazerCore

// Foreground-resume policy. iOS drops sockets/timers in the background; the app must decide
// what to rebuild when the user returns from the Crypto.com app.

@Test func briefBackgroundingWithFreshFeedNeedsNoReconnect() {
    let decision = ForegroundResume.decide(
        suspendedForMs: 3_000,
        lastPollAgeMs: 500,
        clockSampleAgeMs: 1_000
    )
    #expect(decision.needsFeedReconnect == false)
    #expect(decision.needsClockRemeasure == false)
    #expect(decision.treatFeedAsDisconnected == false)
}

@Test func longBackgroundingForcesFullResume() {
    let decision = ForegroundResume.decide(
        suspendedForMs: 45_000,
        lastPollAgeMs: 500,
        clockSampleAgeMs: 1_000
    )
    #expect(decision.needsFeedReconnect == true)
    #expect(decision.needsClockRemeasure == true)
    #expect(decision.treatFeedAsDisconnected == true)
}

@Test func missingFeedOrClockForcesRebuild() {
    let neverPolled = ForegroundResume.decide(
        suspendedForMs: 1_000, lastPollAgeMs: nil, clockSampleAgeMs: 1_000
    )
    #expect(neverPolled.needsFeedReconnect == true)
    #expect(neverPolled.treatFeedAsDisconnected == true)

    let neverMeasuredClock = ForegroundResume.decide(
        suspendedForMs: 1_000, lastPollAgeMs: 500, clockSampleAgeMs: nil
    )
    #expect(neverMeasuredClock.needsClockRemeasure == true)
    #expect(neverMeasuredClock.needsFeedReconnect == false)
}

@Test func staleClockSampleForcesRemeasure() {
    let staleClock = ForegroundResume.decide(
        suspendedForMs: 1_000,
        lastPollAgeMs: 500,
        clockSampleAgeMs: ExchangeClock.defaultMaxSampleAgeMs + 1
    )
    #expect(staleClock.needsClockRemeasure == true)
}
