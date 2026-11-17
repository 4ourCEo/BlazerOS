import Foundation
import Testing
@testable import BlazerCore

struct BreakoutAcceptanceRangeBuilderV1Tests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let digest = String(repeating: "a", count: 64)

    private func bar(_ id: String, _ offset: Double, _ high: Double, _ low: Double,
                     complete: Bool = true, instrument: String = "EUR/USD", provider: String = "OANDA") -> BreakoutAcceptanceBar {
        .init(id: id, instrument: instrument, provider: provider, startTime: t0.addingTimeInterval(offset), open: (high + low) / 2,
              high: high, low: low, close: (high + low) / 2, complete: complete)
    }

    private var lookback: [BreakoutAcceptanceBar] {
        [bar("a", 0, 1.102, 1.098), bar("b", 60, 1.103, 1.097), bar("c", 120, 1.101, 1.099)]
    }
    private var candidate: BreakoutAcceptanceBar { bar("candidate", 180, 1.104, 1.096) }
    private var future: BreakoutAcceptanceBar { bar("future", 240, 9, 0.1) }

    private func profile(tie: BreakoutRangeTiePolicyV1 = .earliestSourceBar,
                         gap: BreakoutRangeGapPolicyV1 = .rejectAnyGap,
                         session: BreakoutRangeSessionPolicyV1 = .rejectSessionCrossing,
                         min: Double = 40, max: Double = 80,
                         minBoundary: BreakoutRangeWidthBoundaryPolicyV1 = .inclusive,
                         maxBoundary: BreakoutRangeWidthBoundaryPolicyV1 = .inclusive,
                         timeframe: Int = 60, lineage: String = "agg-v1",
                         aggregationKind: BreakoutRangeAggregationKindV1 = .providerNative,
                         aggregationMethod: String = "provider-native",
                         sourceSnapshotID: String = "snapshot-1",
                         datasetDigest: String? = nil, gridOrigin: Date = Date(timeIntervalSince1970: 1_700_000_000),
                         sessionDefinition: BreakoutRangeSessionDefinitionV1 = .init(id: "london", timeZoneIdentifier: "Europe/London", dstPolicy: .rejectTransitionBoundary)) -> BreakoutRangeProfileV1 {
        .init(version: "range-v1", instrument: "EUR/USD", provider: "OANDA", environment: "PRACTICE",
            timeframeSeconds: timeframe, gridOrigin: gridOrigin, pipSize: 0.0001, lookbackBars: 3,
            minimumWidthPips: min, maximumWidthPips: max, minimumWidthBoundary: minBoundary,
            maximumWidthBoundary: maxBoundary, tiePolicy: tie, gapPolicy: gap,
            sessionPolicy: session, sessionDefinition: sessionDefinition,
            aggregationLineage: .init(id: lineage, kind: aggregationKind, sourceTimeframeSeconds: 60,
                targetTimeframeSeconds: timeframe, method: aggregationMethod, sourceSnapshotIDs: [sourceSnapshotID]),
            engineIdentity: "engine-sha-1", buildIdentity: "build-42", datasetDigest: datasetDigest ?? digest, codeDigest: digest)
    }

    private func snapshot(_ bars: [BreakoutAcceptanceBar], instrument: String = "EUR/USD",
                          provider: String = "OANDA", environment: String = "PRACTICE",
                          timeframe: Int = 60, lineage: String = "agg-v1",
                          sessions: [String: String]? = nil,
                          constituents: [String: [String]]? = nil,
                          snapshotDigest: String? = nil, dataDigest: String? = nil, snapshotID: String = "snapshot-1",
                          capturedAt: Date? = nil) -> BreakoutRangeSnapshotV1 {
        .init(id: snapshotID, instrument: instrument, provider: provider, environment: environment,
            timeframeSeconds: timeframe, aggregationLineageID: lineage, snapshotDigest: snapshotDigest ?? digest,
            dataDigest: dataDigest ?? digest, capturedAt: capturedAt ?? candidate.endTime(timeframeSeconds: 60),
            bars: bars, sessionIDsByBarID: sessions ?? Dictionary(bars.map { ($0.id, "london-1") }, uniquingKeysWith: { first, _ in first }),
            constituentBarIDsByTargetBarID: constituents ?? Dictionary(bars.map { ($0.id, [$0.id]) }, uniquingKeysWith: { first, _ in first }))
    }

    private func build(_ bars: [BreakoutAcceptanceBar], profile: BreakoutRangeProfileV1? = nil,
                       snapshot: BreakoutRangeSnapshotV1? = nil) -> BreakoutRangeBuilderResultV1 {
        BreakoutAcceptanceRangeBuilderV1.build(profile: profile ?? self.profile(),
            snapshot: snapshot ?? self.snapshot(bars), candidateBarID: "candidate")
    }

    @Test func buildsExactPriorLookbackAndFreezesStructureAtCandidateStart() {
        let result = build(lookback + [candidate])
        #expect(result.accepted)
        #expect(result.sourceBarIDs == ["a", "b", "c"])
        #expect(result.candidateBarID == "candidate")
        #expect(result.candidateStart == candidate.startTime)
        #expect(result.structures.count == 2)
        if case .range(let id, let high, let low, let direction) = result.structures[0] {
            #expect(id.hasPrefix("range-v1-"))
            #expect(direction == .long)
            #expect(high.price == 1.103)
            #expect(low.price == 1.097)
            #expect(high.sourceBarIDs == ["b"])
            #expect(low.sourceBarIDs == ["b"])
            #expect(high.frozenAt == candidate.startTime)
            #expect(low.frozenAt == candidate.startTime)
        } else { Issue.record("Expected an adapter-ready long range structure") }
        if case .range(_, let high, let low, let direction) = result.structures[1] {
            #expect(direction == .short)
            #expect(high.price == low.price + 0.006)
        } else { Issue.record("Expected an adapter-ready short range structure") }
        #expect(result.profileDigest.count == 64)
        #expect(result.inputDigest.count == 64)
        #expect(result.contextDigest.count == 64)
        #expect(result.environment == "PRACTICE")
        #expect(result.datasetDigest == digest)
        #expect(result.snapshotDigest == digest)
        #expect(result.codeDigest == digest)
        #expect(result.sessionDefinition.id == "london")
        #expect(result.orderedSessionIDs == ["london-1", "london-1", "london-1", "london-1"])
        #expect(result.sourceLineageDigest.count == 64)
        #expect(result.constituentBarIDsByTargetBarID["b"] == ["b"])
    }

    @Test func futureBarsAndInputReorderingCannotChangeFrozenOutput() {
        let base = lookback + [candidate]
        let first = build(base)
        let appended = build(base + [future])
        let reordered = build(Array(base.reversed()))
        #expect(first.structures == appended.structures)
        #expect(first.inputDigest == appended.inputDigest)
        #expect(first.profileDigest == appended.profileDigest)
        #expect(first.structures == reordered.structures)
        #expect(first.inputDigest == reordered.inputDigest)
        #expect(first == reordered)
    }

    @Test func appendedDataChangesContextButNotCausalRangeIdentity() {
        let originalBars = lookback + [candidate]
        let first = build(originalBars)
        let changed = snapshot(originalBars + [future], snapshotDigest: String(repeating: "b", count: 64),
            dataDigest: String(repeating: "c", count: 64), snapshotID: "snapshot-2",
            capturedAt: future.endTime(timeframeSeconds: 60))
        let later = build(originalBars + [future], profile: profile(sourceSnapshotID: "snapshot-2", datasetDigest: String(repeating: "d", count: 64)), snapshot: changed)
        #expect(first.inputDigest == later.inputDigest)
        #expect(first.structures == later.structures)
        #expect(first.profileDigest != later.profileDigest)
        #expect(first.structures.map { $0.structureID } == later.structures.map { $0.structureID })
        #expect(first.contextDigest != later.contextDigest)

        let changedLabels = snapshot(originalBars, sessions: ["a":"x", "b":"x", "c":"y", "candidate":"y"])
        let sessionChanged = build(originalBars, profile: profile(session: .allowSessionCrossing), snapshot: changedLabels)
        let sessionOriginal = build(originalBars, profile: profile(session: .allowSessionCrossing))
        #expect(sessionChanged.accepted && sessionOriginal.accepted)
        #expect(sessionChanged.inputDigest != sessionOriginal.inputDigest)
        let dstChanged = build(originalBars,
            profile: profile(session: .allowSessionCrossing,
                sessionDefinition: .init(id: "london", timeZoneIdentifier: "Europe/London", dstPolicy: .allowElapsedTime)))
        #expect(dstChanged.inputDigest != sessionOriginal.inputDigest)
    }

    @Test func selectedTiePolicyAndWidthBoundaryPoliciesAreExplicit() {
        let tied = [bar("early", 0, 1.103, 1.097), bar("mid", 60, 1.102, 1.098),
                    bar("late", 120, 1.103, 1.097), candidate]
        let earliest = build(tied, profile: profile(tie: .earliestSourceBar))
        let latest = build(tied, profile: profile(tie: .latestSourceBar))
        if case .range(_, let hiEarly, let loEarly, _) = earliest.structures.first,
           case .range(_, let hiLatest, let loLatest, _) = latest.structures.first {
            #expect(hiEarly.sourceBarIDs == ["early"])
            #expect(loEarly.sourceBarIDs == ["early"])
            #expect(hiLatest.sourceBarIDs == ["late"])
            #expect(loLatest.sourceBarIDs == ["late"])
        } else { Issue.record("Expected both tie-policy structures") }
        #expect(earliest.profileDigest != latest.profileDigest)
        let exactWidth = (1.103 - 1.097) / 0.0001
        #expect(build(lookback + [candidate], profile: profile(min: exactWidth, max: exactWidth)).accepted)
        #expect(build(lookback + [candidate], profile: profile(min: exactWidth, max: 80, minBoundary: .exclusive))
            .reasonCodes.contains("range_width_outside_profile"))
        #expect(build(lookback + [candidate], profile: profile(min: 40, max: exactWidth, maxBoundary: .exclusive))
            .reasonCodes.contains("range_width_outside_profile"))
    }

    @Test func rejectsIdentityLineageAndProfileErrors() {
        let bars = lookback + [candidate]
        #expect(build(bars, snapshot: snapshot(bars, instrument: "GBP/USD")).reasonCodes.contains("instrument_mismatch"))
        #expect(build(bars, snapshot: snapshot(bars, provider: "other")).reasonCodes.contains("provider_mismatch"))
        #expect(build(bars, snapshot: snapshot(bars, environment: "LIVE")).reasonCodes.contains("environment_mismatch"))
        #expect(build(bars, snapshot: snapshot(bars, timeframe: 300)).reasonCodes.contains("timeframe_mismatch"))
        #expect(build(bars, snapshot: snapshot(bars, lineage: "other")).reasonCodes.contains("aggregation_lineage_mismatch"))
        let wrongRow = [bar("a", 0, 1.102, 1.098, provider: "OTHER"), lookback[1], lookback[2], candidate]
        #expect(build(wrongRow).reasonCodes.contains("bar_identity_mismatch"))
        #expect(build(bars, profile: profile(timeframe: 0, lineage: "")).accepted == false)
        #expect(build(bars, profile: profile(sourceSnapshotID: "other"))
            .reasonCodes.contains("provider_native_snapshot_lineage_mismatch"))
        #expect(build(bars, profile: profile(min: .nan)).reasonCodes.contains("width_profile_invalid"))
    }

    @Test func rejectsMissingDuplicateMalformedIncompleteAndFutureCandidates() {
        #expect(build(lookback).reasonCodes.contains("candidate_bar_missing"))
        let duplicate = lookback + [candidate, bar("candidate", 300, 1.1, 1.0)]
        #expect(build(duplicate).reasonCodes.contains("candidate_bar_id_duplicated"))
        let malformed = [bar("a", 0, 1.0, 1.1), lookback[1], lookback[2], candidate]
        #expect(build(malformed).reasonCodes.contains("lookback_bar_invalid_or_incomplete"))
        let incomplete = [lookback[0], bar("b", 60, 1.103, 1.097, complete: false), lookback[2], candidate]
        #expect(build(incomplete).reasonCodes.contains("lookback_bar_invalid_or_incomplete"))
        let futureSnapshot = snapshot(lookback + [candidate], capturedAt: candidate.startTime)
        #expect(build(lookback + [candidate], snapshot: futureSnapshot).reasonCodes.contains("candidate_bar_future_or_incomplete"))
    }

    @Test func rejectsInsufficientGappedOffGridAndUnapprovedSessionCrossing() {
        #expect(build([lookback[1], lookback[2], candidate]).reasonCodes.contains("insufficient_history"))
        let gapped = [lookback[0], lookback[2], candidate]
        #expect(build(gapped).reasonCodes.contains("insufficient_history"))
        let sourceGap = [lookback[0], bar("b-gap", 120, 1.103, 1.097), bar("c-gap", 180, 1.101, 1.099), bar("candidate", 240, 1.104, 1.096)]
        let sourceGapSnapshot = snapshot(sourceGap, capturedAt: sourceGap.last!.endTime(timeframeSeconds: 60))
        let result = build(sourceGap, snapshot: sourceGapSnapshot)
        #expect(result.reasonCodes.contains("bar_gap_or_off_grid"))
        let crossing = snapshot(lookback + [candidate], sessions: ["a":"s1", "b":"s1", "c":"s2", "candidate":"s2"])
        #expect(build(lookback + [candidate], snapshot: crossing).reasonCodes.contains("session_crossing_not_approved"))
        let allowed = build(lookback + [candidate], profile: profile(session: .allowSessionCrossing), snapshot: crossing)
        #expect(allowed.accepted)
        let approvedGap = build(sourceGap, profile: profile(gap: .allowAtMostMissingBars(1)), snapshot: sourceGapSnapshot)
        #expect(approvedGap.accepted)

        let offGridBars = [bar("a", 30, 1.102, 1.098), bar("b", 90, 1.103, 1.097),
                           bar("c", 150, 1.101, 1.099), bar("candidate", 210, 1.104, 1.096)]
        let offGridSnapshot = snapshot(offGridBars, capturedAt: offGridBars.last!.endTime(timeframeSeconds: 60))
        #expect(build(offGridBars, snapshot: offGridSnapshot).reasonCodes.contains("bar_grid_alignment_invalid"))

        let derivedIDs = ["a": ["m1-a1", "m1-a2"], "b": ["m1-b1", "m1-b2"],
                          "c": ["m1-c1", "m1-c2"], "candidate": ["m1-x1", "m1-x2"]]
        let derivedProfile = profile(aggregationKind: .derived, aggregationMethod: "derived-ohlc")
        let derivedSnapshot = snapshot(lookback + [candidate], constituents: derivedIDs)
        let derived = build(lookback + [candidate], profile: derivedProfile, snapshot: derivedSnapshot)
        #expect(!derived.accepted)
        #expect(derived.reasonCodes.contains("derived_aggregation_lineage_unverified"))
        let overlapping = snapshot(lookback + [candidate], constituents: ["a":["same"], "b":["same"], "c":["c"], "candidate":["candidate"]])
        #expect(build(lookback + [candidate], profile: derivedProfile, snapshot: overlapping)
            .reasonCodes.contains("derived_aggregation_lineage_unverified"))
        #expect(build(lookback + [candidate], snapshot: snapshot(lookback + [candidate],
            constituents: ["a":["wrong"], "b":["b"], "c":["c"], "candidate":["candidate"]]))
            .reasonCodes.contains("provider_native_lineage_mismatch"))
    }

    @Test func rejectsZeroWidthEvenWhenProfileAllowsZeroMinimum() {
        let flat = [bar("a", 0, 1.1, 1.1), bar("b", 60, 1.1, 1.1),
                    bar("c", 120, 1.1, 1.1), candidate]
        let result = build(flat, profile: profile(min: 0, max: 1))
        #expect(result.reasonCodes.contains("range_width_outside_profile"))
    }

    @Test func reportsStableRejectionAndCarriesFullContextIdentity() {
        let narrow = [bar("a", 0, 1.1001, 1.0999), bar("b", 60, 1.1002, 1.0998),
                      bar("c", 120, 1.1001, 1.0999), candidate]
        let a = build(narrow)
        let b = build(narrow)
        #expect(!a.accepted)
        #expect(a.reasonCodes == ["range_width_outside_profile"])
        #expect(a.inputDigest == b.inputDigest)
        #expect(a.contextDigest == b.contextDigest)
        #expect(a.engineIdentity == "engine-sha-1")
        #expect(a.buildIdentity == "build-42")
        #expect(a.dataDigest == digest)
    }
}
