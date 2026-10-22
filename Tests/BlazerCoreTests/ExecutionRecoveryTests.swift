import CloudKit
import Foundation
import Testing
@testable import BlazerCore

// Stage 1 + Stage 2 release gates:
// cached beams never re-arm, identity is not a display hash, interrupted settlements
// finish without duplicating, read failures surface, and reference outcomes never
// count as measured performance.

private let t0 = Date(timeIntervalSince1970: 1_772_000_000)

private func bars(seed: Double = 0) -> [Candle] {
    (0..<3).map { index in
        let step = Double(index) * 0.0001
        let offset = seed + step
        let time = t0.timeIntervalSince1970 + Double(index) * 60
        return Candle(
            time: time,
            open: 1.1000 + offset,
            high: 1.1010 + offset,
            low: 1.0990 + offset,
            close: 1.1005 + offset
        )
    }
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

private func commit(pair: String = "EUR/USD", seed: Double = 0) -> ScanCommit {
    let snapshot = bars(seed: seed)
    return ScanCommit(
        asset: pair,
        engineCall: "HIGH",
        score: 82,
        evidence: "test",
        strike: 1.1005,
        fingerprint: ScanFingerprint.hex(candles: snapshot),
        fullFingerprint: ScanFingerprint.full(pair: pair, candles: snapshot),
        candleCount: snapshot.count,
        candles: snapshot,
        scannedAt: t0
    )
}

private func entry(for commit: ScanCommit, id: String = "arm-1") -> JournalEntry {
    JournalEntry(
        id: id,
        fingerprint: commit.fingerprint,
        pair: commit.asset,
        score: commit.score,
        side: commit.engineCall,
        verb: "TAP HIGH",
        why: commit.evidence,
        strike: commit.strike,
        veto: nil,
        scannedAt: commit.scannedAt
    )
}

private func snapshot(for commit: ScanCommit) -> SnapshotRecord {
    SnapshotRecord(
        hash: commit.fingerprint,
        fullFingerprint: commit.fullFingerprint,
        pair: commit.asset,
        bars: commit.candles,
        strike: commit.strike,
        score: commit.score,
        side: commit.engineCall
    )
}

private func row(for commit: ScanCommit, outcome: String = "HIT", label: String? = "venue-confirmed", arm: String = "arm-1") -> LedgerRow {
    LedgerRow(
        timestamp: t0,
        pair: commit.asset,
        hash: commit.fingerprint,
        score: commit.score,
        side: commit.engineCall,
        veto: false,
        drift: 0,
        outcome: outcome,
        outcomeEventID: arm,
        payout: 0.88,
        stake: 10,
        marketWindow: "London",
        engineSHA: EngineIdentity.pinnedSHA1,
        fullFingerprint: commit.fullFingerprint,
        entryQuote: 1.1001,
        expiryPrice: 1.1009,
        labelSource: label,
        horizonSeconds: 60,
        enteredAt: t0,
        expiryObservedMs: t0.timeIntervalSince1970 * 1000
    )
}

// MARK: - Cached beam

@Test func cachedScanCanNeverProduceAnActionableVerb() {
    #expect(BeamContract.verb(cabinetSide: "HIGH", elapsedMs: 0, vetoed: false) == "TAP HIGH")

    let historical = BeamContract.verb(cabinetSide: "HIGH", elapsedMs: 0, vetoed: false, historical: true)
    #expect(historical == BeamContract.historicalVerb)
    #expect(!historical.hasPrefix("TAP"))

    let frame = DeskFrame.make(
        commit: commit(),
        feed: .live,
        cabinetSide: "HIGH",
        elapsedMs: 0,
        historical: true
    )
    #expect(frame.verb == BeamContract.historicalVerb)
    #expect(frame.remainingMs == 0)
}

// MARK: - Identity and schema

@Test func storageIdentityIncludesPairAndRejectsDisplayHashCollisions() {
    let sameBars = bars()
    let eur = ScanFingerprint.full(pair: "EUR/USD", candles: sameBars)
    let gbp = ScanFingerprint.full(pair: "GBP/USD", candles: sameBars)

    #expect(eur != gbp)
    #expect(ScanFingerprint.isFullIdentity(eur))
    #expect(ScanFingerprint.isFullIdentity(gbp))
    #expect(ScanFingerprint.hex(candles: sameBars) == ScanFingerprint.hex(candles: sameBars))
    #expect(!ScanFingerprint.isFullIdentity(ScanFingerprint.hex(candles: sameBars)))
    #expect(ScanFingerprint.full(pair: "EUR/USD", candles: bars(seed: 0.0002)) != eur)
}

@Test func ledgerWritesDeclaredHeaderAndFixedWidthV3Rows() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let commit = commit()
    let store = LedgerStore(root: root)
    #expect(try await store.record(row(for: commit)))

    let text = try String(contentsOf: FileLocations.ledgerCSV(in: root), encoding: .utf8)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    #expect(lines.first.map(String.init) == LedgerStore.csvHeader)
    #expect(lines.count == 2)

    let fields = try #require(LedgerStore.fields(in: String(lines[1])))
    #expect(fields.count == LedgerStore.columnCount)
    #expect(Int(fields[20]) == LedgerStore.schemaVersion)
    #expect(fields[12] == commit.fullFingerprint)
    #expect(fields[19] == "arm-1")
}

@Test func ledgerStillReadsLegacyV2RowsWrittenUnderTheOldHeader() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let full = String(repeating: "A", count: 40)
    let legacy = [
        "2026-01-01T00:00:00Z", "GBP/JPY", "ABCD1234", "71", "LOW", "false", "0.0000", "MISS",
        "0.88", "10", "London", String(repeating: "B", count: 40), full, "1.1", "1.2",
        "oanda-midpoint-proxy", "180", "2026-01-01T00:00:00Z", "1772000000000", "legacy-arm",
    ].joined(separator: ",")
    let text = LedgerStore.legacyHeader + "\n" + legacy + "\n"
    try Data(text.utf8).write(to: FileLocations.ledgerCSV(in: root))

    let rows = try await LedgerStore(root: root).rows()
    #expect(rows.count == 1)
    #expect(rows[0].outcomeEventID == "legacy-arm")
    #expect(rows[0].fullFingerprint == full)
    #expect(rows[0].labelSource == "oanda-midpoint-proxy")
    #expect(rows[0].horizonSeconds == 180)
    #expect(rows[0].schemaVersion == nil)
}

@Test func duplicateArmCannotAppendASecondOutcome() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let commit = commit()
    let store = LedgerStore(root: root)

    #expect(try await store.record(row(for: commit)))
    #expect(try await store.record(row(for: commit, outcome: "MISS")) == false)
    #expect(try await store.rows().count == 1)
}

// MARK: - Interrupted settlement

@Test func failedSettlementSurvivesAndReconcilesOnceWithoutDuplicating() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let coordinator = PersistenceCoordinator(root: root)
    let commit = commit()
    try await coordinator.recordScan(entry(for: commit), snapshot: snapshot(for: commit))

    // Make the ledger unreadable/unwritable by placing a directory where the file belongs.
    let ledgerURL = FileLocations.ledgerCSV(in: root)
    try FileManager.default.createDirectory(at: ledgerURL, withIntermediateDirectories: true)

    await #expect(throws: (any Error).self) {
        try await coordinator.settle(armID: "arm-1", row: row(for: commit), snapshot: snapshot(for: commit))
    }
    #expect(await coordinator.pendingSettlements().count == 1)

    // The failed write must not have been stamped as a completed outcome.
    let midRestore = await coordinator.restore()
    #expect(midRestore.entries.first?.outcome == nil)
    #expect(midRestore.pendingSettlements.count == 1)

    // Remove the obstruction and reconcile.
    try FileManager.default.removeItem(at: ledgerURL)
    let issues = await coordinator.reconcilePendingSettlements()
    #expect(issues.isEmpty)
    #expect(await coordinator.pendingSettlements().isEmpty)

    let rows = try await LedgerStore(root: root).rows()
    #expect(rows.count == 1)
    #expect(rows[0].outcomeEventID == "arm-1")

    let restored = await coordinator.restore()
    #expect(restored.entries.first?.outcome == "HIT")
    #expect(restored.ledgerRows.count == 1)

    // Reconciling again must not append a second row.
    _ = await coordinator.reconcilePendingSettlements()
    #expect(try await LedgerStore(root: root).rows().count == 1)
}

@Test func restoreReportsDamageInsteadOfReturningEmptyHistory() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    try Data([0xFF, 0xFE, 0xFD]).write(to: FileLocations.ledgerCSV(in: root))
    try Data([0xFF, 0xFE, 0xFD]).write(to: FileLocations.journal(in: root))
    try Data([0xFF, 0xFE, 0xFD]).write(to: FileLocations.snapshots(in: root))

    let restored = await PersistenceCoordinator(root: root).restore()
    let domains = Set(restored.issues.map(\.domain))
    #expect(domains.contains(.ledger))
    #expect(domains.contains(.journal))
    #expect(domains.contains(.snapshots))
    #expect(!restored.issues.first!.userMessage.isEmpty)
}

@Test func corruptPendingSettlementIsSurfacedNotDiscarded() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not-a-pending-record\n".utf8).write(to: FileLocations.pendingSettlements(in: root))

    let restored = await PersistenceCoordinator(root: root).restore()
    #expect(restored.issues.contains { $0.domain == .pending })
}

// MARK: - Open position durability

@Test func openPositionSurvivesRestartAndCanBeCleared() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let trade = ActiveTrade(
        id: "arm-1",
        pair: "EUR/USD",
        side: "HIGH",
        strike: 1.1000,
        score: 82,
        enteredAt: t0,
        durationSec: 180,
        currentPrice: 1.1004,
        fingerprint: "ABCD1234"
    )
    let record = ActivePositionRecord(armID: "arm-1", trade: trade, fullFingerprint: String(repeating: "A", count: 40))

    let first = PersistenceCoordinator(root: root)
    try await first.saveOpenPosition(record)

    let second = PersistenceCoordinator(root: root)
    let restored = await second.restore()
    #expect(restored.activePosition?.armID == "arm-1")
    #expect(restored.activePosition?.trade.durationSec == 180)
    #expect(restored.activePosition?.trade.enteredAt == t0)
    #expect(restored.activePosition?.fullFingerprint == record.fullFingerprint)

    try await second.clearOpenPosition()
    let third = await PersistenceCoordinator(root: root).restore()
    #expect(third.activePosition == nil)
}

@Test func expiredPositionIsReportedAsExpiredRatherThanGuessed() {
    let trade = ActiveTrade(
        id: "arm-1",
        pair: "EUR/USD",
        side: "LOW",
        strike: 1.1000,
        score: 70,
        enteredAt: t0,
        durationSec: 60,
        fingerprint: "ABCD1234"
    )
    #expect(trade.isExpired)
    #expect(trade.remainingMs == 0)
}

// MARK: - Outcome provenance

@Test func referenceOutcomesNeverEnterTheMeasuredSample() {
    let commit = commit()
    let reference = (0..<12).map { index in
        row(for: commit, outcome: index.isMultiple(of: 2) ? "HIT" : "MISS", label: "oanda-midpoint-proxy", arm: "ref-\(index)")
    }
    let confirmed = [
        row(for: commit, outcome: "HIT", label: "venue-confirmed", arm: "confirmed-1"),
        row(for: commit, outcome: "MISS", label: "venue-confirmed", arm: "confirmed-2"),
        row(for: commit, outcome: "HIT", label: "venue-confirmed", arm: "confirmed-3"),
    ]

    let stats = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: reference)
    #expect(stats.sampleSize == 0)
    #expect(stats.referenceSampleSize == 12)
    #expect(!stats.isProvenEdge)

    let mixed = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: reference + confirmed)
    #expect(mixed.sampleSize == 3)
    #expect(mixed.wins == 2)
    #expect(mixed.referenceSampleSize == 12)
    #expect(!mixed.isProvenEdge)
}

@Test func cloudRecordRoundTripsV2MeasurementFields() {
    let commit = commit()
    let original = row(for: commit)
    let record = CloudRecordMapper.makeRecord(from: original)

    #expect(CloudSecurityGate.validate(record: record))

    let restored = CloudRecordMapper.toLedgerRow(from: record)
    #expect(restored?.fullFingerprint == original.fullFingerprint)
    #expect(restored?.payout == 0.88)
    #expect(restored?.stake == 10)
    #expect(restored?.marketWindow == "London")
    #expect(restored?.entryQuote == 1.1001)
    #expect(restored?.expiryPrice == 1.1009)
    #expect(restored?.engineSHA == EngineIdentity.pinnedSHA1)
    #expect(restored?.labelSource == "venue-confirmed")
}

@Test func securityGateStillRejectsCredentialShapedFreeText() {
    let commit = commit()
    let leaking = LedgerRow(
        timestamp: t0,
        pair: "EUR/USD",
        hash: commit.fingerprint,
        score: 50,
        side: "HIGH",
        veto: false,
        drift: 0,
        outcome: "HIT",
        outcomeEventID: "arm",
        marketWindow: "0123456789abcdef0123456789abcdef"
    )
    let record = CloudRecordMapper.makeRecord(from: leaking)
    #expect(!CloudSecurityGate.validate(record: record))
}
