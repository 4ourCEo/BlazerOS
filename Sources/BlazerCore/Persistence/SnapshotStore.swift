import Foundation

/// Frozen scan document. Replay reads these bars. The live quote never rewrites them.
public struct SnapshotRecord: Codable, Equatable, Sendable {
    /// Short display fingerprint of the bars.
    public var hash: String
    /// Full frozen-input identity. Absent on records written before schema v3.
    public var fullFingerprint: String?
    public var pair: String
    public var bars: [Candle]
    /// M5 bars the engine evaluated. Absent on pre-v4 records.
    public var m5Bars: [Candle]?
    public var bid: Double?
    public var ask: Double?
    public var spread: Double?
    public var expirySeconds: Int?
    public var engineSHA: String?
    public var policy: String?
    public var strike: Double
    public var score: Int
    public var side: String

    public init(
        hash: String,
        fullFingerprint: String? = nil,
        pair: String,
        bars: [Candle],
        m5Bars: [Candle]? = nil,
        bid: Double? = nil,
        ask: Double? = nil,
        spread: Double? = nil,
        expirySeconds: Int? = nil,
        engineSHA: String? = nil,
        policy: String? = nil,
        strike: Double,
        score: Int,
        side: String
    ) {
        self.hash = hash
        self.fullFingerprint = fullFingerprint
        self.pair = pair
        self.bars = bars
        self.m5Bars = m5Bars
        self.bid = bid
        self.ask = ask
        self.spread = spread
        self.expirySeconds = expirySeconds
        self.engineSHA = engineSHA
        self.policy = policy
        self.strike = strike
        self.score = score
        self.side = side
    }

    /// Storage identity. Falls back to the short hash for pre-v3 records.
    public var identity: String {
        fullFingerprint ?? hash
    }

    /// Rebuilds the exact frozen input, or nil when the record predates full input storage.
    public var inputSnapshot: ScanInputSnapshot? {
        guard let fullFingerprint, !fullFingerprint.isEmpty else { return nil }
        return ScanInputSnapshot(
            pair: pair,
            m1: bars,
            m5: m5Bars ?? [],
            bid: bid,
            ask: ask,
            spread: spread,
            expirySeconds: expirySeconds ?? Timing.expirySec,
            engineSHA: engineSHA ?? EngineIdentity.pinnedSHA1,
            policy: policy ?? "baseline"
        )
    }
}

/// JSONL snapshots. The same identity is not written twice. A bad line does not drop the others.
public actor SnapshotStore {
    private let url: URL

    public init(root: URL) {
        self.url = FileLocations.snapshots(in: root)
    }

    /// Inserts the record when its identity is new. Returns false when already on disk.
    @discardableResult
    public func archive(_ record: SnapshotRecord) throws -> Bool {
        guard !record.identity.isEmpty else { return false }
        var records = try load()
        if records.contains(where: { $0.identity == record.identity }) { return false }
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
