#if os(macOS)
import CryptoKit
import Foundation
import BlazerCore

public enum MacResearchSignalLifecycle: String, Codable, Sendable, Equatable {
    case forming = "FORMING"
    case confirmed = "CONFIRMED"
    case actionable = "ACTIONABLE"
    case expired = "EXPIRED"
    case invalidated = "INVALIDATED"

    fileprivate var progress: Int {
        switch self {
        case .forming: 0
        case .confirmed: 1
        case .actionable: 2
        case .expired, .invalidated: 3
        }
    }

    fileprivate static func observed(_ stage: MacResearchSignalStage) -> Self {
        switch stage {
        case .forming: .forming
        case .confirmed: .confirmed
        case .actionable: .actionable
        }
    }

    public static func advances(from previous: Self?, to stage: MacResearchSignalStage) -> Bool {
        guard let previous else { return true }
        return observed(stage).progress > previous.progress
    }
}

public enum MacResearchSignalHistoryEventKind: String, Codable, Sendable, Equatable {
    case observed
    case expired
    case invalidated
}

/// Converts only explicit evaluator terminal reasons into signal invalidations.
/// Missing data, failed evaluation, and ordinary no-setup results do not close a
/// previously observed setup.
public enum MacResearchSignalInvalidationResolver {
    private static let terminalReasons: Set<String> = [
        "setup_invalidated", "retest_failed", "retest_expired", "setup_too_old",
        "stop_touched_before_entry", "entry_invalidated"
    ]

    public static func explicitReasons(
        from outcomes: [AdaptiveStrategyEvaluationOutcome]
    ) -> [String: String] {
        Dictionary(outcomes.flatMap { outcome in
            (outcome.rawDiagnostics ?? []).compactMap { diagnostic -> (String, String)? in
                let reason = diagnostic.reasonCode.lowercased()
                guard terminalReasons.contains(reason) else { return nil }
                return (diagnostic.candidateID, reason)
            }
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// Immutable Practice signal history. This is display and audit evidence only;
/// it carries no account approval, order request, or execution authority.
public struct MacResearchSignalHistoryEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let setupKey: String
    public let kind: MacResearchSignalHistoryEventKind
    public let lifecycle: MacResearchSignalLifecycle
    public let observedStage: MacResearchSignalStage
    public let signal: MacResearchSignal
    public let recordedAt: Date
    public let reasonCode: String?

    fileprivate init(id: String, setupKey: String, kind: MacResearchSignalHistoryEventKind,
                     lifecycle: MacResearchSignalLifecycle, signal: MacResearchSignal,
                     recordedAt: Date, reasonCode: String? = nil) {
        self.id = id
        self.setupKey = setupKey
        self.kind = kind
        self.lifecycle = lifecycle
        self.observedStage = signal.stage
        self.signal = signal
        self.recordedAt = recordedAt
        self.reasonCode = reasonCode
    }
}

public enum MacResearchSignalHistoryAppendResult: Sendable, Equatable {
    case appended
    case duplicate
    case superseded
    case terminalSetup
}

public enum MacResearchSignalHistoryError: Error, LocalizedError, Sendable, Equatable {
    case invalidPracticeSignal
    case signalNotInHistory
    case invalidTransition
    case invalidEvent(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPracticeSignal: "Only a valid OANDA Practice signal can enter Practice history"
        case .signalNotInHistory: "The signal observation is not present in history"
        case .invalidTransition: "The signal lifecycle transition is invalid"
        case .invalidEvent(let id): "Invalid signal history event: \(id)"
        }
    }
}

/// Append-only, restart-safe lifecycle history for visible GBP/JPY Practice signals.
/// Writes across store instances are serialized with the repository's research-store lock.
public actor MacResearchSignalHistoryStore {
    private let root: URL

    public init(root: URL = ResearchStore.defaultRoot()) {
        self.root = root.appendingPathComponent("mac-signal-lifecycle-events", isDirectory: true)
    }

    @discardableResult
    public func recordObservation(_ signal: MacResearchSignal) async throws
        -> MacResearchSignalHistoryAppendResult {
        guard Self.validPracticeSignal(signal) else { throw MacResearchSignalHistoryError.invalidPracticeSignal }
        return try await withTransaction {
            let all = try await self.loadUnlocked()
            let key = Self.setupKey(for: signal)
            let stream = all.filter { $0.setupKey == key }.sorted(by: Self.eventOrder)
            let eventID = Self.eventID(setupKey: key, kind: .observed,
                generation: signal.scanGeneration, source: signal.sourceInputIdentity,
                stage: signal.stage.rawValue)
            if let duplicate = stream.first(where: { $0.id == eventID }) {
                return duplicate.signal == signal ? .duplicate : .superseded
            }
            guard let previous = stream.last else {
                let event = MacResearchSignalHistoryEvent(id: eventID, setupKey: key,
                    kind: .observed, lifecycle: .observed(signal.stage), signal: signal,
                    recordedAt: signal.observedAt)
                try await self.appendUnlocked(event)
                return .appended
            }
            guard previous.lifecycle != .expired, previous.lifecycle != .invalidated else {
                return .terminalSetup
            }
            guard signal.scanGeneration > previous.signal.scanGeneration,
                  signal.observedAt >= previous.signal.observedAt else { return .superseded }

            let observed = MacResearchSignalLifecycle.observed(signal.stage)
            let lifecycle = observed.progress > previous.lifecycle.progress ? observed : previous.lifecycle
            let event = MacResearchSignalHistoryEvent(id: eventID, setupKey: key,
                kind: .observed, lifecycle: lifecycle, signal: signal,
                recordedAt: signal.observedAt)
            try await self.appendUnlocked(event)
            return .appended
        }
    }

    @discardableResult
    public func recordExpiry(for signal: MacResearchSignal, at date: Date = Date()) async throws
        -> MacResearchSignalHistoryAppendResult {
        try await recordTerminal(for: signal, kind: .expired, reasonCode: "signal_expired", at: date)
    }

    @discardableResult
    public func recordInvalidation(for signal: MacResearchSignal, reasonCode: String,
                                   at date: Date = Date()) async throws
        -> MacResearchSignalHistoryAppendResult {
        guard Self.validReasonCode(reasonCode) else { throw MacResearchSignalHistoryError.invalidTransition }
        return try await recordTerminal(for: signal, kind: .invalidated, reasonCode: reasonCode, at: date)
    }

    public func events() async throws -> [MacResearchSignalHistoryEvent] {
        try await withTransaction { try await self.loadUnlocked().sorted(by: Self.eventOrder) }
    }

    public func latestEvent(for signal: MacResearchSignal) async throws -> MacResearchSignalHistoryEvent? {
        guard Self.validPracticeSignal(signal) else { throw MacResearchSignalHistoryError.invalidPracticeSignal }
        let key = Self.setupKey(for: signal)
        return try await withTransaction {
            try await self.loadUnlocked().filter { $0.setupKey == key }.max(by: Self.eventOrder)
        }
    }

    /// Appends terminal states for any restored signal whose validity window elapsed.
    /// Historical snapshots remain available; they are never restored as current signals.
    @discardableResult
    public func expireElapsedSignals(asOf date: Date = Date()) async throws -> Int {
        guard date.timeIntervalSince1970.isFinite else { throw MacResearchSignalHistoryError.invalidTransition }
        return try await withTransaction {
            let all = try await self.loadUnlocked()
            let groups = Dictionary(grouping: all, by: \.setupKey)
            var count = 0
            for stream in groups.values {
                guard let latest = stream.max(by: Self.eventOrder),
                      latest.lifecycle != .expired, latest.lifecycle != .invalidated,
                      date >= latest.signal.validUntil else { continue }
                let key = latest.setupKey
                let eventID = Self.eventID(setupKey: key, kind: .expired,
                    generation: latest.signal.scanGeneration, source: latest.signal.sourceInputIdentity,
                    stage: MacResearchSignalLifecycle.expired.rawValue)
                if all.contains(where: { $0.id == eventID }) { continue }
                let event = MacResearchSignalHistoryEvent(id: eventID, setupKey: key,
                    kind: .expired, lifecycle: .expired, signal: latest.signal,
                    recordedAt: date, reasonCode: "signal_expired")
                try await self.appendUnlocked(event)
                count += 1
            }
            return count
        }
    }

    private func recordTerminal(for signal: MacResearchSignal,
                                kind: MacResearchSignalHistoryEventKind,
                                reasonCode: String?, at date: Date) async throws
        -> MacResearchSignalHistoryAppendResult {
        guard Self.validPracticeSignal(signal), date.timeIntervalSince1970.isFinite else {
            throw MacResearchSignalHistoryError.invalidPracticeSignal
        }
        guard date >= signal.observedAt else { throw MacResearchSignalHistoryError.invalidTransition }
        if kind == .expired, date < signal.validUntil { throw MacResearchSignalHistoryError.invalidTransition }
        return try await withTransaction {
            let all = try await self.loadUnlocked()
            let key = Self.setupKey(for: signal)
            let stream = all.filter { $0.setupKey == key }.sorted(by: Self.eventOrder)
            guard let previous = stream.last else { throw MacResearchSignalHistoryError.signalNotInHistory }
            guard previous.signal.scanGeneration == signal.scanGeneration,
                  previous.signal.sourceInputIdentity == signal.sourceInputIdentity else { return .superseded }
            guard previous.lifecycle != .expired, previous.lifecycle != .invalidated else {
                return .duplicate
            }
            let terminal: MacResearchSignalLifecycle = kind == .expired ? .expired : .invalidated
            let eventID = Self.eventID(setupKey: key, kind: kind,
                generation: signal.scanGeneration, source: signal.sourceInputIdentity,
                stage: terminal.rawValue)
            if all.contains(where: { $0.id == eventID }) { return .duplicate }
            let event = MacResearchSignalHistoryEvent(id: eventID, setupKey: key,
                kind: kind, lifecycle: terminal, signal: signal,
                recordedAt: date, reasonCode: reasonCode)
            try await self.appendUnlocked(event)
            return .appended
        }
    }

    private func withTransaction<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let key = root.standardizedFileURL.path
        return try await ResearchStoreLifecycleLockRegistry.shared.withLock(for: key) {
            try await operation()
        }
    }

    private func appendUnlocked(_ event: MacResearchSignalHistoryEvent) throws {
        guard Self.validEvent(event) else { throw MacResearchSignalHistoryError.invalidEvent(event.id) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        let url = root.appendingPathComponent(event.id + ".json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            if try Data(contentsOf: url) == data { return }
            // recordedAt can differ when an expiry is retried after a restart.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let existing = try decoder.decode(MacResearchSignalHistoryEvent.self, from: Data(contentsOf: url))
            guard Self.sameEvent(existing, event) else {
                throw MacResearchSignalHistoryError.invalidEvent(event.id)
            }
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private func loadUnlocked() throws -> [MacResearchSignalHistoryEvent] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let events = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let event = try decoder.decode(MacResearchSignalHistoryEvent.self, from: Data(contentsOf: url))
                guard Self.validEvent(event), url.deletingPathExtension().lastPathComponent == event.id else {
                    throw MacResearchSignalHistoryError.invalidEvent(url.lastPathComponent)
                }
                return event
            }
        try Self.validateArchive(events)
        return events
    }

    private static func validPracticeSignal(_ signal: MacResearchSignal) -> Bool {
        signal.environment == .practice && signal.instrument == "GBP/JPY"
            && !signal.id.isEmpty && !signal.strategyID.isEmpty && !signal.strategyVersion.isEmpty
            && signal.scanGeneration > 0
            && signal.observedAt.timeIntervalSince1970.isFinite
            && signal.validUntil.timeIntervalSince1970.isFinite && signal.validUntil >= signal.observedAt
            && isSHA256OrSHA1(signal.sourceInputIdentity)
            && [signal.entryReference, signal.stopPrice, signal.targetPrice].compactMap { $0 }
                .allSatisfy(\.isFinite)
    }

    private static func validEvent(_ event: MacResearchSignalHistoryEvent) -> Bool {
        guard validPracticeSignal(event.signal)
            && event.recordedAt.timeIntervalSince1970.isFinite
            && isSHA256(event.id) && isSHA256(event.setupKey)
            && event.setupKey == setupKey(for: event.signal)
            && event.observedStage == event.signal.stage
            && ((event.kind == .observed && event.lifecycle.progress < 3)
                || (event.kind == .expired && event.lifecycle == .expired)
                || (event.kind == .invalidated && event.lifecycle == .invalidated))
            && (event.reasonCode.map(validReasonCode) ?? true) else { return false }
        let expectedStage: String
        switch event.kind {
        case .observed:
            guard event.lifecycle.progress >= MacResearchSignalLifecycle.observed(event.signal.stage).progress else {
                return false
            }
            expectedStage = event.signal.stage.rawValue
        case .expired:
            guard event.recordedAt >= event.signal.validUntil else { return false }
            expectedStage = MacResearchSignalLifecycle.expired.rawValue
        case .invalidated:
            guard event.recordedAt >= event.signal.observedAt, event.reasonCode != nil else { return false }
            expectedStage = MacResearchSignalLifecycle.invalidated.rawValue
        }
        return event.id == eventID(setupKey: event.setupKey, kind: event.kind,
            generation: event.signal.scanGeneration, source: event.signal.sourceInputIdentity,
            stage: expectedStage)
    }

    private static func validateArchive(_ events: [MacResearchSignalHistoryEvent]) throws {
        for stream in Dictionary(grouping: events, by: \.setupKey).values {
            let ordered = stream.sorted(by: eventOrder)
            guard let first = ordered.first, first.kind == .observed else {
                throw MacResearchSignalHistoryError.invalidEvent(stream.first?.id ?? "empty")
            }
            for pair in zip(ordered, ordered.dropFirst()) {
                let prior = pair.0
                let next = pair.1
                guard prior.lifecycle != .expired, prior.lifecycle != .invalidated,
                      next.recordedAt >= prior.recordedAt else {
                    throw MacResearchSignalHistoryError.invalidEvent(next.id)
                }
                if next.kind == .observed {
                    guard next.signal.scanGeneration > prior.signal.scanGeneration,
                          next.signal.observedAt >= prior.signal.observedAt,
                          next.lifecycle.progress >= prior.lifecycle.progress else {
                        throw MacResearchSignalHistoryError.invalidEvent(next.id)
                    }
                } else {
                    guard next.signal.scanGeneration == prior.signal.scanGeneration,
                          next.signal.sourceInputIdentity == prior.signal.sourceInputIdentity else {
                        throw MacResearchSignalHistoryError.invalidEvent(next.id)
                    }
                }
            }
        }
    }

    private static func setupKey(for signal: MacResearchSignal) -> String {
        digest(["mac-signal-setup-v1", "OANDA-PRACTICE", signal.instrument,
                signal.strategyID, signal.strategyVersion, signal.id])
    }

    private static func eventID(setupKey: String, kind: MacResearchSignalHistoryEventKind,
                                generation: Int, source: String, stage: String) -> String {
        digest(["mac-signal-event-v1", setupKey, kind.rawValue, String(generation), source, stage])
    }

    private static func digest(_ fields: [String]) -> String {
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSHA256OrSHA1(_ value: String) -> Bool {
        isSHA256(value) || (value.utf8.count == 40 && value.utf8.allSatisfy(isHex))
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy(isHex)
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private static func validReasonCode(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...64).contains(bytes.count)
            && bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private static func eventOrder(_ lhs: MacResearchSignalHistoryEvent,
                                   _ rhs: MacResearchSignalHistoryEvent) -> Bool {
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
        if lhs.signal.scanGeneration != rhs.signal.scanGeneration {
            return lhs.signal.scanGeneration < rhs.signal.scanGeneration
        }
        return lhs.id < rhs.id
    }

    private static func sameEvent(_ lhs: MacResearchSignalHistoryEvent,
                                  _ rhs: MacResearchSignalHistoryEvent) -> Bool {
        lhs.id == rhs.id && lhs.setupKey == rhs.setupKey && lhs.kind == rhs.kind
            && lhs.lifecycle == rhs.lifecycle && lhs.observedStage == rhs.observedStage
            && lhs.signal == rhs.signal && lhs.reasonCode == rhs.reasonCode
    }
}
#endif
