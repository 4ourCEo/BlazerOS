import Foundation
import Testing
@testable import BlazerCore
@testable import LightningDesk

struct ORBBreakRetestLifecycleV1Tests {
    private var session: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 6,
                                                  hour: 9, minute: 30))!
    }

    private func bars() -> [ORBBar] {
        func bar(_ suffix: String, _ minute: Int, _ open: Double, _ high: Double,
                 _ low: Double, _ close: Double) -> ORBBar {
            let start = session.addingTimeInterval(Double(minute * 60))
            return ORBBar(id: "EUR/USD-\(suffix)", instrument: "EUR/USD", sourceTime: start,
                endTime: start.addingTimeInterval(60), open: open, high: high, low: low, close: close)
        }
        return (0..<5).map { bar("range-\($0)", $0, 1.102, 1.105, 1.100, 1.102) } + [
            bar("break", 5, 1.104, 1.107, 1.103, 1.106),
            bar("retest", 6, 1.1055, 1.106, 1.1049, 1.1052),
            bar("confirm", 7, 1.1052, 1.107, 1.105, 1.106)
        ]
    }

    @Test func confirmedProjectionUsesCompletedBarCloseAndStableIdentity() throws {
        let bars = bars()
        let asOf = session.addingTimeInterval(8 * 60)
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars, asOf: asOf)
        guard case let .projected(first) = ORBBreakRetestLifecycleV1.project(decision: decision, bars: bars, asOf: asOf),
              case let .projected(repeated) = ORBBreakRetestLifecycleV1.project(decision: decision, bars: bars,
                                                                                 asOf: asOf.addingTimeInterval(5)) else {
            Issue.record("Expected complete ORB evidence to project")
            return
        }
        #expect(first.state == .confirmed)
        #expect(first.setupID == repeated.setupID)
        #expect(first.eventID == repeated.eventID)
        #expect(first.sourceObservationID == "EUR/USD-confirm")
        #expect(first.sourceTime == bars.last?.endTime)
        #expect(first.sourceTime <= asOf)
        #expect(first.sourceBarIDs == bars.map(\.id))
        let event = ORBBreakRetestLifecycleV1.event(for: first, previousState: nil, recordedAt: asOf)
        #expect(event.planID == decision.candidate?.plan.id)
        #expect(event.quoteSequence == nil)
        #expect(event.sourceBarIDs?.contains(event.sourceObservationID ?? "") == true)
        #expect(event.validation().isEmpty)

        let changedConfiguration = ORBConfiguration(retestTolerance: 0.0002)
        guard case let .projected(revised) = ORBBreakRetestLifecycleV1.project(
            decision: decision, bars: bars, asOf: asOf, configuration: changedConfiguration) else {
            Issue.record("Expected revised configuration evidence to project")
            return
        }
        #expect(revised.setupID != first.setupID)
        #expect(revised.structureID == first.structureID)

        var changedRange = bars
        let originalRangeBar = changedRange[0]
        changedRange[0] = ORBBar(id: "EUR/USD-range-revised", instrument: originalRangeBar.instrument,
            sourceTime: originalRangeBar.sourceTime, endTime: originalRangeBar.endTime,
            open: originalRangeBar.open, high: 1.104, low: originalRangeBar.low, close: originalRangeBar.close)
        let revisedDecision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: changedRange, asOf: asOf)
        guard case let .projected(revisedStructure) = ORBBreakRetestLifecycleV1.project(
            decision: revisedDecision, bars: changedRange, asOf: asOf) else {
            Issue.record("Changed opening range should form a separately identified structure")
            return
        }
        #expect(revisedStructure.setupID != first.setupID)
        #expect(revisedStructure.structureID != first.structureID)
    }

    @Test func invalidationEvidenceRemainsBoundToCausativeRetestBar() throws {
        var sourceBars = bars()
        let retest = sourceBars[6]
        sourceBars[6] = ORBBar(id: retest.id, instrument: retest.instrument,
            sourceTime: retest.sourceTime, endTime: retest.endTime,
            open: retest.open, high: retest.high, low: 1.1039, close: 1.104)
        let asOf = sourceBars[6].endTime
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: sourceBars, asOf: asOf)
        #expect(decision.stage == .invalidated)
        #expect(decision.causativeBarID == retest.id)
        guard case let .projected(first) = ORBBreakRetestLifecycleV1.project(
            decision: decision, bars: sourceBars, asOf: asOf) else {
            Issue.record("Failing retest should produce an invalidation projection")
            return
        }
        let laterStart = sourceBars.last!.endTime
        let later = ORBBar(id: "EUR/USD-after-failure", instrument: "EUR/USD",
            sourceTime: laterStart, endTime: laterStart.addingTimeInterval(60),
            open: 1.104, high: 1.105, low: 1.103, close: 1.104)
        let extendedBars = sourceBars + [later]
        let laterDecision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: extendedBars,
            asOf: later.endTime)
        guard case let .projected(repeated) = ORBBreakRetestLifecycleV1.project(
            decision: laterDecision, bars: extendedBars, asOf: later.endTime) else {
            Issue.record("Later bars should not change the retest invalidation evidence")
            return
        }
        #expect(first.sourceObservationID == retest.id)
        #expect(first.sourceTime == retest.endTime)
        #expect(first.sourceBarIDs == sourceBars.prefix(7).map(\.id))
        #expect(first.sourceBarIDs.contains(retest.id))
        #expect(first.inputDigest == repeated.inputDigest)
        #expect(first.eventID == repeated.eventID)
        #expect(first.sourceObservationID == repeated.sourceObservationID)
        #expect(first.sourceTime == repeated.sourceTime)

        var changedPrefix = sourceBars
        let breakout = changedPrefix[5]
        changedPrefix[5] = ORBBar(id: breakout.id, instrument: breakout.instrument,
            sourceTime: breakout.sourceTime, endTime: breakout.endTime,
            open: breakout.open, high: 1.108, low: breakout.low, close: breakout.close)
        let changedDecision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD",
            bars: changedPrefix, asOf: asOf)
        guard case let .projected(changed) = ORBBreakRetestLifecycleV1.project(
            decision: changedDecision, bars: changedPrefix, asOf: asOf) else {
            Issue.record("Changed causal prefix should remain a valid invalidation")
            return
        }
        #expect(changedDecision.causativeBarID == retest.id)
        #expect(changed.structureID == first.structureID)
        #expect(changed.sourceObservationID == first.sourceObservationID)
        #expect(changed.sourceTime == first.sourceTime)
        #expect(changed.inputDigest != first.inputDigest)
        #expect(changed.eventID != first.eventID)
    }

    @Test func projectionPersistsConfiguredBarTimeframe() async throws {
        let barMinutes = 5
        let configuration = ORBConfiguration(openingRangeMinutes: 25, barMinutes: barMinutes)
        func customBar(_ suffix: String, _ minute: Int, _ open: Double,
                       _ high: Double, _ low: Double, _ close: Double) -> ORBBar {
            let start = session.addingTimeInterval(Double(minute * 60))
            return ORBBar(id: "EUR/USD-\(suffix)", instrument: "EUR/USD", sourceTime: start,
                endTime: start.addingTimeInterval(Double(barMinutes * 60)),
                open: open, high: high, low: low, close: close)
        }
        let customBars = (0..<5).map { index in
            customBar("range-\(index)", index * barMinutes, 1.102, 1.105, 1.100, 1.102)
        } + [
            customBar("break", 25, 1.104, 1.107, 1.103, 1.106),
            customBar("retest", 30, 1.1055, 1.106, 1.1049, 1.1052),
            customBar("confirm", 35, 1.1052, 1.107, 1.105, 1.106)
        ]
        let asOf = session.addingTimeInterval(40 * 60)
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: customBars,
            asOf: asOf, configuration: configuration)
        guard case let .projected(projection) = ORBBreakRetestLifecycleV1.project(
            decision: decision, bars: customBars, asOf: asOf, configuration: configuration) else {
            Issue.record("Custom timeframe evidence should project")
            return
        }
        #expect(projection.timeframeSeconds == 300)
        let event = ORBBreakRetestLifecycleV1.event(for: projection, previousState: nil,
            recordedAt: asOf)
        #expect(event.timeframeSeconds == 300)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orb-custom-timeframe-\(UUID().uuidString)")
        try await ResearchStore(root: root).record(event)
        let reloaded = try await ResearchStore(root: root).v3SetupLifecycleEvents()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.timeframeSeconds == 300)
    }

    @Test func confirmedLifecycleIsVisibleInReviewPlanTimeline() throws {
        let sourceBars = bars()
        let asOf = session.addingTimeInterval(8 * 60)
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: sourceBars, asOf: asOf)
        guard let plan = decision.candidate?.plan,
              case let .projected(projection) = ORBBreakRetestLifecycleV1.project(
                decision: decision, bars: sourceBars, asOf: asOf) else {
            Issue.record("Fixture must produce a persisted plan and lifecycle projection")
            return
        }
        let event = ORBBreakRetestLifecycleV1.event(for: projection, previousState: nil, recordedAt: asOf)
        let detail = try #require(V3ReviewArchiveSnapshot(plans: [plan], setupLifecycleEvents: [event])
            .detail(for: plan.id))
        #expect(detail.timeline.contains { $0.title == "Setup lifecycle · CONFIRMED" })
        #expect(detail.timeline.first(where: { $0.kind == "setup lifecycle" })?.detail.contains("OANDA / OANDA_LIVE") == true)
        #expect(detail.emptyCategories.contains("No entry evidence record is stored."))
    }

    @Test func projectionIgnoresFutureBarsAndUnsealedRanges() throws {
        let bars = bars()
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
            asOf: session.addingTimeInterval(8 * 60))
        #expect(ORBBreakRetestLifecycleV1.project(decision: decision, bars: Array(bars.reversed()),
            asOf: session.addingTimeInterval(8 * 60)) == .unavailable)
        #expect(ORBBreakRetestLifecycleV1.project(decision: decision, bars: bars,
            asOf: session.addingTimeInterval(7 * 60)) == .unavailable)

        let forming = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars.prefix(3).map { $0 },
            asOf: session.addingTimeInterval(3 * 60))
        #expect(ORBBreakRetestLifecycleV1.project(decision: forming, bars: Array(bars.prefix(3)),
            asOf: session.addingTimeInterval(3 * 60)) == .notApplicable)
    }

    @Test func orbLifecycleRequiresNilQuoteSequenceAndStrictCloseTimeProgression() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let digest = String(repeating: "a", count: 64)
        func event(_ id: String, _ previous: V3SetupState?, _ state: V3SetupState,
                   _ sourceTime: Date, sequence: UInt64? = nil) -> V3SetupLifecycleEvent {
            V3SetupLifecycleEvent(id: id, setupID: "orb-setup", instrument: "EUR/USD",
                strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
                provider: "OANDA", environment: .oandaLive, previousState: previous, state: state,
                sourceObservationID: "EUR/USD-bar-\(id)", sourceTime: sourceTime,
                receivedAt: sourceTime, recordedAt: time.addingTimeInterval(300), planID: state == .confirmed ? "orb-plan" : nil,
                reason: "observed", configurationDigest: digest, inputDigest: digest,
                engineVersion: "V3_ORB_ENGINE_1", sourceBarIDs: ["EUR/USD-bar-\(id)"],
                quoteSequence: sequence, reasonCodes: ["observed"], structureID: "orb-structure",
                timeframeSeconds: 60, evidenceSchemaVersion: 1)
        }
        let first = event("bar-1", nil, .watching, time)
        let next = event("bar-2", .watching, .approaching, time.addingTimeInterval(60))
        #expect(V3SetupLifecycle.validationIssues(for: [first, next]).isEmpty)
        let equalTime = event("bar-3", .approaching, .confirmed, time.addingTimeInterval(60))
        #expect(V3SetupLifecycle.validationIssues(for: [first, next, equalTime])
            .contains("orb_source_time_not_strictly_increasing"))
        let inventedSequence = event("bar-4", .watching, .approaching,
                                     time.addingTimeInterval(120), sequence: 2)
        #expect(inventedSequence.validation().contains("evaluator_provenance_incomplete"))
        let terminal = event("bar-5", .approaching, .invalidated, time.addingTimeInterval(180))
        let resurrection = event("bar-6", .invalidated, .watching, time.addingTimeInterval(240))
        #expect(V3SetupLifecycle.validationIssues(for: [first, next, terminal, resurrection])
            .contains("invalid_state_transition"))
    }

    @Test func terminalORBStructureCannotBeRearmedByChangedConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orb-terminal-structure-\(UUID().uuidString)")
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let digest = String(repeating: "c", count: 64)
        func event(_ id: String, setupID: String, state: V3SetupState,
                   sourceTime: Date, configurationDigest: String,
                   structureID: String = "orb-frozen-range") -> V3SetupLifecycleEvent {
            V3SetupLifecycleEvent(id: id, setupID: setupID, instrument: "EUR/USD",
                strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
                provider: "OANDA", environment: .oandaLive, previousState: nil, state: state,
                sourceObservationID: "EUR/USD-\(id)", sourceTime: sourceTime,
                receivedAt: sourceTime, recordedAt: sourceTime.addingTimeInterval(1),
                reason: "observed", configurationDigest: configurationDigest, inputDigest: digest,
                engineVersion: "V3_ORB_ENGINE_1", sourceBarIDs: ["EUR/USD-\(id)"],
                reasonCodes: ["observed"], structureID: structureID,
                timeframeSeconds: 60, evidenceSchemaVersion: 1)
        }
        let terminal = event("orb-terminal", setupID: "orb-setup-old", state: .invalidated,
            sourceTime: time, configurationDigest: digest)
        let reopened = event("orb-reopened", setupID: "orb-setup-new", state: .watching,
            sourceTime: time.addingTimeInterval(60), configurationDigest: String(repeating: "d", count: 64))
        #expect(V3SetupLifecycle.validationIssues(for: [terminal]).isEmpty)
        #expect(V3SetupLifecycle.archiveValidationIssues(for: [terminal, reopened])
            .contains("orb_terminal_structure_rearmed"))
        let store = ResearchStore(root: root)
        try await store.record(terminal)
        do {
            try await ResearchStore(root: root).record(reopened)
            Issue.record("Terminal structure must suppress the changed-configuration stream")
        } catch {
            #expect(error as? ScanError == .failed("ORB_STRUCTURE_SUPPRESSED"))
        }
        #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents() == [terminal])
        let nextSession = event("orb-new-session", setupID: "orb-setup-next-session", state: .watching,
            sourceTime: time.addingTimeInterval(120), configurationDigest: digest,
            structureID: "orb-next-session-range")
        try await ResearchStore(root: root).record(nextSession)
        #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents().count == 2)
    }

    @Test func separateResearchStoresSerializeExactReplayAndRejectConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orb-lifecycle-lock-\(UUID().uuidString)")
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let digest = String(repeating: "b", count: 64)
        let original = V3SetupLifecycleEvent(id: "orb-event", setupID: "orb-setup",
            instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1", provider: "OANDA", environment: .oandaLive,
            previousState: nil, state: .watching, sourceObservationID: "EUR/USD-bar",
            sourceTime: time, receivedAt: time, recordedAt: time, reason: "range_sealed",
            configurationDigest: digest, inputDigest: digest, engineVersion: "V3_ORB_ENGINE_1",
            sourceBarIDs: ["EUR/USD-bar"], reasonCodes: ["range_sealed"],
            structureID: "orb-structure", timeframeSeconds: 60, evidenceSchemaVersion: 1)
        let retry = V3SetupLifecycleEvent(id: original.id, setupID: original.setupID,
            instrument: original.instrument, strategyID: original.strategyID,
            strategyVersion: original.strategyVersion, provider: original.provider,
            environment: original.environment, previousState: original.previousState,
            state: original.state, sourceObservationID: original.sourceObservationID,
            sourceTime: original.sourceTime, receivedAt: time.addingTimeInterval(3),
            recordedAt: time.addingTimeInterval(3), reason: original.reason,
            configurationDigest: original.configurationDigest, inputDigest: original.inputDigest,
            engineVersion: original.engineVersion, sourceBarIDs: original.sourceBarIDs,
            reasonCodes: original.reasonCodes, structureID: original.structureID,
            timeframeSeconds: original.timeframeSeconds, evidenceSchemaVersion: 1)
        async let first: Void = ResearchStore(root: root).record(original)
        async let second: Void = ResearchStore(root: root).record(retry)
        _ = try await (first, second)
        let loaded = try await ResearchStore(root: root).v3SetupLifecycleEvents()
        #expect(loaded.count == 1)
        #expect(loaded[0].recordedAt == time || loaded[0].recordedAt == time.addingTimeInterval(3))

        let gated = V3SetupLifecycleEvent(id: "orb-event-gated", setupID: "orb-setup-gated",
            instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
            strategyVersion: "ORB_BREAK_RETEST_V1", provider: "OANDA", environment: .oandaLive,
            previousState: nil, state: .watching, sourceObservationID: "EUR/USD-gated-bar",
            sourceTime: time.addingTimeInterval(60), receivedAt: time.addingTimeInterval(60),
            recordedAt: time.addingTimeInterval(300), reason: "range_sealed",
            configurationDigest: digest, inputDigest: digest, engineVersion: "V3_ORB_ENGINE_1",
            sourceBarIDs: ["EUR/USD-gated-bar"], reasonCodes: ["range_sealed"],
            structureID: "orb-structure-gated", timeframeSeconds: 60, evidenceSchemaVersion: 1)
        let gatedResult = try await ResearchStore(root: root).record(gated, shouldAppend: { false })
        #expect(gatedResult == .generationSuperseded)
        #expect(try await ResearchStore(root: root).v3SetupLifecycleEvents().count == 1)

        let retainedRoot = root.appendingPathComponent("retained-original", isDirectory: true)
        let firstWrite = try await ResearchStore(root: retainedRoot).record(original,
            shouldAppend: { true })
        let replay = try await ResearchStore(root: retainedRoot).record(retry,
            shouldAppend: { true })
        #expect(firstWrite == .appended)
        #expect(replay == .duplicate)
        let retained = try await ResearchStore(root: retainedRoot).v3SetupLifecycleEvents()
        #expect(retained.count == 1)
        #expect(retained[0].receivedAt == original.receivedAt)
        #expect(retained[0].recordedAt == original.recordedAt)

        let conflict = V3SetupLifecycleEvent(id: original.id, setupID: original.setupID,
            instrument: original.instrument, strategyID: original.strategyID,
            strategyVersion: original.strategyVersion, provider: original.provider,
            environment: original.environment, previousState: original.previousState,
            state: original.state, sourceObservationID: original.sourceObservationID,
            sourceTime: original.sourceTime, receivedAt: time, recordedAt: time,
            reason: "changed", configurationDigest: original.configurationDigest,
            inputDigest: original.inputDigest, engineVersion: original.engineVersion,
            sourceBarIDs: original.sourceBarIDs, reasonCodes: ["changed"],
            structureID: original.structureID, timeframeSeconds: 60, evidenceSchemaVersion: 1)
        await #expect(throws: ScanError.self) { try await ResearchStore(root: root).record(conflict) }
    }
}
