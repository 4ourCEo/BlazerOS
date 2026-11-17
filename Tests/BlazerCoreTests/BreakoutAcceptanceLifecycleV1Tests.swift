import Foundation
import Testing
@testable import BlazerCore

struct BreakoutAcceptanceLifecycleV1Tests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-breakout-lifecycle-\(UUID().uuidString)")

    private func bar(_ id: String, _ offset: TimeInterval, _ open: Double, _ high: Double,
                     _ low: Double, _ close: Double) -> BreakoutAcceptanceBar {
        .init(id: id, instrument: "EUR/USD", provider: "OANDA",
              startTime: t0.addingTimeInterval(offset), open: open, high: high,
              low: low, close: close, complete: true)
    }

    private var structure: BreakoutAcceptanceStructure {
        .range(id: "range-1",
            high: .init(id: "range-high", price: 1.1000, sourceBarIDs: ["s0", "s1"],
                        frozenAt: t0.addingTimeInterval(120)),
            low: .init(id: "range-low", price: 1.0900, sourceBarIDs: ["s0", "s1"],
                       frozenAt: t0.addingTimeInterval(120)), direction: .long)
    }

    private func configuration(structure: BreakoutAcceptanceStructure? = nil,
                               mode: BreakoutAcceptanceMode = .sustainedBarsBeyond(additionalBars: 1, holdBufferPips: 1),
                               maximumSpreadPips: Double = 3) -> BreakoutAcceptanceConfiguration {
        let frozen = structure ?? self.structure
        let at = frozen.frozenAt
        return .init(version: "v1", instrument: "EUR/USD", provider: "OANDA", pipSize: 0.0001,
            timeframeSeconds: 60, structure: frozen, regimeDefinitionID: "atr-v1",
            regimeDefinitionDigest: String(repeating: "a", count: 64), minimumRegimeValue: 0.5,
            maximumRegimeValue: 2, minimumDisplacementPips: 5, acceptanceMode: mode,
            maximumSetupAgeSeconds: 300, maximumCompletedBarsAfterAcceptance: 3,
            sessionPolicy: .sessionAgnostic, rearmPolicy: .newFrozenStructureRequired,
            clusterWindowSeconds: 60, maximumSpreadPips: maximumSpreadPips,
            maximumQuoteAgeSeconds: 10, additionalCostsPips: 1,
            minimumMovementToCostRatio: 2, maximumAdverseEntryDriftPips: 2,
            stop: .init(id: "stop", price: 1.095, sourceBarIDs: ["s0"], frozenAt: at),
            target: .init(id: "target", price: 1.110, sourceBarIDs: ["s1"], frozenAt: at))
    }

    private func evidence(_ bars: [BreakoutAcceptanceBar], config: BreakoutAcceptanceConfiguration,
                          sequence: UInt64, sourceOffset: TimeInterval? = nil,
                          spread: Double = 0.0001) -> BreakoutAcceptanceEvidence {
        let lastEnd = bars.map(\.startTime).max()!.addingTimeInterval(60)
        let sourceTime = t0.addingTimeInterval(sourceOffset ?? lastEnd.timeIntervalSince(t0) + 1)
        let receivedAt = sourceTime.addingTimeInterval(1)
        let bid = bars.last!.close
        let quote = BreakoutAcceptanceQuote(sourceID: "quote", provider: "OANDA", instrument: "EUR/USD",
            sequence: sequence, bid: bid, ask: bid + spread,
            sourceTime: sourceTime, receivedAt: receivedAt)
        let regime = BreakoutAcceptanceRegimeMeasurement(definitionID: "atr-v1",
            definitionDigest: String(repeating: "a", count: 64), value: 1,
            measuredAt: t0.addingTimeInterval(120), sourceBarIDs: ["s0", "s1"])
        return BreakoutAcceptanceV1.evaluate(configuration: config, bars: bars, regime: regime,
            quote: quote, asOf: receivedAt.addingTimeInterval(1), previousEventTimes: [])
    }

    private var history: [BreakoutAcceptanceBar] {
        [bar("s0", 0, 1.095, 1.100, 1.090, 1.095),
         bar("s1", 60, 1.095, 1.100, 1.090, 1.095)]
    }

    private var signalBars: [BreakoutAcceptanceBar] {
        history + [bar("break", 120, 1.099, 1.102, 1.098, 1.101),
                   bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
    }

    @Test func watchingThenConfirmedPersistsAndExactReplayIsIdempotentAfterReload() async throws {
        let config = configuration()
        let store = ResearchStore(root: root)
        let watching = evidence(history, config: config, sequence: 1)
        #expect(watching.status == .watching)
        let first = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: watching, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(first.disposition == .recorded)
        #expect(first.state == .watching)

        let confirmed = evidence(signalBars, config: config, sequence: 2)
        #expect(confirmed.status == .signal)
        let second = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: confirmed, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(second.state == .confirmed)

        let reloaded = ResearchStore(root: root)
        let duplicate = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: confirmed, environment: .oandaPractice, engineVersion: "engine-a", store: reloaded)
        #expect(duplicate.disposition == .duplicate)
        let events = try await reloaded.v3SetupLifecycleEvents()
        #expect(events.count == 2)
        #expect(events.map(\.state) == [.watching, .confirmed])
        #expect(events.allSatisfy { $0.configurationDigest == config.digest() })
        #expect(events.allSatisfy { $0.inputDigest?.count == 64 && $0.engineVersion == "engine-a" })
        #expect(events.allSatisfy { $0.evidenceSchemaVersion == 1 })
        #expect(events.allSatisfy { $0.structureID == "range-1" && $0.timeframeSeconds == 60 })
    }

    @Test func firstObservedSignalStartsAsConfirmedWithoutInventedHistory() async throws {
        let config = configuration()
        let observation = evidence(signalBars, config: config, sequence: 8)
        #expect(observation.status == .signal)
        let store = ResearchStore(root: root)
        let receipt = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: observation, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(receipt.state == .confirmed)
        let events = try await store.v3SetupLifecycleEvents()
        #expect(events.count == 1)
        #expect(events[0].previousState == nil)
        #expect(events[0].state == .confirmed)
        #expect(events[0].sourceBarIDs?.contains("hold") == true)
    }

    @Test func wideSpreadRemainsStaleAndCanRecoverWithoutTerminalizing() async throws {
        let config = configuration(maximumSpreadPips: 1)
        let store = ResearchStore(root: root)
        let wide = evidence(history, config: config, sequence: 1, spread: 0.001)
        #expect(wide.status == .rejected)
        #expect(wide.reasonCodes.contains("spread_exceeds_config"))
        let stale = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: wide, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(stale.state == .stale)

        let fresh = evidence(history, config: config, sequence: 2,
                             sourceOffset: wide.quoteSourceTime.timeIntervalSince(t0) + 1)
        let recovered = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: fresh, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(recovered.state == .watching)
        #expect(try await store.v3SetupLifecycleEvents().map(\.state) == [.stale, .watching])
    }

    @Test func terminalSetupCannotBeRearmedByAnotherConfigOnSameFrozenStructure() async throws {
        let store = ResearchStore(root: root)
        let config = configuration()
        let failedBars = history + [bar("break", 120, 1.099, 1.102, 1.098, 1.101),
                                    bar("fail", 180, 1.101, 1.102, 1.098, 1.099)]
        let failed = evidence(failedBars, config: config, sequence: 1)
        #expect(failed.reasonCodes.contains("acceptance_hold_buffer_not_met"))
        let terminal = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: failed, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(terminal.state == .invalidated)

        let changed = configuration(maximumSpreadPips: 4)
        let retry = evidence(signalBars, config: changed, sequence: 2)
        let suppressed = try await BreakoutAcceptanceLifecycleV1.record(configuration: changed,
            evidence: retry, environment: .oandaPractice, engineVersion: "engine-b", store: store)
        #expect(suppressed.disposition == .terminalSuppressed)
        #expect(suppressed.state == .invalidated)

        let newStructure = BreakoutAcceptanceStructure.range(id: "range-2",
            high: .init(id: "range-high-2", price: 1.100, sourceBarIDs: ["s0", "s1"], frozenAt: t0.addingTimeInterval(120)),
            low: .init(id: "range-low-2", price: 1.090, sourceBarIDs: ["s0", "s1"], frozenAt: t0.addingTimeInterval(120)),
            direction: .long)
        let newConfig = configuration(structure: newStructure)
        let newSignal = evidence(signalBars, config: newConfig, sequence: 3)
        let allowed = try await BreakoutAcceptanceLifecycleV1.record(configuration: newConfig,
            evidence: newSignal, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(allowed.disposition == .recorded)
        #expect(allowed.state == .confirmed)
    }

    @Test func expiryReasonBecomesTerminalSetupExpired() async throws {
        let config = configuration(mode: .boundedRetestHold(maximumRetestBars: 1,
            tolerancePips: 1, confirmationBufferPips: 1))
        let bars = history + [bar("break", 120, 1.099, 1.102, 1.098, 1.101),
                              bar("continue", 180, 1.101, 1.103, 1.1005, 1.102)]
        let expired = evidence(bars, config: config, sequence: 1)
        #expect(expired.status == .expired)
        #expect(expired.reasonCodes.contains("retest_window_expired"))
        let receipt = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: expired, environment: .oandaPractice, engineVersion: "engine-a",
            store: ResearchStore(root: root))
        #expect(receipt.state == .setupExpired)
    }

    @Test func duplicateIdentityChecksAllPersistedEvidenceFields() async throws {
        let config = configuration()
        let observation = evidence(history, config: config, sequence: 1)
        let original = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: observation, environment: .oandaPractice, engineVersion: "engine-a",
            store: ResearchStore(root: root))
        let forgedStore = ResearchStore(root: root.appendingPathComponent("forged"))
        let forged = V3SetupLifecycleEvent(id: original.eventID, setupID: original.setupID,
            instrument: observation.instrument, strategyID: observation.strategyID,
            strategyVersion: observation.strategyVersion, provider: observation.provider,
            environment: .oandaPractice, previousState: nil, state: .watching,
            sourceObservationID: observation.quoteSourceID, sourceTime: observation.quoteSourceTime,
            receivedAt: observation.quoteReceivedAt, recordedAt: observation.observedAt,
            reason: "forged", configurationDigest: observation.configurationDigest,
            inputDigest: observation.inputDigest, engineVersion: "engine-a",
            sourceBarIDs: ["forged-bar"], quoteSequence: observation.quoteSequence,
            reasonCodes: observation.reasonCodes, structureID: observation.structureID,
            timeframeSeconds: observation.timeframeSeconds, evidenceSchemaVersion: 1)
        try await forgedStore.record(forged)
        await #expect(throws: ScanError.self) {
            try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
                evidence: observation, environment: .oandaPractice, engineVersion: "engine-a",
                store: forgedStore)
        }
    }

    @Test func olderSourceTimeOrQuoteSequenceIsRejected() async throws {
        let config = configuration()
        let store = ResearchStore(root: root)
        let first = evidence(history, config: config, sequence: 5)
        _ = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: first, environment: .oandaPractice, engineVersion: "engine-a", store: store)

        let older = evidence(history, config: config, sequence: 6,
                             sourceOffset: first.quoteSourceTime.timeIntervalSince(t0) - 1)
        await #expect(throws: ScanError.self) {
            try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
                evidence: older, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        }

        let repeatedSequence = evidence(history, config: config, sequence: 5,
                                        sourceOffset: first.quoteSourceTime.timeIntervalSince(t0) + 1)
        let laterWithSameSequence = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: repeatedSequence, environment: .oandaPractice, engineVersion: "engine-a", store: store)
        #expect(laterWithSameSequence.disposition == .recorded)
    }

    @Test func environmentIsPartOfSetupIdentity() async throws {
        let config = configuration()
        let observation = evidence(history, config: config, sequence: 1)
        let practice = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: observation, environment: .oandaPractice, engineVersion: "engine-a",
            store: ResearchStore(root: root))
        let live = try await BreakoutAcceptanceLifecycleV1.record(configuration: config,
            evidence: observation, environment: .oandaLive, engineVersion: "engine-a",
            store: ResearchStore(root: root))
        #expect(practice.setupID != live.setupID)
    }

    @Test func oldLifecycleRecordsDecodeWithoutNewOptionalProvenance() throws {
        let json = #"{"id":"old-event","setupID":"old-setup","instrument":"EUR/USD","strategyID":"orb","strategyVersion":"1","provider":"OANDA","environment":"OANDA_LIVE","previousState":null,"state":"WATCHING","sourceObservationID":null,"sourceTime":null,"receivedAt":1800000000,"recordedAt":1800000000,"planID":null,"reason":"legacy"}"#
        let decoded = try JSONDecoder().decode(V3SetupLifecycleEvent.self, from: Data(json.utf8))
        #expect(decoded.reason == "legacy")
        #expect(decoded.configurationDigest == nil)
        #expect(decoded.structureID == nil)
        #expect(decoded.validation().isEmpty)
    }

    @Test func equalRecordedTimesRequireIncreasingSourceSequence() {
        let at = t0
        func event(_ id: String, previous: V3SetupState?, state: V3SetupState,
                   sequence: UInt64) -> V3SetupLifecycleEvent {
            V3SetupLifecycleEvent(id: id, setupID: "ba-setup", instrument: "EUR/USD",
                strategyID: "BREAKOUT_ACCEPTANCE_V1", strategyVersion: "v1", provider: "OANDA",
                environment: .oandaPractice, previousState: previous, state: state,
                sourceObservationID: "quote-\(sequence)", sourceTime: at, receivedAt: at,
                recordedAt: at, reason: "observed", configurationDigest: String(repeating: "a", count: 64),
                inputDigest: String(repeating: "b", count: 64), engineVersion: "engine-a",
                sourceBarIDs: ["bar-1"], quoteSequence: sequence, reasonCodes: ["watch"],
                structureID: "range-1", timeframeSeconds: 60, evidenceSchemaVersion: 1)
        }
        let first = event("e1", previous: nil, state: .watching, sequence: 1)
        let second = event("e2", previous: .watching, state: .approaching, sequence: 2)
        #expect(V3SetupLifecycle.validationIssues(for: [first, second]).isEmpty)

        let duplicateSequence = event("e3", previous: .watching, state: .approaching, sequence: 1)
        #expect(V3SetupLifecycle.validationIssues(for: [first, duplicateSequence])
            .contains("same_source_sequence_not_increasing"))
    }
}
