import Foundation
import Testing
import BlazerCore

@Test func legacyNineColumnLedgerDoesNotReadTheirPriceAsPayout() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-ledger-legacy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let header = "timestamp,pair,hash,score,side,veto,drift,outcome,theirPrice"
    let row = "2026-01-01T00:00:00Z,EUR/USD,ABCD1234,76,HIGH,false,0.0000,HIT,1.2345"
    try Data((header + "\n" + row + "\n").utf8).write(to: FileLocations.ledgerCSV(in: root))

    let result = try await LedgerStore(root: root).read()
    #expect(result.damagedLines == 0)
    #expect(result.rows.count == 1)
    #expect(result.rows[0].payout == nil)
    #expect(result.rows[0].entryQuote == 1.2345)
    #expect(result.rows[0].schemaVersion == nil)
    #expect(result.rows[0].outcomeEventID.contains("2026-01-01T00:00:00Z"))
}

@Test func ledgerHeaderUpgradeKeepsAPreV3Backup() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-ledger-backup-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let legacy = LedgerStore.legacyHeader + "\n"
        + "2026-01-01T00:00:00Z,EUR/USD,ABCD1234,76,HIGH,false,0.0,HIT\n"
    try Data(legacy.utf8).write(to: FileLocations.ledgerCSV(in: root))

    let store = LedgerStore(root: root)
    let row = LedgerRow(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        pair: "EUR/USD",
        hash: "NEWHASH1",
        score: 76,
        side: "HIGH",
        veto: false,
        drift: 0,
        outcome: "MISS",
        outcomeEventID: "arm-new"
    )
    #expect(try await store.record(row))

    let backup = root.appendingPathComponent("scan_ledger.csv.pre-v3.bak")
    #expect(FileManager.default.fileExists(atPath: backup.path))
    let saved = try String(contentsOf: backup, encoding: .utf8)
    #expect(saved.hasPrefix(LedgerStore.legacyHeader))
}

@Test func damagedLinesAreCountedWithoutDeletingTheFile() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-ledger-damaged-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let text = LedgerStore.csvHeader + "\n"
        + "not,a,valid,row\n"
        + "2026-01-01T00:00:00Z,EUR/USD,ABCD1234,76,HIGH,false,0.0,HIT\n"
    let url = FileLocations.ledgerCSV(in: root)
    try Data(text.utf8).write(to: url)

    let result = try await LedgerStore(root: root).read()
    #expect(result.rows.count == 1)
    #expect(result.damagedLines == 1)
    #expect(try String(contentsOf: url, encoding: .utf8) == text)
}

@Test func snapshotArchiveKeepsDifferentFullInputsWithTheSameDisplayHash() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-snapshot-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let bars = [Candle(time: 60_000, open: 1.1, high: 1.2, low: 1.0, close: 1.15)]
    let first = SnapshotRecord(
        hash: "CE239CDB", fullFingerprint: String(repeating: "A", count: 40),
        pair: "EUR/USD", bars: bars, m5Bars: [], strike: 1.15, score: 76, side: "HIGH"
    )
    let second = SnapshotRecord(
        hash: "CE239CDB", fullFingerprint: String(repeating: "B", count: 40),
        pair: "EUR/USD", bars: bars, m5Bars: [], strike: 1.15, score: 76, side: "HIGH"
    )
    let store = SnapshotStore(root: root)
    #expect(try await store.archive(first))
    #expect(try await store.archive(second))
    #expect(try await store.load().count == 2)
    #expect(try await store.archive(second) == false)
}
