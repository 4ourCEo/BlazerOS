import Foundation

/// Frozen scan document. Replay reads these bars. The live quote never rewrites them.
public struct SnapshotRecord: Codable, Equatable, Sendable {
    public var hash: String
    public var pair: String
    public var bars: [Candle]
    public var strike: Double
    public var score: Int
    public var side: String

    public init(hash: String, pair: String, bars: [Candle], strike: Double, score: Int, side: String) {
        self.hash = hash
        self.pair = pair
        self.bars = bars
        self.strike = strike
        self.score = score
        self.side = side
    }
}

/// JSONL snapshots. The same hash is not written twice. A bad line does not drop the others.
public actor SnapshotStore {
    private let url: URL

    public init(root: URL) {
        self.url = FileLocations.snapshots(in: root)
    }

    /// Inserts the record when its hash is new. Returns false when that hash is already on disk.
    @discardableResult
    public func archive(_ record: SnapshotRecord) throws -> Bool {
        guard !record.hash.isEmpty else { return false }
        var records = try load()
        if records.contains(where: { $0.hash == record.hash }) { return false }
        records.append(record)
        try replace(records)
        return true
    }

    public func load() throws -> [SnapshotRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var records: [SnapshotRecord] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(raw).data(using: .utf8),
                let record = try? decoder.decode(SnapshotRecord.self, from: data),
                !record.hash.isEmpty
            else { continue }
            records.append(record)
        }
        return records
    }

    public func bars(for hash: String) throws -> [Candle] {
        try load().first(where: { $0.hash == hash })?.bars ?? []
    }

    private func replace(_ records: [SnapshotRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for record in records {
            var line = try encoder.encode(record)
            line.append(0x0A)
            data.append(line)
        }
        try AtomicFile.write(data, to: url)
    }
}
