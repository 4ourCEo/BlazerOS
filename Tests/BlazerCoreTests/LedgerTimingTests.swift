import Foundation
import Testing
@testable import BlazerCore

@Test func ledgerPersistsHandoffTiming() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-ledger-timing-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LedgerStore(root: root)
    let row = LedgerRow(
        timestamp: Date(),
        pair: "GBP/USD",
        hash: "0505B0F6",
        score: 90,
        side: "TAP HIGH",
        veto: false,
        drift: 1,
        outcome: "MISS",
        outcomeEventID: "0505B0F6-test",
        labelSource: "venue-confirmed",
        horizonSeconds: 60,
        enteredAt: Date(),
        evaluationAgeMs: 6_700,
        recordingDelayMs: 1_900,
        remainingBeamMs: 6_100
    )

    #expect(try await store.record(row))
    let loaded = try await store.rows()
    #expect(loaded.count == 1)
    #expect(loaded[0].evaluationAgeMs == 6_700)
    #expect(loaded[0].recordingDelayMs == 1_900)
    #expect(loaded[0].remainingBeamMs == 6_100)
    #expect(loaded[0].schemaVersion == LedgerStore.schemaVersion)
    #expect(LedgerStore.schemaVersion == 4)
    #expect(LedgerStore.columnCount == 24)
}
