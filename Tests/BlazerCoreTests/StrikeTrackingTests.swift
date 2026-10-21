import Foundation
import Testing
@testable import BlazerCore

// Tracking/accounting invariants: exact money, exits only reduce, unknown money != $0,
// idempotent events, durable across restart, provenance preserved.

private func newPosition(id: String = "P1") -> StrikePosition {
    StrikePosition(
        id: id, symbol: "BTC", side: .yes, strike: 68_400,
        predicate: .aboveStrict, spec: .currentCrypto,
        expiry: Date(timeIntervalSince1970: 1_772_000_000)
    )
}

private func openEvent(_ quantity: Int, price: Decimal?, fee: Decimal?, id: String = "E-open") -> StrikeEvent {
    StrikeEvent(id: id, positionID: "P1",
                kind: .open(quantity: quantity, pricePerContract: price, fee: fee, at: Date()))
}

@Test func openAccumulatesExactEntryCost() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20")), to: &p)
    #expect(p.enteredQuantity == 10)
    #expect(p.openQuantity == 10)
    #expect(p.entryCost == Decimal.strikeMoney("6.00"))   // 10*0.58 + 0.20
    #expect(p.conservesQuantity)
}

@Test func partialExitReducesQuantityAndConserves() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20")), to: &p)
    let exit = StrikeEvent(id: "E-exit", positionID: "P1",
                           kind: .exit(quantity: 4, pricePerContract: Decimal.strikeMoney("0.80"), at: Date()))
    try StrikeLedger.apply(exit, to: &p)
    #expect(p.openQuantity == 6)
    #expect(p.exitedQuantity == 4)
    #expect(p.exitProceeds == Decimal.strikeMoney("3.20"))
    #expect(p.conservesQuantity)
    #expect(p.netCashFlow() == .known(Decimal.strikeMoney("-2.80")))  // 3.20 - 6.00
}

@Test func exitCannotExceedOpenQuantity() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: .zero), to: &p)
    let over = StrikeEvent(id: "E-over", positionID: "P1",
                           kind: .exit(quantity: 11, pricePerContract: Decimal.strikeMoney("0.80"), at: Date()))
    #expect(throws: StrikeLedgerError.overExit(requested: 11, available: 10)) {
        try StrikeLedger.apply(over, to: &p)
    }
    #expect(p.openQuantity == 10)   // unchanged; never flips
}

@Test func settlementPaysContractValueOnWinAndZeroOnLoss() throws {
    var win = newPosition()
    try StrikeLedger.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20")), to: &win)
    try StrikeLedger.apply(
        StrikeEvent(id: "E-settle", positionID: "P1", kind: .settle(result: .inTheMoney, provenance: .userReported, at: Date())),
        to: &win
    )
    #expect(win.settlementPayout == Decimal.strikeMoney("10.00"))
    #expect(win.netCashFlow() == .known(Decimal.strikeMoney("4.00")))  // 10.00 - 6.00
    #expect(win.openQuantity == 0)
    #expect(win.settledQuantity == 10)
    #expect(win.conservesQuantity)

    var loss = newPosition()
    try StrikeLedger.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20")), to: &loss)
    try StrikeLedger.apply(
        StrikeEvent(id: "E-settle", positionID: "P1", kind: .settle(result: .outOfTheMoney, provenance: .userReported, at: Date())),
        to: &loss
    )
    #expect(loss.settlementPayout == Decimal.strikeMoney("0.00"))
    #expect(loss.netCashFlow() == .known(Decimal.strikeMoney("-6.00")))
}

@Test func cannotSettleTwice() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(1, price: Decimal.strikeMoney("0.50"), fee: .zero), to: &p)
    try StrikeLedger.apply(
        StrikeEvent(id: "S1", positionID: "P1", kind: .settle(result: .inTheMoney, provenance: .userReported, at: Date())),
        to: &p
    )
    #expect(throws: StrikeLedgerError.alreadySettled) {
        try StrikeLedger.apply(
            StrikeEvent(id: "S2", positionID: "P1", kind: .settle(result: .outOfTheMoney, provenance: .userReported, at: Date())),
            to: &p
        )
    }
}

@Test func duplicateEventIsIdempotent() throws {
    var p = newPosition()
    let e = openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20"))
    try StrikeLedger.apply(e, to: &p)
    try StrikeLedger.apply(e, to: &p)   // same id -> no-op
    #expect(p.enteredQuantity == 10)
    #expect(p.entryCost == Decimal.strikeMoney("6.00"))
}

@Test func missingMoneyMakesPnLUnknownNotZero() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(10, price: nil, fee: nil), to: &p)
    #expect(p.hasUnknownMoney)
    if case .unknown = p.netCashFlow() {} else {
        #expect(Bool(false), "expected unknown P&L")
    }
}

@Test func provenanceIsPreserved() throws {
    var p = newPosition()
    try StrikeLedger.apply(openEvent(1, price: Decimal.strikeMoney("0.50"), fee: .zero), to: &p)
    try StrikeLedger.apply(
        StrikeEvent(id: "S", positionID: "P1", kind: .settle(result: .inTheMoney, provenance: .venueVerified, at: Date())),
        to: &p
    )
    #expect(p.settlement?.provenance == .venueVerified)
}

@Test func storeSurvivesRestart() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("strike-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    let store = StrikeStore(url: url)
    try await store.create(newPosition())
    try await store.apply(openEvent(10, price: Decimal.strikeMoney("0.58"), fee: Decimal.strikeMoney("0.20")))
    try await store.apply(
        StrikeEvent(id: "S", positionID: "P1", kind: .settle(result: .inTheMoney, provenance: .userReported, at: Date()))
    )

    // Simulate an app restart: a fresh store on the same file.
    let reopened = StrikeStore(url: url)
    let restored = await reopened.position(id: "P1")
    #expect(restored?.enteredQuantity == 10)
    #expect(restored?.settlement?.result == .inTheMoney)
    #expect(restored?.netCashFlow() == .known(Decimal.strikeMoney("4.00")))
}

@Test func storeRejectsUnknownPosition() async throws {
    let store = StrikeStore()
    await #expect(throws: StrikeLedgerError.unknownPosition("P1")) {
        try await store.apply(openEvent(1, price: Decimal.strikeMoney("0.50"), fee: .zero, id: "x"))
    }
}
