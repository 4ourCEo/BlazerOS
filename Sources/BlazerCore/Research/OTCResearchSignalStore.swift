import Foundation

/// A frozen research record: the exact normalized input and the signal it produced. Storing the
/// input (not only the output) lets replay prove look-ahead safety and non-overlap later.
public struct OTCResearchRecord: Codable, Sendable, Equatable, Identifiable {
    public let signal: OTCResearchSignal
    public let input: OTCResearchInput
    /// Frozen evaluator configuration. Replay must use the same version that produced the signal.
    public let configuration: OTCResearchConfiguration

    public init(signal: OTCResearchSignal, input: OTCResearchInput,
                configuration: OTCResearchConfiguration = .standard) {
        self.signal = signal
        self.input = input
        self.configuration = configuration
    }

    public var id: String { signal.id }

    public var isValid: Bool {
        signal.researchOnly && !signal.mayAuthorizeEntry
            && !signal.scoreIsCalibratedWinProbability
            && signal.instrument == input.instrument
            && signal.sourceSnapshotID == input.snapshotID
            && signal.instrument.isResearchOnly
            && signal.engineVersion == configuration.engineVersion
            && signal.strategyVersion == configuration.strategyVersion
            && signal.horizonSeconds == configuration.horizonSeconds
    }
}

/// Append-only, bounded archive of OTC research signals. This is not a ledger and it can never
/// authorize execution. Corrupt or non-research files are refused rather than reinterpreted.
public actor OTCResearchSignalStore {
    private let root: URL
    private let maximumRecords: Int
    private let pruneEvery: Int
    private var writesSincePrune = 0

    public init(root: URL, maximumRecords: Int = 5_000, pruneEvery: Int = 128) {
        self.root = root
        self.maximumRecords = max(1, maximumRecords)
        self.pruneEvery = max(1, pruneEvery)
    }

    public func record(_ record: OTCResearchRecord) throws {
        guard record.isValid,
              record.signal.sourceSnapshotID.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber
                      || $0 == "-" || $0 == "_" || $0 == ".")
              })
        else { throw OTCResearchStoreError.invalidRecord }
        let directory = root
        let stamp = String(format: "%015.3f",
                           record.input.evaluatedAt.timeIntervalSince1970)
        let name = "\(stamp)-\(record.signal.sourceSnapshotID).json"
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try AtomicFile.write(encoder.encode(record), to: url)
        writesSincePrune += 1
        if writesSincePrune >= pruneEvery {
            writesSincePrune = 0
            prune()
        }
    }

    public func records(limit: Int = 500) throws -> [OTCResearchRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let values = try files().compactMap { url -> OTCResearchRecord? in
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(OTCResearchRecord.self, from: data),
                  record.isValid else { return nil }
            return record
        }.sorted {
            if $0.input.evaluatedAt != $1.input.evaluatedAt {
                return $0.input.evaluatedAt < $1.input.evaluatedAt
            }
            return $0.signal.sourceSnapshotID < $1.signal.sourceSnapshotID
        }
        return Array(values.suffix(max(0, limit)))
    }

    public func latest(for instrumentID: String) throws -> OTCResearchSignal? {
        try records(limit: maximumRecords)
            .last { $0.signal.instrument.instrumentID == instrumentID }?
            .signal
    }

    private func files() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func prune() {
        let all = (try? files()) ?? []
        guard all.count > maximumRecords else { return }
        for file in all.prefix(all.count - maximumRecords) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

public enum OTCResearchStoreError: Error, Sendable, Equatable {
    case invalidRecord
}
