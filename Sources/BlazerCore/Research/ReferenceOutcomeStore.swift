import Foundation

/// Bounded local history of OANDA midpoint reference observations.
///
/// These are never venue-confirmed results and are deliberately kept out of the trading
/// ledger. One compact JSONL file with a fixed cap avoids one-file-per-trade growth and keeps
/// launch/Journal reads bounded as history accumulates.
public actor ReferenceOutcomeStore {
    public static let fileName = "reference_outcomes.jsonl"

    private let url: URL
    private let limit: Int
    private var cache: [ResearchOutcome]?

    public init(root: URL, limit: Int = 500) {
        self.url = root.appendingPathComponent(Self.fileName)
        self.limit = max(1, limit)
    }

    /// Returns true only when a new observation was appended.
    @discardableResult
    public func record(_ outcome: ResearchOutcome) throws -> Bool {
        var values = try load()
        let key = Self.key(outcome)
        guard !values.contains(where: { Self.key($0) == key }) else { return false }
        values.append(outcome)
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
        try write(values)
        cache = values
        return true
    }

    /// Newest last. Invalid lines are skipped; the file is not rewritten on read.
    public func outcomes() -> [ResearchOutcome] {
        (try? load()) ?? []
    }

    private static func key(_ outcome: ResearchOutcome) -> String {
        "\(outcome.eventID)-\(outcome.horizon)"
    }

    private func load() throws -> [ResearchOutcome] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: url.path) else {
            cache = []
            return []
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let values = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { try? decoder.decode(ResearchOutcome.self, from: Data($0.utf8)) }
            .suffix(limit)
        let result = Array(values)
        cache = result
        return result
    }

    private func write(_ values: [ResearchOutcome]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for value in values {
            data.append(try encoder.encode(value))
            data.append(0x0A)
        }
        try AtomicFile.write(data, to: url)
    }
}
