import Foundation

public enum PolicyActivityClassification: String, Codable, Sendable, Equatable {
    case active
    case selective
    case inactiveUnderObservedConditions
    case insufficientFeatureData
}

/// A descriptive funnel over persisted engine decisions. It does not infer
/// profitability or authorize a strategy; it explains why a policy did or did
/// not reach the existing entry gate.
public struct PolicyEligibilityFunnel: Codable, Sendable, Equatable, Identifiable {
    public let policy: String
    public let instrument: String?
    public let totalObservations: Int
    public let completeFeatureObservations: Int
    public let directionalSignals: Int
    public let acceptedEntries: Int
    public let waitSignals: Int
    public let activity: PolicyActivityClassification
    public let regimes: [String: Int]
    public let engineReasons: [String: Int]
    public let entryVetoes: [String: Int]

    public var id: String { "\(policy)|\(instrument ?? "all")" }

    public init(policy: String, instrument: String?, totalObservations: Int,
                completeFeatureObservations: Int, directionalSignals: Int,
                acceptedEntries: Int, waitSignals: Int,
                activity: PolicyActivityClassification, regimes: [String: Int],
                engineReasons: [String: Int], entryVetoes: [String: Int]) {
        self.policy = policy; self.instrument = instrument
        self.totalObservations = totalObservations
        self.completeFeatureObservations = completeFeatureObservations
        self.directionalSignals = directionalSignals
        self.acceptedEntries = acceptedEntries; self.waitSignals = waitSignals
        self.activity = activity; self.regimes = regimes
        self.engineReasons = engineReasons; self.entryVetoes = entryVetoes
    }
}

public enum PolicyEligibilityDiagnostics {
    public static func evaluate(events: [ResearchEvent], instrument: String? = nil)
        -> [PolicyEligibilityFunnel] {
        let filtered = events.filter { instrument == nil || $0.input.asset == instrument }
        let policies = Set(filtered.map { $0.signal.policy ?? ScanPolicy.baseline.rawValue }).sorted()
        return policies.map { policy in
            let rows = filtered.filter { ($0.signal.policy ?? ScanPolicy.baseline.rawValue) == policy }
            let featureRows = rows.filter { $0.signal.features != nil }
            let directional = rows.filter { $0.signal.cabinetSide == "HIGH" || $0.signal.cabinetSide == "LOW" }
            let accepted = rows.filter { $0.entryTime != nil }
            let waits = rows.count - directional.count
            let regimes = counts(rows.compactMap { $0.signal.features?.regime })
            let engineReasons = counts(rows.flatMap { reasons(for: $0.signal) })
            let entryVetoes = counts(rows.compactMap(\.entryVeto))
            let activity: PolicyActivityClassification
            if rows.isEmpty || featureRows.count * 100 < rows.count * 95 {
                activity = .insufficientFeatureData
            } else if !accepted.isEmpty {
                activity = accepted.count == rows.count ? .active : .selective
            } else {
                activity = .inactiveUnderObservedConditions
            }
            return PolicyEligibilityFunnel(policy: policy, instrument: instrument,
                totalObservations: rows.count,
                completeFeatureObservations: featureRows.count,
                directionalSignals: directional.count, acceptedEntries: accepted.count,
                waitSignals: waits, activity: activity, regimes: regimes,
                engineReasons: engineReasons, entryVetoes: entryVetoes)
        }
    }

    private static func reasons(for signal: EngineSignal) -> [String] {
        if let vetoes = signal.vetoes, !vetoes.isEmpty { return vetoes }
        return signal.cabinetSide == "WAIT" ? [signal.why] : []
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
    }
}
