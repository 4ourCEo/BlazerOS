import Foundation

/// A settlement that was observed but not yet durably written.
/// Persisted before the desk is allowed to forget the outcome, so a crash or a
/// full disk cannot silently drop a trade.
public struct PendingSettlement: Codable, Equatable, Sendable, Identifiable {
    public var armID: String
    public var row: LedgerRow
    public var snapshot: SnapshotRecord
    public var createdAt: Date
    public var attempts: Int
    public var lastError: String?

    public var id: String { armID }

    public init(
        armID: String,
        row: LedgerRow,
        snapshot: SnapshotRecord,
        createdAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.armID = armID
        self.row = row
        self.snapshot = snapshot
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// A manually placed position the desk is still tracking.
/// `armID` links it back to the journal entry that authorised it.
public struct ActivePositionRecord: Codable, Equatable, Sendable {
    public var armID: String
    public var trade: ActiveTrade
    /// Full pair-and-bars identity of the scan that authorised the entry.
    public var fullFingerprint: String
    /// Complete frozen input, when the app recorded it. Optional for pre-v4 records.
    public var scanInput: ScanInputSnapshot?

    public init(
        armID: String,
        trade: ActiveTrade,
        fullFingerprint: String,
        scanInput: ScanInputSnapshot? = nil
    ) {
        self.armID = armID
        self.trade = trade
        self.fullFingerprint = fullFingerprint
        self.scanInput = scanInput
    }
}

/// Durable recovery state: the open position and any settlement that still needs a write.
/// Kept deliberately separate from the scan documents so a settlement retry never
/// rewrites history that is already trusted.
public actor RecoveryStore {
    public enum RecoveryError: LocalizedError {
        case corruptPendingRecord

        public var errorDescription: String? {
            switch self {
            case .corruptPendingRecord:
                return "A pending settlement record could not be read"
            }
        }
    }

    private let positionURL: URL
    private let pendingURL: URL

    /// Valid pending records plus a count of lines that could not be decoded. Corrupt lines
    /// are copied to a quarantine file, not deleted, and never block a new settlement.
    public struct PendingRead: Sendable, Equatable {
        public var records: [PendingSettlement]
        public var corruptLines: Int

        public init(records: [PendingSettlement], corruptLines: Int) {
            self.records = records
            self.corruptLines = corruptLines
        }
    }

    public init(root: URL) {
        self.positionURL = FileLocations.activePosition(in: root)
        self.pendingURL = FileLocations.pendingSettlements(in: root)
    }

    // MARK: - Open position

    public func loadPosition() throws -> ActivePositionRecord? {
        guard FileManager.default.fileExists(atPath: positionURL.path) else { return nil }
        let data = try Data(contentsOf: positionURL)
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ActivePositionRecord.self, from: data)
    }

    public func savePosition(_ record: ActivePositionRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try AtomicFile.write(try encoder.encode(record), to: positionURL)
    }

    public func clearPosition() throws {
        guard FileManager.default.fileExists(atPath: positionURL.path) else { return }
        try FileManager.default.removeItem(at: positionURL)
    }

    // MARK: - Pending settlements

    public func pending() throws -> [PendingSettlement] {
        let read = try readPending()
        guard read.corruptLines == 0 else { throw RecoveryError.corruptPendingRecord }
        return read.records
    }

    /// Reads every valid record and quarantines (but preserves) undecodable lines.
    public func readPending() throws -> PendingRead {
        guard FileManager.default.fileExists(atPath: pendingURL.path) else {
            return PendingRead(records: [], corruptLines: 0)
        }
        let text = try String(contentsOf: pendingURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [PendingSettlement] = []
        var corrupt: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(raw).data(using: .utf8),
                let record = try? decoder.decode(PendingSettlement.self, from: data),
                !record.armID.isEmpty
            else {
                corrupt.append(String(raw))
                continue
            }
            records.append(record)
        }
        if !corrupt.isEmpty {
            // Preserve the corrupt lines in an audit file, then clean the active queue so
            // they cannot block or duplicate on every subsequent read.
            quarantine(corrupt)
            try? replacePending(records)
        }
        return PendingRead(records: records, corruptLines: corrupt.count)
    }

    /// Adds or replaces the pending record for this arm. Never duplicates.
    public func upsertPending(_ record: PendingSettlement) throws {
        var records = try readPending().records
        if let index = records.firstIndex(where: { $0.armID == record.armID }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try replacePending(records)
    }

    public func removePending(armID: String) throws {
        var records = try readPending().records
        let before = records.count
        records.removeAll { $0.armID == armID }
        guard records.count != before else { return }
        try replacePending(records)
    }

    /// Preserves corrupt pending lines next to the queue so a damaged record remains auditable.
    private func quarantine(_ lines: [String]) {
        let url = pendingURL.deletingLastPathComponent()
            .appendingPathComponent("pending_settlements.corrupt.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Date())
        var payload = lines.map { "{\"quarantined_at\":\"\(stamp)\",\"raw\":\(jsonString($0))}" }
            .joined(separator: "\n")
        payload += "\n"
        guard let data = payload.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? AtomicFile.write(data, to: url)
        }
    }

    private func jsonString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func replacePending(_ records: [PendingSettlement]) throws {
        guard !records.isEmpty else {
            if FileManager.default.fileExists(atPath: pendingURL.path) {
                try FileManager.default.removeItem(at: pendingURL)
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for record in records {
            var line = try encoder.encode(record)
            line.append(0x0A)
            data.append(line)
        }
        try AtomicFile.write(data, to: pendingURL)
    }
}
