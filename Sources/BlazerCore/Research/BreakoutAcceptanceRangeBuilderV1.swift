import CryptoKit
import Foundation

public enum BreakoutRangeTiePolicyV1: String, Codable, Sendable, Equatable { case earliestSourceBar, latestSourceBar }
public enum BreakoutRangeGapPolicyV1: Codable, Sendable, Equatable { case rejectAnyGap, allowAtMostMissingBars(Int) }
public enum BreakoutRangeSessionPolicyV1: String, Codable, Sendable, Equatable { case rejectSessionCrossing, allowSessionCrossing }
public enum BreakoutRangeWidthBoundaryPolicyV1: String, Codable, Sendable, Equatable { case inclusive, exclusive }
public enum BreakoutRangeDSTPolicyV1: String, Codable, Sendable, Equatable { case rejectTransitionBoundary, allowElapsedTime }
public enum BreakoutRangeAggregationKindV1: String, Codable, Sendable, Equatable { case providerNative, derived }

/// Session assignment is provided by the immutable snapshot. The builder validates
/// session labels and carries this IANA zone/DST rule as provenance; it does not
/// calculate recurring session boundaries or enforce the DST transition policy.
public struct BreakoutRangeSessionDefinitionV1: Codable, Sendable, Equatable {
    public let id: String
    public let timeZoneIdentifier: String
    public let dstPolicy: BreakoutRangeDSTPolicyV1
    public init(id: String, timeZoneIdentifier: String, dstPolicy: BreakoutRangeDSTPolicyV1) {
        self.id = id; self.timeZoneIdentifier = timeZoneIdentifier; self.dstPolicy = dstPolicy
    }
}

public struct BreakoutRangeAggregationLineageV1: Codable, Sendable, Equatable {
    public let id: String
    public let kind: BreakoutRangeAggregationKindV1
    public let sourceTimeframeSeconds: Int
    public let targetTimeframeSeconds: Int
    public let method: String
    public let sourceSnapshotIDs: [String]
    public init(id: String, kind: BreakoutRangeAggregationKindV1, sourceTimeframeSeconds: Int, targetTimeframeSeconds: Int,
                method: String, sourceSnapshotIDs: [String]) {
        self.id = id; self.kind = kind; self.sourceTimeframeSeconds = sourceTimeframeSeconds
        self.targetTimeframeSeconds = targetTimeframeSeconds; self.method = method
        self.sourceSnapshotIDs = sourceSnapshotIDs
    }
}

public struct BreakoutRangeProfileV1: Codable, Sendable, Equatable {
    public let version: String
    public let instrument: String
    public let provider: String
    public let environment: String
    public let timeframeSeconds: Int
    public let gridOrigin: Date
    public let pipSize: Double
    public let lookbackBars: Int
    public let minimumWidthPips: Double
    public let maximumWidthPips: Double
    public let minimumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1
    public let maximumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1
    public let tiePolicy: BreakoutRangeTiePolicyV1
    public let gapPolicy: BreakoutRangeGapPolicyV1
    public let sessionPolicy: BreakoutRangeSessionPolicyV1
    public let sessionDefinition: BreakoutRangeSessionDefinitionV1
    public let aggregationLineage: BreakoutRangeAggregationLineageV1
    public let engineIdentity: String
    public let buildIdentity: String
    public let datasetDigest: String
    public let codeDigest: String

    public init(version: String, instrument: String, provider: String, environment: String,
                timeframeSeconds: Int, gridOrigin: Date, pipSize: Double, lookbackBars: Int,
                minimumWidthPips: Double, maximumWidthPips: Double,
                minimumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1,
                maximumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1,
                tiePolicy: BreakoutRangeTiePolicyV1, gapPolicy: BreakoutRangeGapPolicyV1,
                sessionPolicy: BreakoutRangeSessionPolicyV1, sessionDefinition: BreakoutRangeSessionDefinitionV1,
                aggregationLineage: BreakoutRangeAggregationLineageV1,
                engineIdentity: String, buildIdentity: String, datasetDigest: String, codeDigest: String) {
        self.version = version; self.instrument = instrument; self.provider = provider
        self.environment = environment; self.timeframeSeconds = timeframeSeconds; self.gridOrigin = gridOrigin; self.pipSize = pipSize
        self.lookbackBars = lookbackBars; self.minimumWidthPips = minimumWidthPips
        self.maximumWidthPips = maximumWidthPips; self.minimumWidthBoundary = minimumWidthBoundary
        self.maximumWidthBoundary = maximumWidthBoundary; self.tiePolicy = tiePolicy
        self.gapPolicy = gapPolicy; self.sessionPolicy = sessionPolicy; self.sessionDefinition = sessionDefinition
        self.aggregationLineage = aggregationLineage; self.engineIdentity = engineIdentity
        self.buildIdentity = buildIdentity; self.datasetDigest = datasetDigest; self.codeDigest = codeDigest
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        for (v, reason) in [(version,"version_missing"),(instrument,"instrument_missing"),
            (provider,"provider_missing"),(environment,"environment_missing"),
            (engineIdentity,"engine_identity_missing"),(buildIdentity,"build_identity_missing"),
            (aggregationLineage.id,"aggregation_id_missing"),(aggregationLineage.method,"aggregation_method_missing")] {
            if v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(reason) }
        }
        if timeframeSeconds <= 0 || aggregationLineage.targetTimeframeSeconds != timeframeSeconds
            || aggregationLineage.sourceTimeframeSeconds <= 0
            || timeframeSeconds % aggregationLineage.sourceTimeframeSeconds != 0
            || aggregationLineage.sourceSnapshotIDs.isEmpty
            || Set(aggregationLineage.sourceSnapshotIDs).count != aggregationLineage.sourceSnapshotIDs.count
            || aggregationLineage.sourceSnapshotIDs.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("aggregation_lineage_invalid")
        }
        if aggregationLineage.kind == .providerNative,
           (aggregationLineage.sourceTimeframeSeconds != aggregationLineage.targetTimeframeSeconds
            || aggregationLineage.method != "provider-native"
            || aggregationLineage.sourceSnapshotIDs.count != 1) {
            issues.append("provider_native_timeframe_invalid")
        }
        if !gridOrigin.timeIntervalSince1970.isFinite { issues.append("grid_origin_invalid") }
        if sessionDefinition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || TimeZone(identifier: sessionDefinition.timeZoneIdentifier) == nil { issues.append("session_definition_invalid") }
        if !pipSize.isFinite || pipSize <= 0 { issues.append("pip_size_invalid") }
        if lookbackBars < 1 { issues.append("lookback_invalid") }
        if !minimumWidthPips.isFinite || !maximumWidthPips.isFinite || minimumWidthPips < 0 || maximumWidthPips < minimumWidthPips { issues.append("width_profile_invalid") }
        for (value, reason) in [(datasetDigest,"dataset_digest_invalid"),(codeDigest,"code_digest_invalid")] where !Self.validDigest(value) { issues.append(reason) }
        if case .allowAtMostMissingBars(let n) = gapPolicy, n < 0 { issues.append("gap_policy_invalid") }
        return issues.sorted()
    }

    public func digest() -> String { BreakoutRangeBuilderHashV1.hash(self) }
    fileprivate static func validDigest(_ s: String) -> Bool { s.count == 64 && s.allSatisfy(\.isHexDigit) }
}

public struct BreakoutRangeSnapshotV1: Codable, Sendable, Equatable {
    public let id: String
    public let instrument: String
    public let provider: String
    public let environment: String
    public let timeframeSeconds: Int
    public let aggregationLineageID: String
    public let snapshotDigest: String
    public let dataDigest: String
    public let capturedAt: Date
    public let bars: [BreakoutAcceptanceBar]
    /// Authoritative session assignments generated by the caller's versioned calendar.
    public let sessionIDsByBarID: [String: String]
    public let constituentBarIDsByTargetBarID: [String: [String]]
    public init(id: String, instrument: String, provider: String, environment: String,
                timeframeSeconds: Int, aggregationLineageID: String, snapshotDigest: String,
                dataDigest: String, capturedAt: Date, bars: [BreakoutAcceptanceBar], sessionIDsByBarID: [String: String],
                constituentBarIDsByTargetBarID: [String: [String]]) {
        self.id = id; self.instrument = instrument; self.provider = provider; self.environment = environment
        self.timeframeSeconds = timeframeSeconds; self.aggregationLineageID = aggregationLineageID
        self.snapshotDigest = snapshotDigest; self.dataDigest = dataDigest; self.capturedAt = capturedAt; self.bars = bars
        self.sessionIDsByBarID = sessionIDsByBarID
        self.constituentBarIDsByTargetBarID = constituentBarIDsByTargetBarID
    }
}

public struct BreakoutRangeBuilderResultV1: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let reasonCodes: [String]
    public let structures: [BreakoutAcceptanceStructure]
    public let candidateBarID: String
    public let candidateStart: Date
    public let sourceBarIDs: [String]
    /// Ordered as the N lookback bars followed by the candidate bar.
    public let orderedSessionIDs: [String]
    public let constituentBarIDsByTargetBarID: [String: [String]]
    public let sourceLineageDigest: String
    public let profileDigest: String
    public let inputDigest: String
    public let contextDigest: String
    public let environment: String
    public let sessionDefinition: BreakoutRangeSessionDefinitionV1
    public let engineIdentity: String
    public let buildIdentity: String
    public let datasetDigest: String
    public let snapshotDigest: String
    public let codeDigest: String
    public let dataDigest: String
    fileprivate init(accepted: Bool, reasons: [String], structures: [BreakoutAcceptanceStructure],
        candidate: BreakoutAcceptanceBar?, sourceBarIDs: [String], orderedSessionIDs: [String], constituentIDs: [String: [String]], profile: BreakoutRangeProfileV1,
        snapshot: BreakoutRangeSnapshotV1, inputDigest: String) {
        self.accepted = accepted; self.reasonCodes = reasons.sorted(); self.structures = structures
        self.candidateBarID = candidate?.id ?? ""; self.candidateStart = candidate?.startTime ?? .distantPast
        self.sourceBarIDs = sourceBarIDs; self.profileDigest = profile.digest(); self.inputDigest = inputDigest
        self.orderedSessionIDs = orderedSessionIDs
        self.constituentBarIDsByTargetBarID = constituentIDs
        self.sourceLineageDigest = BreakoutRangeBuilderHashV1.hash(constituentIDs)
        self.environment = profile.environment; self.engineIdentity = profile.engineIdentity
        self.sessionDefinition = profile.sessionDefinition
        self.buildIdentity = profile.buildIdentity; self.datasetDigest = profile.datasetDigest
        self.snapshotDigest = snapshot.snapshotDigest; self.codeDigest = profile.codeDigest; self.dataDigest = snapshot.dataDigest
        self.contextDigest = BreakoutRangeBuilderHashV1.hash(ContextDigestPayload(profileDigest: profile.digest(),
            datasetDigest: profile.datasetDigest, snapshotID: snapshot.id, snapshotDigest: snapshot.snapshotDigest,
            dataDigest: snapshot.dataDigest, capturedAt: snapshot.capturedAt, inputDigest: inputDigest))
    }
}

private struct ContextDigestPayload: Encodable {
    let profileDigest: String
    let datasetDigest: String
    let snapshotID: String
    let snapshotDigest: String
    let dataDigest: String
    let capturedAt: Date
    let inputDigest: String
}

public enum BreakoutAcceptanceRangeBuilderV1 {
    public static func build(profile p: BreakoutRangeProfileV1, snapshot s: BreakoutRangeSnapshotV1,
                             candidateBarID: String) -> BreakoutRangeBuilderResultV1 {
        let ordered = s.bars.sorted { $0.startTime == $1.startTime ? $0.id < $1.id : $0.startTime < $1.startTime }
        let candidateMatches = ordered.filter { $0.id == candidateBarID }
        let candidate = candidateMatches.first
        let tf = TimeInterval(p.timeframeSeconds)
        let preceding = candidate.map { c in ordered.filter { $0.endTime(timeframeSeconds: p.timeframeSeconds) <= c.startTime } } ?? []
        let selected = Array(preceding.suffix(max(0, p.lookbackBars)))
        let usedBars = selected + (candidate.map { [$0] } ?? [])
        let orderedSessionIDs = usedBars.map { s.sessionIDsByBarID[$0.id] ?? "" }
        let orderedSessionEvidence = zip(usedBars.map(\.id), orderedSessionIDs).map { ["bar": $0.0, "session": $0.1] }
        let lineageEvidence = usedBars.reduce(into: [String: [String]]()) { result, bar in
            result[bar.id] = s.constituentBarIDsByTargetBarID[bar.id] ?? []
        }
        struct CausalPayload: Encodable {
            let version: String; let instrument: String; let provider: String; let environment: String
            let timeframeSeconds: Int; let gridOrigin: Date; let pipSize: Double; let lookbackBars: Int
            let minimumWidthPips: Double; let maximumWidthPips: Double
            let minimumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1
            let maximumWidthBoundary: BreakoutRangeWidthBoundaryPolicyV1
            let tiePolicy: BreakoutRangeTiePolicyV1; let gapPolicy: BreakoutRangeGapPolicyV1
            let sessionPolicy: BreakoutRangeSessionPolicyV1; let sessionDefinition: BreakoutRangeSessionDefinitionV1
            let aggregationPolicy: AggregationPolicy
            let candidateBarID: String; let selectedBars: [BreakoutAcceptanceBar]
            let candidate: BreakoutAcceptanceBar?; let sessionEvidence: [[String: String]]
            let constituentLineage: [String: [String]]
        }
        struct AggregationPolicy: Encodable {
            let id: String
            let kind: BreakoutRangeAggregationKindV1
            let sourceTimeframeSeconds: Int
            let targetTimeframeSeconds: Int
            let method: String
        }
        let causalPayload = CausalPayload(version: p.version, instrument: p.instrument, provider: p.provider,
            environment: p.environment, timeframeSeconds: p.timeframeSeconds, gridOrigin: p.gridOrigin,
            pipSize: p.pipSize, lookbackBars: p.lookbackBars, minimumWidthPips: p.minimumWidthPips,
            maximumWidthPips: p.maximumWidthPips, minimumWidthBoundary: p.minimumWidthBoundary,
            maximumWidthBoundary: p.maximumWidthBoundary, tiePolicy: p.tiePolicy, gapPolicy: p.gapPolicy,
            sessionPolicy: p.sessionPolicy, sessionDefinition: p.sessionDefinition,
            aggregationPolicy: AggregationPolicy(id: p.aggregationLineage.id,
                kind: p.aggregationLineage.kind, sourceTimeframeSeconds: p.aggregationLineage.sourceTimeframeSeconds,
                targetTimeframeSeconds: p.aggregationLineage.targetTimeframeSeconds,
                method: p.aggregationLineage.method), candidateBarID: candidateBarID,
            selectedBars: selected, candidate: candidate, sessionEvidence: orderedSessionEvidence,
            constituentLineage: lineageEvidence)
        let inputDigest = BreakoutRangeBuilderHashV1.hash(causalPayload)
        func reject(_ reasons: [String]) -> BreakoutRangeBuilderResultV1 {
            .init(accepted: false, reasons: reasons, structures: [], candidate: candidate, sourceBarIDs: selected.map(\.id), orderedSessionIDs: orderedSessionIDs, constituentIDs: lineageEvidence, profile: p, snapshot: s, inputDigest: inputDigest)
        }
        let issues = p.validationIssues()
        guard issues.isEmpty else { return reject(issues) }
        guard !s.id.isEmpty, BreakoutRangeProfileV1.validDigest(s.snapshotDigest), BreakoutRangeProfileV1.validDigest(s.dataDigest) else { return reject(["snapshot_provenance_invalid"]) }
        guard s.instrument == p.instrument else { return reject(["instrument_mismatch"]) }
        guard s.provider == p.provider else { return reject(["provider_mismatch"]) }
        guard s.environment == p.environment else { return reject(["environment_mismatch"]) }
        guard s.timeframeSeconds == p.timeframeSeconds else { return reject(["timeframe_mismatch"]) }
        guard s.aggregationLineageID == p.aggregationLineage.id else { return reject(["aggregation_lineage_mismatch"]) }
        guard p.aggregationLineage.kind == .providerNative else { return reject(["derived_aggregation_lineage_unverified"]) }
        guard p.aggregationLineage.sourceSnapshotIDs == [s.id] else { return reject(["provider_native_snapshot_lineage_mismatch"]) }
        guard candidateMatches.count == 1 else { return reject([candidateMatches.isEmpty ? "candidate_bar_missing" : "candidate_bar_id_duplicated"]) }
        guard let candidate, candidate.complete, candidate.isValid(timeframeSeconds: p.timeframeSeconds) else { return reject(["candidate_bar_invalid"]) }
        guard candidate.startTime.timeIntervalSince1970.isFinite else { return reject(["candidate_time_invalid"]) }
        guard s.capturedAt.timeIntervalSince1970.isFinite,
              candidate.startTime.addingTimeInterval(TimeInterval(p.timeframeSeconds)) <= s.capturedAt else { return reject(["candidate_bar_future_or_incomplete"]) }
        guard selected.count == p.lookbackBars else { return reject(["insufficient_history"]) }
        let used = selected + [candidate]
        guard Set(used.map(\.id)).count == used.count, Set(used.map(\.startTime)).count == used.count else { return reject(["duplicate_bar_input"]) }
        guard used.allSatisfy({ $0.instrument == p.instrument && $0.provider == p.provider }) else { return reject(["bar_identity_mismatch"]) }
        guard used.allSatisfy({ bar in
            let gridSteps = bar.startTime.timeIntervalSince(p.gridOrigin) / tf
            return gridSteps.isFinite && abs(gridSteps - gridSteps.rounded()) < 0.000_000_001
        }) else { return reject(["bar_grid_alignment_invalid"]) }
        guard selected.allSatisfy({ $0.isValid(timeframeSeconds: p.timeframeSeconds) && $0.complete }) else { return reject(["lookback_bar_invalid_or_incomplete"]) }
        guard selected.allSatisfy({ $0.endTime(timeframeSeconds: p.timeframeSeconds) <= s.capturedAt }) else { return reject(["future_lookback_bar"]) }
        guard used.allSatisfy({ bar in
            guard let ids = s.constituentBarIDsByTargetBarID[bar.id] else { return false }
            return !ids.isEmpty && Set(ids).count == ids.count && ids.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }) else { return reject(["aggregation_constituent_lineage_missing_or_invalid"]) }
        let allConstituents = used.flatMap { s.constituentBarIDsByTargetBarID[$0.id] ?? [] }
        guard Set(allConstituents).count == allConstituents.count else { return reject(["aggregation_constituent_lineage_overlap"]) }
        if p.aggregationLineage.kind == .providerNative {
            guard used.allSatisfy({ s.constituentBarIDsByTargetBarID[$0.id] == [$0.id] }) else {
                return reject(["provider_native_lineage_mismatch"])
            }
        }
        let intervals = zip(selected + [candidate], (selected + [candidate]).dropFirst()).map { $1.startTime.timeIntervalSince($0.startTime) }
        guard intervals.allSatisfy({ delta in
            if delta == tf { return true }
            if case .allowAtMostMissingBars(let n) = p.gapPolicy {
                return delta > tf && delta.truncatingRemainder(dividingBy: tf) == 0 && delta <= tf * Double(n + 1)
            }
            return false
        }) else { return reject(["bar_gap_or_off_grid"]) }
        if case .rejectAnyGap = p.gapPolicy, intervals.contains(where: { $0 != tf }) { return reject(["bar_gap_not_approved"]) }
        let sessionIDs = (selected + [candidate]).compactMap { s.sessionIDsByBarID[$0.id] }
        guard sessionIDs.count == selected.count + 1, sessionIDs.allSatisfy({ !$0.isEmpty }) else { return reject(["session_provenance_missing"]) }
        if p.sessionPolicy == .rejectSessionCrossing && Set(sessionIDs).count > 1 { return reject(["session_crossing_not_approved"]) }
        let high = selected.map(\.high).max()!, low = selected.map(\.low).min()!
        let width = (high - low) / p.pipSize
        let minPass = p.minimumWidthBoundary == .inclusive ? width >= p.minimumWidthPips : width > p.minimumWidthPips
        let maxPass = p.maximumWidthBoundary == .inclusive ? width <= p.maximumWidthPips : width < p.maximumWidthPips
        guard width.isFinite, width > 0, minPass, maxPass else { return reject(["range_width_outside_profile"]) }
        let choose: ([BreakoutAcceptanceBar]) -> BreakoutAcceptanceBar = { tied in p.tiePolicy == .earliestSourceBar ? tied.first! : tied.last! }
        let highSource = choose(selected.filter { $0.high == high }), lowSource = choose(selected.filter { $0.low == low })
        let rid = "range-v1-\(inputDigest.prefix(20))"
        let highLevel = BreakoutAcceptanceFrozenLevel(id: "\(rid)-high", price: high, sourceBarIDs: [highSource.id], frozenAt: candidate.startTime)
        let lowLevel = BreakoutAcceptanceFrozenLevel(id: "\(rid)-low", price: low, sourceBarIDs: [lowSource.id], frozenAt: candidate.startTime)
        let structures: [BreakoutAcceptanceStructure] = [
            .range(id: "\(rid)-long", high: highLevel, low: lowLevel, direction: .long),
            .range(id: "\(rid)-short", high: highLevel, low: lowLevel, direction: .short)
        ]
        return .init(accepted: true, reasons: [], structures: structures, candidate: candidate,
            sourceBarIDs: selected.map(\.id), orderedSessionIDs: orderedSessionIDs, constituentIDs: lineageEvidence, profile: p, snapshot: s, inputDigest: inputDigest)
    }
}

private enum BreakoutRangeBuilderHashV1 {
    static func hash<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let data = (try? e.encode(v)) ?? Data("canonical-encoding-error".utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
