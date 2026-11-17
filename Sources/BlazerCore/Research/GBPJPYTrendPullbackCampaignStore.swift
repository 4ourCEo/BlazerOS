import CryptoKit
import Foundation
import Darwin

public enum GBPJPYTrendCampaignError: Error, Sendable, Equatable {
    case invalidDefinition([String])
    case invalidTransaction([String])
    case staleRevision(expected: UInt64, actual: UInt64)
    case cursorConflict(expected: String, actual: String)
    case transactionConflict(String)
    case corruptSnapshot([String])
    case lockTimedOut
    case persistenceFailure(String)
}

/// Immutable identity for one strategy profile, engine build, provider, and session.
/// A new session or profile revision must use a new campaign identity.
public struct GBPJPYTrendPullbackCampaignDefinition: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let configuration: GBPJPYTrendPullbackConfiguration
    public let environment: String
    public let buildID: String
    public let codeDigest: String
    public let sessionID: String
    public let sessionOpen: Date
    public let sessionClose: Date

    public init(configuration: GBPJPYTrendPullbackConfiguration, environment: String,
                buildID: String, codeDigest: String, sessionID: String,
                sessionOpen: Date, sessionClose: Date) {
        schemaVersion = 1
        self.configuration = configuration
        self.environment = environment
        self.buildID = buildID
        self.codeDigest = codeDigest
        self.sessionID = sessionID
        self.sessionOpen = sessionOpen
        self.sessionClose = sessionClose
    }

    public var campaignID: String { Self.hash(self) }

    public func validationIssues() -> [String] {
        var issues = configuration.validationIssues()
        if schemaVersion != 1 { issues.append("schema_version_invalid") }
        if !configuration.allowedEnvironments.contains(environment) { issues.append("environment_mismatch") }
        if buildID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("build_id_missing") }
        if !Self.validDigest(codeDigest) { issues.append("code_digest_invalid") }
        if sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("session_id_missing") }
        if !configuration.allowedSessions.contains(sessionID) { issues.append("campaign_session_not_allowed") }
        if !sessionOpen.timeIntervalSince1970.isFinite || !sessionClose.timeIntervalSince1970.isFinite
            || sessionClose <= sessionOpen { issues.append("session_interval_invalid") }
        if let zone = TimeZone(identifier: configuration.timeZoneID) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let open = calendar.dateComponents([.year, .month, .day], from: sessionOpen)
            let close = calendar.dateComponents([.year, .month, .day], from: sessionClose)
            if open != close { issues.append("campaign_crosses_session_date") }
        }
        return Array(Set(issues)).sorted()
    }

    fileprivate static func validDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    fileprivate static func hash<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = (try? encoder.encode(value)) ?? Data("encoding-failed".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct GBPJPYTrendPullbackCampaignBarPoint: Codable, Sendable, Equatable {
    public let id: String
    public let startTime: Date
    public init(id: String, startTime: Date) { self.id = id; self.startTime = startTime }
}

/// Ordered candidate-window identity. OHLC source evidence remains in discovery evidence;
/// this compact proof lets the store reject skipped, duplicated, or overlapping windows.
public struct GBPJPYTrendPullbackCampaignWindow: Codable, Sendable, Equatable {
    public let points: [GBPJPYTrendPullbackCampaignBarPoint]
    public let digest: String

    public init(points: [GBPJPYTrendPullbackCampaignBarPoint]) {
        self.points = points
        digest = GBPJPYTrendPullbackCampaignDefinition.hash(points)
    }

    public var firstBarID: String? { points.first?.id }
    public var lastBarID: String? { points.last?.id }
    public var start: Date? { points.first?.startTime }
    public var end: Date? { points.last?.startTime }
}

public struct GBPJPYTrendPullbackCampaignEvaluation: Codable, Sendable, Equatable {
    public struct Inputs: Codable, Sendable, Equatable {
        public let lowerBars: [GBPJPYTrendPullbackBar]
        public let higherBars: [GBPJPYTrendPullbackBar]
        public let quotes: [GBPJPYTrendPullbackQuote]
        public let contexts: [GBPJPYTrendPullbackContext]
        public let provenance: GBPJPYTrendPullbackProvenance?
        public let asOf: Date
        public let quoteCursor: GBPJPYTrendPullbackQuoteContinuationCursor
        public let quoteWindowAttestation: GBPJPYTrendPullbackQuoteWindowAttestation?
        public init(lowerBars: [GBPJPYTrendPullbackBar], higherBars: [GBPJPYTrendPullbackBar],
                    quotes: [GBPJPYTrendPullbackQuote], contexts: [GBPJPYTrendPullbackContext],
                    provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
                    quoteCursor: GBPJPYTrendPullbackQuoteContinuationCursor,
                    quoteWindowAttestation: GBPJPYTrendPullbackQuoteWindowAttestation?) {
            self.lowerBars = lowerBars; self.higherBars = higherBars; self.quotes = quotes
            self.contexts = contexts; self.provenance = provenance; self.asOf = asOf
            self.quoteCursor = quoteCursor; self.quoteWindowAttestation = quoteWindowAttestation
        }
    }
    public let eventID: String
    public let inputs: Inputs
    public let decision: GBPJPYTrendPullbackDecision
    public init(eventID: String, inputs: Inputs, decision: GBPJPYTrendPullbackDecision) {
        self.eventID = eventID; self.inputs = inputs; self.decision = decision
    }
}

public struct GBPJPYTrendPullbackCampaignProposal: Codable, Sendable, Equatable {
    public let expectedRevision: UInt64
    public let priorCursorDigest: String
    public let window: GBPJPYTrendPullbackCampaignWindow
    public let discovery: GBPJPYTrendPullbackDiscoveryEvidence
    public let evaluations: [GBPJPYTrendPullbackCampaignEvaluation]

    public init(expectedRevision: UInt64, priorCursorDigest: String,
                window: GBPJPYTrendPullbackCampaignWindow,
                discovery: GBPJPYTrendPullbackDiscoveryEvidence,
                evaluations: [GBPJPYTrendPullbackCampaignEvaluation]) {
        self.expectedRevision = expectedRevision
        self.priorCursorDigest = priorCursorDigest
        self.window = window
        self.discovery = discovery
        self.evaluations = evaluations.sorted { $0.eventID < $1.eventID }
    }

    func transactionID(campaignID: String) -> String {
        let payload = TransactionIdentity(campaignID: campaignID, expectedRevision: expectedRevision,
            priorCursorDigest: priorCursorDigest, windowDigest: window.digest,
            discoveryInputDigest: discovery.batch.inputDigest,
            evaluationInputDigests: evaluations.map(\.decision.inputDigest))
        return GBPJPYTrendPullbackCampaignDefinition.hash(payload)
    }

    private struct TransactionIdentity: Encodable {
        let campaignID: String
        let expectedRevision: UInt64
        let priorCursorDigest: String
        let windowDigest: String
        let discoveryInputDigest: String
        let evaluationInputDigests: [String]
    }
}

public struct GBPJPYTrendPullbackCampaignEventRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let descriptor: GBPJPYTrendPullbackBreakDescriptor
    public let discovery: GBPJPYTrendPullbackDiscoveryEvidence
    public let decision: GBPJPYTrendPullbackDecision
    public let quoteContinuationCursor: GBPJPYTrendPullbackQuoteContinuationCursor?

    fileprivate init(descriptor: GBPJPYTrendPullbackBreakDescriptor,
                     discovery: GBPJPYTrendPullbackDiscoveryEvidence,
                     decision: GBPJPYTrendPullbackDecision,
                     quoteContinuationCursor: GBPJPYTrendPullbackQuoteContinuationCursor?) {
        id = descriptor.id; self.descriptor = descriptor
        self.discovery = discovery; self.decision = decision
        self.quoteContinuationCursor = quoteContinuationCursor
    }

    public var isActive: Bool { decision.disposition == .active }
}

public struct GBPJPYTrendPullbackCampaignTransaction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let revision: UInt64
    public let previousSnapshotDigest: String
    public let proposal: GBPJPYTrendPullbackCampaignProposal
    public let evaluatedEvents: [GBPJPYTrendPullbackCampaignEventRecord]
    public let activeEventsAfter: [GBPJPYTrendPullbackCampaignEventRecord]
    public let cursorAfter: GBPJPYTrendPullbackEventCursor
    public let nextWindowStartAfter: Date
    public let digest: String

    fileprivate init(id: String, revision: UInt64, previousSnapshotDigest: String,
                     proposal: GBPJPYTrendPullbackCampaignProposal,
                     evaluatedEvents: [GBPJPYTrendPullbackCampaignEventRecord],
                     activeEventsAfter: [GBPJPYTrendPullbackCampaignEventRecord],
                     cursorAfter: GBPJPYTrendPullbackEventCursor,
                     nextWindowStartAfter: Date) {
        self.id = id; self.revision = revision; self.previousSnapshotDigest = previousSnapshotDigest
        self.proposal = proposal
        self.evaluatedEvents = evaluatedEvents.sorted { $0.id < $1.id }
        self.activeEventsAfter = activeEventsAfter.sorted { $0.id < $1.id }
        self.cursorAfter = cursorAfter; self.nextWindowStartAfter = nextWindowStartAfter
        digest = Self.makeDigest(id: id, revision: revision, previousSnapshotDigest: previousSnapshotDigest,
            proposal: proposal, evaluatedEvents: self.evaluatedEvents,
            activeEventsAfter: self.activeEventsAfter, cursorAfter: cursorAfter,
            nextWindowStartAfter: nextWindowStartAfter)
    }

    fileprivate var hasValidDigest: Bool {
        digest == Self.makeDigest(id: id, revision: revision,
            previousSnapshotDigest: previousSnapshotDigest, proposal: proposal,
            evaluatedEvents: evaluatedEvents, activeEventsAfter: activeEventsAfter,
            cursorAfter: cursorAfter, nextWindowStartAfter: nextWindowStartAfter)
    }

    private static func makeDigest(id: String, revision: UInt64, previousSnapshotDigest: String,
        proposal: GBPJPYTrendPullbackCampaignProposal,
        evaluatedEvents: [GBPJPYTrendPullbackCampaignEventRecord],
        activeEventsAfter: [GBPJPYTrendPullbackCampaignEventRecord],
        cursorAfter: GBPJPYTrendPullbackEventCursor,
        nextWindowStartAfter: Date) -> String {
        GBPJPYTrendPullbackCampaignDefinition.hash(DigestPayload(id: id, revision: revision,
            previousSnapshotDigest: previousSnapshotDigest, proposal: proposal,
            evaluatedEvents: evaluatedEvents, activeEventsAfter: activeEventsAfter,
            cursorAfter: cursorAfter, nextWindowStartAfter: nextWindowStartAfter))
    }

    private struct DigestPayload: Encodable {
        let id: String; let revision: UInt64; let previousSnapshotDigest: String
        let proposal: GBPJPYTrendPullbackCampaignProposal
        let evaluatedEvents: [GBPJPYTrendPullbackCampaignEventRecord]
        let activeEventsAfter: [GBPJPYTrendPullbackCampaignEventRecord]
        let cursorAfter: GBPJPYTrendPullbackEventCursor
        let nextWindowStartAfter: Date
    }
}

public struct GBPJPYTrendPullbackCampaignSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let definition: GBPJPYTrendPullbackCampaignDefinition
    public let revision: UInt64
    public let cursor: GBPJPYTrendPullbackEventCursor
    public let nextWindowStart: Date
    public let activeEvents: [GBPJPYTrendPullbackCampaignEventRecord]
    public let transactions: [GBPJPYTrendPullbackCampaignTransaction]
    public let digest: String

    fileprivate init(definition: GBPJPYTrendPullbackCampaignDefinition, revision: UInt64,
                     cursor: GBPJPYTrendPullbackEventCursor, nextWindowStart: Date,
                     activeEvents: [GBPJPYTrendPullbackCampaignEventRecord],
                     transactions: [GBPJPYTrendPullbackCampaignTransaction]) {
        schemaVersion = 1; self.definition = definition; self.revision = revision
        self.cursor = cursor; self.nextWindowStart = nextWindowStart
        self.activeEvents = activeEvents.sorted { $0.id < $1.id }
        self.transactions = transactions
        digest = Self.makeDigest(schemaVersion: 1, definition: definition, revision: revision,
            cursor: cursor, nextWindowStart: nextWindowStart, activeEvents: self.activeEvents,
            transactions: transactions)
    }

    fileprivate var hasValidDigest: Bool {
        digest == Self.makeDigest(schemaVersion: schemaVersion, definition: definition,
            revision: revision, cursor: cursor, nextWindowStart: nextWindowStart,
            activeEvents: activeEvents, transactions: transactions)
    }

    fileprivate func validationIssues() -> [String] {
        var issues = definition.validationIssues()
        if schemaVersion != 1 { issues.append("schema_version_invalid") }
        if !cursor.isValid { issues.append("cursor_invalid") }
        if !hasValidDigest { issues.append("snapshot_digest_invalid") }
        var priorCursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        var priorWindowStart = definition.sessionOpen
        var priorSnapshotDigest = GBPJPYTrendPullbackCampaignStore.genesisDigest(for: definition)
        var expectedActive: [String: GBPJPYTrendPullbackCampaignEventRecord] = [:]
        for (index, transaction) in transactions.enumerated() {
            if transaction.revision != UInt64(index + 1) { issues.append("revision_chain_broken") }
            if !transaction.hasValidDigest { issues.append("transaction_digest_invalid") }
            if transaction.previousSnapshotDigest != priorSnapshotDigest { issues.append("snapshot_chain_broken") }
            if transaction.proposal.expectedRevision != UInt64(index) { issues.append("proposal_revision_chain_broken") }
            if transaction.proposal.priorCursorDigest != priorCursor.digest { issues.append("cursor_chain_broken") }
            if transaction.proposal.window.start != priorWindowStart { issues.append("window_chain_broken") }
            issues += GBPJPYTrendPullbackCampaignStore.validateProposal(
                transaction.proposal, definition: definition, expectedStart: priorWindowStart,
                cursor: priorCursor, activeEvents: expectedActive)
            let nextCursor = GBPJPYTrendPullbackCampaignStore.cursorAfter(
                priorCursor, discovery: transaction.proposal.discovery)
            if transaction.cursorAfter != nextCursor { issues.append("cursor_transition_invalid") }
            if transaction.id != transaction.proposal.transactionID(campaignID: definition.campaignID) {
                issues.append("transaction_identity_invalid")
            }
            let expectedNext = GBPJPYTrendPullbackCampaignStore.nextWindowStart(
                transaction.proposal.window, definition: definition)
            if transaction.nextWindowStartAfter != expectedNext { issues.append("window_advance_invalid") }
            if !GBPJPYTrendPullbackCampaignStore.validateEventResults(
                transaction: transaction, previousActive: expectedActive,
                definition: definition) { issues.append("event_transition_invalid") }
            if Set(transaction.activeEventsAfter.map(\.id)).count == transaction.activeEventsAfter.count {
                expectedActive = Dictionary(transaction.activeEventsAfter.map { ($0.id, $0) },
                                            uniquingKeysWith: { first, _ in first })
            } else {
                expectedActive = [:]
            }
            priorCursor = nextCursor
            priorWindowStart = expectedNext
            priorSnapshotDigest = GBPJPYTrendPullbackCampaignSnapshot(definition: definition,
                revision: transaction.revision, cursor: nextCursor, nextWindowStart: expectedNext,
                activeEvents: transaction.activeEventsAfter,
                transactions: Array(transactions.prefix(index + 1))).digest
        }
        if revision != UInt64(transactions.count) { issues.append("snapshot_revision_mismatch") }
        if cursor != priorCursor { issues.append("snapshot_cursor_mismatch") }
        if nextWindowStart != priorWindowStart { issues.append("snapshot_window_mismatch") }
        if Set(activeEvents.map(\.id)).count != activeEvents.count { issues.append("active_event_duplicate") }
        if activeEvents != expectedActive.values.sorted(by: { $0.id < $1.id }) { issues.append("snapshot_active_events_mismatch") }
        if nextWindowStart > definition.sessionClose { issues.append("snapshot_beyond_session_close") }
        return Array(Set(issues)).sorted()
    }

    private static func makeDigest(schemaVersion: Int, definition: GBPJPYTrendPullbackCampaignDefinition,
        revision: UInt64, cursor: GBPJPYTrendPullbackEventCursor, nextWindowStart: Date,
        activeEvents: [GBPJPYTrendPullbackCampaignEventRecord],
        transactions: [GBPJPYTrendPullbackCampaignTransaction]) -> String {
        GBPJPYTrendPullbackCampaignDefinition.hash(DigestPayload(schemaVersion: schemaVersion,
            definition: definition, revision: revision, cursor: cursor, nextWindowStart: nextWindowStart,
            activeEvents: activeEvents, transactions: transactions))
    }
    private struct DigestPayload: Encodable {
        let schemaVersion: Int; let definition: GBPJPYTrendPullbackCampaignDefinition
        let revision: UInt64; let cursor: GBPJPYTrendPullbackEventCursor; let nextWindowStart: Date
        let activeEvents: [GBPJPYTrendPullbackCampaignEventRecord]
        let transactions: [GBPJPYTrendPullbackCampaignTransaction]
    }
}

public struct GBPJPYTrendPullbackCampaignReceipt: Sendable, Equatable {
    public enum Disposition: Sendable, Equatable { case committed, duplicate }
    public let disposition: Disposition
    public let transactionID: String
    public let revision: UInt64
    public let snapshotDigest: String
}

/// Local, research-only durable campaign storage. It is intentionally not called by
/// any selector, notification, or broker adapter.
public actor GBPJPYTrendPullbackCampaignStore {
    private let root: URL
    private let definition: GBPJPYTrendPullbackCampaignDefinition
    private let lockTimeout: TimeInterval
    private let snapshotWriter: @Sendable (Data, URL) throws -> Void
    private var snapshotURL: URL { root.appendingPathComponent(definition.campaignID + ".json") }
    private var lockURL: URL { root.appendingPathComponent(definition.campaignID + ".lock") }

    public init(root: URL, definition: GBPJPYTrendPullbackCampaignDefinition,
                lockTimeout: TimeInterval = 1.0) throws {
        try self.init(root: root, definition: definition, lockTimeout: lockTimeout,
                      snapshotWriter: { data, url in try AtomicFile.write(data, to: url) })
    }

    internal init(root: URL, definition: GBPJPYTrendPullbackCampaignDefinition,
                  lockTimeout: TimeInterval,
                  snapshotWriter: @escaping @Sendable (Data, URL) throws -> Void) throws {
        guard definition.validationIssues().isEmpty else {
            throw GBPJPYTrendCampaignError.invalidDefinition(definition.validationIssues())
        }
        guard lockTimeout.isFinite, lockTimeout > 0, lockTimeout <= 30 else {
            throw GBPJPYTrendCampaignError.invalidDefinition(["lock_timeout_invalid"])
        }
        self.root = root; self.definition = definition; self.lockTimeout = lockTimeout
        self.snapshotWriter = snapshotWriter
    }

    public func initialize() throws -> GBPJPYTrendPullbackCampaignSnapshot {
        let lock = try CampaignWriterLock(url: lockURL, timeout: lockTimeout)
        defer { lock.release() }
        if FileManager.default.fileExists(atPath: snapshotURL.path) { return try readValidatedSnapshot() }
        let empty = GBPJPYTrendPullbackCampaignSnapshot(definition: definition, revision: 0,
            cursor: GBPJPYTrendPullbackEventCursor(consumedKeys: []),
            nextWindowStart: definition.sessionOpen, activeEvents: [], transactions: [])
        try persist(empty)
        return empty
    }

    public func load() throws -> GBPJPYTrendPullbackCampaignSnapshot {
        let lock = try CampaignWriterLock(url: lockURL, timeout: lockTimeout)
        defer { lock.release() }
        return try readValidatedSnapshot()
    }

    public func commit(_ proposal: GBPJPYTrendPullbackCampaignProposal) throws -> GBPJPYTrendPullbackCampaignReceipt {
        let lock = try CampaignWriterLock(url: lockURL, timeout: lockTimeout)
        defer { lock.release() }
        let current = try readValidatedSnapshot()
        let proposedID = proposal.transactionID(campaignID: definition.campaignID)
        if let prior = current.transactions.first(where: { $0.id == proposedID }) {
            guard prior.proposal == proposal else { throw GBPJPYTrendCampaignError.transactionConflict(proposedID) }
            let priorIndex = current.transactions.firstIndex(where: { $0.id == proposedID })!
            let originalSnapshotDigest = GBPJPYTrendPullbackCampaignSnapshot(definition: definition,
                revision: prior.revision, cursor: prior.cursorAfter,
                nextWindowStart: prior.nextWindowStartAfter, activeEvents: prior.activeEventsAfter,
                transactions: Array(current.transactions.prefix(priorIndex + 1))).digest
            return GBPJPYTrendPullbackCampaignReceipt(disposition: .duplicate,
                transactionID: prior.id, revision: prior.revision,
                snapshotDigest: originalSnapshotDigest)
        }
        guard proposal.expectedRevision == current.revision else {
            throw GBPJPYTrendCampaignError.staleRevision(expected: proposal.expectedRevision, actual: current.revision)
        }
        guard proposal.priorCursorDigest == current.cursor.digest else {
            throw GBPJPYTrendCampaignError.cursorConflict(expected: proposal.priorCursorDigest, actual: current.cursor.digest)
        }
        let activeByID = Dictionary(uniqueKeysWithValues: current.activeEvents.map { ($0.id, $0) })
        let issues = Self.validateProposal(proposal, definition: definition,
            expectedStart: current.nextWindowStart, cursor: current.cursor, activeEvents: activeByID)
        guard issues.isEmpty else { throw GBPJPYTrendCampaignError.invalidTransaction(issues) }

        let descriptors = proposal.discovery.batch.descriptors
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let activeEventIDs = Set(activeByID.keys).union(descriptorByID.keys)
        let evaluationByID = Dictionary(uniqueKeysWithValues: proposal.evaluations.map { ($0.eventID, $0) })
        var evaluated: [GBPJPYTrendPullbackCampaignEventRecord] = []
        var activeAfter: [String: GBPJPYTrendPullbackCampaignEventRecord] = [:]
        for eventID in activeEventIDs.sorted() {
            guard let evaluation = evaluationByID[eventID] else {
                throw GBPJPYTrendCampaignError.invalidTransaction(["active_event_evaluation_missing"])
            }
            let base = activeByID[eventID]
            let descriptor = base?.descriptor ?? descriptorByID[eventID]!
            let discovery = base?.discovery ?? proposal.discovery
            let retainedCursor = evaluation.decision.quoteContinuationCursor
                ?? (evaluation.decision.disposition == .active
                    ? (base?.quoteContinuationCursor ?? evaluation.inputs.quoteCursor) : nil)
            let record = GBPJPYTrendPullbackCampaignEventRecord(descriptor: descriptor,
                discovery: discovery, decision: evaluation.decision,
                quoteContinuationCursor: retainedCursor)
            evaluated.append(record)
            if record.isActive { activeAfter[eventID] = record }
        }
        guard evaluationByID.count == activeEventIDs.count else {
            throw GBPJPYTrendCampaignError.invalidTransaction(["event_evaluation_set_mismatch"])
        }
        let nextCursor = Self.cursorAfter(current.cursor, discovery: proposal.discovery)
        let nextStart = Self.nextWindowStart(proposal.window, definition: definition)
        if nextStart == definition.sessionClose && !activeAfter.isEmpty {
            throw GBPJPYTrendCampaignError.invalidTransaction(["active_event_crosses_session_close"])
        }
        let transaction = GBPJPYTrendPullbackCampaignTransaction(id: proposedID,
            revision: current.revision + 1, previousSnapshotDigest: current.digest,
            proposal: proposal, evaluatedEvents: evaluated, activeEventsAfter: Array(activeAfter.values),
            cursorAfter: nextCursor, nextWindowStartAfter: nextStart)
        let updated = GBPJPYTrendPullbackCampaignSnapshot(definition: definition,
            revision: transaction.revision, cursor: nextCursor, nextWindowStart: nextStart,
            activeEvents: Array(activeAfter.values), transactions: current.transactions + [transaction])
        let finalIssues = updated.validationIssues()
        guard finalIssues.isEmpty else { throw GBPJPYTrendCampaignError.invalidTransaction(finalIssues) }
        try persist(updated)
        return GBPJPYTrendPullbackCampaignReceipt(disposition: .committed,
            transactionID: proposedID, revision: updated.revision, snapshotDigest: updated.digest)
    }

    public static func genesisDigest(for definition: GBPJPYTrendPullbackCampaignDefinition) -> String {
        GBPJPYTrendPullbackCampaignSnapshot(definition: definition, revision: 0,
            cursor: GBPJPYTrendPullbackEventCursor(consumedKeys: []),
            nextWindowStart: definition.sessionOpen, activeEvents: [], transactions: []).digest
    }

    fileprivate static func validateProposal(_ proposal: GBPJPYTrendPullbackCampaignProposal,
        definition: GBPJPYTrendPullbackCampaignDefinition, expectedStart: Date,
        cursor: GBPJPYTrendPullbackEventCursor,
        activeEvents: [String: GBPJPYTrendPullbackCampaignEventRecord]) -> [String] {
        var issues: [String] = []
        let batch = proposal.discovery.batch
        let config = definition.configuration
        if proposal.priorCursorDigest != cursor.digest || !cursor.isValid { issues.append("prior_cursor_mismatch") }
        if batch.status != .completeWithEvents && batch.status != .completeEmpty { issues.append("discovery_not_complete") }
        if (batch.status == .completeWithEvents) != !batch.descriptors.isEmpty { issues.append("discovery_status_descriptor_mismatch") }
        if batch.strategyVersion != config.version || batch.profileDigest != config.digest()
            || batch.instrument != config.instrument || batch.provider != config.provider
            || batch.environment != definition.environment { issues.append("campaign_identity_mismatch") }
        if proposal.discovery.provenance.provider != definition.configuration.provider
            || proposal.discovery.provenance.environment != definition.environment
            || proposal.discovery.provenance.buildID != definition.buildID
            || proposal.discovery.provenance.codeDigest != definition.codeDigest
            || !proposal.discovery.provenance.lineageIsProviderNative { issues.append("discovery_provenance_mismatch") }
        if proposal.discovery.contexts.contains(where: { $0.sessionID != definition.sessionID }) {
            issues.append("discovery_session_identity_mismatch")
        }
        if proposal.discovery.cursor != cursor || batch.cursorDigest != cursor.digest { issues.append("discovery_cursor_mismatch") }
        let replayedBatch = GBPJPYTrendPullbackV1.discoverBreakEventBatch(
            lowerBars: proposal.discovery.lowerBars, higherBars: proposal.discovery.higherBars,
            contexts: proposal.discovery.contexts, provenance: proposal.discovery.provenance,
            asOf: batch.asOf, window: batch.window, cursor: proposal.discovery.cursor,
            configuration: config)
        if replayedBatch != batch { issues.append("discovery_replay_mismatch") }
        let lowerBars = proposal.discovery.lowerBars
        let firstMatches = lowerBars.enumerated().filter { $0.element.id == batch.window.firstLowerBarID }
        let lastMatches = lowerBars.enumerated().filter { $0.element.id == batch.window.lastLowerBarID }
        if firstMatches.count != 1 || lastMatches.count != 1 {
            issues.append("discovery_window_endpoints_missing_or_ambiguous")
        } else if firstMatches[0].offset > lastMatches[0].offset {
            issues.append("discovery_window_order_invalid")
        } else {
            let evidenceSlice = Array(lowerBars[firstMatches[0].offset...lastMatches[0].offset])
            let expectedPoints = evidenceSlice.map {
                GBPJPYTrendPullbackCampaignBarPoint(id: $0.id, startTime: $0.startTime)
            }
            if expectedPoints != proposal.window.points { issues.append("discovery_window_evidence_mismatch") }
        }
        if proposal.window.digest != GBPJPYTrendPullbackCampaignDefinition.hash(proposal.window.points) {
            issues.append("window_digest_invalid")
        }
        if proposal.window.points.isEmpty { issues.append("window_empty") }
        if proposal.window.points.count != Set(proposal.window.points.map(\.id)).count
            || proposal.window.points.contains(where: { $0.id.isEmpty || !$0.startTime.timeIntervalSince1970.isFinite }) {
            issues.append("window_identity_invalid")
        }
        let tf = TimeInterval(config.lowerTimeframeSeconds)
        if proposal.window.start != expectedStart { issues.append("window_start_not_expected") }
        if proposal.window.points.first?.id != batch.window.firstLowerBarID
            || proposal.window.points.last?.id != batch.window.lastLowerBarID { issues.append("window_endpoints_mismatch") }
        if !zip(proposal.window.points, proposal.window.points.dropFirst()).allSatisfy({
            $0.1.startTime.timeIntervalSince($0.0.startTime) == tf
        }) {
            issues.append("window_not_contiguous")
        }
        if let last = proposal.window.end,
           last.addingTimeInterval(tf) > definition.sessionClose { issues.append("window_crosses_session_close") }
        for point in proposal.window.points {
            let grid = point.startTime.timeIntervalSince1970 - Double(config.gridOriginUTCSeconds)
            if abs(grid.truncatingRemainder(dividingBy: tf)) > 0.000_001 { issues.append("window_off_grid") }
        }
        let descriptorIDs = batch.descriptors.map(\.id)
        if descriptorIDs.contains(where: { $0.isEmpty }) || Set(descriptorIDs).count != descriptorIDs.count {
            issues.append("descriptor_identity_invalid")
        }
        let consumed = Set(cursor.consumedKeys)
        var newlyConsumed = Set<GBPJPYTrendPullbackConsumedKey>()
        for descriptor in batch.descriptors {
            if descriptor.strategyID != GBPJPYTrendPullbackV1.strategyID
                || descriptor.strategyVersion != config.version || descriptor.profileDigest != config.digest()
                || descriptor.cursorDigest != cursor.digest || descriptor.windowDigest != evaluatorWindowDigest(batch.window)
                || descriptor.firstLowerBarID != batch.window.firstLowerBarID
                || descriptor.lastLowerBarID != batch.window.lastLowerBarID
                || descriptor.direction == .wait || descriptor.frozenSwingID.isEmpty
                || descriptor.breakBarID.isEmpty || !descriptor.breakBarEnd.timeIntervalSince1970.isFinite {
                issues.append("descriptor_binding_invalid")
            }
            if consumed.contains(GBPJPYTrendPullbackConsumedKey(frozenSwingID: descriptor.frozenSwingID,
                                                                 direction: descriptor.direction)) {
                issues.append("consumed_event_rediscovered")
            }
            let consumedKey = GBPJPYTrendPullbackConsumedKey(frozenSwingID: descriptor.frozenSwingID,
                                                               direction: descriptor.direction)
            if !newlyConsumed.insert(consumedKey).inserted { issues.append("duplicate_discovery_key") }
            if activeEvents[descriptor.id] != nil { issues.append("event_id_already_active") }
        }
        let expectedEvaluationIDs = Set(activeEvents.keys).union(descriptorIDs)
        let evaluationIDs = proposal.evaluations.map(\.eventID)
        if Set(evaluationIDs) != expectedEvaluationIDs || Set(evaluationIDs).count != evaluationIDs.count {
            issues.append("evaluation_set_mismatch")
        }
        for evaluation in proposal.evaluations {
            if evaluation.inputs.contexts.contains(where: { $0.sessionID != definition.sessionID }) {
                issues.append("evaluation_session_identity_mismatch")
            }
            if evaluation.eventID != evaluation.decision.eventID { issues.append("evaluation_event_id_mismatch") }
            if evaluation.decision.disposition == .integrityRejected { issues.append("event_integrity_rejected") }
            if evaluation.decision.configurationDigest != config.digest() { issues.append("evaluation_profile_mismatch") }
            if !GBPJPYTrendPullbackCampaignDefinition.validDigest(evaluation.decision.inputDigest) {
                issues.append("evaluation_digest_invalid")
            }
            let candidate = activeEvents[evaluation.eventID]?.descriptor
                ?? batch.descriptors.first(where: { $0.id == evaluation.eventID })
            let discovery = activeEvents[evaluation.eventID]?.discovery ?? proposal.discovery
            if let candidate {
                let expectedInputCursor = activeEvents[evaluation.eventID]?.quoteContinuationCursor
                    ?? GBPJPYTrendPullbackQuoteContinuationCursor(discovery: discovery,
                        candidate: candidate, configuration: config)
                if evaluation.inputs.quoteCursor != expectedInputCursor {
                    issues.append("quote_cursor_prior_state_mismatch")
                }
                let replayedDecision = GBPJPYTrendPullbackV1.evaluateActiveEvent(
                    discovery: discovery, candidate: candidate,
                    evaluationLowerBars: evaluation.inputs.lowerBars,
                    evaluationHigherBars: evaluation.inputs.higherBars,
                    quotes: evaluation.inputs.quotes, evaluationContexts: evaluation.inputs.contexts,
                    quoteCursor: evaluation.inputs.quoteCursor,
                    quoteWindowAttestation: evaluation.inputs.quoteWindowAttestation,
                    provenance: evaluation.inputs.provenance, asOf: evaluation.inputs.asOf,
                    configuration: config)
                if replayedDecision != evaluation.decision { issues.append("evaluation_replay_mismatch") }
                if evaluation.inputs.quoteCursor.eventID != evaluation.eventID { issues.append("quote_cursor_event_mismatch") }
            } else { issues.append("evaluation_candidate_missing") }
            if let existing = activeEvents[evaluation.eventID],
               evaluation.decision.eventID != existing.descriptor.id { issues.append("active_event_identity_mismatch") }
        }
        return Array(Set(issues)).sorted()
    }

    fileprivate static func cursorAfter(_ prior: GBPJPYTrendPullbackEventCursor,
        discovery: GBPJPYTrendPullbackDiscoveryEvidence) -> GBPJPYTrendPullbackEventCursor {
        guard discovery.batch.status == .completeWithEvents else { return prior }
        let keys = prior.consumedKeys + discovery.batch.descriptors.map {
            GBPJPYTrendPullbackConsumedKey(frozenSwingID: $0.frozenSwingID, direction: $0.direction)
        }
        return GBPJPYTrendPullbackEventCursor(consumedKeys: keys)
    }

    fileprivate static func nextWindowStart(_ window: GBPJPYTrendPullbackCampaignWindow,
                                             definition: GBPJPYTrendPullbackCampaignDefinition) -> Date {
        window.end?.addingTimeInterval(TimeInterval(definition.configuration.lowerTimeframeSeconds)) ?? definition.sessionClose
    }

    fileprivate static func validateEventResults(transaction: GBPJPYTrendPullbackCampaignTransaction,
        previousActive: [String: GBPJPYTrendPullbackCampaignEventRecord],
        definition: GBPJPYTrendPullbackCampaignDefinition) -> Bool {
        let descriptorIDs = transaction.proposal.discovery.batch.descriptors.map(\.id)
        let evaluationIDs = transaction.proposal.evaluations.map(\.eventID)
        let eventResultIDs = transaction.evaluatedEvents.map(\.id)
        let activeResultIDs = transaction.activeEventsAfter.map(\.id)
        guard Set(descriptorIDs).count == descriptorIDs.count,
              Set(evaluationIDs).count == evaluationIDs.count,
              Set(eventResultIDs).count == eventResultIDs.count,
              Set(activeResultIDs).count == activeResultIDs.count else { return false }
        let newDescriptors = Dictionary(uniqueKeysWithValues: transaction.proposal.discovery.batch.descriptors.map { ($0.id, $0) })
        let decisions = Dictionary(uniqueKeysWithValues: transaction.proposal.evaluations.map { ($0.eventID, $0.decision) })
        let expectedIDs = Set(previousActive.keys).union(newDescriptors.keys)
        guard Set(decisions.keys) == expectedIDs,
              Set(transaction.evaluatedEvents.map(\.id)) == expectedIDs else { return false }
        for record in transaction.evaluatedEvents {
            guard let decision = decisions[record.id], decision == record.decision,
                  decision.eventID == record.id, decision.configurationDigest == definition.configuration.digest() else { return false }
            if let previous = previousActive[record.id] {
                guard previous.descriptor == record.descriptor, previous.discovery == record.discovery else { return false }
            } else {
                guard newDescriptors[record.id] == record.descriptor,
                  record.discovery == transaction.proposal.discovery else { return false }
            }
            let priorContinuationCursor = previousActive[record.id]?.quoteContinuationCursor
            let evaluationInputCursor = transaction.proposal.evaluations
                .first(where: { $0.eventID == record.id })?.inputs.quoteCursor
            let expectedContinuationCursor = decision.quoteContinuationCursor
                ?? (decision.disposition == .active ? (priorContinuationCursor ?? evaluationInputCursor) : nil)
            guard record.quoteContinuationCursor == expectedContinuationCursor else { return false }
        }
        let expectedActive = transaction.evaluatedEvents.filter(\.isActive).sorted { $0.id < $1.id }
        return expectedActive == transaction.activeEventsAfter
    }

    private func readValidatedSnapshot() throws -> GBPJPYTrendPullbackCampaignSnapshot {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            throw GBPJPYTrendCampaignError.corruptSnapshot(["snapshot_missing_initialize_required"])
        }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let snapshot = try decoder.decode(GBPJPYTrendPullbackCampaignSnapshot.self, from: Data(contentsOf: snapshotURL))
            let issues = snapshot.validationIssues()
            guard issues.isEmpty, snapshot.definition == definition else {
                throw GBPJPYTrendCampaignError.corruptSnapshot(issues.isEmpty ? ["campaign_definition_mismatch"] : issues)
            }
            return snapshot
        } catch let error as GBPJPYTrendCampaignError { throw error }
        catch { throw GBPJPYTrendCampaignError.corruptSnapshot(["snapshot_decode_or_read_failed"]) }
    }

    private func persist(_ snapshot: GBPJPYTrendPullbackCampaignSnapshot) throws {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try snapshotWriter(encoder.encode(snapshot), snapshotURL)
        } catch { throw GBPJPYTrendCampaignError.persistenceFailure("atomic_snapshot_write_failed") }
    }

}

private func evaluatorWindowDigest(_ window: GBPJPYTrendPullbackWindow) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(window)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private struct CampaignWriterLock {
    private let descriptor: Int32
    private let acquired: Bool

    init(url: URL, timeout: TimeInterval) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw GBPJPYTrendCampaignError.persistenceFailure("lock_open_failed") }
        descriptor = fd
        let start = DispatchTime.now().uptimeNanoseconds
        let maxWait = UInt64(timeout * 1_000_000_000)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK && errno != EAGAIN {
                close(fd); throw GBPJPYTrendCampaignError.persistenceFailure("lock_acquire_failed")
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds &- start
            if elapsed >= maxWait { close(fd); throw GBPJPYTrendCampaignError.lockTimedOut }
            Thread.sleep(forTimeInterval: min(0.005, TimeInterval(maxWait - elapsed) / 1_000_000_000))
        }
        acquired = true
    }

    func release() {
        if acquired { _ = flock(descriptor, LOCK_UN); close(descriptor) }
    }
}
