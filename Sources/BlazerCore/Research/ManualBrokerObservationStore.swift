import Foundation

public actor ManualBrokerObservationStore {
    private let root: URL

    public init(root: URL) { self.root = root }

    public func record(_ observation: ManualBrokerChartObservation) throws {
        guard observation.isValid,
              observation.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ShadowMarketDataError.invalidPoint
        }
        let directory = root.appendingPathComponent("manual-broker-chart", isDirectory: true)
        let url = directory.appendingPathComponent(observation.id + ".json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try AtomicFile.write(encoder.encode(observation), to: url)
    }

    public func observations() throws -> [ManualBrokerChartObservation] {
        let directory = root.appendingPathComponent("manual-broker-chart", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(ManualBrokerChartObservation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.observedAt < $1.observedAt }
    }
}
