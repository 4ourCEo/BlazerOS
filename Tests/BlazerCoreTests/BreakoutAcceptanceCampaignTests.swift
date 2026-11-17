import Foundation
import Testing
@testable import BlazerCore

/// Synthetic, deterministic contract campaign. The 100 rows are edge cases for
/// evaluator behavior; they are not a backtest and provide no performance evidence.
struct BreakoutAcceptanceCampaignTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let pip = 0.0001

    private struct Scenario {
        var configuration: BreakoutAcceptanceConfiguration
        var bars: [BreakoutAcceptanceBar]
        var regime: BreakoutAcceptanceRegimeMeasurement
        var quote: BreakoutAcceptanceQuote
        var asOf: Date
        var previous: [Date] = []
    }
    private struct Case {
        let name: String
        let status: BreakoutAcceptanceStatus
        let reason: String?
        let direction: BreakoutAcceptanceDirection?
        let change: (inout Scenario) -> Void
    }
    private typealias Change = (inout Scenario) -> Void

    private func bar(_ id: String, _ minute: Double, _ open: Double, _ high: Double,
                     _ low: Double, _ close: Double, complete: Bool = true,
                     instrument: String = "EUR/USD", provider: String = "OANDA") -> BreakoutAcceptanceBar {
        .init(id: id, instrument: instrument, provider: provider,
              startTime: t0.addingTimeInterval(minute * 60), open: open, high: high,
              low: low, close: close, complete: complete)
    }
    private var hist: [BreakoutAcceptanceBar] {
        [bar("s0", 0, 1.095, 1.100, 1.090, 1.095), bar("s1", 1, 1.095, 1.100, 1.090, 1.095)]
    }
    private var signalBars: [BreakoutAcceptanceBar] {
        hist + [bar("break", 2, 1.099, 1.102, 1.098, 1.101),
                bar("hold", 3, 1.101, 1.103, 1.1005, 1.102)]
    }
    private func level(_ id: String, _ price: Double, _ ids: [String] = ["s0", "s1"], _ minute: Double = 2) -> BreakoutAcceptanceFrozenLevel {
        .init(id: id, price: price, sourceBarIDs: ids, frozenAt: t0.addingTimeInterval(minute * 60))
    }
    private func configuration(
        structure: BreakoutAcceptanceStructure? = nil,
        mode: BreakoutAcceptanceMode = .sustainedBarsBeyond(additionalBars: 1, holdBufferPips: 1),
        displacement: Double = 5, maxAge: Double = 300, maxPost: Int = 3,
        session: BreakoutAcceptanceSessionPolicy = .sessionAgnostic,
        spread: Double = 3, quoteAge: Double = 10, costs: Double = 1,
        costRatio: Double = 2, drift: Double = 2,
        stop: Double = 1.095, target: Double = 1.110,
        instrument: String = "EUR/USD", provider: String = "OANDA",
        version: String = "v1", pipSize: Double = 0.0001, timeframe: Int = 60,
        regimeID: String = "atr-regime-v1", regimeDigest: String = String(repeating: "a", count: 64),
        regimeMin: Double = 0.5, regimeMax: Double = 2
    ) -> BreakoutAcceptanceConfiguration {
        let structure = structure ?? .range(id: "range-1", high: level("range-high", 1.100),
            low: level("range-low", 1.090), direction: .long)
        let freeze = structure.frozenAt
        return .init(version: version, instrument: instrument, provider: provider, pipSize: pipSize,
            timeframeSeconds: timeframe, structure: structure, regimeDefinitionID: regimeID,
            regimeDefinitionDigest: regimeDigest, minimumRegimeValue: regimeMin,
            maximumRegimeValue: regimeMax, minimumDisplacementPips: displacement,
            acceptanceMode: mode, maximumSetupAgeSeconds: maxAge,
            maximumCompletedBarsAfterAcceptance: maxPost, sessionPolicy: session,
            rearmPolicy: .newFrozenStructureRequired, clusterWindowSeconds: 60,
            maximumSpreadPips: spread, maximumQuoteAgeSeconds: quoteAge,
            additionalCostsPips: costs, minimumMovementToCostRatio: costRatio,
            maximumAdverseEntryDriftPips: drift,
            stop: .init(id: "stop", price: stop, sourceBarIDs: ["s0"], frozenAt: freeze),
            target: .init(id: "target", price: target, sourceBarIDs: ["s1"], frozenAt: freeze))
    }
    private func regime(value: Double = 1, id: String = "atr-regime-v1",
                        digest: String = String(repeating: "a", count: 64),
                        measuredMinute: Double = 2, sources: [String] = ["s0", "s1"]) -> BreakoutAcceptanceRegimeMeasurement {
        .init(definitionID: id, definitionDigest: digest, value: value,
              measuredAt: t0.addingTimeInterval(measuredMinute * 60), sourceBarIDs: sources)
    }
    private func quote(after bars: [BreakoutAcceptanceBar], bid: Double = 1.101,
                       spread: Double = 0.0001, sourceID: String = "q1",
                       provider: String = "OANDA", instrument: String = "EUR/USD",
                       sequence: UInt64 = 1, sourceDelta: Double = 1,
                       receiveDelta: Double = 2) -> (BreakoutAcceptanceQuote, Date) {
        let end = bars.map(\.startTime).max()!.addingTimeInterval(60)
        let source = end.addingTimeInterval(sourceDelta)
        let received = end.addingTimeInterval(receiveDelta)
        return (.init(sourceID: sourceID, provider: provider, instrument: instrument,
                      sequence: sequence, bid: bid, ask: bid + spread,
                      sourceTime: source, receivedAt: received), received.addingTimeInterval(1))
    }
    private func base() -> Scenario {
        let bars = signalBars
        let q = quote(after: bars)
        return .init(configuration: configuration(), bars: bars, regime: regime(),
                     quote: q.0, asOf: q.1)
    }
    private func evaluate(_ s: Scenario) -> BreakoutAcceptanceEvidence {
        BreakoutAcceptanceV1.evaluate(configuration: s.configuration, bars: s.bars,
            regime: s.regime, quote: s.quote, asOf: s.asOf, previousEventTimes: s.previous)
    }
    private func session(_ start: Double = 120, _ end: Double = 300) -> BreakoutAcceptanceSessionPolicy {
        .window(id: "campaign-window", timeZoneIdentifier: "UTC",
                start: t0.addingTimeInterval(start), end: t0.addingTimeInterval(end))
    }
    private func cases() -> [Case] {
        var c: [Case] = []
        func add(_ name: String, _ status: BreakoutAcceptanceStatus, _ reason: String? = nil,
                 direction: BreakoutAcceptanceDirection? = nil,
                 change: @escaping Change = { _ in }) {
            c.append(.init(name: name, status: status, reason: reason, direction: direction, change: change))
        }
        // Configuration rejection and exact valid boundaries (18).
        let configCases: [(String, Change)] = [
            ("cfg-empty-version", { $0.configuration = self.configuration(version: " ") }),
            ("cfg-empty-instrument", { $0.configuration = self.configuration(instrument: "") }),
            ("cfg-empty-provider", { $0.configuration = self.configuration(provider: "") }),
            ("cfg-zero-pip", { $0.configuration = self.configuration(pipSize: 0) }),
            ("cfg-zero-timeframe", { $0.configuration = self.configuration(timeframe: 0) }),
            ("cfg-empty-regime-id", { $0.configuration = self.configuration(regimeID: "") }),
            ("cfg-short-regime-digest", { $0.configuration = self.configuration(regimeDigest: "abc") }),
            ("cfg-inverted-regime-range", { $0.configuration = self.configuration(regimeMin: 2, regimeMax: 1) }),
            ("cfg-zero-displacement", { $0.configuration = self.configuration(displacement: 0) }),
            ("cfg-zero-sustained-bars", { $0.configuration = self.configuration(mode: .sustainedBarsBeyond(additionalBars: 0, holdBufferPips: 1)) }),
            ("cfg-negative-hold-buffer", { $0.configuration = self.configuration(mode: .sustainedBarsBeyond(additionalBars: 1, holdBufferPips: -1)) }),
            ("cfg-too-short-time-duration", { $0.configuration = self.configuration(mode: .sustainedTimeBeyond(durationSeconds: 59, holdBufferPips: 0)) }),
            ("cfg-zero-retest-bars", { $0.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 0, tolerancePips: 1, confirmationBufferPips: 1)) }),
            ("cfg-negative-retest-tolerance", { $0.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 1, tolerancePips: -1, confirmationBufferPips: 1)) }),
            ("cfg-zero-max-age", { $0.configuration = self.configuration(maxAge: 0) }),
            ("cfg-negative-post-accept-bars", { $0.configuration = self.configuration(maxPost: -1) }),
            ("cfg-invalid-session-zone", { $0.configuration = self.configuration(session: .window(id: "x", timeZoneIdentifier: "Mars/Olympus", start: self.t0, end: self.t0.addingTimeInterval(600))) }),
            ("cfg-stop-target-order", { $0.configuration = self.configuration(stop: 1.105) })
        ]
        for (name, edit) in configCases { add(name, .rejected, "configuration_invalid", change: edit) }
        add("cfg-session-start-inclusive", .signal, direction: .long) { $0.configuration = self.configuration(session: self.session(120, 300)) }
        add("cfg-session-end-asof-exclusive", .expired, "session_end_expired") { $0.configuration = self.configuration(session: self.session(120, 243)) }

        // Quote identity, ordering, freshness and spread (16).
        let quoteCases: [(String, (Scenario) -> BreakoutAcceptanceQuote)] = [
            ("quote-blank-source", { self.quote(after: $0.bars, sourceID: " ").0 }),
            ("quote-wrong-provider", { self.quote(after: $0.bars, provider: "OTHER").0 }),
            ("quote-wrong-instrument", { self.quote(after: $0.bars, instrument: "GBP/JPY").0 }),
            ("quote-zero-sequence", { self.quote(after: $0.bars, sequence: 0).0 }),
            ("quote-nonpositive-bid", { self.quote(after: $0.bars, bid: 0).0 }),
            ("quote-crossed-market", { self.quote(after: $0.bars, spread: 0).0 }),
            ("quote-future-source", { var x = self.quote(after: $0.bars); x.0 = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: x.1.addingTimeInterval(1), receivedAt: x.1); return x.0 }),
            ("quote-received-after-asof", { var x = self.quote(after: $0.bars); x.0 = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: x.1, receivedAt: x.1.addingTimeInterval(1)); return x.0 }),
            ("quote-ask-nan", { var x = self.quote(after: $0.bars); x.0 = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: .nan, sourceTime: x.0.sourceTime, receivedAt: x.0.receivedAt); return x.0 }),
            ("quote-source-before-final", { var x = self.quote(after: $0.bars); x.0 = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: x.0.sourceTime.addingTimeInterval(-5), receivedAt: x.0.receivedAt); return x.0 })
        ]
        for (name, q) in quoteCases { add(name, .rejected, name == "quote-source-before-final" ? "quote_stale_or_not_newer_than_final_bar" : "quote_provenance_or_order_invalid") { $0.quote = q($0) } }
        add("quote-age-exact-boundary", .signal, direction: .long) { s in
            let end = s.bars.map(\.startTime).max()!.addingTimeInterval(60)
            let source = end.addingTimeInterval(1)
            s.quote = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: source, receivedAt: source)
            s.asOf = source.addingTimeInterval(10)
        }
        add("quote-age-over-boundary", .rejected, "quote_stale_or_not_newer_than_final_bar") { s in
            let end = s.bars.map(\.startTime).max()!.addingTimeInterval(60); let source = end.addingTimeInterval(1)
            s.quote = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: source, receivedAt: source); s.asOf = source.addingTimeInterval(10.001)
        }
        add("quote-spread-exact-limit", .signal, direction: .long) { s in s.configuration = self.configuration(spread: 1); s.quote = self.quote(after: s.bars, spread: 0.0001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("quote-spread-over-limit", .rejected, "spread_exceeds_config") { s in s.configuration = self.configuration(spread: 1); s.quote = self.quote(after: s.bars, spread: 0.0001001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("quote-entry-drift-over-limit", .rejected, "adverse_entry_drift_exceeds_config") { s in s.configuration = self.configuration(drift: 0); s.quote = self.quote(after: s.bars, bid: 1.1021, spread: 0.0001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("quote-equal-source-receive", .signal, direction: .long) { s in s.quote = self.quote(after: s.bars, sourceID: "q-equal", sourceDelta: 1, receiveDelta: 1).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }

        // Bar completeness, provenance, ordering and gaps (16).
        add("bars-empty-history", .rejected, "history_empty") { s in s.bars = [] }
        add("bars-wrong-provider", .rejected, "bar_instrument_or_provider_mismatch") { s in s.bars[0] = self.bar("s0", 0, 1.095, 1.1, 1.09, 1.095, provider: "OTHER") }
        add("bars-wrong-instrument", .rejected, "bar_instrument_or_provider_mismatch") { s in s.bars[0] = self.bar("s0", 0, 1.095, 1.1, 1.09, 1.095, instrument: "GBP/JPY") }
        add("bars-incomplete-last", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars[3] = self.bar("hold", 3, 1.101, 1.103, 1.1005, 1.102, complete: false) }
        add("bars-duplicate-id", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars.append(self.bar("hold", 4, 1.102, 1.104, 1.101, 1.103)) }
        add("bars-duplicate-time", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars.append(self.bar("other", 3, 1.101, 1.103, 1.1005, 1.102)) }
        add("bars-overlapping-time", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars.append(self.bar("overlap", 3.5, 1.101, 1.103, 1.1005, 1.102)) }
        add("bars-future-completion", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars.append(self.bar("future", 5, 1.1, 1.102, 1.099, 1.101)) }
        add("bars-invalid-ohlc", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars[3] = self.bar("hold", 3, 1.101, 1.100, 1.1005, 1.102) }
        add("bars-unsorted-input-normalized", .signal, direction: .long) { s in s.bars.reverse() }
        add("bars-gap-after-break", .rejected, "setup_data_gap_after_break") { s in s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("gap", 4, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("bars-contiguous-history-before-break-produces-signal", .signal, direction: .long) { s in s.bars = [self.hist[0], self.hist[1], self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("hold", 3, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("bars-off-grid-post-freeze", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars = self.hist + [self.bar("break", 2.25, 1.099, 1.102, 1.098, 1.101)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("bars-empty-source-id", .rejected, "bar_completion_future_duplicate_or_overlap_invalid") { s in s.bars[3] = self.bar("", 3, 1.101, 1.103, 1.1005, 1.102) }
        add("bars-quote-not-newer-than-final", .rejected, "quote_stale_or_not_newer_than_final_bar") { s in let q = self.quote(after: s.bars); s.quote = .init(sourceID: "q", provider: "OANDA", instrument: "EUR/USD", sequence: 1, bid: 1.101, ask: 1.1011, sourceTime: q.0.sourceTime.addingTimeInterval(-2), receivedAt: q.0.receivedAt); s.asOf = q.1 }

        // Frozen structure and regime lineage (14).
        add("prov-missing-structure-source", .rejected, "structure_or_regime_provenance_missing") { s in s.configuration = self.configuration(structure: .keyLevel(level: self.level("key", 1.1, ["missing"]), direction: .long)) }
        add("prov-missing-stop-source", .rejected, "structure_or_regime_provenance_missing") { s in s.configuration = self.configuration(); s.configuration = self.reconfigure(s.configuration, stop: .init(id: "stop", price: 1.095, sourceBarIDs: ["absent"], frozenAt: self.t0.addingTimeInterval(120))) }
        add("prov-missing-target-source", .rejected, "structure_or_regime_provenance_missing") { s in s.configuration = self.reconfigure(s.configuration, target: .init(id: "target", price: 1.11, sourceBarIDs: ["absent"], frozenAt: self.t0.addingTimeInterval(120))) }
        add("prov-regime-definition-id", .rejected, "structure_or_regime_provenance_missing") { s in s.regime = self.regime(id: "other") }
        add("prov-regime-definition-digest", .rejected, "structure_or_regime_provenance_missing") { s in s.regime = self.regime(digest: String(repeating: "b", count: 64)) }
        add("prov-empty-regime-sources", .rejected, "structure_or_regime_provenance_missing") { s in s.regime = self.regime(sources: []) }
        add("prov-unknown-regime-source", .rejected, "structure_or_regime_provenance_missing") { s in s.regime = self.regime(sources: ["lost"]) }
        add("prov-structure-freeze-after-source-close", .rejected, "structure_not_frozen_from_prior_completed_data") { s in let freeze = self.t0.addingTimeInterval(120); let structure = BreakoutAcceptanceStructure.keyLevel(level: .init(id: "key", price: 1.1, sourceBarIDs: ["hold"], frozenAt: freeze), direction: .long); s.configuration = self.configuration(structure: structure) }
        add("prov-regime-measured-before-source-close", .rejected, "structure_not_frozen_from_prior_completed_data") { s in s.regime = self.regime(measuredMinute: 0.5) }
        add("prov-regime-measured-after-freeze", .rejected, "structure_not_frozen_from_prior_completed_data") { s in s.regime = self.regime(measuredMinute: 3) }
        add("prov-regime-below-range", .rejected, "regime_ineligible") { s in s.regime = self.regime(value: 0.499) }
        add("prov-regime-above-range", .rejected, "regime_ineligible") { s in s.regime = self.regime(value: 2.001) }
        add("prov-regime-lower-inclusive", .signal, direction: .long) { s in s.regime = self.regime(value: 0.5) }
        add("prov-regime-upper-inclusive", .signal, direction: .long) { s in s.regime = self.regime(value: 2) }

        // Breakout detection and acceptance mode edges (18).
        add("setup-no-break", .watching, "awaiting_initial_break") { s in s.bars = self.hist; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-wick-only", .rejected, "wick_only_break_rejected") { s in s.bars = self.hist + [self.bar("wick", 2, 1.099, 1.102, 1.098, 1.100)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-close-under-displacement", .watching, "minimum_displacement_not_met") { s in s.bars = self.hist + [self.bar("weak", 2, 1.099, 1.102, 1.098, 1.1002)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-displacement-inclusive", .signal, direction: .long) { s in s.configuration = self.configuration(displacement: 10); s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("hold", 3, 1.101, 1.103, 1.1005, 1.102)] }
        add("setup-weak-then-qualified-break", .signal, direction: .long) { s in s.bars = self.hist + [self.bar("weak", 2, 1.099, 1.102, 1.098, 1.1002), self.bar("break2", 3, 1.1002, 1.103, 1.1001, 1.101), self.bar("hold2", 4, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-bars-pending", .awaitingAcceptance, "sustained_bars_pending") { s in s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-hold-buffer-strict-equality", .rejected, "acceptance_hold_buffer_not_met") { s in s.bars[3] = self.bar("hold", 3, 1.101, 1.103, 1.099, 1.1001) }
        add("setup-time-mode-equality", .signal, direction: .long) { s in s.configuration = self.configuration(mode: .sustainedTimeBeyond(durationSeconds: 60, holdBufferPips: 1)) }
        add("setup-time-mode-pending", .awaitingAcceptance, "sustained_duration_pending") { s in s.configuration = self.configuration(mode: .sustainedTimeBeyond(durationSeconds: 120, holdBufferPips: 1)); s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("hold", 3, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-time-mode-falls-back-inside", .rejected, "acceptance_failed_back_inside") { s in s.configuration = self.configuration(mode: .sustainedTimeBeyond(durationSeconds: 60, holdBufferPips: 1)); s.bars[3] = self.bar("hold", 3, 1.101, 1.103, 1.099, 1.100) }
        add("setup-retest-pending", .awaitingAcceptance, "retest_pending") { s in s.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 2, tolerancePips: 3, confirmationBufferPips: 1)); s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("continue", 3, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-retest-expires-bound", .expired, "retest_window_expired") { s in s.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 1, tolerancePips: 3, confirmationBufferPips: 1)); s.bars = self.hist + [self.bar("break", 2, 1.099, 1.102, 1.098, 1.101), self.bar("continue", 3, 1.101, 1.103, 1.1005, 1.102)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-retest-confirm", .signal, direction: .long) { s in s.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 2, tolerancePips: 3, confirmationBufferPips: 1)); s.bars[3] = self.bar("retest", 3, 1.101, 1.102, 1.0998, 1.1002); s.quote = self.quote(after: s.bars, bid: 1.1001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-retest-exact-tolerance", .signal, direction: .long) { s in s.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 2, tolerancePips: 2, confirmationBufferPips: 1)); s.bars[3] = self.bar("retest", 3, 1.101, 1.102, 1.0998, 1.1002); s.quote = self.quote(after: s.bars, bid: 1.1001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("setup-retest-breach", .rejected, "retest_breached_tolerance") { s in s.configuration = self.configuration(mode: .boundedRetestHold(maximumRetestBars: 2, tolerancePips: 1, confirmationBufferPips: 1)); s.bars[3] = self.bar("retest", 3, 1.101, 1.102, 1.0998, 1.1002) }
        add("setup-range-dual-boundary", .rejected, "ambiguous_dual_boundary_break") { s in s.bars[2] = self.bar("dual", 2, 1.095, 1.101, 1.089, 1.1005) }
        add("setup-short-sustained-uses-bid", .signal, direction: .short) { s in let freeze = self.t0.addingTimeInterval(120); let key = BreakoutAcceptanceStructure.keyLevel(level: .init(id: "prior-low", price: 1.1, sourceBarIDs: ["s0", "s1"], frozenAt: freeze), direction: .short); s.configuration = self.configuration(structure: key, stop: 1.105, target: 1.08); s.bars = self.hist + [self.bar("short-break", 2, 1.1005, 1.101, 1.098, 1.099), self.bar("short-hold", 3, 1.099, 1.0995, 1.097, 1.098)]; s.quote = self.quote(after: s.bars, bid: 1.0985).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }

        // Session, age, lifecycle, barriers, dedup and cost gates (18).
        add("life-session-breakout-outside", .rejected, "breakout_outside_configured_session") { s in s.configuration = self.configuration(session: self.session(180, 300)) }
        add("life-setup-age-exact-boundary", .signal, direction: .long) { s in s.configuration = self.configuration(maxAge: 63) }
        add("life-setup-age-over-boundary", .expired, "setup_expired") { s in s.configuration = self.configuration(maxAge: 62) }
        add("life-post-accept-count-exact", .signal, direction: .long) { s in s.configuration = self.configuration(maxPost: 1); s.bars += [self.bar("post", 4, 1.102, 1.104, 1.101, 1.103)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("life-post-accept-count-over", .expired, "post_acceptance_bar_limit_expired") { s in s.configuration = self.configuration(maxPost: 0); s.bars += [self.bar("post", 4, 1.102, 1.104, 1.101, 1.103)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("life-cluster-inside-window", .rejected, "overlapping_event_cluster") { s in s.previous = [self.t0.addingTimeInterval(125)] }
        add("life-cluster-at-boundary", .signal, direction: .long) { s in s.previous = [self.t0.addingTimeInterval(120)] }
        add("life-prior-event-after-asof", .rejected, "prior_event_provenance_invalid") { s in s.previous = [s.asOf.addingTimeInterval(1)] }
        add("life-prior-event-duplicate", .rejected, "prior_event_provenance_invalid") { s in s.previous = [self.t0.addingTimeInterval(200), self.t0.addingTimeInterval(200)] }
        add("life-stop-hit-path", .rejected, "frozen_stop_already_touched") { s in s.bars[2] = self.bar("break", 2, 1.099, 1.102, 1.094, 1.101) }
        add("life-target-hit-path", .expired, "frozen_target_already_reached") { s in s.bars[2] = self.bar("break", 2, 1.099, 1.111, 1.098, 1.101) }
        add("life-both-barriers-ambiguous", .rejected, "post_acceptance_barrier_order_ambiguous") { s in let key = BreakoutAcceptanceStructure.keyLevel(level: self.level("prior-high", 1.1), direction: .long); s.configuration = self.configuration(structure: key); s.bars[2] = self.bar("break", 2, 1.095, 1.111, 1.094, 1.101) }
        add("life-post-accept-invalidation", .rejected, "setup_invalidated_after_acceptance") { s in s.bars += [self.bar("invalidate", 4, 1.102, 1.103, 1.098, 1.099)]; s.quote = self.quote(after: s.bars).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("life-entry-level-order", .rejected, "entry_stop_target_order_invalid") { s in s.configuration = self.configuration(drift: 100); s.quote = self.quote(after: s.bars, bid: 1.110, spread: 0.0001).0; s.asOf = s.quote.receivedAt.addingTimeInterval(1) }
        add("life-cost-ratio-pass", .signal, direction: .long) { s in s.configuration = self.configuration(costs: 1, costRatio: 2) }
        add("life-cost-ratio-fail", .rejected, "movement_to_cost_below_config") { s in s.configuration = self.configuration(costs: 1, costRatio: 100) }
        add("life-zero-additional-cost-invalid", .signal, direction: .long) { s in s.configuration = self.configuration(costs: 0) }
        add("life-key-level-not-range", .signal, direction: .long) { s in let key = BreakoutAcceptanceStructure.keyLevel(level: self.level("prior-high", 1.1), direction: .long); s.configuration = self.configuration(structure: key) }
        return c
    }

    private func reconfigure(_ old: BreakoutAcceptanceConfiguration, stop: BreakoutAcceptanceFrozenLevel? = nil,
                             target: BreakoutAcceptanceFrozenLevel? = nil, stopFreeze: Date? = nil,
                             targetFreeze: Date? = nil) -> BreakoutAcceptanceConfiguration {
        let oldStop = stop ?? .init(id: old.stop.id, price: old.stop.price, sourceBarIDs: old.stop.sourceBarIDs, frozenAt: stopFreeze ?? old.stop.frozenAt)
        let oldTarget = target ?? .init(id: old.target.id, price: old.target.price, sourceBarIDs: old.target.sourceBarIDs, frozenAt: targetFreeze ?? old.target.frozenAt)
        return .init(version: old.version, instrument: old.instrument, provider: old.provider, pipSize: old.pipSize,
            timeframeSeconds: old.timeframeSeconds, structure: old.structure,
            regimeDefinitionID: old.regimeDefinitionID, regimeDefinitionDigest: old.regimeDefinitionDigest,
            minimumRegimeValue: old.minimumRegimeValue, maximumRegimeValue: old.maximumRegimeValue,
            minimumDisplacementPips: old.minimumDisplacementPips, acceptanceMode: old.acceptanceMode,
            maximumSetupAgeSeconds: old.maximumSetupAgeSeconds, maximumCompletedBarsAfterAcceptance: old.maximumCompletedBarsAfterAcceptance,
            sessionPolicy: old.sessionPolicy, rearmPolicy: old.rearmPolicy, clusterWindowSeconds: old.clusterWindowSeconds,
            maximumSpreadPips: old.maximumSpreadPips, maximumQuoteAgeSeconds: old.maximumQuoteAgeSeconds,
            additionalCostsPips: old.additionalCostsPips, minimumMovementToCostRatio: old.minimumMovementToCostRatio,
            maximumAdverseEntryDriftPips: old.maximumAdverseEntryDriftPips, stop: oldStop, target: oldTarget)
    }

    @Test func syntheticOneHundredCaseContractFixtureMatrix() {
        let all = cases()
        #expect(all.count == 100)
        #expect(Set(all.map(\.name)).count == all.count)
        for testCase in all {
            var scenario = base()
            testCase.change(&scenario)
            let result = evaluate(scenario)
            let reasonMatches = testCase.reason.map { result.reasonCodes.contains($0) }
                ?? (testCase.status == .signal ? result.reasonCodes == ["ACCEPTED"]
                    : !result.reasonCodes.contains("ACCEPTED"))
            let directionMatches = result.direction == testCase.direction
            let configurationDigest = scenario.configuration.digest()
            let validDigests = result.configurationDigest == configurationDigest
                && result.inputDigest.count == 64
                && result.inputDigest.allSatisfy(\.isHexDigit)
            let stableIdentity = !result.id.isEmpty && !result.structureID.isEmpty
            let hasReason = !result.reasonCodes.isEmpty
            let planMatches: Bool
            if testCase.status == .signal {
                let expectedEntry = testCase.direction == .long ? scenario.quote.ask : scenario.quote.bid
                planMatches = result.entryReference == expectedEntry
                    && result.stopReference == scenario.configuration.stop.price
                    && result.targetReference == scenario.configuration.target.price
                    && result.spreadPips != nil
            } else {
                planMatches = result.entryReference == nil && result.stopReference == nil
                    && result.targetReference == nil
            }
            if result.status != testCase.status || !reasonMatches || !directionMatches
                || !validDigests || !stableIdentity || !hasReason || !planMatches {
                Issue.record("\(testCase.name): expected \(testCase.status.rawValue)/\(testCase.reason ?? "no required reason")/\(String(describing: testCase.direction)); got \(result.status.rawValue)/\(result.reasonCodes)/\(String(describing: result.direction))")
            }
            let repeated = evaluate(scenario)
            if repeated != result {
                Issue.record("\(testCase.name): identical input changed decision, plan, reason, event identity, or digest")
            }
            if testCase.name == "life-key-level-not-range", result.status == .signal {
                var rearmed = scenario
                let replacement = BreakoutAcceptanceStructure.keyLevel(
                    level: self.level("prior-high-rearmed", 1.100), direction: .long)
                rearmed.configuration = self.configuration(structure: replacement)
                let nextStructure = evaluate(rearmed)
                if nextStructure.status != .signal || nextStructure.id == result.id {
                    Issue.record("life-key-level-not-range: newly frozen structure did not produce a distinct research event identity")
                }
            }
        }
    }
}
