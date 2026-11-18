import CryptoKit
import Foundation

/// Stable identity for one strategy setup. It deliberately excludes scan and
/// observation metadata so repeated observations of the same setup share an ID.
public struct SignalFirstSetupIdentity: Codable, Sendable, Equatable {
    public let strategyID: String
    public let strategyVersion: String
    public let instrument: String
    public let direction: SignalFirstDirection
    public let timeframe: String
    public let configurationSHA256: String
    /// Evaluator-owned identity for the setup event; must not contain scan time.
    public let setupKey: String

    public init(strategyID: String, strategyVersion: String, instrument: String,
                direction: SignalFirstDirection, timeframe: String,
                configurationSHA256: String, setupKey: String) throws {
        let strategyID = strategyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyVersion = strategyVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let instrument = instrument.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "/").uppercased()
        let timeframe = timeframe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let setupKey = setupKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = configurationSHA256.lowercased()
        guard !strategyID.isEmpty, !strategyVersion.isEmpty, !instrument.isEmpty,
              !timeframe.isEmpty, !setupKey.isEmpty else {
            throw SignalFirstContractError.requiredIdentityFieldMissing
        }
        guard Self.isSHA256(digest) else { throw SignalFirstContractError.invalidConfigurationDigest }
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.instrument = instrument
        self.direction = direction
        self.timeframe = timeframe
        self.configurationSHA256 = digest
        self.setupKey = setupKey
    }

    /// Versioned, length-prefixed canonical form avoids separator ambiguity.
    public var signalID: String {
        let fields = ["signal-first-v1", strategyID, strategyVersion, instrument,
                      direction.rawValue, timeframe, configurationSHA256, setupKey]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private enum CodingKeys: String, CodingKey {
        case strategyID, strategyVersion, instrument, direction, timeframe, configurationSHA256, setupKey
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(strategyID: values.decode(String.self, forKey: .strategyID),
            strategyVersion: values.decode(String.self, forKey: .strategyVersion),
            instrument: values.decode(String.self, forKey: .instrument),
            direction: values.decode(SignalFirstDirection.self, forKey: .direction),
            timeframe: values.decode(String.self, forKey: .timeframe),
            configurationSHA256: values.decode(String.self, forKey: .configurationSHA256),
            setupKey: values.decode(String.self, forKey: .setupKey))
    }

    fileprivate static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }
}

public enum SignalFirstDirection: String, Codable, Sendable, Equatable {
    case long = "LONG"
    case short = "SHORT"
}

/// Environment is caller-supplied metadata until VNX-01 binds it to the actual
/// OANDA client receipt/session. This value alone is not credential attestation.
public enum SignalFirstEnvironment: String, Codable, Sendable, Equatable {
    case practice = "PRACTICE"
    case live = "LIVE"
    case replay = "REPLAY"
}

/// Binds an evaluation observation to its declared environment and data snapshot.
public struct SignalFirstScanContext: Codable, Sendable, Equatable {
    public let environment: SignalFirstEnvironment
    public let providerIdentity: String
    public let requestedInstrument: String
    public let scanID: String
    public let generation: UInt64
    public let quoteAsOf: Date?
    public let candleAsOf: Date?
    public let sourceInputIdentity: String

    public init(environment: SignalFirstEnvironment, providerIdentity: String,
                requestedInstrument: String, scanID: String, generation: UInt64,
                quoteAsOf: Date? = nil, candleAsOf: Date? = nil,
                sourceInputIdentity: String? = nil) throws {
        let provider = providerIdentity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let instrument = requestedInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "/").uppercased()
        let scanID = scanID.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputIdentity = sourceInputIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty, !instrument.isEmpty else {
            throw SignalFirstContractError.requiredIdentityFieldMissing
        }
        guard !scanID.isEmpty else { throw SignalFirstContractError.scanIDMissing }
        guard [quoteAsOf, candleAsOf].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
            throw SignalFirstContractError.invalidObservationTime
        }
        guard let inputIdentity, Self.isSourceSnapshotIdentity(inputIdentity) else {
            throw SignalFirstContractError.invalidSourceIdentity
        }
        guard quoteAsOf != nil || candleAsOf != nil else { throw SignalFirstContractError.sourceTimestampMissing }
        self.environment = environment
        self.providerIdentity = provider
        self.requestedInstrument = instrument
        self.scanID = scanID
        self.generation = generation
        self.quoteAsOf = quoteAsOf
        self.candleAsOf = candleAsOf
        self.sourceInputIdentity = inputIdentity.lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case environment, providerIdentity, requestedInstrument, scanID, generation
        case quoteAsOf, candleAsOf, sourceInputIdentity
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(environment: values.decode(SignalFirstEnvironment.self, forKey: .environment),
            providerIdentity: values.decode(String.self, forKey: .providerIdentity),
            requestedInstrument: values.decode(String.self, forKey: .requestedInstrument),
            scanID: values.decode(String.self, forKey: .scanID),
            generation: values.decode(UInt64.self, forKey: .generation),
            quoteAsOf: values.decodeIfPresent(Date.self, forKey: .quoteAsOf),
            candleAsOf: values.decodeIfPresent(Date.self, forKey: .candleAsOf),
            sourceInputIdentity: values.decodeIfPresent(String.self, forKey: .sourceInputIdentity))
    }

    /// Freshness is a boundary check. Future and over-age snapshots fail closed.
    public func isFresh(asOf: Date, maxQuoteAge: TimeInterval,
                        maxCandleAge: TimeInterval) -> Bool {
        guard asOf.timeIntervalSince1970.isFinite,
              maxQuoteAge.isFinite, maxQuoteAge >= 0,
              maxCandleAge.isFinite, maxCandleAge >= 0 else { return false }
        guard let quoteAsOf, let candleAsOf else { return false }
        let quoteAge = asOf.timeIntervalSince(quoteAsOf)
        let candleAge = asOf.timeIntervalSince(candleAsOf)
        return quoteAge >= 0 && quoteAge <= maxQuoteAge
            && candleAge >= 0 && candleAge <= maxCandleAge
    }

    /// Accepts the repository's 40-character SHA-1 scan snapshot ID and SHA-256
    /// archive digests. The source algorithm is retained by length, case is canonicalized.
    private static func isSourceSnapshotIdentity(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 40 || bytes.count == 64 else { return false }
        return bytes.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
        }
    }
}

public struct SignalFirstObservation: Codable, Sendable, Equatable {
    public let context: SignalFirstScanContext
    public let observedAt: Date

    public var scanID: String { context.scanID }
    public var generation: UInt64 { context.generation }

    public init(context: SignalFirstScanContext, observedAt: Date) throws {
        guard observedAt.timeIntervalSince1970.isFinite else {
            throw SignalFirstContractError.invalidObservationTime
        }
        self.context = context
        self.observedAt = observedAt
    }

    private enum CodingKeys: String, CodingKey { case context, observedAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(context: values.decode(SignalFirstScanContext.self, forKey: .context),
            observedAt: values.decode(Date.self, forKey: .observedAt))
    }
}

/// Limits must come from the selected strategy's frozen scan contract; this type
/// validates and applies them but does not choose or widen them.
public struct SignalFirstFreshnessLimits: Codable, Sendable, Equatable {
    public let maxQuoteAge: TimeInterval
    public let maxCandleAge: TimeInterval

    public init(maxQuoteAge: TimeInterval, maxCandleAge: TimeInterval) throws {
        guard maxQuoteAge.isFinite, maxQuoteAge >= 0,
              maxCandleAge.isFinite, maxCandleAge >= 0 else {
            throw SignalFirstContractError.invalidFreshnessLimits
        }
        self.maxQuoteAge = maxQuoteAge
        self.maxCandleAge = maxCandleAge
    }

    private enum CodingKeys: String, CodingKey { case maxQuoteAge, maxCandleAge }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(maxQuoteAge: values.decode(TimeInterval.self, forKey: .maxQuoteAge),
            maxCandleAge: values.decode(TimeInterval.self, forKey: .maxCandleAge))
    }
}

public enum SignalFirstLifecycle: String, Codable, Sendable, Equatable {
    case forming = "FORMING"
    case confirmed = "CONFIRMED"
    case actionable = "ACTIONABLE"
    case expired = "EXPIRED"
    case invalidated = "INVALIDATED"
}

public enum SignalFirstEvaluatorCompletion: Codable, Sendable, Equatable {
    /// Empty references explicitly mean evaluation completed with no setup.
    case completed(candidates: [SignalFirstCandidateReference])
    case failed(reason: SignalFirstReasonCode)
    case dataUnavailable(reason: SignalFirstReasonCode)
    case notConfigured(reason: SignalFirstReasonCode)
    case unsupported(reason: SignalFirstReasonCode)

    public func validate(evaluatorID: String, strategyID: String, strategyVersion: String,
                         timeframe: String) throws {
        switch self {
        case .completed(let candidates):
            let signalIDs = candidates.map(\.signalID)
            guard Set(signalIDs).count == signalIDs.count else {
                throw SignalFirstContractError.invalidCandidateIdentities
            }
            guard candidates.allSatisfy({ $0.evaluatorID == evaluatorID
                && $0.strategyID == strategyID && $0.strategyVersion == strategyVersion
                && $0.timeframe == timeframe }) else {
                throw SignalFirstContractError.candidateReferenceMismatch
            }
        case .failed, .dataUnavailable, .notConfigured, .unsupported:
            break // Reason codes validate when constructed and also validate during decoding.
        }
    }
}

/// Lowercase machine-safe boundary reason. Raw exception messages never enter it.
public struct SignalFirstReasonCode: Codable, Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        let bytes = Array(rawValue.utf8)
        guard (1...64).contains(bytes.count),
              bytes.first.map({ $0 >= 97 && $0 <= 122 }) == true,
              bytes.allSatisfy({ ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 }) else {
            throw SignalFirstContractError.invalidReasonCode
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Minimal join to the actual candidate payload produced by VNX-03.
public struct SignalFirstCandidateReference: Codable, Sendable, Equatable, Identifiable {
    public let signalID: String
    public let evaluatorID: String
    public let strategyID: String
    public let strategyVersion: String
    public let timeframe: String
    public var id: String { signalID }

    public init(signalID: String, evaluatorID: String, strategyID: String, strategyVersion: String,
                timeframe: String) throws {
        let signalID = signalID.lowercased()
        let evaluatorID = evaluatorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyID = strategyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyVersion = strategyVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeframe = timeframe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard SignalFirstSetupIdentity.isSHA256(signalID) else {
            throw SignalFirstContractError.invalidSignalID
        }
        guard !evaluatorID.isEmpty, !strategyID.isEmpty, !strategyVersion.isEmpty, !timeframe.isEmpty else {
            throw SignalFirstContractError.requiredIdentityFieldMissing
        }
        self.signalID = signalID
        self.evaluatorID = evaluatorID
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.timeframe = timeframe
    }

    private enum CodingKeys: String, CodingKey { case signalID, evaluatorID, strategyID, strategyVersion, timeframe }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(signalID: values.decode(String.self, forKey: .signalID),
            evaluatorID: values.decode(String.self, forKey: .evaluatorID),
            strategyID: values.decode(String.self, forKey: .strategyID),
            strategyVersion: values.decode(String.self, forKey: .strategyVersion),
            timeframe: values.decode(String.self, forKey: .timeframe))
    }
}

public struct SignalFirstEvaluatorOutcome: Codable, Sendable, Equatable {
    public let evaluatorID: String
    public let strategyID: String
    public let strategyVersion: String
    public let timeframe: String
    public let completion: SignalFirstEvaluatorCompletion

    public init(evaluatorID: String, strategyID: String, strategyVersion: String, timeframe: String,
                completion: SignalFirstEvaluatorCompletion) throws {
        let evaluatorID = evaluatorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyID = strategyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let strategyVersion = strategyVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeframe = timeframe.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !evaluatorID.isEmpty, !strategyID.isEmpty, !strategyVersion.isEmpty, !timeframe.isEmpty else {
            throw SignalFirstContractError.requiredIdentityFieldMissing
        }
        try completion.validate(evaluatorID: evaluatorID, strategyID: strategyID,
                                strategyVersion: strategyVersion, timeframe: timeframe)
        self.evaluatorID = evaluatorID
        self.strategyID = strategyID
        self.strategyVersion = strategyVersion
        self.timeframe = timeframe
        self.completion = completion
    }

    private enum CodingKeys: String, CodingKey { case evaluatorID, strategyID, strategyVersion, timeframe, completion }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(evaluatorID: values.decode(String.self, forKey: .evaluatorID),
            strategyID: values.decode(String.self, forKey: .strategyID),
            strategyVersion: values.decode(String.self, forKey: .strategyVersion),
            timeframe: values.decode(String.self, forKey: .timeframe),
            completion: values.decode(SignalFirstEvaluatorCompletion.self, forKey: .completion))
    }
}

/// Non-authoritative candidate snapshot. Its lifecycle is evaluator output only;
/// it does not encode approval, account/environment attestation, user action, or
/// broker execution. VNX-01/VNX-05 must bind trusted receipts and reducer history
/// before any authorization, notification, persistence, or execution decision.
public struct SignalFirstObservationRecord: Codable, Sendable, Equatable, Identifiable {
    public let identity: SignalFirstSetupIdentity
    public let observation: SignalFirstObservation
    public let lifecycle: SignalFirstLifecycle

    public var signalID: String { identity.signalID }
    /// Storage/dedup identity includes environment and provider, unlike signalID.
    public var storageKey: String {
        let fields = ["signal-observation-v1", observation.context.environment.rawValue,
                      observation.context.providerIdentity, identity.signalID]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    public var id: String { storageKey }
    public var scanID: String { observation.scanID }
    public var generation: UInt64 { observation.generation }

    public init(identity: SignalFirstSetupIdentity, observation: SignalFirstObservation,
                lifecycle: SignalFirstLifecycle) throws {
        guard identity.instrument == observation.context.requestedInstrument else {
            throw SignalFirstContractError.instrumentMismatch
        }
        self.identity = identity
        self.observation = observation
        self.lifecycle = lifecycle
    }

    private enum CodingKeys: String, CodingKey { case identity, observation, lifecycle }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(identity: values.decode(SignalFirstSetupIdentity.self, forKey: .identity),
            observation: values.decode(SignalFirstObservation.self, forKey: .observation),
            lifecycle: values.decode(SignalFirstLifecycle.self, forKey: .lifecycle))
    }
}

/// Records are lifecycle snapshots. VNX-05's event store/reducer must call this
/// before creating a successor snapshot; terminal states cannot reactivate.
public enum SignalFirstLifecycleTransition {
    public static func validate(from current: SignalFirstLifecycle,
                                to next: SignalFirstLifecycle) throws {
        let allowed: Bool
        switch current {
        case .forming:
            allowed = [.forming, .confirmed, .expired, .invalidated].contains(next)
        case .confirmed:
            allowed = [.confirmed, .actionable, .expired, .invalidated].contains(next)
        case .actionable:
            allowed = [.actionable, .expired, .invalidated].contains(next)
        case .expired:
            allowed = next == .expired
        case .invalidated:
            allowed = next == .invalidated
        }
        guard allowed else { throw SignalFirstContractError.invalidLifecycleTransition }
    }
}

public enum SignalFirstContractError: Error, Sendable, Equatable {
    case requiredIdentityFieldMissing
    case invalidConfigurationDigest
    case scanIDMissing
    case invalidObservationTime
    case sourceTimestampMissing
    case invalidSourceIdentity
    case invalidCandidateIdentities
    case candidateReferenceMismatch
    case invalidReasonCode
    case instrumentMismatch
    case invalidLifecycleTransition
    case invalidSignalID
    case invalidFreshnessLimits
}
