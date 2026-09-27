import Foundation

/// History a relaunch is allowed to show. Bars come from snapshots.
public struct RestoredDesk: Equatable, Sendable {
    public var entries: [JournalEntry]
    public var barsByHash: [String: [Candle]]
    public var stats: OutcomeStats

    public init(entries: [JournalEntry], barsByHash: [String: [Candle]], stats: OutcomeStats) {
        self.entries = entries
        self.barsByHash = barsByHash
        self.stats = stats
    }

    public func bars(for hash: String) -> [Candle] {
        barsByHash[hash] ?? []
    }
}

/// Writes the scan documents together. It does not see quotes, tokens, or the live beam.
public actor PersistenceCoordinator {
    private let ledger: LedgerStore
    private let snapshots: SnapshotStore
    private let journal: JournalStore
    private let cloudSync: CloudSyncCoordinator?

    public init(root: URL, cloudTransport: CloudSyncTransport? = nil, enableCloudSync: Bool = false) {
        self.ledger = LedgerStore(root: root)
        self.snapshots = SnapshotStore(root: root)
        self.journal = JournalStore(root: root)
        if let cloudTransport {
            self.cloudSync = CloudSyncCoordinator(root: root, transport: cloudTransport)
        } else if enableCloudSync {
            self.cloudSync = CloudSyncCoordinator(root: root)
        } else {
            self.cloudSync = nil
        }
    }

    public func restore() async -> RestoredDesk {
        let entries = (try? await journal.load()) ?? []
        let snapshots = (try? await snapshots.load()) ?? []
        let stats = (try? await ledger.stats()) ?? .empty
        var bars: [String: [Candle]] = [:]
        for record in snapshots {
            bars[record.hash] = record.bars
        }
        let newestFirst = entries.sorted { $0.scannedAt > $1.scannedAt }
        return RestoredDesk(entries: newestFirst, barsByHash: bars, stats: stats)
    }

    /// Archives the frozen bars, then the journal card. The same hash is not rewritten.
    public func recordScan(_ entry: JournalEntry, snapshot: SnapshotRecord) async throws {
        _ = try await snapshots.archive(snapshot)
        try await journal.upsert(entry)
    }

    public func noteVeto(armID: String, veto: String) async throws {
        var entries = try await journal.load()
        guard let index = entries.firstIndex(where: { $0.id == armID }) else { return }
        entries[index].veto = veto
        try await journal.save(entries)
    }

    /// Appends one ledger row and stamps the journal. A second call does not append.
    @discardableResult
    public func settle(armID: String, row: LedgerRow, snapshot: SnapshotRecord) async throws -> Bool {
        _ = try await snapshots.archive(snapshot)
        var entries = try await journal.load()
        guard let index = entries.firstIndex(where: { $0.id == armID }) else { return false }
        if entries[index].outcome != nil { return false }
        let wrote = try await ledger.record(row)
        if !wrote {
            if let existing = try await ledger.rows().first(where: { $0.hash == row.hash }) {
                entries[index].outcome = existing.outcome
                try await journal.save(entries)
            }
            return false
        }
        entries[index].outcome = row.outcome
        try await journal.save(entries)
        return true
    }

    /// Complete bidirectional CloudKit sync cycle.
    @discardableResult
    public func sync() async throws -> CloudSyncStats {
        guard let cloudSync else { return .zero }
        return try await cloudSync.sync()
    }

    @discardableResult
    public func pushCloud() async throws -> CloudSyncStats {
        guard let cloudSync else { return .zero }
        return try await cloudSync.push()
    }

    @discardableResult
    public func pullCloud() async throws -> CloudSyncStats {
        guard let cloudSync else { return .zero }
        return try await cloudSync.pull()
    }
}
