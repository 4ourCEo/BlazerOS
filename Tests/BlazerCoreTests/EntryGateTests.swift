import Foundation
import Testing
import BlazerCore

private func gateFixture(now: Date) -> (ScanCommit, DeskFrame, EngineSignal, LiveQuote) {
    let signal = EngineSignal(
        asset: "EUR/USD", cabinetSide: "HIGH", call: "CALL", why: "test",
        price: 1.1, entryPrice: 1.1, confidence: 76,
        asOfMs: now.timeIntervalSince1970 * 1000,
        features: ScanFeatures(
            atr1m: 0.0005, atr5m: 0.0005, efficiency: 0, slopeATR: 0,
            spreadATR: 0, rangeATR: 0, bodyATR: 0, upperWickShare: 0,
            lowerWickShare: 0, twoSidedSweep: false, sweep: nil,
            structureBreak: nil, regime: "test"
        )
    )
    let commit = ScanKernel.commit(
        from: signal,
        bars: [Candle(time: 60_000, open: 1.1, high: 1.11, low: 1.09, close: 1.1)],
        bid: 1.0999, ask: 1.1001, spread: 0.0002, scannedAt: now
    )
    let frame = DeskFrame(
        pair: "EUR/USD", feed: .live, score: commit.score, why: "test",
        strike: commit.strike, verb: "TAP HIGH", remainingMs: 8_000,
        veto: nil, fingerprint: commit.fingerprint, isActionable: true
    )
    let quote = LiveQuote(
        asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
        asOfMs: now.timeIntervalSince1970 * 1000, source: "test"
    )
    return (commit, frame, signal, quote)
}

private func gateContext(
    commit: ScanCommit,
    frame: DeskFrame,
    signal: EngineSignal,
    quote: LiveQuote
) -> DeskEntryGate.Context {
    DeskEntryGate.Context(
        commit: commit, frame: frame, signal: signal, quote: quote,
        lastFreshPollAt: Date(), activeTrade: nil, awaitingOutcome: false,
        settlementInFlight: false, scanning: false, historical: false,
        armedAt: Date(), armID: "arm-1"
    )
}

@Test func entryGateAllowsAFreshArmedBeam() {
    let now = Date()
    let (commit, frame, signal, quote) = gateFixture(now: now)
    #expect(DeskEntryGate.veto(gateContext(commit: commit, frame: frame, signal: signal, quote: quote), now: now) == nil)
}

@Test func entryGateRefusesStaleHistoricalAndCrossPairEntries() {
    let now = Date()
    let (commit, frame, signal, quote) = gateFixture(now: now)
    let fresh = gateContext(commit: commit, frame: frame, signal: signal, quote: quote)

    var staleSignal = signal
    staleSignal.asOfMs = now.addingTimeInterval(-60).timeIntervalSince1970 * 1000
    var stale = fresh
    stale.signal = staleSignal
    #expect(DeskEntryGate.veto(stale, now: now) == .expiredBeam)

    var historical = fresh
    historical.historical = true
    #expect(DeskEntryGate.veto(historical, now: now) == .historical)

    let wrongPair = LiveQuote(
        asset: "USD/JPY", bid: 150, ask: 150.01, mid: 150.005,
        asOfMs: now.timeIntervalSince1970 * 1000, source: "test"
    )
    var crossPair = fresh
    crossPair.quote = wrongPair
    #expect(DeskEntryGate.veto(crossPair, now: now) == .staleFeed)

    let active = ActiveTrade(
        id: "arm-1", pair: "EUR/USD", side: "HIGH", strike: 1.1, score: 76,
        enteredAt: now, durationSec: 60, fingerprint: commit.fingerprint
    )
    var occupied = fresh
    occupied.activeTrade = active
    #expect(DeskEntryGate.veto(occupied, now: now) == .activePositionExists)
}

@Test func entryGateRefusesAVetoedCommit() {
    let now = Date()
    let (commit, frame, signal, quote) = gateFixture(now: now)
    var vetoed = commit
    vetoed.veto = "Spread too wide"
    var context = gateContext(commit: vetoed, frame: frame, signal: signal, quote: quote)
    context.commit = vetoed
    #expect(DeskEntryGate.veto(context, now: now) == .vetoed("Spread too wide"))
}
