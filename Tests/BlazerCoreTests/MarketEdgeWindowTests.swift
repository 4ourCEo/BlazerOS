import Foundation
import Testing
@testable import BlazerCore

// The live countdown must be derived from the same window boundaries as `MarketEdgeWindow.current`.
// Regression: the Intel screen counted down to 09:00 PT for a window that closes at 10:00 PT, and
// advertised a "next prime" on weekends while FX was shut.

private func instant(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Test func morningPrimeCountdownEndsAtTenAM() {
    let at = instant("2026-10-22T16:00:00Z")   // 09:00 PT, Thursday
    let countdown = MarketEdgeWindow.countdown(at: at)

    #expect(countdown.window.isSupremePrime)
    guard case .primeEndsIn(let remaining) = countdown.phase else {
        Issue.record("Expected a prime countdown, got \(countdown.phase)")
        return
    }
    #expect(abs(remaining - 3_600) < 1, "Prime must run until 10:00 PT, not 09:00")
}

@Test func morningPrimeLastMinuteStillCounts() {
    let at = instant("2026-10-22T16:59:00Z")   // 09:59 PT
    guard case .primeEndsIn(let remaining) = MarketEdgeWindow.countdown(at: at).phase else {
        Issue.record("Expected a prime countdown")
        return
    }
    #expect(abs(remaining - 60) < 1)

    let boundary = instant("2026-10-22T17:00:00Z")   // 10:00 PT
    #expect(MarketEdgeWindow.current(at: boundary).isSupremePrime == false)
}

@Test func lateNightCountdownCrossesMidnight() {
    let at = instant("2026-10-23T06:30:00Z")   // 23:30 PT, Thursday
    let countdown = MarketEdgeWindow.countdown(at: at)

    #expect(countdown.window.isTactical)
    guard case .primeEndsIn(let remaining) = countdown.phase else {
        Issue.record("Expected a burst-window countdown, got \(countdown.phase)")
        return
    }
    #expect(abs(remaining - 3_600) < 1, "Burst window closes at 00:30 PT")
}

@Test func offPeakCountsToNextPrime() {
    let at = instant("2026-10-22T19:00:00Z")   // 12:00 PT, outside 5–10 and before 23:00
    guard case .nextPrimeIn(let remaining) = MarketEdgeWindow.countdown(at: at).phase else {
        Issue.record("Expected the next prime window")
        return
    }
    #expect(abs(remaining - 11 * 3_600) < 1, "Next prime is 23:00 PT")
}

@Test func weekendReportsMarketClosedInsteadOfNextPrime() {
    // Saturday 2026-10-24 10:00 PT = 17:00Z. FX reopens Sunday 2026-10-25 17:00 EDT = 21:00Z.
    let at = instant("2026-10-24T17:00:00Z")
    let countdown = MarketEdgeWindow.countdown(at: at)

    #expect(countdown.window.isPrime == false)
    guard case .marketClosed(let opensIn) = countdown.phase else {
        Issue.record("Expected market closed, got \(countdown.phase)")
        return
    }
    #expect(abs(opensIn - 28 * 3_600) < 1, "Weekend must count to the Sunday open")
}

@Test func closedOnlyUntilSundayOpen() {
    let closed = instant("2026-10-25T20:59:00Z")   // Sunday 16:59 New York
    if case .marketClosed = MarketEdgeWindow.countdown(at: closed).phase {} else {
        Issue.record("Market should be closed before the Sunday open")
    }

    let open = instant("2026-10-25T21:01:00Z")     // Sunday 17:01 New York
    if case .marketClosed = MarketEdgeWindow.countdown(at: open).phase {
        Issue.record("Market should be open after the Sunday open")
    }
}

@Test func countdownUsesTheSameWindowAsCurrent() {
    let samples = [
        "2026-10-22T12:00:00Z",
        "2026-10-22T14:00:00Z",
        "2026-10-22T16:00:00Z",
        "2026-10-23T06:30:00Z",
        "2026-10-24T17:00:00Z",
        "2026-10-25T21:01:00Z",
    ]

    for iso in samples {
        let at = instant(iso)
        #expect(MarketEdgeWindow.countdown(at: at).window == MarketEdgeWindow.current(at: at))
    }
}
