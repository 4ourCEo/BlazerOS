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

    public func record(_ experiment: ResearchExperiment) throws {
        try writeOnce(experiment, directory: "experiments", name: experiment.id)
    }

    public func experiments() throws -> [ResearchExperiment] {
        try load(ResearchExperiment.self, directory: "experiments")
    }

    public func record(_ report: ResearchExperimentReport) throws {
        try writeOnce(report, directory: "reports", name: report.id)
    }

    public func reports() throws -> [ResearchExperimentReport] {
        try load(ResearchExperimentReport.self, directory: "reports")
    }

    /// Rolling checkpoints are isolated research records. They cannot carry entry authority.
    public func record(_ result: RollingRevalidationResult) throws {
        guard result.researchOnly, !result.mayAuthorizeEntry,
              result.identity.count == 64,
              result.identity.allSatisfy({ $0.isHexDigit }) else {
            throw ScanError.failed("Invalid rolling research result")
        }
        try writeOnce(result, directory: "rolling-revalidation", name: result.identity)
    }

    public func rollingRevalidationResults() throws -> [RollingRevalidationResult] {
        try load(RollingRevalidationResult.self, directory: "rolling-revalidation")
    }

    /// Validation-stage records share the existing immutable research archive. They are never
    /// read by the live engine, ledger, entry gate, or CloudKit mapper.
    public func record(_ result: StrategyValidationRecord) throws {
        guard result.engineSHA == EngineIdentity.pinnedSHA1,
              result.id.count == 64, result.id.allSatisfy(\.isHexDigit),
              result.id == StrategyValidationEngine.recordID(
                caseDigest: result.caseDigest,
                configurationDigest: result.configurationDigest),
              result.inputDigest.count == 64, result.inputDigest.allSatisfy(\.isHexDigit),
              result.caseDigest.count == 64, result.caseDigest.allSatisfy(\.isHexDigit),
              result.configurationDigest.count == 64,
              result.configurationDigest.allSatisfy(\.isHexDigit),
              !result.caseID.isEmpty,
              (result.configuration.map {
                  StrategyValidationEngine.digest(of: $0) == result.configurationDigest
              } ?? false),
              result.executionKind == (result.stage == .liveObservation ? .recordedManual : .simulated),
              !result.isVenueOutcome || (result.stage == .liveObservation
                  && !(result.venueEventID ?? "").isEmpty) else {
            throw ScanError.failed("Invalid strategy validation record")
        }
        try writeOnce(result, directory: "strategy-validation", name: result.id)
    }

    public func strategyValidationRecords() throws -> [StrategyValidationRecord] {
        let named = try loadNamed(StrategyValidationRecord.self, directory: "strategy-validation")
        let cases = try strategyValidationCases()
        let casesByID = Dictionary(grouping: cases, by: \.id)
        for (url, result) in named {
            guard url.deletingPathExtension().lastPathComponent == result.id,
                  result.id == StrategyValidationEngine.recordID(
                    caseDigest: result.caseDigest,
                    configurationDigest: result.configurationDigest),
                  let matches = casesByID[result.caseID], matches.count == 1,
                  let item = matches.first,
                  StrategyValidationEngine.digest(of: item) == result.caseDigest,
                  try ResearchEvent.digest(of: item.input) == result.inputDigest else {
                throw ScanError.failed("Strategy validation record identity mismatch: \(result.caseID)")
            }
            if let configuration = result.configuration,
               StrategyValidationEngine.digest(of: configuration) != result.configurationDigest {
                throw ScanError.failed("Strategy validation configuration mismatch: \(result.caseID)")
            }
        }
        return named.map(\.1)
    }

    public func record(_ item: StrategyValidationCase) throws {
        let digest = StrategyValidationEngine.digest(of: item)
        try writeOnce(item, directory: "strategy-validation-cases", name: digest)
    }

    public func strategyValidationCases() throws -> [StrategyValidationCase] {
        let named = try loadNamed(StrategyValidationCase.self, directory: "strategy-validation-cases")
        for (url, item) in named where url.deletingPathExtension().lastPathComponent
            != StrategyValidationEngine.digest(of: item) {
            throw ScanError.failed("Strategy validation case identity mismatch: \(item.id)")
        }
        return named.map(\.1)
    }

    public func record(_ campaign: ForwardValidationCampaign) throws {
        try writeOnce(campaign, directory: "campaigns", name: campaign.id)
    }

    public func campaigns() throws -> [ForwardValidationCampaign] {
        try load(ForwardValidationCampaign.self, directory: "campaigns")
    }

    public func record(_ gap: ResearchGap) throws {
        try writeOnce(gap, directory: "gap-register", name: gap.id)
    }

    public func gaps() throws -> [ResearchGap] {
        try load(ResearchGap.self, directory: "gap-register")
    }

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
        try loadNamed(type, directory: directory).map(\.1)
    }

    private func loadNamed<T: Decodable>(_ type: T.Type, directory: String) throws -> [(URL, T)] {
        let path = root.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        // A corrupt record is an explicit error, never silently converted into missing data.
        return try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0, try decoder.decode(type, from: Data(contentsOf: $0))) }
    }
}
