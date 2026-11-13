import Foundation

/// A named completed-bar stream. A stream is data that must be declared; it is
/// not a holding-period or exit-duration declaration.
public struct ResearchDataResolution: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let barDurationSeconds: Double
    public let minimumCompletedBars: Int

    public init(id: String, name: String, barDurationSeconds: Double, minimumCompletedBars: Int) throws {
        guard Self.isNamed(id), Self.isNamed(name) else { throw ResearchRoleContractError.invalidName }
        guard barDurationSeconds.isFinite, barDurationSeconds > 0 else { throw ResearchRoleContractError.invalidDuration }
        guard minimumCompletedBars > 0 else { throw ResearchRoleContractError.invalidBarCount }
        self.id = id; self.name = name; self.barDurationSeconds = barDurationSeconds; self.minimumCompletedBars = minimumCompletedBars
    }
    private static func isNamed(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private enum CodingKeys: String, CodingKey { case id, name, barDurationSeconds, minimumCompletedBars }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: v.decode(String.self, forKey: .id), name: v.decode(String.self, forKey: .name),
                      barDurationSeconds: v.decode(Double.self, forKey: .barDurationSeconds),
                      minimumCompletedBars: v.decode(Int.self, forKey: .minimumCompletedBars))
    }
}

public enum ResearchLookback: Codable, Sendable, Equatable {
    case bars(Int)
    case duration(seconds: Double)
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: Keys.self)
        if let kind = try v.decodeIfPresent(String.self, forKey: .kind) {
            switch kind { case "bars": try self.init(validatingBars: v.decode(Int.self, forKey: .value)); case "duration": try self.init(validatingDuration: v.decode(Double.self, forKey: .value)); default: throw ResearchRoleContractError.invalidLookback }
        } else if v.contains(.bars) {
            if let n = try? v.decode(Int.self, forKey: .bars) { try self.init(validatingBars: n) }
            else {
                let value = try v.decode(LegacyAssociatedValue.self, forKey: .bars).value
                guard value.isFinite, value.rounded() == value,
                      value >= Double(Int.min), value <= Double(Int.max) else {
                    throw ResearchRoleContractError.invalidLookback
                }
                try self.init(validatingBars: Int(value))
            }
        } else if v.contains(.duration) {
            if let d = try? v.decode(DurationValue.self, forKey: .duration) { try self.init(validatingDuration: d.seconds) }
            else { try self.init(validatingDuration: v.decode(LegacyAssociatedValue.self, forKey: .duration).value) }
        } else { throw ResearchRoleContractError.invalidLookback }
    }
    public func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: Keys.self)
        switch self { case .bars(let n): try v.encode("bars", forKey: .kind); try v.encode(n, forKey: .value)
        case .duration(let s): try v.encode("duration", forKey: .kind); try v.encode(s, forKey: .value) }
    }
    private enum Keys: String, CodingKey { case kind, value, bars, duration }
    private struct DurationValue: Decodable { let seconds: Double }
    private struct LegacyAssociatedValue: Decodable {
        let value: Double
        private enum CodingKeys: String, CodingKey { case positional = "_0" }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            value = try values.decode(Double.self, forKey: .positional)
        }
    }
    private init(validatingBars n: Int) throws { guard n > 0 else { throw ResearchRoleContractError.invalidLookback }; self = .bars(n) }
    private init(validatingDuration s: Double) throws { guard s.isFinite, s > 0 else { throw ResearchRoleContractError.invalidLookback }; self = .duration(seconds: s) }
}

/// Rules are evaluated in array order. A later rule is a fallback, not a bar
/// duration or implicit default. Thresholds therefore decrease strictly.
public struct ResearchResolutionSelectionRule: Codable, Sendable, Equatable {
    public let selectionRole: String
    public let resolutionID: String
    public let minimumCompletedBars: Int
    public init(selectionRole: String, resolutionID: String, minimumCompletedBars: Int) throws {
        guard Self.named(selectionRole), Self.named(resolutionID) else { throw ResearchRoleContractError.invalidName }
        guard minimumCompletedBars > 0 else { throw ResearchRoleContractError.invalidBarCount }
        self.selectionRole = selectionRole; self.resolutionID = resolutionID; self.minimumCompletedBars = minimumCompletedBars
    }
    private static func named(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private enum Keys: String, CodingKey { case selectionRole, resolutionID, minimumCompletedBars }
    public init(from decoder: Decoder) throws { let v = try decoder.container(keyedBy: Keys.self); try self.init(selectionRole: v.decode(String.self, forKey: .selectionRole), resolutionID: v.decode(String.self, forKey: .resolutionID), minimumCompletedBars: v.decode(Int.self, forKey: .minimumCompletedBars)) }
}

public extension Array where Element == ResearchResolutionSelectionRule {
    /// Selects the first eligible rule using the completed-bar count for that
    /// rule's own stream. A single shared count would misrepresent fallback
    /// behavior when resolutions have different history availability.
    func selectedResolutionID(selectionRole: String, completedBarsByResolution: [String: Int]) -> String? {
        first(where: {
            $0.selectionRole == selectionRole &&
                (completedBarsByResolution[$0.resolutionID] ?? 0) >= $0.minimumCompletedBars
        })?.resolutionID
    }
}

/// One independently-windowed feature dependency. Exactly one source kind is
/// allowed, so a selection role does not silently become a second stream.
public struct ResearchFeatureInput: Codable, Sendable, Equatable {
    public let sourceResolutionID: String?
    public let selectionRole: String?
    public let lookback: ResearchLookback
    public init(sourceResolutionID: String, lookback: ResearchLookback) throws { try self.init(sourceResolutionID: sourceResolutionID, selectionRole: nil, lookback: lookback) }
    public init(selectionRole: String, lookback: ResearchLookback) throws { try self.init(sourceResolutionID: nil, selectionRole: selectionRole, lookback: lookback) }
    private init(sourceResolutionID: String?, selectionRole: String?, lookback: ResearchLookback) throws {
        guard (sourceResolutionID != nil) != (selectionRole != nil), sourceResolutionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true, selectionRole?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true else { throw ResearchRoleContractError.invalidSelection }
        self.sourceResolutionID = sourceResolutionID; self.selectionRole = selectionRole; self.lookback = lookback
    }
    private enum Keys: String, CodingKey { case sourceResolutionID, selectionRole, lookback }
    public init(from decoder: Decoder) throws { let v = try decoder.container(keyedBy: Keys.self); try self.init(sourceResolutionID: v.decodeIfPresent(String.self, forKey: .sourceResolutionID), selectionRole: v.decodeIfPresent(String.self, forKey: .selectionRole), lookback: v.decode(ResearchLookback.self, forKey: .lookback)) }
}

public struct ResearchFeatureRole: Codable, Sendable, Equatable {
    public let name: String
    public let version: String
    /// Legacy single-source API. It is nil when the feature uses a role.
    public let inputs: [ResearchFeatureInput]
    public let policyScope: String?

    public init(name: String, version: String, sourceResolutionID: String, lookback: ResearchLookback, policyScope: String? = nil) throws {
        try self.init(name: name, version: version, inputs: [try ResearchFeatureInput(sourceResolutionID: sourceResolutionID, lookback: lookback)], policyScope: policyScope)
    }
    public init(name: String, version: String, sourceResolutionIDs: [String], selectionRole: String? = nil, lookback: ResearchLookback, policyScope: String? = nil) throws {
        var values = try sourceResolutionIDs.map { try ResearchFeatureInput(sourceResolutionID: $0, lookback: lookback) }
        if let selectionRole { values.append(try ResearchFeatureInput(selectionRole: selectionRole, lookback: lookback)) }
        try self.init(name: name, version: version, inputs: values, policyScope: policyScope)
    }
    public init(name: String, version: String, inputs: [ResearchFeatureInput], policyScope: String? = nil) throws {
        guard Self.named(name), Self.named(version), !inputs.isEmpty else { throw ResearchRoleContractError.invalidName }
        guard policyScope == nil || Self.named(policyScope!) else { throw ResearchRoleContractError.invalidPolicyScope }
        self.name = name; self.version = version; self.inputs = inputs; self.policyScope = policyScope
    }
    /// Compatibility accessor for the original single-source API. Multi-source
    /// features return their first declared source; role-only features return
    /// their role. New consumers should use `sourceResolutionIDs`/`selectionRole`.
    public var sourceResolutionID: String { inputs.first?.sourceResolutionID ?? inputs.first?.selectionRole ?? "" }
    public var sourceResolutionIDs: [String] { inputs.compactMap(\.sourceResolutionID) }
    public var selectionRole: String? { inputs.first(where: { $0.selectionRole != nil })?.selectionRole }
    public var lookback: ResearchLookback { inputs[0].lookback }
    private static func named(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private enum Keys: String, CodingKey { case name, version, inputs, sourceResolutionID, sourceResolutionIDs, selectionRole, lookback, policyScope }
    public func encode(to encoder: Encoder) throws {
        var v = encoder.container(keyedBy: Keys.self); try v.encode(name, forKey: .name); try v.encode(version, forKey: .version)
        if inputs.count == 1, let source = inputs[0].sourceResolutionID { try v.encode(source, forKey: .sourceResolutionID); try v.encode(inputs[0].lookback, forKey: .lookback) } else { try v.encode(inputs, forKey: .inputs) }
        try v.encodeIfPresent(policyScope, forKey: .policyScope)
    }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: Keys.self)
        let inputs: [ResearchFeatureInput]
        if let decoded = try v.decodeIfPresent([ResearchFeatureInput].self, forKey: .inputs) { inputs = decoded }
        else { let ids = try v.decodeIfPresent([String].self, forKey: .sourceResolutionIDs) ?? v.decodeIfPresent(String.self, forKey: .sourceResolutionID).map { [$0] } ?? []; let lb = try v.decode(ResearchLookback.self, forKey: .lookback); var legacy = try ids.map { try ResearchFeatureInput(sourceResolutionID: $0, lookback: lb) }; if let role = try v.decodeIfPresent(String.self, forKey: .selectionRole) { legacy.append(try ResearchFeatureInput(selectionRole: role, lookback: lb)) }; inputs = legacy }
        try self.init(name: v.decode(String.self, forKey: .name), version: v.decode(String.self, forKey: .version), inputs: inputs, policyScope: v.decodeIfPresent(String.self, forKey: .policyScope))
    }
}

public enum ResearchFreshnessKind: String, Codable, Sendable { case quoteAge, futureSkew, completedBarTrigger }
public struct ResearchFreshnessRequirement: Codable, Sendable, Equatable {
    public let kind: ResearchFreshnessKind
    public let sourceRole: String
    public let maximumSeconds: Double
    public init(kind: ResearchFreshnessKind, sourceRole: String, maximumSeconds: Double) throws {
        guard !sourceRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName }
        guard maximumSeconds.isFinite, maximumSeconds > 0 else { throw ResearchRoleContractError.invalidFreshness }
        self.kind = kind; self.sourceRole = sourceRole; self.maximumSeconds = maximumSeconds
    }
    private enum Keys: String, CodingKey { case kind, sourceRole, maximumSeconds }
    public init(from decoder: Decoder) throws { let v = try decoder.container(keyedBy: Keys.self); try self.init(kind: v.decode(ResearchFreshnessKind.self, forKey: .kind), sourceRole: v.decode(String.self, forKey: .sourceRole), maximumSeconds: v.decode(Double.self, forKey: .maximumSeconds)) }
}

public enum ResearchTriggerCadence: Codable, Sendable, Equatable { case barClose(resolutionID: String); case quoteEvent(name: String) }
public enum ResearchExitSemantics: Codable, Sendable, Equatable {
    case fixedDuration(seconds: Double)
    /// A configured choice among supported fixed outcome durations, not a
    /// claim that every evaluation uses one particular duration.
    case fixedDurationChoices(seconds: [Double])
    case structural(planName: String)
    case structuralWithSetupExpiry(planName: String, maximumSetupDurationSeconds: Double?)
}
public struct ResearchStrategyIdentity: Codable, Sendable, Equatable {
    public let name: String; public let version: String
    public init(name: String, version: String) throws { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName }; self.name = name; self.version = version }
    private enum Keys: String, CodingKey { case name, version }
    public init(from decoder: Decoder) throws { let v = try decoder.container(keyedBy: Keys.self); try self.init(name: v.decode(String.self, forKey: .name), version: v.decode(String.self, forKey: .version)) }
}

public enum ResearchRoleContractError: Error, Equatable, Sendable {
    case invalidName, invalidDuration, invalidBarCount, invalidLookback, invalidFixedHorizon, invalidFreshness, invalidPolicyScope, invalidSelection, invalidFallbackOrder
    case duplicateResolutionID(String), missingResolutionID(String), duplicateFeatureRoleName(String), duplicateSelectionRole(String), duplicateSelectionResolution(String), missingSelectionRole(String), missingFreshnessSource(String)
}

/// Metadata-only separation of streams, selection, features, freshness,
/// trigger cadence, and exit semantics. This contract does not alter engines.
public struct ResearchRoleContract: Codable, Sendable, Equatable {
    public let dataResolutions: [ResearchDataResolution]
    public let resolutionSelections: [ResearchResolutionSelectionRule]
    public let featureRoles: [ResearchFeatureRole]
    public let freshnessRequirements: [ResearchFreshnessRequirement]
    public let trigger: ResearchTriggerCadence
    public let exit: ResearchExitSemantics
    public let strategy: ResearchStrategyIdentity
    public let engineIdentity: String?
    public let declaredInputRoles: [String]

    public init(dataResolutions: [ResearchDataResolution], resolutionSelections: [ResearchResolutionSelectionRule] = [], featureRoles: [ResearchFeatureRole], freshnessRequirements: [ResearchFreshnessRequirement] = [], declaredInputRoles: [String] = [], trigger: ResearchTriggerCadence, exit: ResearchExitSemantics, strategy: ResearchStrategyIdentity, engineIdentity: String?) throws {
        var ids = Set<String>(); for r in dataResolutions { guard ids.insert(r.id).inserted else { throw ResearchRoleContractError.duplicateResolutionID(r.id) } }
        var roles = Set<String>()
        var previousByRole: [String: Int] = [:]; var pairs = Set<String>(); for rule in resolutionSelections { guard ids.contains(rule.resolutionID) else { throw ResearchRoleContractError.missingResolutionID(rule.resolutionID) }; roles.insert(rule.selectionRole); let pair = "\(rule.selectionRole)\u{1F}\(rule.resolutionID)"; guard pairs.insert(pair).inserted else { throw ResearchRoleContractError.duplicateSelectionResolution(rule.resolutionID) }; if let previous = previousByRole[rule.selectionRole] { guard rule.minimumCompletedBars < previous else { throw ResearchRoleContractError.invalidFallbackOrder } }; previousByRole[rule.selectionRole] = rule.minimumCompletedBars }
        guard Set(declaredInputRoles).count == declaredInputRoles.count, declaredInputRoles.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ResearchRoleContractError.invalidName }
        var names = Set<String>(); for f in featureRoles { guard names.insert(f.name).inserted else { throw ResearchRoleContractError.duplicateFeatureRoleName(f.name) }; for input in f.inputs { if let id = input.sourceResolutionID { guard ids.contains(id) else { throw ResearchRoleContractError.missingResolutionID(id) } }; if let role = input.selectionRole { guard roles.contains(role) else { throw ResearchRoleContractError.missingSelectionRole(role) } }; switch input.lookback { case .bars(let n): guard n > 0 else { throw ResearchRoleContractError.invalidLookback }; case .duration(let s): guard s.isFinite, s > 0 else { throw ResearchRoleContractError.invalidLookback } } } }
        let freshnessRoles = ids.union(roles).union(declaredInputRoles); for freshness in freshnessRequirements { guard freshnessRoles.contains(freshness.sourceRole) else { throw ResearchRoleContractError.missingFreshnessSource(freshness.sourceRole) } }
        if case .barClose(let id) = trigger { guard ids.contains(id) else { throw ResearchRoleContractError.missingResolutionID(id) } }
        if case .quoteEvent(let name) = trigger { guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName } }
        if case .fixedDuration(let s) = exit { guard s.isFinite, s > 0 else { throw ResearchRoleContractError.invalidFixedHorizon } }
        if case .fixedDurationChoices(let values) = exit {
            guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 > 0 }),
                  Set(values).count == values.count else { throw ResearchRoleContractError.invalidFixedHorizon }
        }
        if case .structural(let p) = exit { guard !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName } }
        if case .structuralWithSetupExpiry(let p, let expiry) = exit { guard !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName }; if let expiry { guard expiry.isFinite, expiry > 0 else { throw ResearchRoleContractError.invalidDuration } } }
        guard !strategy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !strategy.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName }
        guard engineIdentity == nil || !engineIdentity!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ResearchRoleContractError.invalidName }
        self.dataResolutions = dataResolutions; self.resolutionSelections = resolutionSelections; self.featureRoles = featureRoles; self.freshnessRequirements = freshnessRequirements; self.declaredInputRoles = declaredInputRoles; self.trigger = trigger; self.exit = exit; self.strategy = strategy; self.engineIdentity = engineIdentity
    }
    private enum Keys: String, CodingKey { case dataResolutions, resolutionSelections, featureRoles, freshnessRequirements, declaredInputRoles, trigger, exit, strategy, engineIdentity }
    public init(from decoder: Decoder) throws { let v = try decoder.container(keyedBy: Keys.self); try self.init(dataResolutions: v.decode([ResearchDataResolution].self, forKey: .dataResolutions), resolutionSelections: v.decodeIfPresent([ResearchResolutionSelectionRule].self, forKey: .resolutionSelections) ?? [], featureRoles: v.decode([ResearchFeatureRole].self, forKey: .featureRoles), freshnessRequirements: v.decodeIfPresent([ResearchFreshnessRequirement].self, forKey: .freshnessRequirements) ?? [], declaredInputRoles: v.decodeIfPresent([String].self, forKey: .declaredInputRoles) ?? [], trigger: v.decode(ResearchTriggerCadence.self, forKey: .trigger), exit: v.decode(ResearchExitSemantics.self, forKey: .exit), strategy: v.decode(ResearchStrategyIdentity.self, forKey: .strategy), engineIdentity: v.decodeIfPresent(String.self, forKey: .engineIdentity)) }
}
