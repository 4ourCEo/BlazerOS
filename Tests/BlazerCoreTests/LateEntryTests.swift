import Foundation
import Testing
@testable import BlazerCore
import LightningDesk

// Losing the eight-second action window must not lose the data point. Late logging stays
// available for ten minutes, requires a directional signal, and is refused while a position
// is open or an outcome is pending.

private func signal(_ side: String) -> EngineSignal {
    EngineSignal(
        asset: "EUR/USD",
        cabinetSide: side,
        call: side == "HIGH" ? "TAP HIGH" : (side == "LOW" ? "TAP LOW" : "WAIT"),
        why: "test",
        price: 1.1
    )
}

private func commit(_ signal: EngineSignal, scannedAt: Date) -> ScanCommit {
    ScanKernel.commit(from: signal, bars: [], scannedAt: scannedAt)
}

@Test func lateEntryIsAvailableAfterTheBeamCloses() {
    let now = Date()
    let high = signal("HIGH")
    let recent = commit(high, scannedAt: now.addingTimeInterval(-30))

    #expect(LightningDeskModel.canLogLateEntry(
        commit: recent, signal: high, activeTrade: nil,
        awaitingOutcome: false, settlementInFlight: false,
        scanning: false, historical: false, now: now
    ))
}

@Test func lateEntryExpiresAfterTenMinutes() {
    let now = Date()
    let high = signal("HIGH")
    let stale = commit(high, scannedAt: now.addingTimeInterval(-11 * 60))

    #expect(!LightningDeskModel.canLogLateEntry(
        commit: stale, signal: high, activeTrade: nil,
        awaitingOutcome: false, settlementInFlight: false,
        scanning: false, historical: false, now: now
    ))
}

@Test func lateEntryRequiresDirectionAndAClearDesk() {
    let now = Date()
    let wait = signal("WAIT")
    let recentWait = commit(wait, scannedAt: now.addingTimeInterval(-10))
    let high = signal("HIGH")
    let recent = commit(high, scannedAt: now.addingTimeInterval(-10))

    #expect(!LightningDeskModel.canLogLateEntry(
        commit: recentWait, signal: wait, activeTrade: nil,
        awaitingOutcome: false, settlementInFlight: false,
        scanning: false, historical: false, now: now
    ))
    #expect(!LightningDeskModel.canLogLateEntry(
        commit: recent, signal: high, activeTrade: nil,
        awaitingOutcome: true, settlementInFlight: false,
        scanning: false, historical: false, now: now
    ))
    #expect(!LightningDeskModel.canLogLateEntry(
        commit: recent, signal: high, activeTrade: nil,
        awaitingOutcome: false, settlementInFlight: false,
        scanning: false, historical: true, now: now
    ))
}
