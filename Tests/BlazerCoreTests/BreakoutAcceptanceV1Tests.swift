import Foundation
import Testing
@testable import BlazerCore

struct BreakoutAcceptanceV1Tests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let pip = 0.0001

    private func bar(_ id: String, _ offset: Double, _ open: Double, _ high: Double,
                     _ low: Double, _ close: Double, complete: Bool = true,
                     instrument: String = "EUR/USD", provider: String = "OANDA") -> BreakoutAcceptanceBar {
        BreakoutAcceptanceBar(id: id, instrument: instrument, provider: provider,
                              startTime: t0.addingTimeInterval(offset), open: open,
                              high: high, low: low, close: close, complete: complete)
    }

    private var history: [BreakoutAcceptanceBar] {
        [bar("s0", 0, 1.095, 1.100, 1.090, 1.095),
         bar("s1", 60, 1.095, 1.100, 1.090, 1.095)]
    }

    private func breakout(_ close: Double = 1.101, high: Double = 1.102,
                          low: Double = 1.098) -> BreakoutAcceptanceBar {
        bar("break", 120, 1.099, high, low, close)
    }

    private func rangeStructure(direction: BreakoutAcceptanceDirection = .long,
                                frozenAt: Date? = nil) -> BreakoutAcceptanceStructure {
        let freeze = frozenAt ?? t0.addingTimeInterval(120)
        return .range(id: "range-1",
            high: .init(id: "range-high", price: 1.100, sourceBarIDs: ["s0", "s1"], frozenAt: freeze),
            low: .init(id: "range-low", price: 1.090, sourceBarIDs: ["s0", "s1"], frozenAt: freeze),
            direction: direction)
    }

    private func config(mode: BreakoutAcceptanceMode = .sustainedBarsBeyond(additionalBars: 1, holdBufferPips: 1),
                        structure: BreakoutAcceptanceStructure? = nil,
                        stopPrice: Double = 1.095, targetPrice: Double = 1.110,
                        minimumDisplacementPips: Double = 5,
                        maxSetupAgeSeconds: TimeInterval = 300,
                        maxBarsAfterAcceptance: Int = 3,
                        sessionPolicy: BreakoutAcceptanceSessionPolicy = .sessionAgnostic,
                        minMovementToCostRatio: Double = 2,
                        maxAdverseDriftPips: Double = 2,
                        maximumSpreadPips: Double = 3,
                        maximumQuoteAgeSeconds: TimeInterval = 10,
                        version: String = "v1") -> BreakoutAcceptanceConfiguration {
        let freeze = structure?.frozenAt ?? t0.addingTimeInterval(120)
        return BreakoutAcceptanceConfiguration(version: version, instrument: "EUR/USD", provider: "OANDA", pipSize: pip,
            timeframeSeconds: 60, structure: structure ?? rangeStructure(frozenAt: freeze),
            regimeDefinitionID: "atr-regime-v1", regimeDefinitionDigest: String(repeating: "a", count: 64),
            minimumRegimeValue: 0.5,
            maximumRegimeValue: 2.0, minimumDisplacementPips: minimumDisplacementPips,
            acceptanceMode: mode, maximumSetupAgeSeconds: maxSetupAgeSeconds,
            maximumCompletedBarsAfterAcceptance: maxBarsAfterAcceptance,
            sessionPolicy: sessionPolicy, rearmPolicy: .newFrozenStructureRequired,
            clusterWindowSeconds: 60,
            maximumSpreadPips: maximumSpreadPips,
            maximumQuoteAgeSeconds: maximumQuoteAgeSeconds, additionalCostsPips: 1,
            minimumMovementToCostRatio: minMovementToCostRatio,
            maximumAdverseEntryDriftPips: maxAdverseDriftPips,
            stop: .init(id: "stop", price: stopPrice, sourceBarIDs: ["s0"], frozenAt: freeze),
            target: .init(id: "target", price: targetPrice, sourceBarIDs: ["s1"], frozenAt: freeze))
    }

    private func regime(value: Double = 1) -> BreakoutAcceptanceRegimeMeasurement {
        .init(definitionID: "atr-regime-v1", definitionDigest: String(repeating: "a", count: 64), value: value,
              measuredAt: t0.addingTimeInterval(120), sourceBarIDs: ["s0", "s1"])
    }

    private func quote(after bars: [BreakoutAcceptanceBar], bid: Double = 1.1010,
                       spread: Double = 0.0001, sourceID: String = "quote-1",
                       sourceOffset: Double? = nil, receivedOffset: Double? = nil,
                       sequence: UInt64 = 1) -> (BreakoutAcceptanceQuote, Date) {
        let end = bars.max(by: { $0.startTime < $1.startTime })!.startTime.addingTimeInterval(60)
        let sourceAt = t0.addingTimeInterval(sourceOffset ?? end.timeIntervalSince(t0) + 1)
        let receivedAt = t0.addingTimeInterval(receivedOffset ?? sourceAt.timeIntervalSince(t0) + 1)
        let asOf = receivedAt.addingTimeInterval(1)
        return (.init(sourceID: sourceID, provider: "OANDA", instrument: "EUR/USD", sequence: sequence,
                      bid: bid, ask: bid + spread, sourceTime: sourceAt, receivedAt: receivedAt), asOf)
    }

    private func evaluate(_ bars: [BreakoutAcceptanceBar], config: BreakoutAcceptanceConfiguration,
                          regime: BreakoutAcceptanceRegimeMeasurement? = nil,
                          quote overrideQuote: BreakoutAcceptanceQuote? = nil,
                          asOf overrideAsOf: Date? = nil,
                          previous: [Date] = []) -> BreakoutAcceptanceEvidence {
        let generated = quote(after: bars)
        return BreakoutAcceptanceV1.evaluate(configuration: config, bars: bars,
            regime: regime ?? self.regime(), quote: overrideQuote ?? generated.0,
            asOf: overrideAsOf ?? generated.1, previousEventTimes: previous)
    }

    @Test func sustainedBarsProducesResearchSignalWithFreshAskAndFrozenEvidence() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let result = evaluate(bars, config: config())
        #expect(result.status == .signal)
        #expect(result.direction == .long)
        #expect(result.entryReference == 1.1011)
        #expect(result.stopReference == 1.095)
        #expect(result.targetReference == 1.110)
        #expect(result.breakoutBarID == "break")
        #expect(result.acceptanceBarID == "hold")
        #expect(result.sourceBarIDs.contains("s0"))
        #expect(result.sourceBarIDs.contains("s1"))
        #expect(result.sourceBarIDs.contains("hold"))
        #expect(result.quoteSourceID == "quote-1")
        #expect(result.provider == "OANDA")
    }

    @Test func timeAndRetestModesAreDistinctAndRequireTheirOwnConfirmation() {
        let sustained = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let timeResult = evaluate(sustained,
            config: config(mode: .sustainedTimeBeyond(durationSeconds: 60, holdBufferPips: 1)))
        #expect(timeResult.status == .signal)

        let retestBars = history + [breakout(),
            bar("retest", 180, 1.101, 1.102, 1.0998, 1.1002)]
        let retestQuote = quote(after: retestBars, bid: 1.1000)
        let retestResult = evaluate(retestBars,
            config: config(mode: .boundedRetestHold(maximumRetestBars: 3,
                tolerancePips: 3, confirmationBufferPips: 1)),
            quote: retestQuote.0, asOf: retestQuote.1)
        #expect(retestResult.status == .signal)
        #expect(retestResult.acceptanceBarID == "retest")
        #expect(timeResult.configurationDigest != retestResult.configurationDigest)
        #expect(timeResult.inputDigest != retestResult.inputDigest)
    }

    @Test func rejectsWickOnlyDisplacementAndRegimeFailures() {
        let wick = history + [bar("wick", 120, 1.099, 1.102, 1.098, 1.100)]
        #expect(evaluate(wick, config: config()).reasonCodes.contains("wick_only_break_rejected"))

        let smallBreak = history + [breakout(1.1002)]
        #expect(evaluate(smallBreak, config: config()).reasonCodes.contains("minimum_displacement_not_met"))
        let weakThenStrong = history + [
            breakout(1.1002),
            bar("strong-break", 180, 1.1002, 1.103, 1.1001, 1.1010),
            bar("strong-hold", 240, 1.101, 1.103, 1.1005, 1.102)
        ]
        let laterSignal = evaluate(weakThenStrong, config: config())
        #expect(laterSignal.status == .signal)
        #expect(laterSignal.breakoutBarID == "strong-break")
        #expect(evaluate(history + [breakout()], config: config(), regime: regime(value: 3))
            .reasonCodes.contains("regime_ineligible"))
    }

    @Test func barsModeWaitsThenRejectsAcceptanceFailureAndRetestExpiry() {
        let pending = evaluate(history + [breakout()], config: config())
        #expect(pending.status == .awaitingAcceptance)
        #expect(pending.reasonCodes.contains("sustained_bars_pending"))

        let failed = history + [breakout(), bar("fail", 180, 1.101, 1.102, 1.098, 1.099)]
        #expect(evaluate(failed, config: config()).reasonCodes.contains("acceptance_hold_buffer_not_met"))

        let noRetest = history + [breakout(), bar("continue", 180, 1.101, 1.103, 1.1005, 1.102)]
        let expired = evaluate(noRetest, config: config(mode: .boundedRetestHold(maximumRetestBars: 1,
            tolerancePips: 1, confirmationBufferPips: 1)))
        #expect(expired.status == .expired)
        #expect(expired.reasonCodes.contains("retest_window_expired"))
    }

    @Test func sustainedAcceptanceStartsAfterBreakAndRetestCannotExceedTolerance() {
        let oneAdditional = history + [breakout(),
            bar("hold-1", 180, 1.101, 1.103, 1.1005, 1.102)]
        let needsTwo = evaluate(oneAdditional,
            config: config(mode: .sustainedBarsBeyond(additionalBars: 2, holdBufferPips: 1)))
        #expect(needsTwo.status == .awaitingAcceptance)
        #expect(needsTwo.reasonCodes.contains("sustained_bars_pending"))

        let twoAdditional = oneAdditional + [
            bar("hold-2", 240, 1.102, 1.104, 1.101, 1.103)
        ]
        #expect(evaluate(twoAdditional,
            config: config(mode: .sustainedBarsBeyond(additionalBars: 2, holdBufferPips: 1))).status == .signal)

        let deepRetest = history + [breakout(),
            bar("deep-retest", 180, 1.101, 1.102, 1.0995, 1.1002)]
        #expect(evaluate(deepRetest, config: config(mode: .boundedRetestHold(
            maximumRetestBars: 3, tolerancePips: 3, confirmationBufferPips: 1)))
            .reasonCodes.contains("retest_breached_tolerance"))

        let withinHoldBuffer = history + [breakout(),
            bar("inside-buffer", 180, 1.101, 1.102, 1.1000, 1.10005)]
        #expect(evaluate(withinHoldBuffer, config: config()).reasonCodes
            .contains("acceptance_hold_buffer_not_met"))
    }

    @Test func rejectsMissingConfigProvenanceAndUnfrozenLevels() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        #expect(evaluate(bars, config: config(version: "")).reasonCodes.contains("configuration_invalid"))

        let unknownStructure = BreakoutAcceptanceStructure.keyLevel(
            level: .init(id: "unknown", price: 1.1, sourceBarIDs: ["missing"],
                         frozenAt: t0.addingTimeInterval(120)), direction: .long)
        #expect(evaluate(bars, config: config(structure: unknownStructure))
            .reasonCodes.contains("structure_or_regime_provenance_missing"))

        let futureFreeze = rangeStructure(frozenAt: t0.addingTimeInterval(250))
        let lateQuote = quote(after: bars, sourceOffset: 241)
        #expect(evaluate(bars, config: config(structure: futureFreeze), quote: lateQuote.0,
                          asOf: t0.addingTimeInterval(242))
            .reasonCodes.contains("structure_not_frozen_from_prior_completed_data"))
        let earlyRegime = BreakoutAcceptanceRegimeMeasurement(definitionID: "atr-regime-v1",
            definitionDigest: String(repeating: "a", count: 64), value: 1,
            measuredAt: t0.addingTimeInterval(30), sourceBarIDs: ["s0", "s1"])
        #expect(evaluate(bars, config: config(), regime: earlyRegime).reasonCodes
            .contains("structure_not_frozen_from_prior_completed_data"))
    }

    @Test func rejectsIncompleteFutureDuplicateOverlappingAndOffGridBars() {
        let incomplete = history + [bar("partial", 120, 1.099, 1.102, 1.098, 1.101, complete: false)]
        #expect(evaluate(incomplete, config: config())
            .reasonCodes.contains("bar_completion_future_duplicate_or_overlap_invalid"))
        let future = history + [bar("future", 600, 1.1, 1.102, 1.099, 1.101)]
        let freshForHistory = quote(after: history + [breakout()])
        #expect(evaluate(future, config: config(), quote: freshForHistory.0, asOf: freshForHistory.1)
            .reasonCodes.contains("bar_completion_future_duplicate_or_overlap_invalid"))
        let duplicate = history + [bar("dup", 60, 1.095, 1.100, 1.090, 1.095)]
        #expect(evaluate(duplicate, config: config())
            .reasonCodes.contains("bar_completion_future_duplicate_or_overlap_invalid"))
        let overlap = history + [bar("overlap", 90, 1.095, 1.100, 1.090, 1.095)]
        #expect(evaluate(overlap, config: config())
            .reasonCodes.contains("bar_completion_future_duplicate_or_overlap_invalid"))
    }

    @Test func rejectsQuoteFreshnessSpreadMovementCostAndInvalidPlanOrdering() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let generated = quote(after: bars)
        let stale = BreakoutAcceptanceQuote(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1,
            bid: 1.101, ask: 1.1011, sourceTime: generated.0.sourceTime.addingTimeInterval(-30),
            receivedAt: generated.0.receivedAt)
        #expect(evaluate(bars, config: config(), quote: stale).reasonCodes
            .contains("quote_stale_or_not_newer_than_final_bar"))

        let futureQuote = BreakoutAcceptanceQuote(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1,
            bid: 1.101, ask: 1.1011, sourceTime: generated.1.addingTimeInterval(1),
            receivedAt: generated.1.addingTimeInterval(2))
        #expect(evaluate(bars, config: config(), quote: futureQuote, asOf: generated.1)
            .reasonCodes.contains("quote_provenance_or_order_invalid"))

        let tooOldReceived = generated.0.receivedAt.addingTimeInterval(20)
        let tooOld = BreakoutAcceptanceQuote(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1,
            bid: 1.101, ask: 1.1011, sourceTime: generated.0.sourceTime,
            receivedAt: tooOldReceived)
        #expect(evaluate(bars, config: config(), quote: tooOld,
                         asOf: tooOldReceived.addingTimeInterval(1))
            .reasonCodes.contains("quote_stale_or_not_newer_than_final_bar"))

        let wide = BreakoutAcceptanceQuote(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1,
            bid: 1.101, ask: 1.102, sourceTime: generated.0.sourceTime,
            receivedAt: generated.0.receivedAt)
        #expect(evaluate(bars, config: config(), quote: wide, asOf: generated.1)
            .reasonCodes.contains("spread_exceeds_config"))

        #expect(evaluate(bars, config: config(minMovementToCostRatio: 100))
            .reasonCodes.contains("movement_to_cost_below_config"))
        #expect(evaluate(bars, config: config(stopPrice: 1.105))
            .reasonCodes.contains("configuration_invalid"))
        let wrongInstrument = BreakoutAcceptanceQuote(sourceID: "q", provider: "OANDA",
            instrument: "GBP/JPY", sequence: 1, bid: 1.101, ask: 1.1011,
            sourceTime: generated.0.sourceTime, receivedAt: generated.0.receivedAt)
        #expect(evaluate(bars, config: config(), quote: wrongInstrument, asOf: generated.1)
            .reasonCodes.contains("quote_provenance_or_order_invalid"))
        let wrongQuoteProvider = BreakoutAcceptanceQuote(sourceID: "q", provider: "OTHER",
            instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011,
            sourceTime: generated.0.sourceTime, receivedAt: generated.0.receivedAt)
        #expect(evaluate(bars, config: config(), quote: wrongQuoteProvider, asOf: generated.1)
            .reasonCodes.contains("quote_provenance_or_order_invalid"))
        let wrongBarSource = history + [bar("wrong-pair", 120, 1.099, 1.102, 1.098, 1.101,
                                            instrument: "GBP/JPY")]
        #expect(evaluate(wrongBarSource, config: config()).reasonCodes
            .contains("bar_instrument_or_provider_mismatch"))
    }

    @Test func rejectsDuplicateClusterInvalidationAmbiguityAndSetupExpiry() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        #expect(evaluate(bars, config: config(), previous: [t0.addingTimeInterval(200)])
            .reasonCodes.contains("overlapping_event_cluster"))

        let invalidated = bars + [bar("invalidate", 240, 1.102, 1.103, 1.098, 1.099)]
        #expect(evaluate(invalidated, config: config()).reasonCodes
            .contains("setup_invalidated_after_acceptance"))

        let dual = history + [bar("dual", 120, 1.095, 1.101, 1.089, 1.1005)]
        #expect(evaluate(dual, config: config()).reasonCodes.contains("ambiguous_dual_boundary_break"))

        let expiredConfig = config(maxSetupAgeSeconds: 30)
        let freshLateQuote = quote(after: bars, sourceOffset: 300)
        #expect(evaluate(bars, config: expiredConfig, quote: freshLateQuote.0,
                         asOf: freshLateQuote.1).status == .expired)
    }

    @Test func shortUsesBidAndRequiresFrozenMatchingKeyLevel() {
        let freeze = t0.addingTimeInterval(120)
        let keyLevel = BreakoutAcceptanceStructure.keyLevel(
            level: .init(id: "prior-low", price: 1.100, sourceBarIDs: ["s0", "s1"], frozenAt: freeze),
            direction: .short)
        let bars = history + [
            bar("short-break", 120, 1.1005, 1.101, 1.098, 1.099),
            bar("short-hold", 180, 1.099, 1.0995, 1.097, 1.098)
        ]
        let generated = quote(after: bars, bid: 1.0985, spread: 0.0001)
        let result = evaluate(bars,
            config: config(structure: keyLevel, stopPrice: 1.105, targetPrice: 1.080),
            quote: generated.0, asOf: generated.1)
        #expect(result.status == .signal)
        #expect(result.direction == .short)
        #expect(result.entryReference == 1.0985)
    }

    @Test func rejectsGapsAndChecksPostAcceptanceStopsTargetsAndAmbiguousOHLC() {
        let accepted = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let gapBars = accepted + [bar("gap", 300, 1.102, 1.104, 1.101, 1.103)]
        #expect(evaluate(gapBars, config: config()).reasonCodes.contains("setup_data_gap_after_break"))

        let targetHit = accepted + [bar("target-hit", 240, 1.102, 1.111, 1.101, 1.110)]
        #expect(evaluate(targetHit, config: config()).reasonCodes.contains("frozen_target_already_reached"))
        let stopHit = accepted + [bar("stop-hit", 240, 1.100, 1.101, 1.094, 1.095)]
        #expect(evaluate(stopHit, config: config()).reasonCodes.contains("frozen_stop_already_touched"))
        let ambiguous = accepted + [bar("both-hit", 240, 1.100, 1.111, 1.094, 1.100)]
        #expect(evaluate(ambiguous, config: config()).reasonCodes
            .contains("post_acceptance_barrier_order_ambiguous"))

        let postLimit = accepted + [bar("after", 240, 1.102, 1.104, 1.101, 1.103)]
        #expect(evaluate(postLimit, config: config(maxBarsAfterAcceptance: 0)).status == .expired)
    }

    @Test func explicitSessionWindowGatesBreakoutAndExpiresAtSessionEnd() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let inside = config(sessionPolicy: .window(id: "london-fixture",
            timeZoneIdentifier: "Europe/London", start: t0.addingTimeInterval(60),
            end: t0.addingTimeInterval(300)))
        #expect(evaluate(bars, config: inside).status == .signal)

        let endsBeforeQuote = config(sessionPolicy: .window(id: "london-fixture",
            timeZoneIdentifier: "Europe/London", start: t0.addingTimeInterval(60),
            end: t0.addingTimeInterval(240)))
        #expect(evaluate(bars, config: endsBeforeQuote).reasonCodes.contains("session_end_expired"))
    }

    @Test func replayAndInputOrderingAreDeterministicAndModeIsHashed() {
        let bars = history + [breakout(), bar("hold", 180, 1.101, 1.103, 1.1005, 1.102)]
        let first = evaluate(bars, config: config())
        let replay = evaluate(bars, config: config())
        let reordered = evaluate(Array(bars.reversed()), config: config())
        #expect(first == replay)
        #expect(first.inputDigest == reordered.inputDigest)
        let refreshed = quote(after: bars, bid: 1.1015)
        let refreshedResult = evaluate(bars, config: config(), quote: refreshed.0, asOf: refreshed.1)
        #expect(refreshedResult.id == first.id)
        #expect(refreshedResult.inputDigest != first.inputDigest)
        #expect(first.configurationDigest != evaluate(bars,
            config: config(mode: .sustainedTimeBeyond(durationSeconds: 60, holdBufferPips: 1))).configurationDigest)
    }
}
