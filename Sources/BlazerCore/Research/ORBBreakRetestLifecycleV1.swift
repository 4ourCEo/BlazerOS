import Foundation
import CryptoKit

public enum ORBLifecycleEvidenceStatus: String, Codable, Sendable, Equatable {
    case notAttempted = "NOT_ATTEMPTED"
    case notApplicable = "NOT_APPLICABLE"
    case noTransition = "NO_TRANSITION"
    case recorded = "RECORDED"
    /// This opening range already produced a terminal ORB observation or one
    /// confirmed candidate. It is a strategy-structure guard, never a fill status.
    case structureSuppressed = "STRUCTURE_SUPPRESSED"
    case unavailable = "UNAVAILABLE"

    public var displayText: String {
        switch self {
        case .notAttempted: "Not attempted"
        case .notApplicable: "Not applicable"
        case .noTransition: "No new transition"
        case .recorded: "Recorded"
        case .structureSuppressed: "Suppressed for this ORB range"
        case .unavailable: "Unavailable"
        }
    }
}

/// Deterministic, bar-sourced lifecycle projection for the native ORB evaluator.
/// It records setup evidence only; it does not create entries or positions.
public enum ORBBreakRetestLifecycleV1 {
    private struct FrozenOpeningRangeIdentity: Encodable {
        let instrument: String
        let sessionStartMilliseconds: Int64
        let sourceBars: [ORBBar]
    }

    public enum Result: Sendable, Equatable {
        case notApplicable
        case projected(Projection)
        case unavailable
    }

    public struct Projection: Sendable, Equatable {
        public let setupID: String
        public let instrument: String
        public let structureID: String
        public let state: V3SetupState
        public let sourceTime: Date
        public let sourceObservationID: String
        public let sourceBarIDs: [String]
        public let configurationDigest: String
        public let inputDigest: String
        public let strategyVersion: String
        public let engineVersion: String
        public let timeframeSeconds: Int
        public let planID: String?
        public let reason: String
        public let eventID: String
    }

    /// Returns no transition before the opening range seals. Malformed evidence
    /// remains distinguishable from an ordinary pre-range observation.
    public static func project(decision: ORBDecision, bars: [ORBBar], asOf: Date,
                               provider: String = "OANDA",
                               environment: V3ProviderEnvironment = .oandaLive,
                               configuration: ORBConfiguration? = nil) -> Result {
        guard provider == "OANDA", environment == .oandaLive else { return .notApplicable }
        if [.noData, .rangeForming].contains(decision.stage) { return .notApplicable }
        guard let sessionStart = decision.sessionStart,
              [ORBStage.rangeSealed, .boundaryApproaching, .breakoutConfirmed, .retestPending,
               .retestInProgress, .setupConfirmed, .invalidated, .expired].contains(decision.stage)
        else { return .unavailable }

        let configuration = configuration ?? ORBBreakRetestV1.configuration(for: bars.first?.instrument ?? "")
        let completed = bars.filter { $0.endTime <= asOf }
        guard !completed.isEmpty,
              Set(completed.map(\.id)).count == completed.count,
              Set(completed.map(\.endTime)).count == completed.count,
              zip(completed, completed.dropFirst()).allSatisfy({ $0.0.endTime < $0.1.endTime }),
              let instrument = completed.first?.instrument,
              completed.allSatisfy({ $0.instrument == instrument && $0.isFinite }) else { return .unavailable }

        let sessionMillis = Int64((sessionStart.timeIntervalSince1970 * 1_000).rounded())
        let rangeEnd = sessionStart.addingTimeInterval(TimeInterval(configuration.openingRangeMinutes * 60))
        let openingRangeBars = completed.filter { $0.sourceTime >= sessionStart && $0.endTime <= rangeEnd }
        let barDuration = TimeInterval(configuration.barMinutes * 60)
        guard configuration.barMinutes > 0,
              openingRangeBars.count == configuration.openingRangeMinutes / configuration.barMinutes,
              openingRangeBars.first?.sourceTime == sessionStart,
              openingRangeBars.allSatisfy({ $0.endTime == $0.sourceTime.addingTimeInterval(barDuration) }),
              zip(openingRangeBars, openingRangeBars.dropFirst())
                .allSatisfy({ $0.0.sourceTime.addingTimeInterval(barDuration) == $0.1.sourceTime }) else {
            return .unavailable
        }
        let configurationDigest = digest(configuration)
        let frozenStructure = FrozenOpeningRangeIdentity(instrument: instrument,
            sessionStartMilliseconds: sessionMillis, sourceBars: openingRangeBars)
        let structureID = "orb-structure-\(digest(frozenStructure))"
        let setupID = "orb-setup-\(digest("\(structureID)|\(configurationDigest)"))"
        let candidate = decision.candidate
        if decision.stage == .setupConfirmed {
            guard let candidate,
                  [candidate.breakoutBarID, candidate.retestBarID, candidate.confirmationBarID]
                    .allSatisfy({ id in completed.contains(where: { $0.id == id }) }),
                  candidate.plan.sourceObservationID == candidate.confirmationBarID else { return .unavailable }
        }
        let terminalLimit: Date? = decision.stage == .expired
            ? sessionStart.addingTimeInterval(TimeInterval((configuration.openingRangeMinutes
                + configuration.maximumSetupMinutes) * 60)) : nil
        let confirmationTime = candidate.flatMap { candidate in
            completed.first(where: { $0.id == candidate.confirmationBarID })?.endTime
        }
        let relevantBars: [ORBBar]
        let source: ORBBar
        if decision.stage == .invalidated {
            guard let causativeBarID = decision.causativeBarID,
                  let causativeBar = completed.first(where: { $0.id == causativeBarID }) else {
                return .unavailable
            }
            source = causativeBar
            relevantBars = completed.filter {
                $0.sourceTime >= sessionStart && $0.endTime <= causativeBar.endTime
            }
        } else {
            relevantBars = completed.filter { bar in
                bar.sourceTime >= sessionStart && (terminalLimit.map { bar.endTime <= $0 } ?? true)
                    && (confirmationTime.map { bar.endTime <= $0 } ?? true)
            }
            guard let latestRelevantBar = relevantBars.last else { return .unavailable }
            source = latestRelevantBar
        }
        // The input digest covers every eligible bar used to reach the projected
        // state, not just the final bar that names the transition.
        let citedIDs = relevantBars.map(\.id)
        guard !citedIDs.isEmpty,
              citedIDs.contains(source.id), source.endTime <= asOf else { return .unavailable }

        let state: V3SetupState
        switch decision.stage {
        case .rangeSealed, .boundaryApproaching: state = .watching
        case .breakoutConfirmed, .retestPending, .retestInProgress: state = .approaching
        case .setupConfirmed: state = .confirmed
        case .invalidated: state = .invalidated
        case .expired: state = .setupExpired
        default: return .unavailable
        }
        let inputDigest = digest(relevantBars)
        let eventID = "orb-event-\(digest("\(setupID)|\(state.rawValue)|\(inputDigest)"))"
        return .projected(Projection(setupID: setupID, instrument: instrument, structureID: structureID, state: state,
            sourceTime: source.endTime, sourceObservationID: source.id, sourceBarIDs: citedIDs,
            configurationDigest: configurationDigest, inputDigest: inputDigest,
            strategyVersion: configuration.strategyVersion,
            engineVersion: configuration.engineVersion,
            timeframeSeconds: configuration.barMinutes * 60, planID: candidate?.plan.id,
            reason: decision.reason, eventID: eventID))
    }

    public static func event(for projection: Projection, previousState: V3SetupState?,
                             recordedAt: Date = Date()) -> V3SetupLifecycleEvent {
        V3SetupLifecycleEvent(id: projection.eventID, setupID: projection.setupID,
            instrument: projection.instrument,
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: projection.strategyVersion,
            provider: "OANDA", environment: .oandaLive,
            previousState: previousState, state: projection.state,
            sourceObservationID: projection.sourceObservationID, sourceTime: projection.sourceTime,
            receivedAt: recordedAt, recordedAt: recordedAt, planID: projection.planID,
            reason: projection.reason, configurationDigest: projection.configurationDigest,
            inputDigest: projection.inputDigest, engineVersion: projection.engineVersion,
            sourceBarIDs: projection.sourceBarIDs, quoteSequence: nil,
            reasonCodes: [projection.reason], structureID: projection.structureID,
            timeframeSeconds: projection.timeframeSeconds,
            evidenceSchemaVersion: 1)
    }

    private static func digest<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = (try? encoder.encode(value)) ?? Data(String(describing: value).utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
