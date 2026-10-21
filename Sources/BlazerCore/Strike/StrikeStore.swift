import Foundation

// MARK: - Durable strike position store
//
// Positions are persisted atomically after every applied event, so an interrupted save cannot
// corrupt the file, and a restart rebuilds state exactly. Applying a duplicate event is a no-op.

public actor StrikeStore {
    public struct Snapshot: Sendable, Codable {
        public var positions: [StrikePosition]
        public init(positions: [StrikePosition]) { self.positions = positions }
    }

    private var positions: [String: StrikePosition] = [:]
    private let url: URL?

    /// - Parameter url: file to persist to. `nil` keeps the store in memory only (tests/previews).
    public init(url: URL? = nil) {
        self.url = url
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            positions = Dictionary(snapshot.positions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        } catch {
            // Preserve an unreadable store instead of silently losing every position on the
            // next write. The file is moved aside; the desk starts empty but auditable.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    /// Create a position and apply its opening event with a single atomic write.
    /// A crash cannot leave a zero-quantity orphan that needs a second save to repair.
    public func create(_ position: StrikePosition, opening event: StrikeEvent) throws -> StrikePosition {
        var opened = position
        try StrikeLedger.apply(event, to: &opened)
        positions[position.id] = opened
        try persist()
        return opened
    }

    public func position(id: String) -> StrikePosition? { positions[id] }

    public func all() -> [StrikePosition] {
        positions.values.sorted { $0.id < $1.id }
    }

    /// Create (or replace) a position record and persist.
    public func create(_ position: StrikePosition) throws {
        positions[position.id] = position
        try persist()
    }

    /// Apply an event to its position, persisting on success. Idempotent for repeated ids.
    @discardableResult
    public func apply(_ event: StrikeEvent) throws -> StrikePosition {
        guard var position = positions[event.positionID] else {
            throw StrikeLedgerError.unknownPosition(event.positionID)
        }
        try StrikeLedger.apply(event, to: &position)
        positions[event.positionID] = position
        try persist()
        return position
    }

    /// Atomic write: the temp-file swap means an interrupted save cannot leave a truncated file.
    private func persist() throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(Snapshot(positions: all()))
        try data.write(to: url, options: .atomic)
    }
}
