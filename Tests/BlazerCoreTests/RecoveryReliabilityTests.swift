import Foundation
import Testing
import BlazerCore

private func temporaryRoot() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-recovery-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func pendingRecord(arm: String) -> PendingSettlement {
    let row = LedgerRow(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        pair: "EUR/USD", hash: "ABCD1234", score: 76, side: "HIGH",
        veto: false, drift: 0, outcome: "HIT", outcomeEventID: arm
    )
    let snapshot = SnapshotRecord(
        hash: "ABCD1234", pair: "EUR/USD", bars: [], strike: 1.1, score: 76, side: "HIGH"
    )
    return PendingSettlement(armID: arm, row: row, snapshot: snapshot)
}

@Test func corruptPendingLineDoesNotBlockValidSettlements() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let valid = try encoder.encode(pendingRecord(arm: "arm-valid"))
    var data = Data("not-a-record\n".utf8)
    data.append(valid)
    data.append(0x0A)
    try data.write(to: FileLocations.pendingSettlements(in: root))

    let restored = await PersistenceCoordinator(root: root).restore()
    #expect(restored.pendingSettlements.map(\.armID) == ["arm-valid"])
    #expect(restored.issues.contains { $0.domain == .pending })

    // The corrupt line is preserved next to the queue.
    let quarantine = root.appendingPathComponent("pending_settlements.corrupt.jsonl")
    #expect(FileManager.default.fileExists(atPath: quarantine.path))
    let quarantined = try String(contentsOf: quarantine, encoding: .utf8)
    #expect(quarantined.contains("not-a-record"))
}

@Test func newPendingCanBeQueuedAfterCorruption() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("garbage\n".utf8).write(to: FileLocations.pendingSettlements(in: root))

    let coordinator = PersistenceCoordinator(root: root)
    let restored = await coordinator.restore()
    #expect(restored.issues.contains { $0.domain == .pending })
    #expect(restored.pendingSettlements.isEmpty)
}

@Test func activePositionRoundTripsItsCompleteScanInput() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date()
    let trade = ActiveTrade(
        id: "arm-1", pair: "EUR/USD", side: "HIGH", strike: 1.1, score: 76,
        enteredAt: now, durationSec: 60, currentPrice: 1.1, fingerprint: "ABCD1234"
    )
    let input = ScanInputSnapshot(
        pair: "EUR/USD",
        m1: [Candle(time: 60_000, open: 1.09, high: 1.11, low: 1.08, close: 1.1)],
        m5: [Candle(time: 0, open: 1.08, high: 1.12, low: 1.07, close: 1.1)],
        bid: 1.0999, ask: 1.1001, spread: 0.0002,
        expirySeconds: 60, engineSHA: "engine", policy: "baseline"
    )
    let record = ActivePositionRecord(
        armID: "arm-1", trade: trade,
        fullFingerprint: input.identity, scanInput: input
    )
    let first = PersistenceCoordinator(root: root)
    try await first.saveOpenPosition(record)

    let restored = await PersistenceCoordinator(root: root).restore()
    #expect(restored.activePosition?.scanInput?.m5.count == 1)
    #expect(restored.activePosition?.fullFingerprint == input.identity)
}

@Test func strikeStoreCreatesPositionAndOpeningEventInOneWrite() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("strike-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    var position = StrikePosition(
        id: "P1", symbol: "BTC/USDT", side: .yes, strike: 100_000,
        predicate: .aboveStrict, spec: .currentCrypto,
        expiry: Date(timeIntervalSince1970: 1_700_000_060)
    )
    let event = StrikeEvent(
        id: "E1", positionID: "P1",
        kind: .open(quantity: 10, pricePerContract: Decimal(string: "0.58")!, fee: Decimal(string: "0.20")!, at: Date())
    )
    let store = StrikeStore(url: url)
    position = try await store.create(position, opening: event)

    let reopened = StrikeStore(url: url)
    let restored = await reopened.position(id: "P1")
    #expect(restored?.enteredQuantity == 10)
    #expect(restored?.openQuantity == 10)
    #expect(restored?.conservesQuantity == true)
    #expect(position.netCashFlow() == restored?.netCashFlow())
}
