import Foundation

/// Something the desk could not read or reconcile at launch. Surfaced to the user
/// instead of being swallowed into an empty history.
public struct RestoreIssue: Equatable, Sendable {
    public enum Domain: String, Sendable, Equatable {
        case journal
        case snapshots
        case ledger
        case position
        case pending
    }

    public var domain: Domain
    public var message: String

    public init(domain: Domain, message: String) {
        self.domain = domain
        self.message = message
    }

    public var userMessage: String {
        switch domain {
        case .journal: return "Journal history is unreadable: \(message)"
        case .snapshots: return "Saved scan bars are unreadable: \(message)"
        case .ledger: return "Outcome history is unreadable: \(message)"
        case .position: return "Open position could not be restored: \(message)"
        case .pending: return "An unsaved outcome is waiting: \(message)"
        }
    }
}

/// History a relaunch is allowed to show. Bars come from snapshots.
public struct RestoredDesk: Equatable, Sendable {
    public var entries: [JournalEntry]
    public var barsByHash: [String: [Candle]]
    public var stats: OutcomeStats
    /// Venue-confirmed outcomes only. The performance header reads this, never `stats`.
    public var confirmedStats: OutcomeStats
    public var ledgerRows: [LedgerRow]
    /// Reads that failed. Never silently treated as empty history.
    public var issues: [RestoreIssue]
    /// Outcomes observed but not yet durably written.
    public var pendingSettlements: [PendingSettlement]
    /// A manually placed position that was still open when the app stopped.
    public var activePosition: ActivePositionRecord?

    public init(
        entries: [JournalEntry],
        barsByHash: [String: [Candle]],
        stats: OutcomeStats,
        ledgerRows: [LedgerRow] = [],
        confirmedStats: OutcomeStats? = nil,
        issues: [RestoreIssue] = [],
        pendingSettlements: [PendingSettlement] = [],
        activePosition: ActivePositionRecord? = nil
    ) {
        self.entries = entries
        self.barsByHash = barsByHash
        self.stats = stats
        self.confirmedStats = confirmedStats ?? stats
        self.ledgerRows = ledgerRows
        self.issues = issues
        self.pendingSettlements = pendingSettlements
        self.activePosition = activePosition
    }

    public func bars(for hash: String) -> [Candle] {
        barsByHash[hash] ?? []
    }

    public var hasRecoverableState: Bool {
        !pendingSettlements.isEmpty || activePosition != nil
    }
}

/// Writes the scan documents together. It does not see quotes, tokens, or the live beam.
///
/// A settlement is not considered complete until the ledger row and the journal stamp
/// are both durable. If either write fails, the pending record survives for retry.
public actor PersistenceCoordinator {
    private let ledger: LedgerStore
    private let snapshots: SnapshotStore
    private let journal: JournalStore
    private let recovery: RecoveryStore
    private let cloudSync: CloudSyncCoordinator?

    /// Serializes read-modify-write operations on the journal. Actor isolation alone is
    /// reentrant at every `await`, so two settlements could otherwise save stale arrays.
    private var journalBusy = false
    private var journalWaiters: [CheckedContinuation<Void, Never>] = []

    private func acquireJournal() async {
        if !journalBusy {
            journalBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            journalWaiters.append(continuation)
        }
    }

    private func releaseJournal() {
        if journalWaiters.isEmpty {
            journalBusy = false
        } else {
            journalWaiters.removeFirst().resume()
        }
    }

    public init(root: URL, cloudTransport: CloudSyncTransport? = nil, enableCloudSync: Bool = false) {
        self.ledger = LedgerStore(root: root)
        self.snapshots = SnapshotStore(root: root)
        self.journal = JournalStore(root: root)
        self.recovery = RecoveryStore(root: root)
        if let cloudTransport {
            self.cloudSync = CloudSyncCoordinator(root: root, transport: cloudTransport)
        } else if enableCloudSync {
            self.cloudSync = CloudSyncCoordinator(root: root)
        } else {
            self.cloudSync = nil
        }
    }

    public func restore() async -> RestoredDesk {
        var issues: [RestoreIssue] = []

        var entries: [JournalEntry] = []
        do {
            entries = try await journal.load()
        } catch {
            issues.append(RestoreIssue(domain: .journal, message: error.localizedDescription))
        }

        var snapshotRecords: [SnapshotRecord] = []
        do {
            snapshotRecords = try await snapshots.load()
        } catch {
            issues.append(RestoreIssue(domain: .snapshots, message: error.localizedDescription))
        }

        var rows: [LedgerRow] = []
        do {
            let result = try await ledger.read()
            rows = result.rows
            if result.damagedLines > 0 {
                issues.append(RestoreIssue(
                    domain: .ledger,
                    message: "\(result.damagedLines) ledger line(s) could not be parsed; the original file was left untouched"
                ))
            }
        } catch {
            issues.append(RestoreIssue(domain: .ledger, message: error.localizedDescription))
        }

        var position: ActivePositionRecord?
        do {
            position = try await recovery.loadPosition()
        } catch {
            issues.append(RestoreIssue(domain: .position, message: error.localizedDescription))
        }

        var pending: [PendingSettlement] = []
        do {
            let result = try await recovery.readPending()
            pending = result.records
            if result.corruptLines > 0 {
                issues.append(RestoreIssue(
                    domain: .pending,
                    message: "\(result.corruptLines) pending settlement line(s) were corrupt and quarantined; valid outcomes remain queued"
                ))
            }
        } catch {
            issues.append(RestoreIssue(domain: .pending, message: error.localizedDescription))
        }

        var bars: [String: [Candle]] = [:]
        for record in snapshotRecords {
            bars[record.hash] = record.bars
            if let full = record.fullFingerprint {
                bars[full] = record.bars
            }
        }

        let newestFirst = entries.sorted { $0.scannedAt > $1.scannedAt }
        return RestoredDesk(
            entries: newestFirst,
            barsByHash: bars,
            stats: OutcomeStats.tally(rows),
            ledgerRows: rows,
            confirmedStats: OutcomeStats.confirmedTally(rows),
            issues: issues,
            pendingSettlements: pending,
            activePosition: position
        )
    }

    /// Archives the frozen bars, then the journal card. The same identity is not rewritten.
    public func recordScan(_ entry: JournalEntry, snapshot: SnapshotRecord) async throws {
        await acquireJournal()
        defer { releaseJournal() }
        _ = try await snapshots.archive(snapshot)
        try await journal.upsert(entry)
    }

    public func noteVeto(armID: String, veto: String) async throws {
        await acquireJournal()
        defer { releaseJournal() }
        var entries = try await journal.load()
        guard let index = entries.firstIndex(where: { $0.id == armID }) else { return }
        entries[index].veto = veto
        try await journal.save(entries)
    }

    /// Attaches voice notes, tags, emotions, or lessons to a journal entry.
    public func annotate(
        entryID: String,
        voiceNote: VoiceNote? = nil,
        tag: Tag? = nil,
        emotion: Emotion? = nil,
        lesson: Lesson? = nil
    ) async throws {
        await acquireJournal()
        defer { releaseJournal() }
        var entries = try await journal.load()
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        if let voiceNote { entries[index].voiceNote = voiceNote }
        if let tag { entries[index].tag = tag }
        if let emotion { entries[index].emotion = emotion }
        if let lesson { entries[index].lesson = lesson }
        try await journal.save(entries)
    }

    // MARK: - Open position

    public func saveOpenPosition(_ record: ActivePositionRecord) async throws {
        try await recovery.savePosition(record)
    }

    public func clearOpenPosition() async throws {
        try await recovery.clearPosition()
    }

    public func openPosition() async -> ActivePositionRecord? {
        try? await recovery.loadPosition()
    }

    // MARK: - Settlement

    /// Appends one ledger row and stamps the journal. A second call does not append.
    ///
    /// On failure the pending record is kept on disk and the error is rethrown, so the
    /// caller can keep the outcome in front of the user instead of reporting success.
    @discardableResult
    public func settle(armID: String, row: LedgerRow, snapshot: SnapshotRecord) async throws -> Bool {
        await acquireJournal()
        defer { releaseJournal() }
        do {
            let wrote = try await writeSettlement(armID: armID, row: row, snapshot: snapshot)
            let durable = wrote ? true : (try await journalHasOutcome(armID: armID))
            if durable {
                try? await recovery.removePending(armID: armID)
            }
            return wrote
        } catch {
            var attempts = 1
            if let existing = try? await recovery.readPending().records.first(where: { $0.armID == armID }) {
                attempts = existing.attempts + 1
            }
            // Surface a failed pending write instead of silently losing the outcome.
            try await recovery.upsertPending(
                PendingSettlement(
                    armID: armID,
                    row: row,
                    snapshot: snapshot,
                    attempts: attempts,
                    lastError: error.localizedDescription
                )
            )
            throw error
        }
    }

    public func pendingSettlements() async -> [PendingSettlement] {
        (try? await recovery.readPending().records) ?? []
    }

    /// Retries every pending settlement. A row that already reached the ledger is only
    /// stamped onto the journal. Returns the issues that remain.
    public func reconcilePendingSettlements() async -> [RestoreIssue] {
        await acquireJournal()
        defer { releaseJournal() }
        var remaining: [RestoreIssue] = []
        let pending: [PendingSettlement]
        do {
            let read = try await recovery.readPending()
            pending = read.records
            if read.corruptLines > 0 {
                remaining.append(RestoreIssue(
                    domain: .pending,
                    message: "\(read.corruptLines) corrupt pending line(s) quarantined"
                ))
            }
        } catch {
            return [RestoreIssue(domain: .pending, message: error.localizedDescription)]
        }
        for record in pending {
            do {
                let wrote = try await writeSettlement(
                    armID: record.armID,
                    row: record.row,
                    snapshot: record.snapshot
                )
                let durable = wrote ? true : (try await journalHasOutcome(armID: record.armID))
                if durable {
                    try await recovery.removePending(armID: record.armID)
                } else {
                    remaining.append(
                        RestoreIssue(
                            domain: .pending,
                            message: "Journal entry \(record.armID) is missing; outcome kept for recovery"
                        )
                    )
                }
            } catch {
                try? await recovery.upsertPending(
                    PendingSettlement(
                        armID: record.armID,
                        row: record.row,
                        snapshot: record.snapshot,
                        createdAt: record.createdAt,
                        attempts: record.attempts + 1,
                        lastError: error.localizedDescription
                    )
                )
                remaining.append(
                    RestoreIssue(
                        domain: .pending,
                        message: "\(record.row.pair) \(record.row.outcome) at \(record.row.enteredAt.map { "\($0)" } ?? record.row.timestamp.description)"
                    )
                )
            }
        }
        return remaining
    }

    private func journalHasOutcome(armID: String) async throws -> Bool {
        let entries = try await journal.load()
        return entries.first(where: { $0.id == armID })?.outcome != nil
    }

    /// The actual write. Snapshots first, then the ledger, then the journal stamp.
    private func writeSettlement(armID: String, row: LedgerRow, snapshot: SnapshotRecord) async throws -> Bool {
        _ = try await snapshots.archive(snapshot)
        var entries = try await journal.load()
        guard let index = entries.firstIndex(where: { $0.id == armID }) else { return false }
        if entries[index].outcome != nil { return false }

        let wrote = try await ledger.record(row)
        if !wrote {
            // Already present from an earlier attempt: adopt the durable outcome.
            let all = try await ledger.rows()
            let existing = all.first { $0.identity == row.identity && $0.pair == row.pair }
                ?? all.first { $0.outcomeEventID == row.outcomeEventID }
            if let existing {
                entries[index].outcome = existing.outcome
                try await journal.save(entries)
            }
            return false
        }
        entries[index].outcome = row.outcome
        try await journal.save(entries)
        return true
    }

    // MARK: - CloudKit

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
