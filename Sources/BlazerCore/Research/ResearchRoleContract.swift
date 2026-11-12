import Foundation

/// A named, completed-bar data stream used by a research contract.
public struct ResearchDataResolution: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let barDurationSeconds: Double
    public let minimumCompletedBars: Int

    public init(id: String, name: String, barDurationSeconds: Double, minimumCompletedBars: Int) throws {
        guard Self.isNamed(id), Self.isNamed(name) else { throw ResearchRoleContractError.invalidName }
        guard barDurationSeconds.isFinite, barDurationSeconds > 0 else {
            throw ResearchRoleContractError.invalidDuration
        }
        guard minimumCompletedBars > 0 else { throw ResearchRoleContractError.invalidBarCount }
        self.id = id
        self.name = name
        self.barDurationSeconds = barDurationSeconds
        self.minimumCompletedBars = minimumCompletedBars
    }

    private static func isNamed(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private enum CodingKeys: String, CodingKey { case id, name, barDurationSeconds, minimumCompletedBars }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            barDurationSeconds: values.decode(Double.self, forKey: .barDurationSeconds),
            minimumCompletedBars: values.decode(Int.self, forKey: .minimumCompletedBars)
        )
    }
}

public enum ResearchLookback: Codable, Sendable, Equatable {
    case bars(Int)
    case duration(seconds: Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(TaggedLookback.self)
        switch value {
        case let .bars(count): try self.init(validatingBars: count)
        case let .duration(seconds): try self.init(validatingDuration: seconds)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bars(count): try container.encode(TaggedLookback.bars(count))
        case let .duration(seconds): try container.encode(TaggedLookback.duration(seconds))
        }
    }

    private init(validatingBars count: Int) throws {
        guard count > 0 else { throw ResearchRoleContractError.invalidLookback }
        self = .bars(count)
    }

    private init(validatingDuration seconds: Double) throws {
        guard seconds.isFinite, seconds > 0 else { throw ResearchRoleContractError.invalidLookback }
        self = .duration(seconds: seconds)
    }

    private enum TaggedLookback: Codable {
        case bars(Int)
        case duration(Double)
    }
}

public struct ResearchFeatureRole: Codable, Sendable, Equatable {
    public let name: String
    public let version: String
    public let sourceResolutionID: String
    public let lookback: ResearchLookback

    public init(name: String, version: String, sourceResolutionID: String, lookback: ResearchLookback) throws {
        guard Self.isNamed(name), Self.isNamed(version), Self.isNamed(sourceResolutionID) else {
            throw ResearchRoleContractError.invalidName
        }
        self.name = name
        self.version = version
        self.sourceResolutionID = sourceResolutionID
        self.lookback = lookback
    }

    private static func isNamed(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum ResearchTriggerCadence: Codable, Sendable, Equatable {
    case barClose(resolutionID: String)
    case quoteEvent(name: String)
}

public enum ResearchExitSemantics: Codable, Sendable, Equatable {
    case fixedDuration(seconds: Double)
    /// Structural exits are identified by a plan; they intentionally have no fixed horizon.
    case structural(planName: String)
}

public struct ResearchStrategyIdentity: Codable, Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchRoleContractError.invalidName
        }
        self.name = name
        self.version = version
    }
}

public enum ResearchRoleContractError: Error, Equatable, Sendable {
    case invalidName
    case invalidDuration
    case invalidBarCount
    case invalidLookback
    case invalidFixedHorizon
    case duplicateResolutionID(String)
    case missingResolutionID(String)
    case duplicateFeatureRoleName(String)
}

/// Metadata-only separation of data, features, trigger cadence, and holding semantics.
public struct ResearchRoleContract: Codable, Sendable, Equatable {
    public let dataResolutions: [ResearchDataResolution]
    public let featureRoles: [ResearchFeatureRole]
    public let trigger: ResearchTriggerCadence
    public let exit: ResearchExitSemantics
    public let strategy: ResearchStrategyIdentity
    public let engineIdentity: String?

    public init(
        dataResolutions: [ResearchDataResolution],
        featureRoles: [ResearchFeatureRole],
        trigger: ResearchTriggerCadence,
        exit: ResearchExitSemantics,
        strategy: ResearchStrategyIdentity,
        engineIdentity: String?
    ) throws {
        var resolutionIDs = Set<String>()
        for resolution in dataResolutions {
            guard resolutionIDs.insert(resolution.id).inserted else {
                throw ResearchRoleContractError.duplicateResolutionID(resolution.id)
            }
        }
        var featureNames = Set<String>()
        for feature in featureRoles {
            guard Self.isNamed(feature.name), Self.isNamed(feature.version),
                  Self.isNamed(feature.sourceResolutionID) else {
                throw ResearchRoleContractError.invalidName
            }
            guard featureNames.insert(feature.name).inserted else {
                throw ResearchRoleContractError.duplicateFeatureRoleName(feature.name)
            }
            guard resolutionIDs.contains(feature.sourceResolutionID) else {
                throw ResearchRoleContractError.missingResolutionID(feature.sourceResolutionID)
            }
            switch feature.lookback {
            case let .bars(count) where count > 0:
                break
            case let .duration(seconds) where seconds.isFinite && seconds > 0:
                break
            default:
                throw ResearchRoleContractError.invalidLookback
            }
        }
        switch trigger {
        case let .barClose(resolutionID):
            guard resolutionIDs.contains(resolutionID) else {
                throw ResearchRoleContractError.missingResolutionID(resolutionID)
            }
        case let .quoteEvent(name):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResearchRoleContractError.invalidName
            }
        }
        switch exit {
        case let .fixedDuration(seconds) where seconds.isFinite && seconds > 0:
            break
        case let .structural(planName) where !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            break
        default:
            throw ResearchRoleContractError.invalidFixedHorizon
        }
        if let engineIdentity, engineIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ResearchRoleContractError.invalidName
        }
        guard Self.isNamed(strategy.name), Self.isNamed(strategy.version) else {
            throw ResearchRoleContractError.invalidName
        }
        self.dataResolutions = dataResolutions
        self.featureRoles = featureRoles
        self.trigger = trigger
        self.exit = exit
        self.strategy = strategy
        self.engineIdentity = engineIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case dataResolutions, featureRoles, trigger, exit, strategy, engineIdentity
    }

    private static func isNamed(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            dataResolutions: values.decode([ResearchDataResolution].self, forKey: .dataResolutions),
            featureRoles: values.decode([ResearchFeatureRole].self, forKey: .featureRoles),
            trigger: values.decode(ResearchTriggerCadence.self, forKey: .trigger),
            exit: values.decode(ResearchExitSemantics.self, forKey: .exit),
            strategy: values.decode(ResearchStrategyIdentity.self, forKey: .strategy),
            engineIdentity: values.decodeIfPresent(String.self, forKey: .engineIdentity)
        )
    }
}
