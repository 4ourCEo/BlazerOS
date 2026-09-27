import CloudKit
import Foundation

public struct CloudSyncStats: Equatable, Sendable {
    public var pushedLedger: Int
    public var pushedSnapshots: Int
    public var pushedJournal: Int
    public var pulledLedger: Int
    public var pulledSnapshots: Int
    public var pulledJournal: Int

    public init(
        pushedLedger: Int = 0,
        pushedSnapshots: Int = 0,
        pushedJournal: Int = 0,
        pulledLedger: Int = 0,
        pulledSnapshots: Int = 0,
        pulledJournal: Int = 0
    ) {
        self.pushedLedger = pushedLedger
        self.pushedSnapshots = pushedSnapshots
        self.pushedJournal = pushedJournal
        self.pulledLedger = pulledLedger
        self.pulledSnapshots = pulledSnapshots
        self.pulledJournal = pulledJournal
    }

    public static let zero = CloudSyncStats()
}

/// Orchestrates synchronization between local persistence stores and CloudKit.
/// Live quotes, active beams, and credentials are intentionally excluded from all sync operations.
public actor CloudSyncCoordinator {
    private let ledgerStore: LedgerStore
    private let snapshotStore: SnapshotStore
    private let journalStore: JournalStore
    private let transport: CloudSyncTransport

    public init(root: URL, transport: CloudSyncTransport = NativeCloudKitTransport()) {
        self.ledgerStore = LedgerStore(root: root)
        self.snapshotStore = SnapshotStore(root: root)
        self.journalStore = JournalStore(root: root)
        self.transport = transport
    }

    /// Pushes local documents to CloudKit. Rejects any sensitive or device-local records.
    @discardableResult
    public func push() async throws -> CloudSyncStats {
        let status = try await transport.accountStatus()
        guard status == .available else {
            throw CloudSyncError.unauthenticated
        }

        var toSave: [CKRecord] = []
        var stats = CloudSyncStats()

        // 1. Ledger
        let rows = try await ledgerStore.rows()
        for row in rows {
            guard CloudSecurityGate.validate(row: row) else {
                throw CloudSyncError.securityGateViolation(row.hash)
            }
            let record = CloudRecordMapper.makeRecord(from: row)
            toSave.append(record)
            stats.pushedLedger += 1
        }

        // 2. Snapshots
        let snapshots = try await snapshotStore.load()
        for snapshot in snapshots {
            if let record = CloudRecordMapper.makeRecord(from: snapshot) {
                toSave.append(record)
                stats.pushedSnapshots += 1
            }
        }

        // 3. Journal
        let entries = try await journalStore.load()
        for entry in entries {
            let record = CloudRecordMapper.makeRecord(from: entry)
            toSave.append(record)
            stats.pushedJournal += 1
        }

        if !toSave.isEmpty {
            _ = try await transport.modifyRecords(toSave: toSave, toDelete: [])
        }
        return stats
    }

    /// Pulls remote documents from CloudKit and merges them into local stores.
    @discardableResult
    public func pull() async throws -> CloudSyncStats {
        let status = try await transport.accountStatus()
        guard status == .available else {
            throw CloudSyncError.unauthenticated
        }

        var stats = CloudSyncStats()

        // 1. Ledger
        let remoteLedgerRecords = try await transport.queryRecords(recordType: CloudRecordType.ledger)
        for record in remoteLedgerRecords {
            guard CloudSecurityGate.validate(record: record),
                  let row = CloudRecordMapper.toLedgerRow(from: record) else { continue }
            // Respect single-write rule: a repeat outcome write returns false
            if (try? await ledgerStore.record(row)) == true {
                stats.pulledLedger += 1
            }
        }

        // 2. Snapshots
        let remoteSnapshotRecords = try await transport.queryRecords(recordType: CloudRecordType.snapshot)
        for record in remoteSnapshotRecords {
            guard CloudSecurityGate.validate(record: record),
                  let snapshot = CloudRecordMapper.toSnapshotRecord(from: record) else { continue }
            // Respect immutability rule: duplicate hash is not overwritten
            if (try? await snapshotStore.archive(snapshot)) == true {
                stats.pulledSnapshots += 1
            }
        }

        // 3. Journal
        let remoteJournalRecords = try await transport.queryRecords(recordType: CloudRecordType.journal)
        for record in remoteJournalRecords {
            guard CloudSecurityGate.validate(record: record),
                  let entry = CloudRecordMapper.toJournalEntry(from: record) else { continue }
            try? await journalStore.upsert(entry)
            stats.pulledJournal += 1
        }

        return stats
    }

    /// Complete bidirectional sync cycle.
    @discardableResult
    public func sync() async throws -> CloudSyncStats {
        let pushed = try await push()
        let pulled = try await pull()
        return CloudSyncStats(
            pushedLedger: pushed.pushedLedger,
            pushedSnapshots: pushed.pushedSnapshots,
            pushedJournal: pushed.pushedJournal,
            pulledLedger: pulled.pulledLedger,
            pulledSnapshots: pulled.pulledSnapshots,
            pulledJournal: pulled.pulledJournal
        )
    }
}
