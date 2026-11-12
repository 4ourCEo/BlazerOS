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

    public func record(_ rehearsal: AdaptiveMarketRehearsalRecord) throws {
        guard rehearsal.validation().isEmpty else { throw ScanError.failed("Invalid adaptive rehearsal") }
        try writeOnceOrVerify(rehearsal, directory: "adaptive-rehearsals", name: rehearsal.id)
    }

    public func adaptiveRehearsals() throws -> [AdaptiveMarketRehearsalRecord] {
        try loadNamed(AdaptiveMarketRehearsalRecord.self, directory: "adaptive-rehearsals").map(\.1)
    }

    /// Stores executable V3 spot evidence separately from legacy midpoint outcomes.
    /// Replaying the same ID is accepted only when the complete record is identical.
    public func record(_ outcome: V3DurableSpotOutcome) throws {
        guard outcome.validation().isEmpty,
              outcome.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid V3 spot outcome")
        }
        try writeOnceOrVerify(outcome, directory: "v3-spot-outcomes", name: outcome.id)
    }

    /// Immutable V3 plan snapshots use their identity as the storage key. A later
    /// lifecycle change must be represented by a new plan/event, never by mutation.
    public func record(_ plan: V3TradePlan) throws {
        guard plan.validation().isEmpty,
              plan.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid V3 trade plan")
        }
        try writeOnceOrVerify(plan, directory: "v3-trade-plans", name: plan.id)
    }

    public func v3TradePlans() throws -> [V3TradePlan] {
        let named = try loadNamed(V3TradePlan.self, directory: "v3-trade-plans")
        for (_, plan) in named where !plan.validation().isEmpty {
            throw ScanError.failed("Invalid V3 trade plan: \(plan.id)")
        }
        return named.map(\.1)
    }

    /// ForwardTest-facing V3 path: evaluate executable sides first, then persist the
    /// complete provenance envelope. Missing exit evidence remains UNRESOLVED.
    @discardableResult
    public func recordV3SpotOutcome(plan: V3TradePlan, entry: V3MarketObservation?,
                                    exit: V3MarketObservation?, recordedAt: Date) throws
        -> V3DurableSpotOutcome {
        guard plan.validation().isEmpty else { throw ScanError.failed("Invalid V3 trade plan") }
        guard let provenance = entry ?? exit,
              provenance.instrument == plan.instrument else {
            throw ScanError.failed("V3 observation instrument mismatch")
        }
        let evaluation = V3SpotOutcomeEvaluator.evaluate(side: plan.side, units: plan.units,
            entry: entry, exit: exit)
        let exitID = exit?.id ?? "missing-exit"
        let outcome = V3DurableSpotOutcome(id: "\(plan.id)-\(exitID)",
            planID: plan.id, instrument: plan.instrument, provider: provenance.provider,
            environment: provenance.environment, entryObservation: entry,
            exitObservation: exit, evaluation: evaluation,
            strategyVersion: plan.strategyVersion, engineVersion: plan.engineVersion,
            recordedAt: recordedAt)
        try record(outcome)
        return outcome
    }

    public func v3SpotOutcomes() throws -> [V3DurableSpotOutcome] {
        let named = try loadNamed(V3DurableSpotOutcome.self, directory: "v3-spot-outcomes")
        for (_, outcome) in named where !outcome.validation().isEmpty {
            throw ScanError.failed("Invalid V3 spot outcome: \(outcome.id)")
        }
        return named.map(\.1)
    }

    /// Position lifecycle events are append-only evidence, separate from plans and outcomes.
    public func record(_ position: V3PositionRecord) throws {
        guard position.validation().isEmpty,
              position.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid V3 position record")
        }
        try writeOnceOrVerify(position, directory: "v3-position-events", name: position.id)
    }

    public func v3PositionRecords() throws -> [V3PositionRecord] {
        let named = try loadNamed(V3PositionRecord.self, directory: "v3-position-events")
        for (_, position) in named where !position.validation().isEmpty {
            throw ScanError.failed("Invalid V3 position record: \(position.id)")
        }
        return named.map(\.1).sorted { $0.updatedAt > $1.updatedAt }
    }

    public func record(_ entry: V3PlanEntryEvidence) throws {
        guard !entry.id.isEmpty, !entry.planID.isEmpty,
              entry.observation.validation(now: entry.observation.receivedAt).isEmpty else {
            throw ScanError.failed("Invalid V3 plan entry evidence")
        }
        try writeOnceOrVerify(entry, directory: "v3-plan-entry-evidence", name: entry.id)
    }

    public func v3PlanEntryEvidence() throws -> [V3PlanEntryEvidence] {
        try loadNamed(V3PlanEntryEvidence.self, directory: "v3-plan-entry-evidence").map(\.1)
    }

    public func record(_ outcome: V3StructuralOutcome) throws {
        guard outcome.validation().isEmpty,
              outcome.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid V3 structural outcome")
        }
        try writeOnceOrVerify(outcome, directory: "v3-structural-outcomes", name: outcome.id)
    }

    public func v3StructuralOutcomes() throws -> [V3StructuralOutcome] {
        let named = try loadNamed(V3StructuralOutcome.self, directory: "v3-structural-outcomes")
        for (_, outcome) in named where !outcome.validation().isEmpty {
            throw ScanError.failed("Invalid V3 structural outcome: \(outcome.id)")
        }
        return named.map(\.1)
    }

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
        let casesByDigest = Dictionary(uniqueKeysWithValues: cases.map {
            (StrategyValidationEngine.digest(of: $0), $0)
        })
        for (url, result) in named {
            guard url.deletingPathExtension().lastPathComponent == result.id,
                  result.id == StrategyValidationEngine.recordID(
                    caseDigest: result.caseDigest,
                    configurationDigest: result.configurationDigest),
                  let item = casesByDigest[result.caseDigest], item.id == result.caseID,
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

    private func writeOnceOrVerify<T: Codable>(_ value: T, directory: String, name: String) throws {
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ScanError.failed("Invalid research event ID")
        }
        let url = root.appendingPathComponent(directory).appendingPathComponent(name + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(value)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == encoded else {
                throw ScanError.failed("Research record identity conflict: \(name)")
            }
            return
        }
        try AtomicFile.write(encoded, to: url)
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
