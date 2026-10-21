import Foundation
import Testing
import BlazerCore

@Test func stalePickerFallbackStaysWAIT() {
    let staleDirectional = EngineSignal(
        asset: "EUR/USD", cabinetSide: "HIGH", call: "CALL", why: "stale",
        price: 1.1, entryPrice: 1.1, confidence: 80,
        asOfMs: Date().addingTimeInterval(-60).timeIntervalSince1970 * 1000
    )
    let fallback = DeskPickPolicy.unavailable(basedOn: staleDirectional)
    #expect(fallback.cabinetSide == "WAIT")
    #expect(fallback.call == "WAIT")
    #expect(fallback.asset == "EUR/USD")
    #expect(fallback.asOfMs == staleDirectional.asOfMs)
}

@Test func onlyFreshDirectionalSignalsAreActionable() {
    let now = Date()
    let fresh = EngineSignal(
        asset: "EUR/USD", cabinetSide: "LOW", call: "PUT", why: "",
        price: 1.1, confidence: 70,
        asOfMs: now.addingTimeInterval(-2).timeIntervalSince1970 * 1000
    )
    let stale = EngineSignal(
        asset: "EUR/USD", cabinetSide: "LOW", call: "PUT", why: "",
        price: 1.1, confidence: 70,
        asOfMs: now.addingTimeInterval(-30).timeIntervalSince1970 * 1000
    )
    #expect(DeskPickPolicy.isActionable(fresh, now: now))
    #expect(!DeskPickPolicy.isActionable(stale, now: now))
}

@Test func savedTapBecomesHistoricalAfterTheBeam() {
    let scan = Date(timeIntervalSince1970: 1_700_000_000)
    let inside = scan.addingTimeInterval(Timing.liveMs / 1000 - 1)
    let outside = scan.addingTimeInterval(Timing.liveMs / 1000 + 1)

    #expect(SavedScanPresentation.word(outcome: nil, verb: "TAP HIGH", scannedAt: scan, now: inside) == "TAP HIGH")
    #expect(SavedScanPresentation.word(outcome: nil, verb: "TAP HIGH", scannedAt: scan, now: outside) == "HISTORICAL")
    #expect(SavedScanPresentation.word(outcome: "HIT", verb: "TAP HIGH", scannedAt: scan, now: outside) == "HIT")
    #expect(!SavedScanPresentation.isLive(outcome: "HIT", scannedAt: scan, now: inside))
}
