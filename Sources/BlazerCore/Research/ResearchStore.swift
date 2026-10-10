import Foundation

/// Separate local research archive. It is never read by the trading ledger or CloudKit mapper.
public actor ResearchStore {
    private let root: URL
    public init(root: URL) { self.root = root }

    public static func defaultRoot(synthetic: Bool = false) -> URL {
        FileLocations.applicationSupport().appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent(synthetic ? "synthetic" : "oanda-proxy", isDirectory: true)
    }

    public func record(_ event: ResearchEvent) throws {
        try writeOnce(event, directory: "events", name: event.id)
    }

    public func record(_ outcome: ResearchOutcome) throws {
        try writeOnce(outcome, directory: "outcomes", name: "\(outcome.eventID)-\(outcome.horizon)")
    }

    public func events() throws -> [ResearchEvent] {
        let events = try load(ResearchEvent.self, directory: "events")
        for event in events {
            guard event.inputDigest == (try ResearchEvent.digest(of: event.input)) else {
                throw ScanError.failed("Research input digest mismatch: \(event.id)")
            }
        }
        return events
    }
    public func outcomes() throws -> [ResearchOutcome] { try load(ResearchOutcome.self, directory: "outcomes") }

    private func writeOnce<T: Encodable>(_ value: T, directory: String, name: String) throws {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid research event ID")
        }
        let url = root.appendingPathComponent(directory).appendingPathComponent(name + ".json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try AtomicFile.write(encoder.encode(value), to: url)
    }

    private func load<T: Decodable>(_ type: T.Type, directory: String) throws -> [T] {
        let path = root.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        // A corrupt record is an explicit error, never silently converted into missing data.
        return try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decoder.decode(type, from: Data(contentsOf: $0)) }
    }
}
