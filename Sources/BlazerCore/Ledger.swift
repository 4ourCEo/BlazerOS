import Foundation

/// One HIT/MISS row. CSV columns match the Mac scan ledger so a file can move without translation.
public struct LedgerEntry: Codable, Sendable, Equatable, Identifiable {
    public var timestamp: Date
    public var pair: String
    public var hash: String
    public var score: Int
    public var side: String
    public var veto: Bool
    public var drift: Double
    public var outcome: String
    public var theirPrice: Double?
    /// Arm id. Together with `hash` this is the idempotency key. Not a CSV column.
    public var outcomeEventID: String

    public var id: String { "\(hash)+\(outcomeEventID)" }

    public init(
        timestamp: Date,
        pair: String,
        hash: String,
        score: Int,
        side: String,
        veto: Bool,
        drift: Double,
        outcome: String,
        theirPrice: Double?,
        outcomeEventID: String
    ) {
        self.timestamp = timestamp
        self.pair = pair
        self.hash = hash
        self.score = score
        self.side = side
        self.veto = veto
        self.drift = drift
        self.outcome = outcome
        self.theirPrice = theirPrice
        self.outcomeEventID = outcomeEventID
    }

    public static let csvHeader = "timestamp,pair,hash,score,side,veto,drift,outcome,theirPrice"
}

/// Append-only local ledger. CloudKit is a later transport over the same rows. No secrets.
public actor LedgerFile {
    public static let fileName = "scan_ledger.csv"
    public static let snapshotName = "scan_snapshots.jsonl"

    private let root: URL
    private var archivedHashes: Set<String> = []
    private var hashesLoaded = false
    private var handle: FileHandle?
    private var headerReady = false
    private var claimed: OutcomeTerminal = OutcomeTerminal()

    public init(root: URL) {
        self.root = root
    }

    /// One CSV row. A repeat claim for the same hash + arm id is refused.
    @discardableResult
    public func pipe(_ entry: LedgerEntry) throws -> Bool {
        guard claimed.claim(scanHash: entry.hash, outcomeEventID: entry.outcomeEventID) else {
            return false
        }
        try ensureHandle()
        guard let handle else { return false }
        let ts = Self.iso8601.string(from: entry.timestamp)
        let priceField: String
        if let theirPrice = entry.theirPrice, theirPrice.isFinite {
            priceField = String(theirPrice)
        } else {
            priceField = ""
        }
        let row = [
            csv(ts),
            csv(entry.pair),
            csv(entry.hash),
            csv(String(entry.score)),
            csv(entry.side),
            csv(entry.veto ? "true" : "false"),
            csv(String(format: "%.4f", entry.drift)),
            csv(entry.outcome),
            csv(priceField),
        ].joined(separator: ",") + "\n"
        guard let data = row.data(using: .utf8) else { return false }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        return true
    }

    /// Persist the candle set that produced `hash`. Same hash is not rewritten.
    public func archiveSnapshot(hash: String, asset: String, scannedAt: Date, candles: [Candle]) throws {
        guard !hash.isEmpty else { return }
        try loadArchivedHashesIfNeeded()
        if archivedHashes.contains(hash) { return }
        archivedHashes.insert(hash)
        struct Row: Encodable {
            var hash: String
            var asset: String
            var scannedAt: String
            var candles: [Candle]
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent(Self.snapshotName)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            let fh = try FileHandle(forWritingTo: url)
            defer { try? fh.close() }
            try fh.seekToEnd()
            let row = Row(
                hash: hash,
                asset: asset,
                scannedAt: Self.iso8601.string(from: scannedAt),
                candles: candles
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(row)
            data.append(0x0A)
            try fh.write(contentsOf: data)
            try fh.synchronize()
        } catch {
            archivedHashes.remove(hash)
            throw error
        }
    }

    private func loadArchivedHashesIfNeeded() throws {
        if hashesLoaded { return }
        hashesLoaded = true
        let url = root.appendingPathComponent(Self.snapshotName)
        guard FileManager.default.fileExists(atPath: url.path),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        struct HashOnly: Decodable { var hash: String }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                let row = try? JSONDecoder().decode(HashOnly.self, from: data),
                !row.hash.isEmpty
            else { continue }
            archivedHashes.insert(row.hash)
        }
    }

    private func ensureHandle() throws {
        if handle != nil, headerReady { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(Self.fileName)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        let fh = try FileHandle(forWritingTo: url)
        try fh.seekToEnd()
        if !exists || fh.offsetInFile == 0 {
            if let data = (LedgerEntry.csvHeader + "\n").data(using: .utf8) {
                try fh.write(contentsOf: data)
                try fh.synchronize()
            }
        }
        handle = fh
        headerReady = true
    }

    private static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func csv(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
