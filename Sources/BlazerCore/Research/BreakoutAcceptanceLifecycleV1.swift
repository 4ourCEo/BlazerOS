import CryptoKit
import Foundation

public enum BreakoutAcceptanceLifecycleDisposition: String, Codable, Sendable, Equatable {
    case recorded
    case duplicate
    case terminalSuppressed
}

public struct BreakoutAcceptanceLifecycleReceipt: Sendable, Equatable {
    public let disposition: BreakoutAcceptanceLifecycleDisposition
    public let setupID: String
    public let eventID: String
    public let state: V3SetupState

    public init(disposition: BreakoutAcceptanceLifecycleDisposition, setupID: String,
                eventID: String, state: V3SetupState) {
        self.disposition = disposition
        self.setupID = setupID
        self.eventID = eventID
        self.state = state
    }
}

/// Projects pure Breakout Acceptance evidence into the existing local research lifecycle.
/// This adapter has no selector or broker execution authority.
public enum BreakoutAcceptanceLifecycleV1 {
    private static let structuralInvalidationReasons: Set<String> = [
        "acceptance_failed_back_inside", "acceptance_hold_buffer_not_met",
        "retest_breached_tolerance", "retest_failed_to_hold",
        "setup_invalidated_after_acceptance", "frozen_stop_already_touched"
    ]
    private static let expiryReasons: Set<String> = [
        "setup_expired", "accepted_setup_expired", "retest_window_expired",
        "session_end_expired", "post_acceptance_bar_limit_expired",
        "frozen_target_already_reached"
    ]

    public static func record(configuration: BreakoutAcceptanceConfiguration,
                              evidence: BreakoutAcceptanceEvidence,
                              environment: V3ProviderEnvironment,
                              engineVersion: String,
                              store: ResearchStore) async throws -> BreakoutAcceptanceLifecycleReceipt {
        try validate(configuration: configuration, evidence: evidence,
                     environment: environment, engineVersion: engineVersion)
        let setupID = digest(SetupIdentity(strategyID: evidence.strategyID,
            strategyVersion: evidence.strategyVersion, configurationDigest: evidence.configurationDigest,
            engineVersion: engineVersion, instrument: evidence.instrument, provider: evidence.provider,
            environment: environment, timeframeSeconds: evidence.timeframeSeconds,
            structureID: evidence.structureID, direction: configuration.structure.direction))
        let target = targetState(for: evidence)
        let eventID = "ba-event-\(digest(EventIdentity(setupID: setupID, state: target, inputDigest: evidence.inputDigest)))"
        let allEvents = try await store.v3SetupLifecycleEvents()
        let existingEvents = allEvents.filter { $0.setupID == setupID }
        let existingIssues = V3SetupLifecycle.validationIssues(for: existingEvents)
        guard existingIssues.isEmpty else { throw ScanError.failed("Corrupt Breakout Acceptance lifecycle: \(existingIssues.joined(separator: ","))") }

        if let existing = existingEvents.first(where: { $0.id == eventID }) {
            guard existing.instrument == evidence.instrument,
                  existing.strategyID == evidence.strategyID,
                  existing.strategyVersion == evidence.strategyVersion,
                  existing.provider == evidence.provider,
                  existing.environment == environment,
                  existing.planID == nil,
                  existing.configurationDigest == evidence.configurationDigest,
                  existing.inputDigest == evidence.inputDigest,
                  existing.engineVersion == engineVersion,
                  existing.state == target,
                  existing.sourceObservationID == evidence.quoteSourceID,
                  existing.sourceTime == evidence.quoteSourceTime,
                  existing.receivedAt == evidence.quoteReceivedAt,
                  existing.recordedAt == evidence.observedAt,
                  existing.quoteSequence == evidence.quoteSequence,
                  existing.reason == (evidence.reasonCodes.isEmpty ? evidence.status.rawValue : evidence.reasonCodes.joined(separator: ",")),
                  existing.reasonCodes == evidence.reasonCodes,
                  existing.sourceBarIDs == evidence.sourceBarIDs,
                  existing.structureID == evidence.structureID,
                  existing.timeframeSeconds == evidence.timeframeSeconds,
                  existing.evidenceSchemaVersion == 1 else {
                throw ScanError.failed("Breakout Acceptance lifecycle event ID conflict")
            }
            return .init(disposition: .duplicate, setupID: setupID, eventID: eventID, state: target)
        }

        // Configuration and engine revisions produce distinct setup IDs, but do
        // not silently re-arm a terminal frozen structure under the same scope.
        let terminalForSameStructure = allEvents.first { event in
            event.strategyID == evidence.strategyID
                && event.instrument == evidence.instrument
                && event.provider == evidence.provider
                && event.environment == environment
                && event.timeframeSeconds == evidence.timeframeSeconds
                && event.structureID == evidence.structureID
                && [.invalidated, .setupExpired].contains(event.state)
        }
        if let terminalForSameStructure, terminalForSameStructure.setupID != setupID {
            return .init(disposition: .terminalSuppressed, setupID: setupID,
                         eventID: eventID, state: terminalForSameStructure.state)
        }

        let latest = existingEvents.max(by: eventOrder)
        if let latest {
            guard evidence.quoteSourceTime >= (latest.sourceTime ?? .distantPast) else {
                throw ScanError.failed("Breakout Acceptance source time moved backwards")
            }
            if let lastSequence = latest.quoteSequence {
                guard evidence.quoteSequence >= lastSequence else {
                    throw ScanError.failed("Breakout Acceptance quote sequence moved backwards")
                }
                if evidence.quoteSourceTime == latest.sourceTime,
                   evidence.quoteSequence <= lastSequence {
                    throw ScanError.failed("Breakout Acceptance same-time quote sequence did not increase")
                }
            }
            if [.invalidated, .setupExpired].contains(latest.state), target != latest.state {
                return .init(disposition: .terminalSuppressed, setupID: setupID,
                             eventID: eventID, state: latest.state)
            }
        }

        let event = V3SetupLifecycleEvent(id: eventID, setupID: setupID,
            instrument: evidence.instrument, strategyID: evidence.strategyID,
            strategyVersion: evidence.strategyVersion, provider: evidence.provider,
            environment: environment, previousState: latest?.state, state: target,
            sourceObservationID: evidence.quoteSourceID, sourceTime: evidence.quoteSourceTime,
            receivedAt: evidence.quoteReceivedAt, recordedAt: evidence.observedAt,
            reason: evidence.reasonCodes.isEmpty ? evidence.status.rawValue : evidence.reasonCodes.joined(separator: ","),
            configurationDigest: evidence.configurationDigest, inputDigest: evidence.inputDigest,
            engineVersion: engineVersion, sourceBarIDs: evidence.sourceBarIDs,
            quoteSequence: evidence.quoteSequence, reasonCodes: evidence.reasonCodes,
            structureID: evidence.structureID, timeframeSeconds: evidence.timeframeSeconds,
            evidenceSchemaVersion: 1)
        guard event.validation().isEmpty else {
            throw ScanError.failed("Invalid Breakout Acceptance lifecycle event: \(event.validation().joined(separator: ","))")
        }
        try await store.record(event)
        return .init(disposition: .recorded, setupID: setupID, eventID: eventID, state: target)
    }

    private static func targetState(for evidence: BreakoutAcceptanceEvidence) -> V3SetupState {
        switch evidence.status {
        case .watching: return .watching
        case .awaitingAcceptance: return .approaching
        case .signal: return .confirmed
        case .expired:
            return evidence.reasonCodes.allSatisfy(expiryReasons.contains) && !evidence.reasonCodes.isEmpty
                ? .setupExpired : .stale
        case .rejected:
            return !evidence.reasonCodes.isEmpty && evidence.reasonCodes.allSatisfy(structuralInvalidationReasons.contains)
                ? .invalidated : .stale
        }
    }

    private static func validate(configuration: BreakoutAcceptanceConfiguration,
                                 evidence: BreakoutAcceptanceEvidence,
                                 environment: V3ProviderEnvironment,
                                 engineVersion: String) throws {
        guard evidence.strategyID == "BREAKOUT_ACCEPTANCE_V1",
              evidence.strategyVersion == configuration.version,
              evidence.configurationDigest == configuration.digest(),
              evidence.instrument == configuration.instrument,
              evidence.timeframeSeconds == configuration.timeframeSeconds,
              evidence.structureID == configuration.structure.structureID,
              evidence.provider == configuration.provider,
              evidence.inputDigest.count == 64,
              evidence.inputDigest.allSatisfy(\.isHexDigit),
              !evidence.sourceBarIDs.isEmpty,
              Set(evidence.sourceBarIDs).count == evidence.sourceBarIDs.count,
              evidence.quoteSequence > 0,
              !evidence.quoteSourceID.isEmpty,
              !engineVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              compatible(environment: environment, provider: evidence.provider) else {
            throw ScanError.failed("Breakout Acceptance evidence identity or provenance mismatch")
        }
        if evidence.status == .signal {
            guard evidence.direction == configuration.structure.direction else {
                throw ScanError.failed("Breakout Acceptance signal direction mismatch")
            }
        } else if evidence.direction != nil {
            throw ScanError.failed("Non-signal Breakout Acceptance evidence contains a direction")
        }
        guard evidence.quoteSourceTime.timeIntervalSince1970.isFinite,
              evidence.quoteReceivedAt.timeIntervalSince1970.isFinite,
              evidence.observedAt.timeIntervalSince1970.isFinite,
              evidence.quoteSourceTime <= evidence.quoteReceivedAt,
              evidence.quoteReceivedAt <= evidence.observedAt else {
            throw ScanError.failed("Breakout Acceptance quote timestamps are invalid")
        }
    }

    private static func compatible(environment: V3ProviderEnvironment, provider: String) -> Bool {
        switch environment {
        case .oandaPractice, .oandaLive: return provider == "OANDA"
        case .tradingView: return provider.caseInsensitiveCompare("TradingView") == .orderedSame
        case .simulated: return provider.caseInsensitiveCompare("SIMULATED") == .orderedSame
        case .unknown: return false
        }
    }

    private static func eventOrder(_ lhs: V3SetupLifecycleEvent, _ rhs: V3SetupLifecycleEvent) -> Bool {
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
        if let left = lhs.quoteSequence, let right = rhs.quoteSequence, left != right { return left < right }
        return lhs.id < rhs.id
    }

    private struct SetupIdentity: Encodable {
        let strategyID: String; let strategyVersion: String; let configurationDigest: String
        let engineVersion: String; let instrument: String; let provider: String
        let environment: V3ProviderEnvironment; let timeframeSeconds: Int
        let structureID: String; let direction: BreakoutAcceptanceDirection
    }
    private struct EventIdentity: Encodable { let setupID: String; let state: V3SetupState; let inputDigest: String }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("invalid".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
