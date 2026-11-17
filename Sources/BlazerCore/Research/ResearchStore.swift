import CryptoKit
import Foundation

public enum V3UserPositionReportError: Error, LocalizedError, Sendable, Equatable {
    case liveArchiveRequired
    case planUnavailable
    case invalidPlanBinding
    case invalidReport
    case legacyReportRequiresReview
    case existingReportRequiresCorrection
    case invalidCorrection
    case recordConflict
    case invalidPositionArchive

    public var errorDescription: String? {
        switch self {
        case .liveArchiveRequired: "User-reported positions are available only in the Live OANDA archive"
        case .planUnavailable: "The exact Live OANDA plan is unavailable"
        case .invalidPlanBinding: "The report does not match the selected plan"
        case .invalidReport: "The user-reported position details are invalid"
        case .legacyReportRequiresReview: "An older user report exists for this plan and needs review"
        case .existingReportRequiresCorrection: "A report already exists; use the correction action"
        case .invalidCorrection: "The correction does not match the current user report"
        case .recordConflict: "The report conflicts with stored evidence"
        case .invalidPositionArchive: "The position evidence archive is unavailable"
        }
    }
}

public enum V3UserPositionCloseError: Error, LocalizedError, Sendable, Equatable {
    case liveArchiveRequired, planUnavailable, positionUnavailable, invalidReport
    case chronologyInvalid, existingCloseRequiresCorrection, invalidCorrection
    case recordConflict, invalidCloseArchive

    public var errorDescription: String? {
        switch self {
        case .liveArchiveRequired: "User-reported closes are available only in the Live OANDA archive"
        case .planUnavailable: "The exact Live OANDA plan is unavailable"
        case .positionUnavailable: "The exact user-reported opening position is unavailable"
        case .invalidReport: "The user-reported close details are invalid"
        case .chronologyInvalid: "The reported close time is earlier than the referenced opening time"
        case .existingCloseRequiresCorrection: "A close report already exists; use the correction action"
        case .invalidCorrection: "The close correction does not match the current close report"
        case .recordConflict: "The close report conflicts with stored evidence"
        case .invalidCloseArchive: "The user-reported close archive is unavailable"
        }
    }
}

private struct UserReportedPositionCloseIdentity: Encodable {
    let positionID: String
    let planID: String
    let openingRecordID: String
    let predecessorID: String?
    let exitPrice: Double?
    let closedAt: Date?
}

private struct UserReportedPositionIdentity: Encodable {
    let positionID: String
    let predecessorID: String?
    let planID: String
    let instrument: String
    let side: V3SpotSide
    let units: Double
    let entryPrice: Double?
    let userReportedEnteredAt: Date?
}

public enum V3SetupLifecycleAppendResult: Sendable, Equatable {
    case appended
    case duplicate
    case generationSuperseded
}

public enum V3PlanEntryAppendResult: Sendable, Equatable {
    case appended(V3PlanEntryEvidence)
    case alreadyRecorded(V3PlanEntryEvidence)
    case generationSuperseded
}

public enum V3ShadowStructuralOutcomeAppendResult: Sendable, Equatable {
    case appended(V3StructuralOutcome)
    case alreadyRecorded(V3StructuralOutcome)
    case noTerminalTrigger
    case generationSuperseded
}

/// Serializes lifecycle read/validate/append operations across store actor instances
/// that address the same standardized research root.
public actor ResearchStoreLifecycleLockRegistry {
    public static let shared = ResearchStoreLifecycleLockRegistry()
    private var tails: [String: (ticket: UUID, task: Task<Void, Never>)] = [:]

    public func withLock<T: Sendable>(for key: String,
                                      operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let prior = tails[key]?.task
        let task = Task<T, Error> {
            await prior?.value
            return try await operation()
        }
        let tail = Task<Void, Never> { _ = try? await task.value }
        let ticket = UUID()
        tails[key] = (ticket, tail)
        do {
            let value = try await task.value
            if tails[key]?.ticket == ticket { tails.removeValue(forKey: key) }
            return value
        } catch {
            if tails[key]?.ticket == ticket { tails.removeValue(forKey: key) }
            throw error
        }
    }
}

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
        guard outcome.validation().isEmpty, Self.safeV3ID(outcome.id),
              Self.safeV3ID(outcome.planID),
              [outcome.entryObservation?.id, outcome.exitObservation?.id].compactMap({ $0 }).allSatisfy(Self.safeV3Reference) else {
            throw ScanError.failed("Invalid V3 spot outcome")
        }
        try writeOnceOrVerify(outcome, directory: "v3-spot-outcomes", name: outcome.id)
    }

    /// Immutable V3 plan snapshots use their identity as the storage key. A later
    /// lifecycle change must be represented by a new plan/event, never by mutation.
    public func record(_ plan: V3TradePlan) throws {
        guard plan.validation().isEmpty, Self.safeV3ID(plan.id),
              Self.safeV3Reference(plan.sourceObservationID), plan.evidenceIDs.allSatisfy(Self.safeV3ReferenceList) else {
            throw ScanError.failed("Invalid V3 trade plan")
        }
        try writeOnceOrVerify(plan, directory: "v3-trade-plans", name: plan.id)
    }

    public func v3TradePlans() throws -> [V3TradePlan] {
        let named = try loadNamed(V3TradePlan.self, directory: "v3-trade-plans")
        for (url, plan) in named {
            guard url.deletingPathExtension().lastPathComponent == plan.id,
                  Self.safeV3ID(plan.id), Self.safeV3Reference(plan.sourceObservationID),
                  plan.evidenceIDs.allSatisfy(Self.safeV3ReferenceList), plan.validation().isEmpty else {
                throw ScanError.failed("Invalid V3 trade plan: \(plan.id)")
            }
        }
        return named.map(\.1)
    }

    /// Append-only setup monitor history. Events are immutable and scoped by setup;
    /// conflicting ID reuse or ambiguous same-time transitions fail closed on write/replay.
    public func record(_ event: V3SetupLifecycleEvent) async throws {
        _ = try await record(event, shouldAppend: { true })
    }

    /// The optional gate runs inside the per-root transaction immediately before
    /// the append, after waiting for other ResearchStore instances and validating tail.
    @discardableResult
    public func record(_ event: V3SetupLifecycleEvent,
                       shouldAppend: @escaping @Sendable () async -> Bool) async throws -> V3SetupLifecycleAppendResult {
        // Swift actors serialize one instance only; different model refreshes can
        // construct separate stores for this same root. The shared lock covers the
        // entire read-tail, validation, replay check, and append transaction.
        let standardizedRoot = root.standardizedFileURL.path
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(for: standardizedRoot) { [self] in
            try await self.recordLifecycleUnlocked(event, shouldAppend: shouldAppend)
        }
    }

    private func recordLifecycleUnlocked(_ event: V3SetupLifecycleEvent,
                                         shouldAppend: @Sendable () async -> Bool) async throws -> V3SetupLifecycleAppendResult {
        guard event.validation().isEmpty, Self.safeV3ID(event.id), Self.safeV3ID(event.setupID),
              event.planID.map(Self.safeV3ID) ?? true,
              event.sourceObservationID.map(Self.safeV3Reference) ?? true,
              event.sourceBarIDs?.allSatisfy(Self.safeV3Reference) ?? true else {
            throw ScanError.failed("Invalid V3 setup lifecycle event")
        }
        let records = try loadNamed(V3SetupLifecycleEvent.self, directory: "v3-setup-lifecycle-events").map(\.1)
        if let existing = records.first(where: { $0.id == event.id }) {
            guard Self.sameLifecyclePayload(existing, event) else {
                throw ScanError.failed("Conflicting V3 setup lifecycle event ID: \(event.id)")
            }
            return .duplicate
        }
        if event.strategyID == "ORB_BREAK_RETEST_V1", let structureID = event.structureID,
           records.contains(where: {
               $0.strategyID == "ORB_BREAK_RETEST_V1" && $0.structureID == structureID
                   && $0.setupID != event.setupID
                   && [.confirmed, .invalidated, .setupExpired].contains($0.state)
           }) {
            throw ScanError.failed("ORB_STRUCTURE_SUPPRESSED")
        }
        let stream = records.filter { $0.setupID == event.setupID } + [event]
        guard V3SetupLifecycle.validationIssues(for: stream).isEmpty else {
            throw ScanError.failed("Invalid V3 setup lifecycle stream: \(event.setupID)")
        }
        guard V3SetupLifecycle.archiveValidationIssues(for: records + [event]).isEmpty else {
            throw ScanError.failed("Invalid V3 setup lifecycle archive")
        }
        guard await shouldAppend() else { return .generationSuperseded }
        try writeOnceOrVerify(event, directory: "v3-setup-lifecycle-events", name: event.id)
        return .appended
    }

    private static func sameLifecyclePayload(_ lhs: V3SetupLifecycleEvent,
                                             _ rhs: V3SetupLifecycleEvent) -> Bool {
        lhs.id == rhs.id && lhs.setupID == rhs.setupID && lhs.instrument == rhs.instrument
            && lhs.strategyID == rhs.strategyID && lhs.strategyVersion == rhs.strategyVersion
            && lhs.provider == rhs.provider && lhs.environment == rhs.environment
            && lhs.previousState == rhs.previousState && lhs.state == rhs.state
            && lhs.sourceObservationID == rhs.sourceObservationID && lhs.sourceTime == rhs.sourceTime
            && lhs.planID == rhs.planID && lhs.reason == rhs.reason
            && lhs.configurationDigest == rhs.configurationDigest && lhs.inputDigest == rhs.inputDigest
            && lhs.engineVersion == rhs.engineVersion && lhs.sourceBarIDs == rhs.sourceBarIDs
            && lhs.quoteSequence == rhs.quoteSequence && lhs.reasonCodes == rhs.reasonCodes
            && lhs.evidenceSchemaVersion == rhs.evidenceSchemaVersion && lhs.structureID == rhs.structureID
            && lhs.timeframeSeconds == rhs.timeframeSeconds
    }

    public func v3SetupLifecycleEvents() throws -> [V3SetupLifecycleEvent] {
        let named = try loadNamed(V3SetupLifecycleEvent.self, directory: "v3-setup-lifecycle-events")
        for (url, event) in named {
            guard url.deletingPathExtension().lastPathComponent == event.id,
                  Self.safeV3ID(event.id), Self.safeV3ID(event.setupID),
                  event.planID.map(Self.safeV3ID) ?? true,
                  event.sourceObservationID.map(Self.safeV3Reference) ?? true,
                  event.sourceBarIDs?.allSatisfy(Self.safeV3Reference) ?? true,
                  event.validation().isEmpty else {
                throw ScanError.failed("Invalid V3 setup lifecycle event: \(event.id)")
            }
        }
        let events = named.map(\.1)
        guard V3SetupLifecycle.archiveValidationIssues(for: events).isEmpty else {
            throw ScanError.failed("Invalid V3 setup lifecycle archive")
        }
        return events.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.id < $1.id
        }
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
        for (url, outcome) in named {
            guard url.deletingPathExtension().lastPathComponent == outcome.id,
                  Self.safeV3ID(outcome.id), Self.safeV3ID(outcome.planID),
                  [outcome.entryObservation?.id, outcome.exitObservation?.id].compactMap({ $0 }).allSatisfy(Self.safeV3Reference),
                  outcome.validation().isEmpty else {
                throw ScanError.failed("Invalid V3 spot outcome: \(outcome.id)")
            }
        }
        return named.map(\.1)
    }

    /// Position lifecycle events are append-only evidence, separate from plans and outcomes.
    public func record(_ position: V3PositionRecord) throws {
        guard position.validation().isEmpty, Self.safeV3ID(position.id),
              position.planID.map(Self.safeV3ID) ?? true,
              position.positionID == nil, position.supersedesRecordID == nil else {
            throw ScanError.failed("Invalid V3 position record")
        }
        try writeOnceOrVerify(position, directory: "v3-position-events", name: position.id)
    }

    /// Records one explicit user assertion for an exact Live OANDA plan. This is
    /// separate from a market observation and from every broker/order state.
    /// Read-plan, validate-chain, replay check, and append are serialized across
    /// ResearchStore instances for the same normalized archive root.
    @discardableResult
    public func recordUserReportedPosition(planID: String, units: Double,
                                           entryPrice: Double? = nil,
                                           userReportedEnteredAt: Date? = nil,
                                           updatedAt: Date,
                                           supersedesRecordID: String? = nil) async throws
        -> V3PositionRecord {
        guard root.lastPathComponent == "live-oanda" else {
            throw V3UserPositionReportError.liveArchiveRequired
        }
        let rootKey = root.standardizedFileURL.path
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(for: rootKey) { [self] in
            try await self.recordUserReportedPositionUnlocked(planID: planID, units: units,
                entryPrice: entryPrice, userReportedEnteredAt: userReportedEnteredAt,
                updatedAt: updatedAt, supersedesRecordID: supersedesRecordID)
        }
    }

    private func recordUserReportedPositionUnlocked(planID: String, units: Double,
                                                     entryPrice: Double?,
                                                     userReportedEnteredAt: Date?,
                                                     updatedAt: Date,
                                                     supersedesRecordID: String?) async throws
        -> V3PositionRecord {
        let now = Date()
        guard Self.safeV3ID(planID), units.isFinite, units > 0,
              entryPrice.map({ $0.isFinite && $0 > 0 }) ?? true,
              updatedAt.timeIntervalSince1970.isFinite,
              updatedAt <= now.addingTimeInterval(5),
              userReportedEnteredAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
            throw V3UserPositionReportError.invalidReport
        }
        let plans = try v3TradePlans()
        guard let plan = plans.first(where: { $0.id == planID }), plan.validation().isEmpty else {
            throw V3UserPositionReportError.planUnavailable
        }
        guard updatedAt.addingTimeInterval(5) >= plan.createdAt,
              userReportedEnteredAt.map({ $0 >= plan.createdAt && $0 <= updatedAt.addingTimeInterval(5) }) ?? true else {
            throw V3UserPositionReportError.invalidPlanBinding
        }

        let records = try v3PositionRecords()
        let positionID = Self.userPositionID(planID: planID)
        let samePlan = records.filter { $0.planID == planID }
        if samePlan.contains(where: {
            $0.state == .userReported && $0.provenance == .manualTradeReport && $0.positionID == nil
        }) {
            throw V3UserPositionReportError.legacyReportRequiresReview
        }

        let samePosition = records.filter { $0.positionID == positionID }
        let predecessor: V3PositionRecord?
        if let supersedesRecordID {
            guard Self.safeV3ID(supersedesRecordID),
                  let prior = samePosition.first(where: { $0.id == supersedesRecordID }),
                  prior.planID == planID, prior.instrument == plan.instrument,
                  prior.side == plan.side, prior.state == .userReported,
                  prior.provenance == .manualTradeReport,
                  prior.broker == nil, prior.brokerPositionID == nil,
                  prior.updatedAt <= updatedAt else {
                throw V3UserPositionReportError.invalidCorrection
            }
            predecessor = prior
        } else {
            predecessor = nil
        }

        let storedEnteredAt = userReportedEnteredAt.map {
            Date(timeIntervalSince1970: ($0.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        }
        let identity = UserReportedPositionIdentity(positionID: positionID,
            predecessorID: predecessor?.id, planID: planID, instrument: plan.instrument,
            side: plan.side, units: units, entryPrice: entryPrice,
            userReportedEnteredAt: storedEnteredAt)
        let id = "userposrev-\(Self.digest(identity))"
        let storedUpdatedAt = Date(timeIntervalSince1970:
            (updatedAt.timeIntervalSince1970 * 1_000).rounded() / 1_000)
        let record = V3PositionRecord(id: id, positionID: positionID, planID: plan.id,
            supersedesRecordID: predecessor?.id, instrument: plan.instrument,
            state: .userReported, side: plan.side, units: units,
            entryPrice: entryPrice, userReportedEnteredAt: storedEnteredAt,
            provenance: .manualTradeReport, updatedAt: storedUpdatedAt)
        if let existing = samePosition.first(where: { $0.id == id }) {
            guard Self.sameUserReportedPayload(existing, record) else {
                throw V3UserPositionReportError.recordConflict
            }
            return existing // Exact retry retains the original stored updatedAt.
        }
        guard !records.contains(where: { $0.id == id }) else {
            throw V3UserPositionReportError.recordConflict
        }
        if let predecessor {
            guard !samePosition.contains(where: { $0.supersedesRecordID == predecessor.id }) else {
                throw V3UserPositionReportError.invalidCorrection
            }
        } else if !samePosition.isEmpty {
            throw V3UserPositionReportError.existingReportRequiresCorrection
        }
        guard record.validation().isEmpty, Self.safeV3ID(record.id),
              Self.positionArchiveIssues(records + [record]).isEmpty else {
            throw V3UserPositionReportError.invalidReport
        }
        try writeOnceOrVerify(record, directory: "v3-position-events", name: record.id)
        return record
    }

    public func v3PositionRecords() throws -> [V3PositionRecord] {
        let named = try loadNamed(V3PositionRecord.self, directory: "v3-position-events")
        for (url, position) in named {
            guard url.deletingPathExtension().lastPathComponent == position.id,
                  Self.safeV3ID(position.id), position.planID.map(Self.safeV3ID) ?? true,
                  position.positionID.map(Self.safeV3ID) ?? true,
                  position.supersedesRecordID.map(Self.safeV3ID) ?? true,
                  position.validation().isEmpty else {
                throw ScanError.failed("Invalid V3 position record: \(position.id)")
            }
        }
        let records = named.map(\.1)
        guard Self.positionArchiveIssues(records).isEmpty else {
            throw ScanError.failed("Invalid V3 position correction archive")
        }
        return records.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Records an explicit user assertion that an already-opened position was
    /// closed outside BlazerOS. It is independent of broker and simulated state.
    @discardableResult
    public func recordUserReportedPositionClose(positionID: String, closedAt: Date? = nil,
                                                 exitPrice: Double? = nil, recordedAt: Date = Date(),
                                                 supersedesCloseID: String? = nil) async throws
        -> V3UserReportedPositionClose {
        guard root.standardizedFileURL.lastPathComponent == "live-oanda" else {
            throw V3UserPositionCloseError.liveArchiveRequired
        }
        let rootKey = root.standardizedFileURL.path
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(for: rootKey) { [self] in
            try await self.recordUserReportedPositionCloseUnlocked(positionID: positionID,
                closedAt: closedAt, exitPrice: exitPrice, recordedAt: recordedAt,
                supersedesCloseID: supersedesCloseID)
        }
    }

    private func recordUserReportedPositionCloseUnlocked(positionID: String, closedAt: Date?,
                                                           exitPrice: Double?, recordedAt: Date,
                                                           supersedesCloseID: String?) async throws
        -> V3UserReportedPositionClose {
        let now = Date()
        guard Self.safeV3ID(positionID), recordedAt.timeIntervalSince1970.isFinite,
              recordedAt <= now.addingTimeInterval(5),
              closedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              closedAt.map({ $0 <= recordedAt.addingTimeInterval(1) }) ?? true,
              exitPrice.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw V3UserPositionCloseError.invalidReport
        }
        let positions = try v3PositionRecords()
        let related = positions.filter { $0.positionID == positionID }
        let supersededPositions = Set(related.compactMap(\.supersedesRecordID))
        guard let openingLeaf = related.first(where: { !supersededPositions.contains($0.id) }),
              openingLeaf.state == .userReported,
              openingLeaf.provenance == .manualTradeReport,
              let planID = openingLeaf.planID,
              let plan = try v3TradePlans().first(where: { $0.id == planID }),
              plan.validation().isEmpty, openingLeaf.instrument == plan.instrument,
              openingLeaf.side == plan.side else {
            throw V3UserPositionCloseError.positionUnavailable
        }
        let existing = try v3UserReportedPositionCloses()
        let samePosition = existing.filter { $0.positionID == positionID }
        let predecessor: V3UserReportedPositionClose?
        let openingRecordID: String
        if let supersedesCloseID {
            guard Self.safeV3ID(supersedesCloseID),
                  let prior = samePosition.first(where: { $0.id == supersedesCloseID }),
                  prior.planID == planID else {
                throw V3UserPositionCloseError.invalidCorrection
            }
            let retryIdentity = UserReportedPositionCloseIdentity(positionID: positionID,
                planID: planID, openingRecordID: prior.openingRecordID,
                predecessorID: prior.id, exitPrice: exitPrice,
                closedAt: Self.millisecondDate(closedAt))
            let retryID = "userclose-\(Self.digest(retryIdentity))"
            if let retry = samePosition.first(where: { $0.id == retryID }) {
                let retryCandidate = V3UserReportedPositionClose(id: retryID,
                    positionID: positionID, planID: planID,
                    openingRecordID: prior.openingRecordID, supersedesCloseID: prior.id,
                    exitPrice: exitPrice, closedAt: Self.millisecondDate(closedAt),
                    recordedAt: retry.recordedAt)
                guard Self.sameUserReportedClosePayload(retry, retryCandidate) else {
                    throw V3UserPositionCloseError.recordConflict
                }
                return retry
            }
            guard let currentLeaf = Self.closeLeaf(in: samePosition),
                  currentLeaf.id == supersedesCloseID else {
                throw V3UserPositionCloseError.invalidCorrection
            }
            predecessor = prior
            openingRecordID = prior.openingRecordID
        } else {
            if let existingRoot = samePosition.first(where: { $0.supersedesCloseID == nil }) {
                let retryIdentity = UserReportedPositionCloseIdentity(positionID: positionID,
                    planID: planID, openingRecordID: existingRoot.openingRecordID,
                    predecessorID: nil, exitPrice: exitPrice,
                    closedAt: Self.millisecondDate(closedAt))
                let retryID = "userclose-\(Self.digest(retryIdentity))"
                if let retry = samePosition.first(where: { $0.id == retryID }) {
                    let retryCandidate = V3UserReportedPositionClose(id: retryID,
                        positionID: positionID, planID: planID,
                        openingRecordID: existingRoot.openingRecordID, exitPrice: exitPrice,
                        closedAt: Self.millisecondDate(closedAt), recordedAt: retry.recordedAt)
                    guard Self.sameUserReportedClosePayload(retry, retryCandidate) else {
                        throw V3UserPositionCloseError.recordConflict
                    }
                    return retry
                }
                throw V3UserPositionCloseError.existingCloseRequiresCorrection
            }
            predecessor = nil
            openingRecordID = openingLeaf.id
        }
        guard let openingRevision = related.first(where: { $0.id == openingRecordID }) else {
            throw V3UserPositionCloseError.positionUnavailable
        }
        if let closedAt, let enteredAt = openingRevision.userReportedEnteredAt, closedAt < enteredAt {
            throw V3UserPositionCloseError.chronologyInvalid
        }
        let identity = UserReportedPositionCloseIdentity(positionID: positionID, planID: planID,
            openingRecordID: openingRecordID, predecessorID: predecessor?.id,
            exitPrice: exitPrice, closedAt: Self.millisecondDate(closedAt))
        let id = "userclose-\(Self.digest(identity))"
        let record = V3UserReportedPositionClose(id: id, positionID: positionID, planID: planID,
            openingRecordID: openingRecordID, supersedesCloseID: predecessor?.id,
            exitPrice: exitPrice, closedAt: Self.millisecondDate(closedAt),
            recordedAt: Self.millisecondDate(recordedAt) ?? recordedAt)
        if let duplicate = samePosition.first(where: { $0.id == id }) {
            guard Self.sameUserReportedClosePayload(duplicate, record) else {
                throw V3UserPositionCloseError.recordConflict
            }
            return duplicate
        }
        guard record.validation().isEmpty, Self.safeV3ID(record.id),
              Self.closeArchiveIssues(existing + [record], positions: positions).isEmpty else {
            throw V3UserPositionCloseError.invalidReport
        }
        try writeOnceOrVerify(record, directory: "v3-user-position-closes", name: record.id)
        return record
    }

    public func v3UserReportedPositionCloses() throws -> [V3UserReportedPositionClose] {
        let positions = try v3PositionRecords()
        let named = try loadNamed(V3UserReportedPositionClose.self, directory: "v3-user-position-closes")
        for (url, close) in named {
            guard url.deletingPathExtension().lastPathComponent == close.id,
                  [close.id, close.positionID, close.planID, close.openingRecordID]
                    .allSatisfy(Self.safeV3ID),
                  close.supersedesCloseID.map(Self.safeV3ID) ?? true,
                  close.validation().isEmpty else {
                throw ScanError.failed("Invalid user-reported position close: \(close.id)")
            }
        }
        let records = named.map(\.1)
        guard Self.closeArchiveIssues(records, positions: positions).isEmpty else {
            throw ScanError.failed("Invalid user-reported position close archive")
        }
        return records.sorted { $0.recordedAt > $1.recordedAt }
    }

    public func record(_ entry: V3PlanEntryEvidence) throws {
        guard root.standardizedFileURL.lastPathComponent != "live-oanda" else {
            throw ScanError.failed("Live entry evidence requires the exact-plan observation writer")
        }
        guard Self.v3PlanEntryEvidenceIssues(entry).isEmpty else {
            throw ScanError.failed("Invalid V3 plan entry evidence")
        }
        try writeOnceOrVerify(entry, directory: "v3-plan-entry-evidence", name: entry.id)
    }

    /// Records the first eligible Live OANDA shadow-entry quote for an exact,
    /// already persisted plan. The per-root lock serializes this with other
    /// store instances and the gate runs immediately before the immutable append.
    public func recordLivePlanEntryObservation(planID: String,
        observation: V3MarketObservation, recordedAt: Date,
        shouldAppend: @escaping @Sendable () async -> Bool) async throws -> V3PlanEntryAppendResult {
        guard root.standardizedFileURL.lastPathComponent == "live-oanda" else {
            throw ScanError.failed("Live OANDA archive required")
        }
        let rootKey = root.standardizedFileURL.path
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(for: rootKey) { [self] in
            try await self.recordLivePlanEntryObservationUnlocked(planID: planID,
                observation: observation, recordedAt: recordedAt, shouldAppend: shouldAppend)
        }
    }

    private func recordLivePlanEntryObservationUnlocked(planID: String,
        observation: V3MarketObservation, recordedAt: Date,
        shouldAppend: @Sendable () async -> Bool) async throws -> V3PlanEntryAppendResult {
            let plans = try v3TradePlans()
            guard let plan = plans.first(where: { $0.id == planID }),
                  plan.instrument == observation.instrument,
                  plan.state == .validated,
                  let deviation = plan.maxEntryDeviation,
                  observation.provider.uppercased() == "OANDA",
                  observation.environment == .oandaLive,
                  observation.sourceTime >= plan.createdAt,
                  observation.validation(now: observation.receivedAt, maxAge: 5).isEmpty,
                  observation.spread <= plan.maxSpread else {
                throw ScanError.failed("Live entry observation does not match the persisted plan")
            }
            let executable = plan.side == .long ? observation.ask : observation.bid
            let lower = plan.entryPrice - deviation
            let upper = plan.entryPrice + deviation
            guard executable >= lower, executable <= upper,
                  executable > min(plan.stopPrice, plan.targetPrice),
                  executable < max(plan.stopPrice, plan.targetPrice) else {
                throw ScanError.failed("Live entry observation is outside the plan entry band")
            }
            let lifecycle = try v3SetupLifecycleEvents()
            if let confirmed = lifecycle.first(where: { $0.planID == plan.id && $0.state == .confirmed }),
               lifecycle.contains(where: { $0.setupID == confirmed.setupID
                   && [.invalidated, .setupExpired].contains($0.state)
                   && ($0.sourceTime ?? .distantFuture) <= observation.sourceTime }) {
                throw ScanError.failed("Live entry observation follows terminal setup evidence")
            }
            let existing = try v3PlanEntryEvidence().filter { $0.planID == plan.id }
            guard existing.count <= 1 else { throw ScanError.failed("Multiple entry observations for plan") }
            if let entry = existing.first { return .alreadyRecorded(entry) }
            let digest = SHA256.hash(data: Data(plan.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let entry = V3PlanEntryEvidence(id: "live-entry-\(digest)", planID: plan.id,
                observation: observation, quality: .observed, recordedAt: recordedAt)
            guard Self.v3PlanEntryEvidenceIssues(entry).isEmpty else {
                throw ScanError.failed("Invalid Live plan entry observation")
            }
            guard await shouldAppend() else { return .generationSuperseded }
            try writeOnceOrVerify(entry, directory: "v3-plan-entry-evidence", name: entry.id)
            return .appended(entry)
    }

    public func v3PlanEntryEvidence() throws -> [V3PlanEntryEvidence] {
        let named = try loadNamed(V3PlanEntryEvidence.self, directory: "v3-plan-entry-evidence")
        for (url, entry) in named {
            guard url.deletingPathExtension().lastPathComponent == entry.id,
                  Self.v3PlanEntryEvidenceIssues(entry).isEmpty else {
                throw ScanError.failed("Invalid V3 plan entry evidence: \(entry.id)")
            }
        }
        return named.map(\.1)
    }

    public func record(_ outcome: V3StructuralOutcome) throws {
        guard root.standardizedFileURL.lastPathComponent != "live-oanda" else {
            throw ScanError.failed("Live structural outcomes require the exact-plan shadow writer")
        }
        guard outcome.validation().isEmpty, Self.safeV3ID(outcome.id),
              Self.safeV3ID(outcome.planID),
              [outcome.entryObservation?.id, outcome.exitObservation?.id].compactMap({ $0 }).allSatisfy(Self.safeV3Reference) else {
            throw ScanError.failed("Invalid V3 structural outcome")
        }
        try writeOnceOrVerify(outcome, directory: "v3-structural-outcomes", name: outcome.id)
    }

    public func v3StructuralOutcomes() throws -> [V3StructuralOutcome] {
        let named = try loadNamed(V3StructuralOutcome.self, directory: "v3-structural-outcomes")
        for (url, outcome) in named {
            guard url.deletingPathExtension().lastPathComponent == outcome.id,
                  Self.safeV3ID(outcome.id), Self.safeV3ID(outcome.planID),
                  [outcome.entryObservation?.id, outcome.exitObservation?.id].compactMap({ $0 }).allSatisfy(Self.safeV3Reference),
                  outcome.validation().isEmpty else {
                throw ScanError.failed("Invalid V3 structural outcome: \(outcome.id)")
            }
        }
        return named.map(\.1)
    }

    /// Persists only a terminal simulated market-path result for the exact Live
    /// plan and observed entry reference. It does not represent a position close.
    public func recordLiveShadowStructuralOutcome(planID: String,
        exitObservation: V3MarketObservation, recordedAt: Date,
        shouldAppend: @escaping @Sendable () async -> Bool) async throws -> V3ShadowStructuralOutcomeAppendResult {
        guard root.standardizedFileURL.lastPathComponent == "live-oanda" else {
            throw ScanError.failed("Live OANDA archive required")
        }
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(
            for: root.standardizedFileURL.path) { [self] in
                try await self.recordLiveShadowStructuralOutcomeUnlocked(planID: planID,
                    exitObservation: exitObservation, recordedAt: recordedAt,
                    shouldAppend: shouldAppend)
            }
    }

    private func recordLiveShadowStructuralOutcomeUnlocked(planID: String,
        exitObservation: V3MarketObservation, recordedAt: Date,
        shouldAppend: @Sendable () async -> Bool) async throws -> V3ShadowStructuralOutcomeAppendResult {
        let plans = try v3TradePlans()
        guard let plan = plans.first(where: { $0.id == planID }),
              plan.state == .validated else {
            throw ScanError.failed("Exact validated Live plan unavailable")
        }
        let entries = try v3PlanEntryEvidence().filter { $0.planID == plan.id }
        guard entries.count == 1, let entry = entries.first,
              entry.quality == .observed,
              entry.observation.instrument == plan.instrument,
              entry.observation.provider == "OANDA",
              entry.observation.environment == .oandaLive,
              entry.observation.validation(now: entry.observation.receivedAt).isEmpty,
              entry.observation.sourceTime >= plan.createdAt,
              entry.observation.spread <= plan.maxSpread else {
            throw ScanError.failed("Exact observed Live entry reference unavailable")
        }
        guard let maxEntryDeviation = plan.maxEntryDeviation else {
            throw ScanError.failed("Persisted plan has no entry-deviation tolerance")
        }
        let executableEntry = plan.side == .long ? entry.observation.ask : entry.observation.bid
        guard executableEntry >= plan.entryPrice - maxEntryDeviation,
              executableEntry <= plan.entryPrice + maxEntryDeviation,
              executableEntry > min(plan.stopPrice, plan.targetPrice),
              executableEntry < max(plan.stopPrice, plan.targetPrice) else {
            throw ScanError.failed("Persisted entry reference is outside the plan structure")
        }
        guard exitObservation.instrument == plan.instrument,
              exitObservation.provider == "OANDA",
              exitObservation.environment == .oandaLive,
              exitObservation.validation(now: exitObservation.receivedAt, maxAge: 5).isEmpty,
              exitObservation.spread <= plan.maxSpread else {
            return .noTerminalTrigger
        }
        guard exitObservation.sourceTime > entry.observation.sourceTime,
              exitObservation.receivedAt > entry.observation.receivedAt else {
            return .noTerminalTrigger
        }

        let lifecycle = try v3SetupLifecycleEvents()
        let confirmations = lifecycle.filter { $0.planID == plan.id && $0.state == .confirmed }
        let terminalEvents = confirmations.flatMap { confirmed in
            lifecycle.filter { $0.setupID == confirmed.setupID
                && [.invalidated, .setupExpired].contains($0.state) }
        }
        if !terminalEvents.isEmpty {
            guard terminalEvents.allSatisfy({ $0.sourceTime != nil }),
                  let terminalSourceTime = terminalEvents.compactMap(\.sourceTime).min(),
                  exitObservation.sourceTime < terminalSourceTime else {
                return .noTerminalTrigger
            }
        }

        let evaluated = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry,
            exitQuotes: [exitObservation], asOf: exitObservation.receivedAt,
            quality: .simulated, maximumEvidenceAge: 5,
            entryFreshnessAtReceipt: true)
        guard [.winner, .loser].contains(evaluated.status) else { return .noTerminalTrigger }
        let identity = [plan.id, entry.id, evaluated.exitReason.rawValue,
                        exitObservation.id, String(exitObservation.sourceTime.timeIntervalSince1970)]
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let outcome = V3StructuralOutcome(id: "shadow-structural-\(digest)", planID: plan.id,
            instrument: plan.instrument, strategyVersion: plan.strategyVersion,
            engineVersion: plan.engineVersion, quality: .simulated, status: evaluated.status,
            exitReason: evaluated.exitReason, entryObservation: entry.observation,
            exitObservation: exitObservation, entryPrice: evaluated.entryPrice,
            exitPrice: evaluated.exitPrice, netPnl: evaluated.netPnl,
            spreadCost: evaluated.spreadCost, additionalCosts: evaluated.additionalCosts,
            recordedAt: recordedAt)
        guard outcome.validation().isEmpty, Self.safeV3ID(outcome.id), Self.safeV3ID(outcome.planID),
              Self.safeV3Reference(outcome.entryObservation?.id ?? ""),
              Self.safeV3Reference(outcome.exitObservation?.id ?? "") else {
            throw ScanError.failed("Invalid Live shadow structural outcome")
        }
        let existing = try v3StructuralOutcomes().filter { $0.planID == plan.id }
        guard existing.count <= 1 else { throw ScanError.failed("Multiple terminal outcomes for plan") }
        if let prior = existing.first {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            let path = root.appendingPathComponent("v3-structural-outcomes", isDirectory: true)
                .appendingPathComponent(prior.id + ".json")
            guard prior.id == outcome.id,
                  try Data(contentsOf: path) == encoder.encode(outcome) else {
                throw ScanError.failed("Conflicting terminal outcome for plan")
            }
            return .alreadyRecorded(prior)
        }
        guard await shouldAppend() else { return .generationSuperseded }
        try writeOnceOrVerify(outcome, directory: "v3-structural-outcomes", name: outcome.id)
        return .appended(outcome)
    }

    public func record(_ experiment: ResearchExperiment) throws {
        try writeOnce(experiment, directory: "experiments", name: experiment.id)
    }

    public func experiments() throws -> [ResearchExperiment] {
        try load(ResearchExperiment.self, directory: "experiments")
    }

    /// Append one immutable experiment attempt. Attempt numbers are allocated by this actor
    /// and cannot be reused, so rejected and superseded attempts remain in the audit trail.
    public func record(_ attempt: ResearchExperimentAttempt) throws {
        try validate(attempt)
        guard try experiments().contains(where: { $0.id == attempt.experimentID }) else {
            throw ScanError.failed("Research attempt references an unknown experiment")
        }
        let allExisting = try attempts()
        if let sameID = allExisting.first(where: { $0.id == attempt.id }) {
            guard sameID == attempt else {
                throw ScanError.failed("Research attempt ID already exists with different content")
            }
            return
        }
        let existing = allExisting.filter { $0.experimentID == attempt.experimentID }
        guard !existing.contains(where: { $0.attemptNumber == attempt.attemptNumber }),
              attempt.attemptNumber == existing.count + 1 else {
            throw ScanError.failed("Research attempt number must be the next immutable sequence")
        }
        if let supersedes = attempt.supersedesAttemptID,
           !existing.contains(where: { $0.id == supersedes }) {
            throw ScanError.failed("Superseded attempt must exist in the same experiment")
        }
        try writeOnce(attempt, directory: "experiment-attempts", name: attempt.id)
    }

    public func attempts(experimentID: String? = nil) throws -> [ResearchExperimentAttempt] {
        let named = try loadNamed(ResearchExperimentAttempt.self, directory: "experiment-attempts")
        for (url, attempt) in named where url.deletingPathExtension().lastPathComponent != attempt.id {
            throw ScanError.failed("Research attempt identity does not match its archive name")
        }
        let all = named.map(\.1)
        let knownExperiments = Set(try experiments().map(\.id))
        for attempt in all {
            try validate(attempt)
            guard knownExperiments.contains(attempt.experimentID) else {
                throw ScanError.failed("Research attempt references an unknown experiment")
            }
        }
        let grouped = Dictionary(grouping: all, by: \.experimentID)
        guard grouped.values.allSatisfy({ values in
            let numbers = values.map(\.attemptNumber)
            return Set(numbers).count == numbers.count
                && numbers.sorted() == Array(1...numbers.count)
        }) else {
            throw ScanError.failed("Research attempt sequence is corrupt")
        }
        return all.filter { experimentID == nil || $0.experimentID == experimentID }
            .sorted {
                $0.experimentID == $1.experimentID
                    ? $0.attemptNumber < $1.attemptNumber
                    : $0.experimentID < $1.experimentID
            }
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

    /// Append-only record of Live strategy decisions, kept apart from Practice
    /// rehearsal evidence. Repeated decision IDs must be byte-identical.
    public func record(_ decision: LiveStrategyDecision) throws {
        guard decision.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              decision.instrument.isEmpty == false,
              decision.plan?.validation().isEmpty ?? true else {
            throw ScanError.failed("Invalid Live strategy decision")
        }
        try writeOnceOrVerify(decision, directory: "live-strategy-decisions", name: decision.id)
    }

    public func liveStrategyDecisions() throws -> [LiveStrategyDecision] {
        let named = try loadNamed(LiveStrategyDecision.self, directory: "live-strategy-decisions")
        for (url, decision) in named where url.deletingPathExtension().lastPathComponent != decision.id
            || decision.instrument.isEmpty || !(decision.plan?.validation().isEmpty ?? true) {
            throw ScanError.failed("Invalid persisted Live strategy decision")
        }
        return named.map(\.1).sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
            return $0.id < $1.id
        }
    }

    private func validate(_ attempt: ResearchExperimentAttempt) throws {
        let nonempty = [attempt.id, attempt.experimentID, attempt.strategyID,
            attempt.strategyVersion, attempt.hypothesis, attempt.instrumentID,
            attempt.exitContract, attempt.benchmark, attempt.decisionRationale]
        let assumptions = [attempt.executionAssumptions.spread,
            attempt.executionAssumptions.slippage, attempt.executionAssumptions.entryDelay,
            attempt.executionAssumptions.financing, attempt.executionAssumptions.fillModel]
        let evidence = attempt.outcomeEvidence
        let countsValid = evidence.independentEligibleSetups >= 0 && evidence.resolved >= 0
            && evidence.ambiguous >= 0 && evidence.unresolved >= 0
            && evidence.resolved + evidence.ambiguous + evidence.unresolved
                <= evidence.independentEligibleSetups
        let expectationValid = [evidence.netExpectancyR, evidence.uncertaintyLowerR,
            evidence.uncertaintyUpperR].compactMap { $0 }.allSatisfy(\.isFinite)
        let boundsValid: Bool
        switch (evidence.uncertaintyLowerR, evidence.uncertaintyUpperR) {
        case (nil, nil): boundsValid = true
        case let (lower?, upper?): boundsValid = lower <= upper
        default: boundsValid = false
        }
        let uncertaintyMethodValid = evidence.uncertaintyLowerR == nil
            || !(evidence.uncertaintyMethod ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let assumptionsValid = assumptions.allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let archivesValid = !attempt.dataArchives.isEmpty
            && attempt.dataArchives.allSatisfy {
                !$0.sourceIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.archiveSHA256.count == 64 && $0.archiveSHA256.allSatisfy(\.isHexDigit)
            }
        let archiveIDs = attempt.dataArchives.map { "\($0.sourceIdentity):\($0.archiveSHA256)" }
        let rolesValid = !attempt.timeframeRoles.isEmpty && attempt.timeframeRoles.allSatisfy {
            !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let parametersValid = !attempt.parameterVariations.isEmpty
            && attempt.parameterVariations.allSatisfy {
                !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.isEmpty
            }
        guard nonempty.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              attempt.attemptNumber > 0, attempt.createdAt.timeIntervalSince1970.isFinite,
              assumptionsValid, archivesValid, Set(archiveIDs).count == archiveIDs.count,
              rolesValid, parametersValid, countsValid, expectationValid, boundsValid,
              uncertaintyMethodValid else {
            throw ScanError.failed("Invalid research experiment attempt")
        }
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

    private static func safeV3ID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    private static func userPositionID(planID: String) -> String {
        "userpos-\(digest(planID))"
    }

    private static func millisecondDate(_ value: Date?) -> Date? {
        value.map { Date(timeIntervalSince1970: ($0.timeIntervalSince1970 * 1_000).rounded() / 1_000) }
    }

    private static func closeLeaf(in records: [V3UserReportedPositionClose]) -> V3UserReportedPositionClose? {
        let superseded = Set(records.compactMap(\.supersedesCloseID))
        return records.first { !superseded.contains($0.id) }
    }

    private static func sameUserReportedClosePayload(_ lhs: V3UserReportedPositionClose,
                                                     _ rhs: V3UserReportedPositionClose) -> Bool {
        lhs.id == rhs.id && lhs.positionID == rhs.positionID && lhs.planID == rhs.planID
            && lhs.openingRecordID == rhs.openingRecordID
            && lhs.supersedesCloseID == rhs.supersedesCloseID
            && lhs.exitPrice == rhs.exitPrice && lhs.closedAt == rhs.closedAt
            && lhs.provenance == rhs.provenance
    }

    private static func closeArchiveIssues(_ records: [V3UserReportedPositionClose],
                                           positions: [V3PositionRecord]) -> [String] {
        var issues: [String] = []
        let positionsByID = Dictionary(grouping: positions, by: \.positionID)
        let groups = Dictionary(grouping: records, by: \.positionID)
        for (positionID, group) in groups {
            let ids = Set(group.map(\.id))
            let roots = group.filter { $0.supersedesCloseID == nil }
            if roots.count != 1 { issues.append("user_close_root_count") }
            if group.contains(where: { $0.positionID != positionID || !$0.validation().isEmpty }) {
                issues.append("user_close_invalid_record")
            }
            let openingRevisions = positionsByID[positionID] ?? []
            if group.contains(where: { close in
                close.planID != (openingRevisions.first?.planID ?? "")
                    || !openingRevisions.contains(where: { $0.id == close.openingRecordID })
            }) { issues.append("user_close_opening_revision_missing") }
            for close in group {
                if let closeTime = close.closedAt,
                   closeTime > close.recordedAt.addingTimeInterval(1) {
                    issues.append("user_close_time_after_report")
                }
                if let open = openingRevisions.first(where: { $0.id == close.openingRecordID }),
                   let closeTime = close.closedAt, let entryTime = open.userReportedEnteredAt,
                   closeTime < entryTime { issues.append("user_close_chronology_invalid") }
                if let predecessorID = close.supersedesCloseID {
                    guard let predecessor = group.first(where: { $0.id == predecessorID }),
                          predecessor.planID == close.planID,
                          predecessor.openingRecordID == close.openingRecordID,
                          predecessor.recordedAt <= close.recordedAt else {
                        issues.append("user_close_invalid_predecessor")
                        continue
                    }
                }
            }
            let successors = group.compactMap(\.supersedesCloseID).reduce(into: [String: Int]()) {
                $0[$1, default: 0] += 1
            }
            if successors.values.contains(where: { $0 > 1 }) { issues.append("user_close_branch") }
            if group.contains(where: { $0.supersedesCloseID.map { !ids.contains($0) } ?? false }) {
                issues.append("user_close_missing_predecessor")
            }
            if let root = roots.first {
                var visited: Set<String> = []
                var current: V3UserReportedPositionClose? = root
                while let item = current, visited.insert(item.id).inserted {
                    current = group.first(where: { $0.supersedesCloseID == item.id })
                }
                if visited.count != group.count { issues.append("user_close_disconnected_chain") }
            }
        }
        return Array(Set(issues)).sorted()
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = (try? encoder.encode(value)) ?? Data(String(describing: value).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sameUserReportedPayload(_ lhs: V3PositionRecord,
                                                _ rhs: V3PositionRecord) -> Bool {
        func sameInstant(_ left: Date?, _ right: Date?) -> Bool {
            guard let left, let right else { return left == nil && right == nil }
            return Int64((left.timeIntervalSince1970 * 1_000).rounded())
                == Int64((right.timeIntervalSince1970 * 1_000).rounded())
        }
        return lhs.id == rhs.id && lhs.positionID == rhs.positionID
            && lhs.supersedesRecordID == rhs.supersedesRecordID
            && lhs.planID == rhs.planID && lhs.instrument == rhs.instrument
            && lhs.state == rhs.state && lhs.side == rhs.side && lhs.units == rhs.units
            && lhs.entryPrice == rhs.entryPrice
            && sameInstant(lhs.userReportedEnteredAt, rhs.userReportedEnteredAt)
            && lhs.broker == rhs.broker && lhs.brokerPositionID == rhs.brokerPositionID
            && lhs.exitPrice == rhs.exitPrice && lhs.provenance == rhs.provenance
    }

    private static func positionArchiveIssues(_ records: [V3PositionRecord]) -> [String] {
        var issues: [String] = []
        let keyed = records.filter { $0.positionID != nil }
        var groups: [String: [V3PositionRecord]] = [:]
        for record in keyed {
            guard let positionID = record.positionID else { continue }
            if !safeV3ID(positionID) || !safeV3ID(record.id)
                || !(record.planID.map(safeV3ID) ?? false)
                || record.validation().isEmpty == false {
                issues.append("invalid_user_position_record")
            }
            guard positionID == userPositionID(planID: record.planID ?? "") else {
                issues.append("user_position_id_mismatch")
                continue
            }
            groups[positionID, default: []].append(record)
        }
        for group in groups.values {
            guard let first = group.first else { continue }
            if group.contains(where: {
                $0.planID != first.planID || $0.instrument != first.instrument || $0.side != first.side
                    || $0.state != .userReported || $0.provenance != .manualTradeReport
                    || $0.broker != nil || $0.brokerPositionID != nil || $0.exitPrice != nil
            }) { issues.append("user_position_identity_changed") }
            let ids = group.map(\.id)
            if Set(ids).count != ids.count { issues.append("user_position_duplicate_record_id") }
            let groupIDs = Set(ids)
            let roots = group.filter { $0.supersedesRecordID == nil }
            if roots.count != 1 { issues.append("user_position_root_count") }
            var successorCount: [String: Int] = [:]
            for record in group {
                guard let predecessorID = record.supersedesRecordID else { continue }
                successorCount[predecessorID, default: 0] += 1
                guard let predecessor = group.first(where: { $0.id == predecessorID }),
                      predecessor.positionID == record.positionID,
                      predecessor.planID == record.planID,
                      predecessor.instrument == record.instrument,
                      predecessor.side == record.side,
                      predecessor.state == .userReported,
                      predecessor.provenance == .manualTradeReport,
                      predecessor.updatedAt <= record.updatedAt else {
                    issues.append("user_position_invalid_predecessor")
                    continue
                }
                if predecessor.broker != nil || predecessor.brokerPositionID != nil {
                    issues.append("user_position_supersedes_broker_record")
                }
            }
            if successorCount.values.contains(where: { $0 > 1 }) {
                issues.append("user_position_branching_correction")
            }
            if group.contains(where: { $0.supersedesRecordID.map({ !groupIDs.contains($0) }) ?? false }) {
                issues.append("user_position_missing_predecessor")
            }
            if let root = roots.first {
                var visited: Set<String> = []
                var current: V3PositionRecord? = root
                while let record = current {
                    guard visited.insert(record.id).inserted else {
                        issues.append("user_position_correction_cycle")
                        break
                    }
                    current = group.first(where: { $0.supersedesRecordID == record.id })
                }
                if visited.count != group.count { issues.append("user_position_disconnected_correction_chain") }
            }
        }
        return Array(Set(issues)).sorted()
    }

    /// Reference identities are not filenames and may include an instrument separator.
    /// Slash-separated segments remain bounded to safe ASCII tokens with no traversal.
    private static func safeV3Reference(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let segments = value.split(separator: "/", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            !segment.isEmpty && segment != "." && segment != ".."
                && segment.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0)
                        || (97...122).contains($0) || $0 == 45 || $0 == 95
                }
        }
    }

    private static func safeV3ReferenceList(_ value: String) -> Bool {
        !value.isEmpty && value.split(separator: ",", omittingEmptySubsequences: false).allSatisfy {
            safeV3Reference(String($0))
        }
    }

    private static func v3PlanEntryEvidenceIssues(_ entry: V3PlanEntryEvidence) -> [String] {
        guard safeV3ID(entry.id), safeV3ID(entry.planID),
              safeV3Reference(entry.observation.id),
              entry.recordedAt.timeIntervalSince1970.isFinite,
              entry.observation.validation(now: entry.observation.receivedAt).isEmpty else {
            return ["invalid_entry_evidence"]
        }
        return []
    }
}
