import Testing
import Foundation
@testable import BlazerCore

struct GBPJPYTrendPullbackV1Tests {
    private struct Fixture {
        let config: GBPJPYTrendPullbackConfiguration
        let lower: [GBPJPYTrendPullbackBar]
        let higher: [GBPJPYTrendPullbackBar]
        let context: GBPJPYTrendPullbackContext
        let provenance: GBPJPYTrendPullbackProvenance
        let asOf: Date
        let quote: GBPJPYTrendPullbackQuote
    }

    private func evaluate(lowerBars: [GBPJPYTrendPullbackBar], higherBars: [GBPJPYTrendPullbackBar],
                          quotes: [GBPJPYTrendPullbackQuote], contexts: [GBPJPYTrendPullbackContext],
                          provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
                          configuration: GBPJPYTrendPullbackConfiguration?,
                          window: GBPJPYTrendPullbackWindow? = nil,
                          cursor: GBPJPYTrendPullbackEventCursor? = nil,
                          candidate: GBPJPYTrendPullbackBreakDescriptor? = nil) -> GBPJPYTrendPullbackDecision {
        let actualWindow = window ?? GBPJPYTrendPullbackWindow(
            firstLowerBarID: lowerBars.first?.id ?? "missing-first",
            lastLowerBarID: lowerBars.last?.id ?? "missing-last")
        let actualCursor = cursor ?? GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let discovered = configuration.map {
            GBPJPYTrendPullbackV1.discoverBreakEvents(lowerBars: lowerBars, higherBars: higherBars,
                contexts: contexts, asOf: asOf, window: actualWindow, cursor: actualCursor, configuration: $0)
        } ?? []
        let selected = candidate ?? discovered.first ?? GBPJPYTrendPullbackBreakDescriptor(
            id: "missing-event", strategyID: GBPJPYTrendPullbackV1.strategyID,
            strategyVersion: configuration?.version ?? "", profileDigest: configuration?.digest() ?? "",
            cursorDigest: actualCursor.digest, windowDigest: "missing-window-digest",
            firstLowerBarID: actualWindow.firstLowerBarID, lastLowerBarID: actualWindow.lastLowerBarID,
            frozenSwingID: "missing-swing", direction: .wait, breakBarID: "missing-break",
            breakBarEnd: asOf, higherTimeframeContextCutoff: asOf, sourceIDs: [])
        return GBPJPYTrendPullbackV1.evaluate(lowerBars: lowerBars, higherBars: higherBars,
            quotes: quotes, contexts: contexts, provenance: provenance, asOf: asOf,
            configuration: configuration, window: actualWindow, cursor: actualCursor, candidate: selected)
    }

    private func fixture(sessionAtTouch: String? = nil, maximumBarsFromBreak: Int = 8,
                         maximumBarsAfterPullback: Int = 5) -> Fixture {
        let config = GBPJPYTrendPullbackConfiguration(version: "synthetic-test-v1", instrument: "GBP/JPY", provider: "synthetic",
            allowedEnvironments: ["practice"], pipSize: 0.01, priceTickSize: 0.001,
            lowerTimeframeSeconds: 60, higherTimeframeSeconds: 300, gridOriginUTCSeconds: 0,
            lowerLeftBars: 2, lowerRightBars: 2, higherLeftBars: 2, higherRightBars: 2,
            maximumContextAgeSeconds: 7_200, atrLookbackBars: 3, minimumBreakATR: 0.5,
            pullbackToleranceATR: 0.2, invalidationBufferATR: 0.1, continuationBufferATR: 0.1,
            maximumBarsFromBreak: maximumBarsFromBreak, maximumBarsAfterPullback: maximumBarsAfterPullback,
            stopBufferATR: 0.2, targetR: 2,
            maximumSourceQuoteAgeSeconds: 5, maximumReceiptQuoteAgeSeconds: 5,
            quoteSamplingPolicy: "synthetic-complete", maximumSpreadPips: 2,
            maximumAdverseDriftPips: 2, additionalRoundTripCostPips: 0.1,
            minimumRewardToCost: 2, sessionCalendarDigest: "calendar-test", timeZoneID: "UTC",
            allowedSessions: sessionAtTouch == nil ? ["test-session"] : ["test-session", sessionAtTouch!],
            regimeVersion: "regime-test-v1", allowedRegimes: ["trend"],
            buildIdentityPolicy: "explicit", digestVersion: "sha256-sorted-json-v1")
        let lowerStart = Date(timeIntervalSince1970: 1_800_006_000) // UTC grid aligned, after HTF context forms.
        let values: [(Double, Double, Double, Double)] = [
            (180, 180.1, 179.9, 180), (180, 180.2, 179.9, 180.1),
            (180.2, 180.4, 180, 180.2), (180.8, 181, 180.1, 180.8),
            (180.6, 180.9, 180.3, 180.6), (180.6, 180.8, 180.2, 180.6),
            (180.8, 181.5, 180.5, 181.4), (181, 181.3, 180.9, 181),
            (181.1, 181.6, 181, 181.5)
        ]
        let lower = values.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "l\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: lowerStart.addingTimeInterval(Double(i * 60)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
        let htfStart = lowerStart.addingTimeInterval(-3_600)
        let hValues: [(Double, Double, Double, Double)] = [
            (180, 180.5, 179.5, 180), (180, 180.6, 179.6, 180.1),
            (180, 180.4, 179, 180.2), (180.2, 180.6, 179.4, 180.3),
            (180.5, 181, 179.5, 180.8), (180.4, 180.8, 179.6, 180.3),
            (180.3, 180.7, 179.2, 180.4), (180.4, 180.8, 179.7, 180.5),
            (180.6, 181.2, 179.6, 180.9), (180.7, 180.9, 179.7, 180.8),
            (180.5, 180.9, 179.8, 180.4), (180.4, 180.8, 179.9, 180.5)
        ]
        let higher = hValues.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "h\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: htfStart.addingTimeInterval(Double(i * 300)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
        let start = lowerStart.addingTimeInterval(-1_800)
        let context = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "context-test",
            sourceIDs: ["calendar-source", "regime-source"], measuredAt: start,
            sessionOpen: start, sessionClose: lowerStart.addingTimeInterval(10_000))
        let provenance = GBPJPYTrendPullbackProvenance(environment: "practice", buildID: "synthetic-build",
            codeDigest: "synthetic-code", snapshotDigest: "synthetic-snapshot", lineageIsProviderNative: true,
            quoteWindowComplete: true, quoteSamplingPolicy: "synthetic-complete")
        let asOf = lowerStart.addingTimeInterval(9 * 60 + 3)
        let quote = GBPJPYTrendPullbackQuote(id: "q1", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 1, sourceTime: lowerStart.addingTimeInterval(9 * 60 + 1),
            receivedAt: asOf, bid: 181.500, ask: 181.510)
        var contexts = [context]
        if let sessionAtTouch {
            contexts.append(GBPJPYTrendPullbackContext(sessionID: sessionAtTouch, sessionCalendarDigest: "calendar-test",
                timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "next-context",
                sourceIDs: ["next-session-source"], measuredAt: lowerStart.addingTimeInterval(8 * 60),
                sessionOpen: lowerStart.addingTimeInterval(8 * 60), sessionClose: lowerStart.addingTimeInterval(20_000)))
        }
        return Fixture(config: config, lower: lower, higher: higher, context: contexts[0], provenance: provenance, asOf: asOf, quote: quote)
    }

    private func withMinimumRewardToCost(_ config: GBPJPYTrendPullbackConfiguration,
                                         _ minimum: Double) -> GBPJPYTrendPullbackConfiguration {
        GBPJPYTrendPullbackConfiguration(version: config.version, instrument: config.instrument,
            provider: config.provider, allowedEnvironments: config.allowedEnvironments,
            pipSize: config.pipSize, priceTickSize: config.priceTickSize,
            lowerTimeframeSeconds: config.lowerTimeframeSeconds, higherTimeframeSeconds: config.higherTimeframeSeconds,
            gridOriginUTCSeconds: config.gridOriginUTCSeconds, lowerLeftBars: config.lowerLeftBars,
            lowerRightBars: config.lowerRightBars, higherLeftBars: config.higherLeftBars,
            higherRightBars: config.higherRightBars, maximumContextAgeSeconds: config.maximumContextAgeSeconds,
            atrLookbackBars: config.atrLookbackBars, minimumBreakATR: config.minimumBreakATR,
            pullbackToleranceATR: config.pullbackToleranceATR, invalidationBufferATR: config.invalidationBufferATR,
            continuationBufferATR: config.continuationBufferATR, maximumBarsFromBreak: config.maximumBarsFromBreak,
            maximumBarsAfterPullback: config.maximumBarsAfterPullback, stopBufferATR: config.stopBufferATR,
            targetR: config.targetR, maximumSourceQuoteAgeSeconds: config.maximumSourceQuoteAgeSeconds,
            maximumReceiptQuoteAgeSeconds: config.maximumReceiptQuoteAgeSeconds,
            quoteSamplingPolicy: config.quoteSamplingPolicy, maximumSpreadPips: config.maximumSpreadPips,
            maximumAdverseDriftPips: config.maximumAdverseDriftPips,
            additionalRoundTripCostPips: config.additionalRoundTripCostPips,
            minimumRewardToCost: minimum, sessionCalendarDigest: config.sessionCalendarDigest,
            timeZoneID: config.timeZoneID, allowedSessions: config.allowedSessions,
            regimeVersion: config.regimeVersion, allowedRegimes: config.allowedRegimes,
            buildIdentityPolicy: config.buildIdentityPolicy, digestVersion: config.digestVersion)
    }

    private func twoSwingBars(_ f: Fixture, suppressFirstTouch: Bool = false) -> [GBPJPYTrendPullbackBar] {
        var bars = f.lower
        if suppressFirstTouch {
            bars[7] = GBPJPYTrendPullbackBar(id: "l7", instrument: "GBP/JPY", provider: "synthetic",
                startTime: bars[7].startTime, open: 181.2, high: 181.3, low: 181.2, close: 181.25, complete: true)
            bars[8] = GBPJPYTrendPullbackBar(id: "l8", instrument: "GBP/JPY", provider: "synthetic",
                startTime: bars[8].startTime, open: 181.3, high: 181.6, low: 181.2, close: 181.4, complete: true)
        }
        let start = bars[0].startTime
        let later: [(Double, Double, Double, Double)] = [
            (181.4, 181.7, 181.2, 181.5), (181.8, 182, 181.4, 181.8),
            (181.6, 181.8, 181.3, 181.6), (181.5, 181.7, 181.2, 181.5),
            (182.3, 182.7, 181.5, 182.6)
        ]
        for (offset, value) in later.enumerated() {
            let index = 9 + offset
            bars.append(GBPJPYTrendPullbackBar(id: "l\(index)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: start.addingTimeInterval(Double(index * 60)), open: value.0, high: value.1,
                low: value.2, close: value.3, complete: true))
        }
        return bars
    }

    private func discover(_ bars: [GBPJPYTrendPullbackBar], fixture f: Fixture,
                          window: GBPJPYTrendPullbackWindow? = nil,
                          cursor: GBPJPYTrendPullbackEventCursor? = nil,
                          asOf: Date? = nil, config: GBPJPYTrendPullbackConfiguration? = nil) -> [GBPJPYTrendPullbackBreakDescriptor] {
        let selectedWindow = window ?? GBPJPYTrendPullbackWindow(firstLowerBarID: bars[0].id, lastLowerBarID: bars[bars.count - 1].id)
        return GBPJPYTrendPullbackV1.discoverBreakEvents(lowerBars: bars, higherBars: f.higher,
            contexts: [f.context], asOf: asOf ?? end(bars.last!).addingTimeInterval(3), window: selectedWindow,
            cursor: cursor ?? GBPJPYTrendPullbackEventCursor(consumedKeys: []), configuration: config ?? f.config)
    }

    private func typedDiscovery(_ f: Fixture, lowerBars: [GBPJPYTrendPullbackBar],
            window: GBPJPYTrendPullbackWindow, contexts: [GBPJPYTrendPullbackContext]? = nil,
            asOf: Date, cursor: GBPJPYTrendPullbackEventCursor = GBPJPYTrendPullbackEventCursor(consumedKeys: []))
        -> GBPJPYTrendPullbackDiscoveryEvidence {
        let discoveryContexts = contexts ?? [f.context]
        let discoveryProvenance = GBPJPYTrendPullbackDiscoveryProvenance(provider: "synthetic",
            environment: "practice", buildID: f.provenance.buildID, codeDigest: f.provenance.codeDigest,
            snapshotDigest: f.provenance.snapshotDigest, lineageIsProviderNative: true,
            sourceIDs: ["discovery-feed", "discovery-build"])
        let batch = GBPJPYTrendPullbackV1.discoverBreakEventBatch(lowerBars: lowerBars,
            higherBars: f.higher, contexts: discoveryContexts, provenance: discoveryProvenance,
            asOf: asOf, window: window, cursor: cursor, configuration: f.config)
        return GBPJPYTrendPullbackDiscoveryEvidence(batch: batch, lowerBars: lowerBars,
            higherBars: f.higher, contexts: discoveryContexts, provenance: discoveryProvenance,
            cursor: cursor)
    }

    private func quoteProvenance(_ f: Fixture, snapshot: String = "continued-snapshot",
                                 complete: Bool = true, buildID: String? = nil,
                                 codeDigest: String? = nil) -> GBPJPYTrendPullbackProvenance {
        GBPJPYTrendPullbackProvenance(environment: "practice", buildID: buildID ?? f.provenance.buildID,
            codeDigest: codeDigest ?? f.provenance.codeDigest, snapshotDigest: snapshot,
            lineageIsProviderNative: true, quoteWindowComplete: complete,
            quoteSamplingPolicy: f.config.quoteSamplingPolicy)
    }

    private func activeEvaluate(discovery: GBPJPYTrendPullbackDiscoveryEvidence,
            candidate: GBPJPYTrendPullbackBreakDescriptor,
            evaluationLowerBars: [GBPJPYTrendPullbackBar], evaluationHigherBars: [GBPJPYTrendPullbackBar],
            quotes: [GBPJPYTrendPullbackQuote], evaluationContexts: [GBPJPYTrendPullbackContext],
            provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
            configuration: GBPJPYTrendPullbackConfiguration,
            quoteCursor suppliedCursor: GBPJPYTrendPullbackQuoteContinuationCursor? = nil,
            quoteWindowAttestation suppliedAttestation: GBPJPYTrendPullbackQuoteWindowAttestation? = nil)
        -> GBPJPYTrendPullbackDecision {
        var quoteCursor = suppliedCursor ?? GBPJPYTrendPullbackQuoteContinuationCursor(
            discovery: discovery, candidate: candidate, configuration: configuration)
        var attestation = suppliedAttestation
        if !quotes.isEmpty && suppliedCursor == nil, let provenance {
            let firstReceipt = quotes.map(\.receivedAt).min() ?? asOf
            let probeAsOf = max(discovery.batch.asOf, min(asOf, firstReceipt.addingTimeInterval(-0.001)))
            let preflight = GBPJPYTrendPullbackV1.evaluateActiveEvent(discovery: discovery,
                candidate: candidate, evaluationLowerBars: evaluationLowerBars,
                evaluationHigherBars: evaluationHigherBars, quotes: [], evaluationContexts: evaluationContexts,
                quoteCursor: quoteCursor, quoteWindowAttestation: nil, provenance: provenance,
                asOf: probeAsOf, configuration: configuration)
            quoteCursor = preflight.quoteContinuationCursor ?? quoteCursor
            if let start = preflight.quoteConfirmationEnd {
                let observations = quotes.filter { $0.sourceTime > start && $0.sourceTime <= asOf }
                attestation = GBPJPYTrendPullbackQuoteWindowAttestation(
                    sourceSnapshotDigest: provenance.snapshotDigest, coverageStart: start,
                    completeThrough: asOf, firstSequence: observations.first?.sequence,
                    lastSequence: observations.last?.sequence, sequencePolicy: "CONTIGUOUS_SEQUENCE_V1",
                    observations: observations, priorAttestationDigest: quoteCursor.attestation?.digest)
            }
        }
        return GBPJPYTrendPullbackV1.evaluateActiveEvent(discovery: discovery, candidate: candidate,
            evaluationLowerBars: evaluationLowerBars, evaluationHigherBars: evaluationHigherBars,
            quotes: quotes, evaluationContexts: evaluationContexts, quoteCursor: quoteCursor,
            quoteWindowAttestation: attestation, provenance: provenance, asOf: asOf,
            configuration: configuration)
    }

    private func end(_ bar: GBPJPYTrendPullbackBar) -> Date {
        bar.startTime.addingTimeInterval(TimeInterval(fixture().config.lowerTimeframeSeconds))
    }

    @Test func absentProfileFailsClosedWithConfigurationIncomplete() {
        let decision = evaluate(lowerBars: [], higherBars: [], quotes: [],
            contexts: [], provenance: nil, asOf: Date(timeIntervalSince1970: 1_800_000_000), configuration: nil)
        #expect(decision.state == .waiting)
        #expect(decision.direction == .wait)
        #expect(decision.reasonCodes == ["CONFIGURATION_INCOMPLETE"])
        #expect(decision.eventID == nil)
        #expect(Set(decision.reasonCodes) == Set(decision.typedReasonCodes.map(\.rawValue)))
    }

    @Test func everyEmittedReasonHasAnExhaustiveTypedReasonCode() {
        let emitted = [
            "CONFIGURATION_INCOMPLETE", "CONFIGURATION_INVALID", "version_missing", "instrument_missing",
            "provider_missing", "quote_sampling_policy_missing", "session_calendar_digest_missing",
            "timezone_missing", "regime_version_missing", "build_identity_policy_missing", "digest_version_missing",
            "instrument_not_gbp_jpy", "environment_allowlist_invalid", "price_units_invalid", "timeframes_invalid",
            "grid_origin_invalid", "lookbacks_invalid", "bar_limits_invalid", "context_age_invalid",
            "minimum_break_atr_invalid", "invalidation_buffer_atr_invalid", "continuation_buffer_atr_invalid",
            "stop_buffer_atr_invalid", "target_r_invalid", "maximum_spread_pips_invalid",
            "minimum_reward_to_cost_invalid", "pullback_tolerance_atr_invalid", "maximum_adverse_drift_pips_invalid",
            "additional_round_trip_cost_pips_invalid", "source_quote_age_invalid", "receipt_quote_age_invalid",
            "timezone_invalid", "allowed_sessions_invalid", "allowed_regimes_invalid", "provenance_missing",
            "provenance_invalid", "derived_lineage_unverified", "cursor_invalid", "evaluation_window_invalid",
            "candidate_descriptor_mismatch", "candidate_break_unknown", "candidate_break_out_of_window",
            "candidate_break_not_first_eligible_event", "bars_invalid_or_unordered", "BAR_DATA_INVALID",
            "BAR_IDENTITY_MISMATCH", "BAR_ORDER_INVALID", "LOWER_HISTORY_INSUFFICIENT",
            "HIGHER_HISTORY_INSUFFICIENT", "missing_grid_interval", "CONTEXT_DATA_UNAVAILABLE",
            "CONTEXT_MEASURED_DISALLOWED", "CONTEXT_IDENTITY_MISMATCH", "CONTEXT_INELIGIBLE",
            "AWAITING_FIRST_PULLBACK", "AWAITING_CONTINUATION", "PULLBACK_WINDOW_EXPIRED",
            "CONFIRMATION_WINDOW_EXPIRED", "SESSION_CLOSED", "ENTRY_INTERVAL_UNRESOLVED", "ENTRY_TOO_LATE",
            "quote_sequence_invalid", "QUOTE_IDENTITY_MISMATCH", "QUOTE_DATA_INVALID", "PRICE_OFF_TICK",
            "SPREAD_LIMIT", "ADVERSE_DRIFT_LIMIT", "REWARD_TO_COST_BELOW_MINIMUM", "STRUCTURAL_INVALIDATION",
            "FIRST_TOUCH_INVALIDATED", "STOP_DIRECTION_INVALID", "STOP_TOUCHED_BEFORE_ENTRY",
            "ROUNDED_LEVEL_ORDER_INVALID", "COST_DENOMINATOR_INVALID", "STOP_CROSSED_IN_QUOTE_WINDOW",
            "RESEARCH_CANDIDATE", "DATA_QUALITY_HOLD", "evaluation_identity_mismatch"
        ]
        #expect(emitted.allSatisfy { GBPJPYTrendPullbackReasonCode(rawValue: $0) != nil })
        #expect(Set(GBPJPYTrendPullbackReasonCode.allCases.map(\.rawValue)).count
            == GBPJPYTrendPullbackReasonCode.allCases.count)
    }

    @Test func invalidExplicitProfileIsRejectedAndCannotEmitPlan() {
        let c = GBPJPYTrendPullbackConfiguration(version: "test-v1", instrument: "GBP/JPY", provider: "synthetic",
            allowedEnvironments: ["practice"], pipSize: 0.01, priceTickSize: 0.001,
            lowerTimeframeSeconds: 60, higherTimeframeSeconds: 300, gridOriginUTCSeconds: 0,
            lowerLeftBars: 2, lowerRightBars: 2, higherLeftBars: 2, higherRightBars: 2,
            maximumContextAgeSeconds: 1_200, atrLookbackBars: 3, minimumBreakATR: 0.5,
            pullbackToleranceATR: 0.2, invalidationBufferATR: 0.1, continuationBufferATR: 0.1,
            maximumBarsFromBreak: 8, maximumBarsAfterPullback: 5, stopBufferATR: 0.2, targetR: 2,
            maximumSourceQuoteAgeSeconds: 5, maximumReceiptQuoteAgeSeconds: 5,
            quoteSamplingPolicy: "synthetic-complete", maximumSpreadPips: 2,
            maximumAdverseDriftPips: 2, additionalRoundTripCostPips: 0.1,
            minimumRewardToCost: 2, sessionCalendarDigest: "calendar-test", timeZoneID: "UTC",
            allowedSessions: ["test-session"], regimeVersion: "regime-test-v1", allowedRegimes: ["trend"],
            buildIdentityPolicy: "explicit", digestVersion: "sha256-sorted-json-v1")
        let invalid = GBPJPYTrendPullbackConfiguration(version: c.version, instrument: c.instrument,
            provider: c.provider, allowedEnvironments: c.allowedEnvironments, pipSize: c.pipSize,
            priceTickSize: c.priceTickSize, lowerTimeframeSeconds: c.lowerTimeframeSeconds,
            higherTimeframeSeconds: c.higherTimeframeSeconds, gridOriginUTCSeconds: c.gridOriginUTCSeconds,
            lowerLeftBars: c.lowerLeftBars, lowerRightBars: c.lowerRightBars, higherLeftBars: c.higherLeftBars,
            higherRightBars: c.higherRightBars, maximumContextAgeSeconds: c.maximumContextAgeSeconds,
            atrLookbackBars: c.atrLookbackBars, minimumBreakATR: 0, pullbackToleranceATR: c.pullbackToleranceATR,
            invalidationBufferATR: c.invalidationBufferATR, continuationBufferATR: c.continuationBufferATR,
            maximumBarsFromBreak: c.maximumBarsFromBreak, maximumBarsAfterPullback: c.maximumBarsAfterPullback,
            stopBufferATR: c.stopBufferATR, targetR: c.targetR,
            maximumSourceQuoteAgeSeconds: c.maximumSourceQuoteAgeSeconds,
            maximumReceiptQuoteAgeSeconds: c.maximumReceiptQuoteAgeSeconds, quoteSamplingPolicy: c.quoteSamplingPolicy,
            maximumSpreadPips: c.maximumSpreadPips, maximumAdverseDriftPips: c.maximumAdverseDriftPips,
            additionalRoundTripCostPips: c.additionalRoundTripCostPips, minimumRewardToCost: c.minimumRewardToCost,
            sessionCalendarDigest: c.sessionCalendarDigest, timeZoneID: c.timeZoneID, allowedSessions: c.allowedSessions,
            regimeVersion: c.regimeVersion, allowedRegimes: c.allowedRegimes,
            buildIdentityPolicy: c.buildIdentityPolicy, digestVersion: c.digestVersion)
        let decision = evaluate(lowerBars: [], higherBars: [], quotes: [], contexts: [],
            provenance: nil, asOf: Date(timeIntervalSince1970: 1_800_000_000), configuration: invalid)
        #expect(decision.state == .rejected)
        #expect(decision.reasonCodes.contains("CONFIGURATION_INVALID"))
        #expect(decision.reasonCodes.contains("minimum_break_atr_invalid"))
        #expect(decision.eventID == nil)
        #expect(decision.entryPrice == nil)
    }

    @Test func profileDigestExcludesSnapshotButInputDigestTracksInputs() {
        let c = GBPJPYTrendPullbackConfiguration(version: "test-v1", instrument: "GBP/JPY", provider: "synthetic",
            allowedEnvironments: ["practice"], pipSize: 0.01, priceTickSize: 0.001,
            lowerTimeframeSeconds: 60, higherTimeframeSeconds: 300, gridOriginUTCSeconds: 0,
            lowerLeftBars: 2, lowerRightBars: 2, higherLeftBars: 2, higherRightBars: 2,
            maximumContextAgeSeconds: 1_200, atrLookbackBars: 3, minimumBreakATR: 0.5,
            pullbackToleranceATR: 0.2, invalidationBufferATR: 0.1, continuationBufferATR: 0.1,
            maximumBarsFromBreak: 8, maximumBarsAfterPullback: 5, stopBufferATR: 0.2, targetR: 2,
            maximumSourceQuoteAgeSeconds: 5, maximumReceiptQuoteAgeSeconds: 5,
            quoteSamplingPolicy: "synthetic-complete", maximumSpreadPips: 2,
            maximumAdverseDriftPips: 2, additionalRoundTripCostPips: 0.1,
            minimumRewardToCost: 2, sessionCalendarDigest: "calendar-test", timeZoneID: "UTC",
            allowedSessions: ["test-session"], regimeVersion: "regime-test-v1", allowedRegimes: ["trend"],
            buildIdentityPolicy: "explicit", digestVersion: "sha256-sorted-json-v1")
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let p1 = GBPJPYTrendPullbackProvenance(environment: "practice", buildID: "build", codeDigest: "code",
            snapshotDigest: "snap-a", lineageIsProviderNative: true, quoteWindowComplete: true, quoteSamplingPolicy: "synthetic-complete")
        let p2 = GBPJPYTrendPullbackProvenance(environment: "practice", buildID: "build", codeDigest: "code",
            snapshotDigest: "snap-b", lineageIsProviderNative: true, quoteWindowComplete: true, quoteSamplingPolicy: "synthetic-complete")
        let a = evaluate(lowerBars: [], higherBars: [], quotes: [], contexts: [], provenance: p1, asOf: t, configuration: c)
        let b = evaluate(lowerBars: [], higherBars: [], quotes: [], contexts: [], provenance: p2, asOf: t, configuration: c)
        #expect(a.configurationDigest == b.configurationDigest)
        #expect(a.inputDigest != b.inputDigest)
        #expect(a.buildID == "build" && a.codeDigest == "code")
        let mismatch = GBPJPYTrendPullbackProvenance(environment: "practice", buildID: "build", codeDigest: "code",
            snapshotDigest: "snap-c", lineageIsProviderNative: true, quoteWindowComplete: true, quoteSamplingPolicy: "unregistered-policy")
        let rejected = evaluate(lowerBars: [], higherBars: [], quotes: [], contexts: [], provenance: mismatch, asOf: t, configuration: c)
        #expect(rejected.state == .rejected)
        #expect(rejected.buildID == "build" && rejected.codeDigest == "code")
        #expect(rejected.reasonCodes.contains("provenance_invalid"))
    }

    @Test func syntheticLongBreakPullbackAndQuoteProduceResearchPlan() {
        let f = fixture()
        let fullWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: f.lower[0].id, lastLowerBarID: f.lower[8].id)
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let descriptors = discover(f.lower, fixture: f, window: fullWindow, cursor: cursor, asOf: f.asOf)
        #expect(descriptors.count == 1)
        #expect(descriptors[0].breakBarID == "l6")
        #expect(descriptors[0].firstLowerBarID == "l0")
        #expect(descriptors[0].lastLowerBarID == "l8")
        let contexts = [f.context]
        let decision = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote],
            contexts: contexts, provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: fullWindow, cursor: cursor, candidate: descriptors[0])
        #expect(decision.state == .signal)
        #expect(decision.direction == .long)
        #expect(decision.eventID != nil)
        #expect(decision.eventStart != nil)
        #expect(decision.eventEnd == f.asOf)
        #expect(decision.buildID == "synthetic-build")
        #expect(decision.codeDigest == "synthetic-code")
        #expect(decision.higherTimeframeContextCutoff != nil)
        #expect(decision.breakBarID == "l6")
        #expect(decision.frozenSwingID == "l3")
        #expect(decision.entryPrice == f.quote.ask)
        #expect(decision.selectedQuoteID == f.quote.id)
        #expect(decision.quoteBid == f.quote.bid && decision.quoteAsk == f.quote.ask)
        #expect(decision.quoteSourceTime == f.quote.sourceTime && decision.quoteReceivedAt == f.quote.receivedAt)
        #expect(decision.quoteSourceAgeSeconds == f.asOf.timeIntervalSince(f.quote.sourceTime))
        #expect(decision.quoteReceiptAgeSeconds == f.asOf.timeIntervalSince(f.quote.receivedAt))
        #expect(decision.additionalRoundTripCostPips == f.config.additionalRoundTripCostPips)
        #expect(decision.stopPrice != nil && decision.stopPrice! < f.quote.ask)
        #expect(decision.targetPrice != nil && decision.targetPrice! > f.quote.ask)
        #expect(abs((decision.stopPrice ?? 0) - 180.760) < 0.000001) // stop rounds outward for a long.
        #expect(abs((decision.targetPrice ?? 0) - 183.010) < 0.000001) // target rounds toward entry.
        #expect(decision.rawStopPrice != nil && decision.rawStopPrice! >= decision.stopPrice!)
        #expect(decision.rawTargetPrice != nil && decision.rawTargetPrice! >= decision.targetPrice!)
        #expect((decision.rawStopPrice! - decision.stopPrice!) < f.config.priceTickSize)
        #expect((decision.rawTargetPrice! - decision.targetPrice!) < f.config.priceTickSize)
        #expect(decision.rewardToCost != nil && decision.rewardToCost! >= f.config.minimumRewardToCost)
        #expect(decision.cursorDigest == cursor.digest)
        #expect(Set(descriptors[0].sourceIDs).isSuperset(of: ["l0", "l1", "l2", "l3", "l4", "l5", "l6", "h2", "calendar-source", "regime-source"]))

        let offTick = GBPJPYTrendPullbackQuote(id: "q-off-tick", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 1, sourceTime: f.quote.sourceTime,
            receivedAt: f.asOf, bid: 181.500, ask: 181.5105)
        let offTickDecision = evaluate(lowerBars: f.lower, higherBars: f.higher,
            quotes: [offTick], contexts: contexts, provenance: f.provenance, asOf: f.asOf, configuration: f.config)
        #expect(offTickDecision.state == .rejected)
        #expect(offTickDecision.reasonCodes.contains("PRICE_OFF_TICK"))
        #expect(offTickDecision.selectedQuoteID == offTick.id)
        #expect(offTickDecision.quoteBid == offTick.bid && offTickDecision.quoteAsk == offTick.ask)

        let preConfirmation = GBPJPYTrendPullbackQuote(id: "q-pre", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 0, sourceTime: f.quote.sourceTime.addingTimeInterval(-3),
            receivedAt: f.quote.sourceTime.addingTimeInterval(-2), bid: 181.490, ask: 181.500)
        let withOldQuote = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [preConfirmation, f.quote],
            contexts: contexts, provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: fullWindow, cursor: cursor, candidate: descriptors[0])
        #expect(withOldQuote.state == .signal)
        #expect(withOldQuote.entryPrice == f.quote.ask)
        let postEntryQuote = GBPJPYTrendPullbackQuote(id: "q-after-entry", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 2, sourceTime: f.quote.sourceTime.addingTimeInterval(1),
            receivedAt: f.asOf, bid: 181.520, ask: 181.530)
        let withPostEntry = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote, postEntryQuote],
            contexts: contexts, provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: fullWindow, cursor: cursor, candidate: descriptors[0])
        #expect(withPostEntry.inputDigest == decision.inputDigest)
        #expect(!withPostEntry.sourceIDs.contains("q-after-entry"))

        let confirmationEnd = f.lower[8].startTime.addingTimeInterval(60)
        let barStartingAtConfirmationEnd = GBPJPYTrendPullbackBar(id: "between", instrument: "GBP/JPY",
            provider: "synthetic", startTime: confirmationEnd, open: 181.5, high: 181.6,
            low: 181.4, close: 181.5, complete: true)
        let afterInterveningBar = GBPJPYTrendPullbackQuote(id: "q-after-bar", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 3,
            sourceTime: confirmationEnd.addingTimeInterval(61), receivedAt: confirmationEnd.addingTimeInterval(63),
            bid: 181.500, ask: 181.510)
        let gapBars = f.lower + [barStartingAtConfirmationEnd]
        let gapWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: f.lower[0].id,
            lastLowerBarID: barStartingAtConfirmationEnd.id)
        let gapCandidates = discover(gapBars, fixture: f, window: gapWindow, cursor: cursor, asOf: afterInterveningBar.receivedAt)
        let gapDecision = evaluate(lowerBars: gapBars, higherBars: f.higher,
            quotes: [afterInterveningBar], contexts: contexts, provenance: f.provenance,
            asOf: afterInterveningBar.receivedAt, configuration: f.config,
            window: gapWindow, cursor: cursor, candidate: gapCandidates[0])
        #expect(gapDecision.state == .rejected)
        #expect(gapDecision.reasonCodes.contains("ENTRY_TOO_LATE"))
        #expect(gapDecision.disposition == .terminal)
        #expect(gapDecision.sourceIDs.contains("between"))

        let strictCostConfig = withMinimumRewardToCost(f.config, 1_000)
        let strictCostCandidate = discover(f.lower, fixture: f, window: fullWindow, cursor: cursor,
            asOf: f.asOf, config: strictCostConfig)[0]
        let costRejected = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote],
            contexts: contexts, provenance: f.provenance, asOf: f.asOf, configuration: strictCostConfig,
            window: fullWindow, cursor: cursor, candidate: strictCostCandidate)
        #expect(costRejected.state == .rejected)
        #expect(costRejected.reasonCodes.contains("REWARD_TO_COST_BELOW_MINIMUM"))
        #expect(costRejected.selectedQuoteID == f.quote.id)
        #expect(costRejected.rawStopPrice != nil && costRejected.stopPrice != nil)
        #expect(costRejected.rawTargetPrice != nil && costRejected.targetPrice != nil)
        #expect(costRejected.additionalRoundTripCostPips == strictCostConfig.additionalRoundTripCostPips)

        let refreshedQuote = GBPJPYTrendPullbackQuote(id: "q2", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 2, sourceTime: f.quote.sourceTime.addingTimeInterval(1),
            receivedAt: f.asOf.addingTimeInterval(1), bid: 181.501, ask: 181.511)
        let refreshed = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [refreshedQuote],
            contexts: contexts, provenance: f.provenance, asOf: f.asOf.addingTimeInterval(1), configuration: f.config)
        #expect(refreshed.eventID == decision.eventID)
        #expect(refreshed.inputDigest != decision.inputDigest)

        let later = GBPJPYTrendPullbackQuote(id: "q2", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 2, sourceTime: f.quote.sourceTime.addingTimeInterval(1),
            receivedAt: f.asOf.addingTimeInterval(1), bid: 181.501, ask: 181.511)
        let outOfOrderQuotes = evaluate(lowerBars: f.lower, higherBars: f.higher,
            quotes: [later, f.quote], contexts: contexts, provenance: f.provenance,
            asOf: f.asOf.addingTimeInterval(1), configuration: f.config)
        #expect(outOfOrderQuotes.state == .rejected)
        #expect(outOfOrderQuotes.reasonCodes.contains("quote_sequence_invalid"))
    }

    @Test func sourceBarsMustAlreadyBeChronologicalAndCompleteWarmupMustPrecedeAtr() {
        let f = fixture()
        let reversed = evaluate(lowerBars: Array(f.lower.reversed()), higherBars: f.higher,
            quotes: [f.quote], contexts: [f.context], provenance: f.provenance, asOf: f.asOf, configuration: f.config)
        #expect(reversed.state == .rejected)
        #expect(reversed.reasonCodes.contains("bars_invalid_or_unordered"))

        let tooShort = Array(f.lower.prefix(3))
        let tooShortWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: tooShort[0].id, lastLowerBarID: tooShort[2].id)
        let tooShortEvents = GBPJPYTrendPullbackV1.discoverBreakEvents(lowerBars: tooShort, higherBars: f.higher,
            contexts: [f.context], asOf: f.asOf, window: tooShortWindow,
            cursor: GBPJPYTrendPullbackEventCursor(consumedKeys: []), configuration: f.config)
        #expect(tooShortEvents.isEmpty)

        var offTickBars = f.lower
        let original = offTickBars[2]
        offTickBars[2] = GBPJPYTrendPullbackBar(id: original.id, instrument: original.instrument,
            provider: original.provider, startTime: original.startTime, open: 180.0005,
            high: original.high, low: original.low, close: original.close, complete: true)
        let offTickCandle = evaluate(lowerBars: offTickBars, higherBars: f.higher,
            quotes: [f.quote], contexts: [f.context], provenance: f.provenance,
            asOf: f.asOf, configuration: f.config)
        #expect(offTickCandle.state == .rejected)
        #expect(offTickCandle.reasonCodes.contains("bars_invalid_or_unordered"))
    }

    @Test func activeBreakAndPullbackWaitUntilTheirConfiguredDeadlines() {
        let f = fixture()
        let afterBreak = evaluate(lowerBars: Array(f.lower.prefix(7)), higherBars: f.higher,
            quotes: [], contexts: [f.context], provenance: f.provenance,
            asOf: f.lower[6].startTime.addingTimeInterval(61), configuration: f.config)
        #expect(afterBreak.state == .waiting)
        #expect(afterBreak.reasonCodes.contains("AWAITING_FIRST_PULLBACK"))
        let refreshedPending = evaluate(lowerBars: Array(f.lower.prefix(7)), higherBars: f.higher,
            quotes: [], contexts: [f.context], provenance: f.provenance,
            asOf: f.lower[6].startTime.addingTimeInterval(62), configuration: f.config)
        #expect(refreshedPending.eventID == afterBreak.eventID)
        #expect(refreshedPending.eventStart == afterBreak.eventStart)
        #expect(refreshedPending.inputDigest != afterBreak.inputDigest)
        #expect(afterBreak.eventID != nil)
        #expect(afterBreak.buildID == f.provenance.buildID)
        #expect(afterBreak.codeDigest == f.provenance.codeDigest)

        let afterTouch = evaluate(lowerBars: Array(f.lower.prefix(8)), higherBars: f.higher,
            quotes: [], contexts: [f.context], provenance: f.provenance,
            asOf: f.lower[7].startTime.addingTimeInterval(61), configuration: f.config)
        #expect(afterTouch.state == .waiting)
        #expect(afterTouch.reasonCodes.contains("AWAITING_CONTINUATION"))

        let closingContext = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "closing-context",
            sourceIDs: ["closing-source"], measuredAt: f.context.measuredAt,
            sessionOpen: f.context.sessionOpen, sessionClose: f.lower[7].startTime.addingTimeInterval(121))
        let sessionEndedWithoutNewBar = evaluate(lowerBars: Array(f.lower.prefix(8)), higherBars: f.higher,
            quotes: [], contexts: [closingContext], provenance: f.provenance,
            asOf: f.lower[7].startTime.addingTimeInterval(122), configuration: f.config)
        #expect(sessionEndedWithoutNewBar.state == .expired)
        #expect(sessionEndedWithoutNewBar.reasonCodes.contains("SESSION_CLOSED"))

        let closingBeforeTouch = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "closing-before-touch",
            sourceIDs: ["closing-source"], measuredAt: f.context.measuredAt,
            sessionOpen: f.context.sessionOpen, sessionClose: f.lower[6].startTime.addingTimeInterval(120))
        let noTouchAfterSession = evaluate(lowerBars: Array(f.lower.prefix(7)), higherBars: f.higher,
            quotes: [], contexts: [closingBeforeTouch], provenance: f.provenance,
            asOf: f.lower[6].startTime.addingTimeInterval(121), configuration: f.config)
        #expect(noTouchAfterSession.state == .expired)
        #expect(noTouchAfterSession.reasonCodes.contains("SESSION_CLOSED"))

        var postCloseInvalidationBars = Array(f.lower.prefix(9))
        postCloseInvalidationBars[8] = GBPJPYTrendPullbackBar(id: "l8", instrument: "GBP/JPY",
            provider: "synthetic", startTime: f.lower[8].startTime, open: 181.1,
            high: 181.2, low: 180.7, close: 180.8, complete: true)
        let closesDuringInvalidation = GBPJPYTrendPullbackContext(sessionID: "test-session",
            sessionCalendarDigest: "calendar-test", timeZoneID: "UTC", regime: "trend",
            regimeVersion: "regime-test-v1", digest: "closes-during-invalidating-bar",
            sourceIDs: ["closing-source"], measuredAt: f.context.measuredAt,
            sessionOpen: f.context.sessionOpen,
            sessionClose: f.lower[8].startTime.addingTimeInterval(30))
        let sessionClosePrecedesStructuralInvalidation = evaluate(lowerBars: postCloseInvalidationBars,
            higherBars: f.higher, quotes: [], contexts: [closesDuringInvalidation],
            provenance: f.provenance, asOf: f.lower[8].startTime.addingTimeInterval(61),
            configuration: f.config)
        #expect(sessionClosePrecedesStructuralInvalidation.state == .expired)
        #expect(sessionClosePrecedesStructuralInvalidation.reasonCodes.contains("SESSION_CLOSED"))
        #expect(!sessionClosePrecedesStructuralInvalidation.reasonCodes.contains("STRUCTURAL_INVALIDATION"))

        var postBreakCloseBars = Array(f.lower.prefix(8))
        postBreakCloseBars[7] = GBPJPYTrendPullbackBar(id: "l7", instrument: "GBP/JPY",
            provider: "synthetic", startTime: f.lower[7].startTime, open: 181.0,
            high: 181.1, low: 180.7, close: 180.8, complete: true)
        let closesBeforeFirstTouch = GBPJPYTrendPullbackContext(sessionID: "test-session",
            sessionCalendarDigest: "calendar-test", timeZoneID: "UTC", regime: "trend",
            regimeVersion: "regime-test-v1", digest: "closes-before-first-touch",
            sourceIDs: ["closing-source"], measuredAt: f.context.measuredAt,
            sessionOpen: f.context.sessionOpen,
            sessionClose: f.lower[7].startTime.addingTimeInterval(30))
        let sessionClosePrecedesBreakInvalidation = evaluate(lowerBars: postBreakCloseBars,
            higherBars: f.higher, quotes: [], contexts: [closesBeforeFirstTouch],
            provenance: f.provenance, asOf: f.lower[7].startTime.addingTimeInterval(61),
            configuration: f.config)
        #expect(sessionClosePrecedesBreakInvalidation.state == .expired)
        #expect(sessionClosePrecedesBreakInvalidation.reasonCodes.contains("SESSION_CLOSED"))
        #expect(!sessionClosePrecedesBreakInvalidation.reasonCodes.contains("STRUCTURAL_INVALIDATION"))

        let shortWindow = fixture(maximumBarsFromBreak: 2)
        let filler = (7...8).map { i in
            GBPJPYTrendPullbackBar(id: "f\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: shortWindow.lower[6].startTime.addingTimeInterval(Double((i - 6) * 60)),
                open: 181.3, high: 181.4, low: 181.2, close: 181.3, complete: true)
        }
        let noPullbackBars = Array(shortWindow.lower.prefix(7)) + filler
        let expiredBreak = evaluate(lowerBars: noPullbackBars, higherBars: shortWindow.higher,
            quotes: [], contexts: [shortWindow.context], provenance: shortWindow.provenance,
            asOf: filler[1].startTime.addingTimeInterval(61), configuration: shortWindow.config)
        #expect(expiredBreak.state == .expired)
        #expect(expiredBreak.reasonCodes.contains("PULLBACK_WINDOW_EXPIRED"))

        let confirmationWindow = fixture(maximumBarsAfterPullback: 2)
        var noTrigger = Array(confirmationWindow.lower.prefix(8))
        for i in 8...9 {
            noTrigger.append(GBPJPYTrendPullbackBar(id: "n\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: confirmationWindow.lower[0].startTime.addingTimeInterval(Double(i * 60)),
                open: 181.1, high: 181.25, low: 181, close: 181.2, complete: true))
        }
        let waitingTrigger = evaluate(lowerBars: Array(noTrigger.prefix(9)), higherBars: confirmationWindow.higher,
            quotes: [], contexts: [confirmationWindow.context], provenance: confirmationWindow.provenance,
            asOf: noTrigger[8].startTime.addingTimeInterval(61), configuration: confirmationWindow.config)
        #expect(waitingTrigger.state == .waiting)
        let expiredTrigger = evaluate(lowerBars: noTrigger, higherBars: confirmationWindow.higher,
            quotes: [], contexts: [confirmationWindow.context], provenance: confirmationWindow.provenance,
            asOf: noTrigger[9].startTime.addingTimeInterval(61), configuration: confirmationWindow.config)
        #expect(expiredTrigger.state == .expired)
        #expect(expiredTrigger.reasonCodes.contains("CONFIRMATION_WINDOW_EXPIRED"))
    }

    @Test func activeContinuationWaitsThenSignalsWithStableOriginAndReplayDigest() throws {
        let f = fixture()
        let discoveryBars = Array(f.lower.prefix(7))
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l6")
        let asOfDiscovery = end(f.lower[6]).addingTimeInterval(1)
        let discovery = typedDiscovery(f, lowerBars: discoveryBars, window: window, asOf: asOfDiscovery)
        #expect(discovery.batch.status == .completeWithEvents)
        #expect(discovery.batch.descriptors.count == 1)
        let event = discovery.batch.descriptors[0]

        let pending = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: discoveryBars, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "pending", complete: false),
            asOf: asOfDiscovery, configuration: f.config)
        #expect(pending.state == .waiting)
        #expect(pending.disposition == .active)
        #expect(pending.eventID == event.id)
        #expect(pending.reasonCodes.contains("AWAITING_FIRST_PULLBACK"))

        let signaled = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        let restartedReplay = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        #expect(signaled.state == .signal)
        #expect(signaled.disposition == .terminal)
        #expect(signaled.typedReasonCodes.contains(.researchCandidate))
        #expect(signaled.eventID == pending.eventID)
        #expect(signaled.firstLowerBarID == event.firstLowerBarID)
        #expect(signaled.lastLowerBarID == event.lastLowerBarID)
        #expect(signaled.cursorDigest == event.cursorDigest)
        #expect(signaled.inputDigest != pending.inputDigest)
        #expect(restartedReplay == signaled)
        let encodedEvidence = try JSONEncoder().encode(discovery)
        let persistedRoundTrip = try JSONDecoder().decode(GBPJPYTrendPullbackDiscoveryEvidence.self, from: encodedEvidence)
        #expect(persistedRoundTrip == discovery)
    }

    @Test func continuationRejectsAsOfBeforeDiscovery() {
        let f = fixture()
        let discoveryBars = Array(f.lower.prefix(7))
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l6")
        let asOfDiscovery = end(f.lower[6]).addingTimeInterval(1)
        let discovery = typedDiscovery(f, lowerBars: discoveryBars, window: window, asOf: asOfDiscovery)
        let event = discovery.batch.descriptors[0]
        let stale = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: discoveryBars, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, complete: false),
            asOf: asOfDiscovery.addingTimeInterval(-1), configuration: f.config)
        #expect(stale.state == .rejected)
        #expect(stale.disposition == .integrityRejected)
        #expect(stale.reasonCodes == ["evaluation_time_before_discovery"])
    }

    @Test func decisionCodableRecomputesTypedReasonsAndRejectsTampering() throws {
        let f = fixture()
        let discoveryBars = Array(f.lower.prefix(7))
        let discoveryAsOf = end(f.lower[6]).addingTimeInterval(1)
        let discovery = typedDiscovery(f, lowerBars: discoveryBars,
            window: .init(firstLowerBarID: "l0", lastLowerBarID: "l6"), asOf: discoveryAsOf)
        let decision = activeEvaluate(discovery: discovery,
            candidate: discovery.batch.descriptors[0], evaluationLowerBars: discoveryBars,
            evaluationHigherBars: f.higher, quotes: [], evaluationContexts: [f.context],
            provenance: quoteProvenance(f, complete: false), asOf: discoveryAsOf,
            configuration: f.config)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(decision)
        #expect(try decoder.decode(GBPJPYTrendPullbackDecision.self, from: encoded) == decision)

        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(payload["typedReasonCodes"] == nil)
        payload["reasonCodes"] = ["unknown_reason"]
        let unknownReason = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) {
            try decoder.decode(GBPJPYTrendPullbackDecision.self, from: unknownReason)
        }

        payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload["reasonCodes"] = ["AWAITING_FIRST_PULLBACK", "AWAITING_FIRST_PULLBACK"]
        let duplicateReason = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) {
            try decoder.decode(GBPJPYTrendPullbackDecision.self, from: duplicateReason)
        }

        payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload["disposition"] = "TERMINAL"
        let invalidDisposition = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: DecodingError.self) {
            try decoder.decode(GBPJPYTrendPullbackDecision.self, from: invalidDisposition)
        }
    }

    @Test func typedDiscoveryDistinguishesValidEmptyFromInvalidAndMissingData() {
        let f = fixture()
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let validEmptyWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l5")
        let validEmpty = typedDiscovery(f, lowerBars: Array(f.lower.prefix(6)),
            window: validEmptyWindow, asOf: end(f.lower[5]).addingTimeInterval(1), cursor: cursor)
        #expect(validEmpty.batch.status == .completeEmpty)

        let invalidWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: "not-present", lastLowerBarID: "l5")
        let invalid = typedDiscovery(f, lowerBars: Array(f.lower.prefix(6)), window: invalidWindow,
            asOf: end(f.lower[5]).addingTimeInterval(1), cursor: cursor)
        #expect(invalid.batch.status == .integrityRejected(.evaluationWindowInvalid))
        #expect(invalid.batch.status != .completeEmpty)

        let noContext = typedDiscovery(f, lowerBars: Array(f.lower.prefix(6)),
            window: validEmptyWindow, contexts: [], asOf: end(f.lower[5]).addingTimeInterval(1), cursor: cursor)
        #expect(noContext.batch.status == .retryableDataQuality(.contextDataUnavailable))
        #expect(noContext.batch.status != .completeEmpty)

        let provenance = typedDiscovery(f, lowerBars: Array(f.lower.prefix(6)),
            window: validEmptyWindow, asOf: end(f.lower[5]).addingTimeInterval(1), cursor: cursor).provenance
        let insufficientLower = GBPJPYTrendPullbackV1.discoverBreakEventBatch(
            lowerBars: Array(f.lower.prefix(3)), higherBars: f.higher, contexts: [f.context],
            provenance: provenance, asOf: end(f.lower[2]).addingTimeInterval(1),
            window: GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l2"),
            cursor: cursor, configuration: f.config)
        #expect(insufficientLower.status == .retryableDataQuality(.lowerHistoryInsufficient))
        let insufficientHigher = GBPJPYTrendPullbackV1.discoverBreakEventBatch(
            lowerBars: Array(f.lower.prefix(6)), higherBars: Array(f.higher.prefix(5)), contexts: [f.context],
            provenance: provenance, asOf: end(f.lower[5]).addingTimeInterval(1),
            window: validEmptyWindow, cursor: cursor, configuration: f.config)
        #expect(insufficientHigher.status == .retryableDataQuality(.higherHistoryInsufficient))
        let disallowedContext = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "range", regimeVersion: "regime-test-v1", digest: "measured-range",
            sourceIDs: ["disallowed-regime-source"], measuredAt: f.context.measuredAt,
            sessionOpen: f.context.sessionOpen, sessionClose: f.context.sessionClose)
        let measuredEmpty = typedDiscovery(f, lowerBars: Array(f.lower.prefix(6)),
            window: validEmptyWindow, contexts: [disallowedContext],
            asOf: end(f.lower[5]).addingTimeInterval(1), cursor: cursor)
        #expect(measuredEmpty.batch.status == .completeEmpty)
        #expect(measuredEmpty.batch.diagnosticReasonCodes.contains(.contextMeasuredDisallowed))
    }

    @Test func continuationSeparatesQuoteDataQualityFromRiskAndKeepsBadBarsActive() throws {
        let f = fixture()
        let discoveryBars = Array(f.lower.prefix(7))
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l6")
        let discovery = typedDiscovery(f, lowerBars: discoveryBars, window: window,
            asOf: end(f.lower[6]).addingTimeInterval(1))
        let event = discovery.batch.descriptors[0]

        let offTick = GBPJPYTrendPullbackQuote(id: "first-off-tick", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: f.quote.sourceTime, receivedAt: f.quote.receivedAt, bid: 181.500, ask: 181.5105)
        let laterGood = GBPJPYTrendPullbackQuote(id: "later-good", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 2,
            sourceTime: f.quote.sourceTime.addingTimeInterval(1), receivedAt: f.asOf,
            bid: 181.500, ask: 181.510)
        let quoteHold = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        #expect(quoteHold.state == .waiting)
        #expect(quoteHold.disposition == .active)
        #expect(quoteHold.reasonCodes.contains("PRICE_OFF_TICK"))
        #expect(quoteHold.selectedQuoteID == offTick.id)
        #expect(quoteHold.quoteBid == offTick.bid && quoteHold.quoteAsk == offTick.ask)
        #expect(quoteHold.typedReasonCodes.contains(.priceOffTick))
        let heldCursor = try #require(quoteHold.quoteContinuationCursor)

        let quoteShopped = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor)
        #expect(quoteShopped.disposition == .integrityRejected)
        #expect(quoteShopped.reasonCodes.contains("quote_cursor_mismatch"))

        let cursorTimeRegression = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f),
            asOf: heldCursor.asOf.addingTimeInterval(-1), configuration: f.config,
            quoteCursor: heldCursor)
        #expect(cursorTimeRegression.reasonCodes.contains("quote_cursor_mismatch"))

        let initialCursor = GBPJPYTrendPullbackQuoteContinuationCursor(
            discovery: discovery, candidate: event, configuration: f.config)
        let boundaryProbe = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, complete: false),
            asOf: f.asOf, configuration: f.config, quoteCursor: initialCursor)
        let quoteBoundary = try #require(boundaryProbe.quoteConfirmationEnd)
        let emptyAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "continued-snapshot", coverageStart: quoteBoundary,
            completeThrough: f.asOf, firstSequence: nil, lastSequence: nil,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [])
        let attestedEmpty = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: initialCursor,
            quoteWindowAttestation: emptyAttestation)
        let emptyCursor = try #require(attestedEmpty.quoteContinuationCursor)
        #expect(emptyCursor.attestation == emptyAttestation)

        let lateArrival = GBPJPYTrendPullbackQuote(id: "late-arrival", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: quoteBoundary.addingTimeInterval(1), receivedAt: f.asOf,
            bid: 181.500, ask: 181.510)
        let lateArrivalAsOf = f.asOf.addingTimeInterval(1)
        let lateArrivalAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "late-arrival-snapshot", coverageStart: quoteBoundary,
            completeThrough: lateArrivalAsOf, firstSequence: 1, lastSequence: 1,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [lateArrival],
            priorAttestationDigest: emptyCursor.attestation?.digest)
        let retroactiveArrival = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [lateArrival],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "late-arrival-snapshot"),
            asOf: lateArrivalAsOf, configuration: f.config, quoteCursor: emptyCursor,
            quoteWindowAttestation: lateArrivalAttestation)
        #expect(retroactiveArrival.reasonCodes.contains("quote_cursor_mismatch"))

        let timelyArrival = GBPJPYTrendPullbackQuote(id: "timely-arrival", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: f.asOf.addingTimeInterval(1), receivedAt: f.asOf.addingTimeInterval(1),
            bid: 181.500, ask: 181.510)
        let timelyAsOf = f.asOf.addingTimeInterval(2)
        let timelyAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "timely-snapshot", coverageStart: quoteBoundary,
            completeThrough: timelyAsOf, firstSequence: 1, lastSequence: 1,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [timelyArrival],
            priorAttestationDigest: emptyCursor.attestation?.digest)
        let timelyArrivalResult = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [timelyArrival],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "timely-snapshot"),
            asOf: timelyAsOf, configuration: f.config, quoteCursor: emptyCursor,
            quoteWindowAttestation: timelyAttestation)
        #expect(timelyArrivalResult.state == .signal)

        let futureSource = GBPJPYTrendPullbackQuote(id: "future-source", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: f.asOf.addingTimeInterval(1), receivedAt: f.asOf.addingTimeInterval(2),
            bid: 181.500, ask: 181.510)
        let futureSourceResult = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [futureSource],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        #expect(futureSourceResult.disposition == .integrityRejected)
        #expect(futureSourceResult.reasonCodes.contains("quote_window_attestation_invalid"))

        let futureReceipt = GBPJPYTrendPullbackQuote(id: "future-receipt", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: f.quote.sourceTime, receivedAt: f.asOf.addingTimeInterval(1),
            bid: 181.500, ask: 181.510)
        let futureReceiptResult = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [futureReceipt],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        #expect(futureReceiptResult.disposition == .integrityRejected)
        #expect(futureReceiptResult.reasonCodes.contains("quote_window_attestation_invalid"))

        let skippedSequenceQuote = GBPJPYTrendPullbackQuote(id: "gap-quote", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 3,
            sourceTime: laterGood.sourceTime, receivedAt: laterGood.receivedAt, bid: laterGood.bid, ask: laterGood.ask)
        let skippedSequence = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, skippedSequenceQuote],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "gap"),
            asOf: f.asOf, configuration: f.config)
        #expect(skippedSequence.disposition == .integrityRejected)
        #expect(skippedSequence.reasonCodes.contains("quote_window_attestation_invalid")
            || skippedSequence.reasonCodes.contains("quote_cursor_mismatch"))

        let badSnapshotAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "wrong-snapshot", coverageStart: try #require(heldCursor.confirmationEnd),
            completeThrough: f.asOf, firstSequence: 1, lastSequence: 2,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [offTick, laterGood],
            priorAttestationDigest: heldCursor.attestation?.digest)
        let badSnapshot = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor,
            quoteWindowAttestation: badSnapshotAttestation)
        #expect(badSnapshot.reasonCodes.contains("quote_window_attestation_invalid"))
        #expect(badSnapshot.quoteContinuationCursor == nil)

        var earlyInvalidBars = f.lower
        earlyInvalidBars[7] = GBPJPYTrendPullbackBar(id: "l7", instrument: "GBP/JPY",
            provider: "synthetic", startTime: f.lower[7].startTime, open: 181.0005,
            high: f.lower[7].high, low: f.lower[7].low, close: f.lower[7].close, complete: true)
        let earlyBadEvidence = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: earlyInvalidBars, evaluationHigherBars: f.higher,
            quotes: [offTick, laterGood], evaluationContexts: [f.context],
            provenance: quoteProvenance(f), asOf: f.asOf, configuration: f.config,
            quoteCursor: heldCursor, quoteWindowAttestation: badSnapshotAttestation)
        #expect(earlyBadEvidence.reasonCodes.contains("BAR_DATA_INVALID"))
        #expect(earlyBadEvidence.quoteContinuationCursor == nil)

        let boundary = try #require(heldCursor.confirmationEnd)
        let badStartAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "continued-snapshot", coverageStart: boundary.addingTimeInterval(1),
            completeThrough: f.asOf, firstSequence: 1, lastSequence: 2,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [offTick, laterGood],
            priorAttestationDigest: heldCursor.attestation?.digest)
        let badStart = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor,
            quoteWindowAttestation: badStartAttestation)
        #expect(badStart.reasonCodes.contains("quote_window_attestation_invalid"))

        let badPriorAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "continued-snapshot", coverageStart: boundary,
            completeThrough: f.asOf, firstSequence: 1, lastSequence: 2,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: [offTick, laterGood],
            priorAttestationDigest: "unrelated-prior-window")
        let badPrior = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [offTick, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor,
            quoteWindowAttestation: badPriorAttestation)
        #expect(badPrior.reasonCodes.contains("quote_window_attestation_invalid"))

        let changedIdentity = GBPJPYTrendPullbackQuote(id: "changed-id", instrument: offTick.instrument,
            provider: offTick.provider, environment: offTick.environment, sequence: offTick.sequence,
            sourceTime: offTick.sourceTime, receivedAt: offTick.receivedAt, bid: 181.500, ask: 181.510,
            correctionOfDigest: offTick.contentDigest)
        let changedIdentityResult = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [changedIdentity, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor)
        #expect(changedIdentityResult.reasonCodes.contains("quote_cursor_mismatch"))
        let changedSequence = GBPJPYTrendPullbackQuote(id: offTick.id, instrument: offTick.instrument,
            provider: offTick.provider, environment: offTick.environment, sequence: offTick.sequence + 1,
            sourceTime: offTick.sourceTime, receivedAt: offTick.receivedAt, bid: 181.500, ask: 181.510,
            correctionOfDigest: offTick.contentDigest)
        let changedSequenceResult = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [changedSequence, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config, quoteCursor: heldCursor)
        #expect(changedSequenceResult.reasonCodes.contains("quote_cursor_mismatch"))

        let correctedFirst = GBPJPYTrendPullbackQuote(id: offTick.id, instrument: offTick.instrument,
            provider: offTick.provider, environment: offTick.environment, sequence: offTick.sequence,
            sourceTime: offTick.sourceTime, receivedAt: f.asOf.addingTimeInterval(1), bid: 181.500, ask: 181.510,
            correctionOfDigest: offTick.contentDigest)
        let correctionObservations = [correctedFirst, laterGood]
        let correctionAttestation = GBPJPYTrendPullbackQuoteWindowAttestation(
            sourceSnapshotDigest: "corrected", coverageStart: try #require(heldCursor.confirmationEnd),
            completeThrough: f.asOf.addingTimeInterval(1), firstSequence: 1, lastSequence: 2,
            sequencePolicy: "CONTIGUOUS_SEQUENCE_V1", observations: correctionObservations,
            priorAttestationDigest: heldCursor.attestation?.digest)
        let correction = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [correctedFirst, laterGood],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "corrected"),
            asOf: f.asOf.addingTimeInterval(1), configuration: f.config, quoteCursor: heldCursor,
            quoteWindowAttestation: correctionAttestation)
        #expect(correction.state == .signal)
        #expect(correction.selectedQuoteID == correctedFirst.id)
        #expect(correction.inputDigest != quoteHold.inputDigest)

        let riskQuote = GBPJPYTrendPullbackQuote(id: "wide-risk-quote", instrument: "GBP/JPY",
            provider: "synthetic", environment: "practice", sequence: 1,
            sourceTime: f.quote.sourceTime, receivedAt: f.quote.receivedAt, bid: 181.450, ask: 181.560)
        let riskRejected = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [riskQuote],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "wide"),
            asOf: f.asOf, configuration: f.config)
        #expect(riskRejected.disposition == .terminal)
        #expect(riskRejected.reasonCodes.contains("ADVERSE_DRIFT_LIMIT") || riskRejected.reasonCodes.contains("SPREAD_LIMIT"))
        #expect(riskRejected.typedReasonCodes.contains(.adverseDriftLimit)
            || riskRejected.typedReasonCodes.contains(.spreadLimit))

        var invalidatingBars = f.lower
        invalidatingBars[7] = GBPJPYTrendPullbackBar(id: "l7", instrument: "GBP/JPY", provider: "synthetic",
            startTime: f.lower[7].startTime, open: 181.0, high: 181.1, low: 180.7, close: 180.8, complete: true)
        let structuralReject = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: Array(invalidatingBars.prefix(8)), evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, complete: false),
            asOf: end(invalidatingBars[7]).addingTimeInterval(1), configuration: f.config)
        #expect(structuralReject.disposition == .terminal)
        #expect(structuralReject.reasonCodes.contains("STRUCTURAL_INVALIDATION"))
        #expect(structuralReject.typedReasonCodes.contains(.structuralInvalidation))

        let flat = (7...14).map { i in
            GBPJPYTrendPullbackBar(id: "hold\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: f.lower[6].startTime.addingTimeInterval(Double((i - 6) * 60)),
                open: 181.5, high: 181.6, low: 181.4, close: 181.5, complete: true)
        }
        let expiredAt = end(flat.last!).addingTimeInterval(1)
        let expired = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: discoveryBars + flat, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "expiry", complete: false),
            asOf: expiredAt, configuration: f.config)
        #expect(expired.state == .expired)
        #expect(expired.disposition == .terminal)

        var corruptBars = discoveryBars + flat
        let corrupt = corruptBars[14]
        corruptBars[14] = GBPJPYTrendPullbackBar(id: corrupt.id, instrument: corrupt.instrument,
            provider: corrupt.provider, startTime: corrupt.startTime, open: 181.5005,
            high: corrupt.high, low: corrupt.low, close: corrupt.close, complete: true)
        let heldForCorrection = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: corruptBars, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, snapshot: "bad-bar", complete: false),
            asOf: expiredAt, configuration: f.config)
        #expect(heldForCorrection.state == .waiting)
        #expect(heldForCorrection.disposition == .active)
        #expect(heldForCorrection.eventID == event.id)
        #expect(heldForCorrection.reasonCodes.contains("BAR_DATA_INVALID"))
        #expect(heldForCorrection.inputDigest != expired.inputDigest)
    }

    @Test func continuationRejectsIdentityMismatchAndClassifiesContextAvailability() {
        let f = fixture()
        let discoveryBars = Array(f.lower.prefix(7))
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l6")
        let discovery = typedDiscovery(f, lowerBars: discoveryBars, window: window,
            asOf: end(f.lower[6]).addingTimeInterval(1))
        let event = discovery.batch.descriptors[0]
        let wrongBuild = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: [f.context], provenance: quoteProvenance(f, buildID: "other-build"),
            asOf: f.asOf, configuration: f.config)
        #expect(wrongBuild.disposition == .integrityRejected)
        #expect(wrongBuild.reasonCodes.contains("provenance_invalid"))
        #expect(wrongBuild.typedReasonCodes.contains(.provenanceInvalid))
        #expect(wrongBuild.eventID == event.id)

        let staleAsOf = discovery.batch.asOf.addingTimeInterval(f.config.maximumContextAgeSeconds + 1)
        let missingContext = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: discoveryBars, evaluationHigherBars: f.higher, quotes: [],
            evaluationContexts: discovery.contexts, provenance: quoteProvenance(f),
            asOf: staleAsOf, configuration: f.config)
        #expect(missingContext.disposition == .active)
        #expect(missingContext.reasonCodes.contains("CONTEXT_DATA_UNAVAILABLE"))
        #expect(missingContext.eventID == event.id)

        let substitutedHistoricalContext = GBPJPYTrendPullbackContext(sessionID: f.context.sessionID,
            sessionCalendarDigest: f.context.sessionCalendarDigest, timeZoneID: f.context.timeZoneID,
            regime: f.context.regime, regimeVersion: f.context.regimeVersion,
            digest: "substituted-historical-context", sourceIDs: ["substituted-source"],
            measuredAt: f.context.measuredAt, sessionOpen: f.context.sessionOpen,
            sessionClose: f.context.sessionClose)
        let substituted = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: [substitutedHistoricalContext], provenance: quoteProvenance(f),
            asOf: f.asOf, configuration: f.config)
        #expect(substituted.disposition == .integrityRejected)
        #expect(substituted.reasonCodes.contains("evaluation_identity_mismatch"))

        let historicalAppend = GBPJPYTrendPullbackContext(sessionID: f.context.sessionID,
            sessionCalendarDigest: f.context.sessionCalendarDigest, timeZoneID: f.context.timeZoneID,
            regime: f.context.regime, regimeVersion: f.context.regimeVersion,
            digest: "not-causally-later", sourceIDs: ["not-later-source"],
            measuredAt: discovery.batch.asOf, sessionOpen: f.context.sessionOpen,
            sessionClose: f.context.sessionClose)
        let nonCausalAddition = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: discovery.contexts + [historicalAppend], provenance: quoteProvenance(f),
            asOf: f.asOf, configuration: f.config)
        #expect(nonCausalAddition.disposition == .integrityRejected)
        #expect(nonCausalAddition.reasonCodes.contains("evaluation_identity_mismatch"))

        let disallowed = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "range", regimeVersion: "regime-test-v1", digest: "measured-range",
            sourceIDs: ["disallowed-regime-source"], measuredAt: discovery.batch.asOf.addingTimeInterval(1),
            sessionOpen: f.context.sessionOpen, sessionClose: f.context.sessionClose)
        let measuredDisallowed = activeEvaluate(discovery: discovery, candidate: event,
            evaluationLowerBars: f.lower, evaluationHigherBars: f.higher, quotes: [f.quote],
            evaluationContexts: discovery.contexts + [disallowed], provenance: quoteProvenance(f), asOf: f.asOf,
            configuration: f.config)
        #expect(measuredDisallowed.disposition == .terminal)
        #expect(measuredDisallowed.reasonCodes.contains("CONTEXT_MEASURED_DISALLOWED"))
    }

    @Test func overlappingActiveDescriptorsAdvanceIndependently() {
        let f = fixture()
        let bars = twoSwingBars(f)
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: bars[0].id, lastLowerBarID: bars[bars.count - 1].id)
        let horizon = end(bars.last!).addingTimeInterval(3)
        let discovery = typedDiscovery(f, lowerBars: bars, window: window, asOf: horizon)
        #expect(discovery.batch.status == .completeWithEvents)
        #expect(discovery.batch.descriptors.count == 2)
        let results = discovery.batch.descriptors.map { candidate in
            activeEvaluate(discovery: discovery, candidate: candidate,
                evaluationLowerBars: bars, evaluationHigherBars: f.higher, quotes: [],
                evaluationContexts: [f.context], provenance: quoteProvenance(f, complete: false),
                asOf: horizon, configuration: f.config)
        }
        #expect(results[0].eventID == discovery.batch.descriptors[0].id)
        #expect(results[1].eventID == discovery.batch.descriptors[1].id)
        #expect(results[0].eventID != results[1].eventID)
        #expect(results[0].breakBarID == "l6")
        #expect(results[1].breakBarID == "l13")
        #expect(results.allSatisfy { $0.disposition == .active || $0.disposition == .terminal })
    }

    @Test func bullishBreakUsesConfirmedSwingHighEvenWhenANewerSwingLowExists() {
        let f = fixture()
        let start = f.lower[0].startTime
        let values: [(Double, Double, Double, Double)] = [
            (180, 180.1, 179.9, 180), (180, 180.2, 179.9, 180.1),
            (180.2, 180.4, 180, 180.2), (180.8, 181, 180.1, 180.8),
            (180.6, 180.9, 180.3, 180.6), (180.6, 180.8, 180.2, 180.6),
            (180, 180.2, 179.8, 180), (180.2, 180.4, 179.9, 180.2),
            (180.3, 180.5, 180, 180.3), (180.8, 181.5, 180.5, 181.4),
            (181, 181.3, 180.9, 181), (181.1, 181.6, 181, 181.5)
        ]
        let lower = values.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "x\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: start.addingTimeInterval(Double(i * 60)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
        let asOf = start.addingTimeInterval(12 * 60 + 3)
        let quote = GBPJPYTrendPullbackQuote(id: "qx", instrument: "GBP/JPY", provider: "synthetic",
            environment: "practice", sequence: 1, sourceTime: start.addingTimeInterval(12 * 60 + 1),
            receivedAt: asOf, bid: 181.500, ask: 181.510)
        let decision = evaluate(lowerBars: lower, higherBars: f.higher, quotes: [quote],
            contexts: [f.context], provenance: f.provenance, asOf: asOf, configuration: f.config)
        #expect(decision.state == .signal)
        #expect(decision.breakBarID == "x9")
        #expect(decision.frozenSwingID == "x3")
    }

    @Test func discoveryReturnsDistinctOverlappingEventsAndOnlyOneBreakPerSwing() {
        let f = fixture()
        let bars = twoSwingBars(f)
        let asOf = end(bars.last!).addingTimeInterval(3)
        let events = discover(bars, fixture: f, asOf: asOf)
        #expect(events.map(\.breakBarID) == ["l6", "l13"])
        #expect(events.map(\.frozenSwingID) == ["l3", "l10"])
        #expect(events.map(\.direction) == [.long, .long])
        #expect(events.allSatisfy { $0.cursorDigest == GBPJPYTrendPullbackEventCursor(consumedKeys: []).digest })
        // The repeated close at l9 stays attached to l3's first break at l6.
        #expect(events.filter { $0.frozenSwingID == "l3" }.count == 1)
        #expect(events[1].breakBarEnd.timeIntervalSince(events[0].breakBarEnd) <= TimeInterval(f.config.maximumBarsFromBreak * f.config.lowerTimeframeSeconds))
    }

    @Test func cursorAndWindowKeepLaterDistinctEventEvaluableAndRetireOlderSwing() {
        let f = fixture()
        let bars = twoSwingBars(f)
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [
            GBPJPYTrendPullbackConsumedKey(frozenSwingID: "l3", direction: .long)
        ])
        let laterWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: "l7", lastLowerBarID: "l13")
        let laterEvents = discover(bars, fixture: f, window: laterWindow, cursor: cursor,
                                   asOf: end(bars.last!).addingTimeInterval(3))
        #expect(laterEvents.map(\.breakBarID) == ["l13"])
        #expect(laterEvents[0].frozenSwingID == "l10")
        #expect(laterEvents[0].cursorDigest == cursor.digest)

        let fullWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l13")
        let emptyCursorEvents = discover(bars, fixture: f, window: fullWindow,
                                         asOf: end(bars.last!).addingTimeInterval(3))
        let consumedCursorEvents = discover(bars, fixture: f, window: fullWindow, cursor: cursor,
                                            asOf: end(bars.last!).addingTimeInterval(3))
        let emptyCursorLater = emptyCursorEvents.first { $0.breakBarID == "l13" }!
        let consumedCursorLater = consumedCursorEvents.first { $0.breakBarID == "l13" }!
        #expect(emptyCursorLater.id == consumedCursorLater.id)
        #expect(emptyCursorLater.cursorDigest != consumedCursorLater.cursorDigest)
        let emptyCursorDecision = evaluate(lowerBars: bars, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: end(bars.last!).addingTimeInterval(3), configuration: f.config,
            window: fullWindow, cursor: GBPJPYTrendPullbackEventCursor(consumedKeys: []), candidate: emptyCursorLater)
        let consumedCursorDecision = evaluate(lowerBars: bars, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: end(bars.last!).addingTimeInterval(3), configuration: f.config,
            window: fullWindow, cursor: cursor, candidate: consumedCursorLater)
        #expect(emptyCursorDecision.eventID == consumedCursorDecision.eventID)
        #expect(emptyCursorDecision.inputDigest != consumedCursorDecision.inputDigest)
        #expect(laterEvents[0].id == consumedCursorLater.id) // Window cursor is outside event identity.

        let afterNewPivot = GBPJPYTrendPullbackWindow(firstLowerBarID: "l12", lastLowerBarID: "l13")
        let superseded = discover(bars, fixture: f, window: afterNewPivot,
                                  asOf: end(bars.last!).addingTimeInterval(3))
        #expect(superseded.map(\.frozenSwingID) == ["l10"])

        let decision = evaluate(lowerBars: bars, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: end(bars.last!).addingTimeInterval(3), configuration: f.config,
            window: laterWindow, cursor: cursor, candidate: laterEvents[0])
        #expect(decision.state == .waiting)
        #expect(decision.eventID == laterEvents[0].id)
        #expect(decision.cursorDigest == cursor.digest)
    }

    @Test func laterDistinctSwingRemainsEvaluableAfterOlderEventExpires() {
        let f = fixture(maximumBarsFromBreak: 2)
        let bars = twoSwingBars(f, suppressFirstTouch: true)
        let asOf = end(bars.last!).addingTimeInterval(3)
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l13")
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let events = discover(bars, fixture: f, window: window, cursor: cursor, asOf: asOf)
        #expect(events.map(\.breakBarID) == ["l6", "l13"])
        let older = evaluate(lowerBars: bars, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: asOf, configuration: f.config,
            window: window, cursor: cursor, candidate: events[0])
        #expect(older.state == .expired)
        #expect(older.eventID == events[0].id)
        let later = evaluate(lowerBars: bars, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: asOf, configuration: f.config,
            window: window, cursor: cursor, candidate: events[1])
        #expect(later.state == .waiting)
        #expect(later.eventID == events[1].id)
    }

    @Test func descriptorWindowCursorAndCandidateMismatchesFailClosed() {
        let f = fixture()
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l8")
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let events = discover(f.lower, fixture: f, window: window, cursor: cursor, asOf: f.asOf)
        let descriptor = events[0]

        let narrowed = GBPJPYTrendPullbackWindow(firstLowerBarID: "l7", lastLowerBarID: "l8")
        let outside = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote], contexts: [f.context],
            provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: narrowed, cursor: cursor, candidate: descriptor)
        #expect(outside.state == .rejected)

        let wrongCursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [
            GBPJPYTrendPullbackConsumedKey(frozenSwingID: "other-swing", direction: .long)
        ])
        let cursorMismatch = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote], contexts: [f.context],
            provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: window, cursor: wrongCursor, candidate: descriptor)
        #expect(cursorMismatch.state == .rejected)
        #expect(cursorMismatch.reasonCodes.contains("candidate_descriptor_mismatch"))

        let changed = GBPJPYTrendPullbackBreakDescriptor(id: descriptor.id, strategyID: descriptor.strategyID,
            strategyVersion: descriptor.strategyVersion, profileDigest: descriptor.profileDigest,
            cursorDigest: descriptor.cursorDigest, windowDigest: descriptor.windowDigest,
            firstLowerBarID: descriptor.firstLowerBarID, lastLowerBarID: descriptor.lastLowerBarID,
            frozenSwingID: "different-swing", direction: .short, breakBarID: descriptor.breakBarID,
            breakBarEnd: descriptor.breakBarEnd, higherTimeframeContextCutoff: descriptor.higherTimeframeContextCutoff,
            sourceIDs: descriptor.sourceIDs)
        let mismatch = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote], contexts: [f.context],
            provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: window, cursor: cursor, candidate: changed)
        #expect(mismatch.state == .rejected)
        #expect(mismatch.reasonCodes.contains("candidate_descriptor_mismatch"))

        let missing = GBPJPYTrendPullbackWindow(firstLowerBarID: "no-such-first", lastLowerBarID: "l8")
        #expect(discover(f.lower, fixture: f, window: missing, cursor: cursor, asOf: f.asOf).isEmpty)
        let missingEndpoint = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote], contexts: [f.context],
            provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: missing, cursor: cursor, candidate: descriptor)
        #expect(missingEndpoint.state == .rejected)
        #expect(missingEndpoint.reasonCodes.contains("evaluation_window_invalid"))
        let duplicatedEndpointBars = f.lower + [GBPJPYTrendPullbackBar(id: "l0", instrument: "GBP/JPY",
            provider: "synthetic", startTime: f.lower[8].startTime.addingTimeInterval(60),
            open: 181.4, high: 181.5, low: 181.3, close: 181.4, complete: true)]
        #expect(discover(duplicatedEndpointBars, fixture: f, window: window, cursor: cursor, asOf: f.asOf).isEmpty)
        let unknownCandidate = GBPJPYTrendPullbackBreakDescriptor(id: descriptor.id,
            strategyID: descriptor.strategyID, strategyVersion: descriptor.strategyVersion,
            profileDigest: descriptor.profileDigest, cursorDigest: descriptor.cursorDigest,
            windowDigest: descriptor.windowDigest, firstLowerBarID: descriptor.firstLowerBarID,
            lastLowerBarID: descriptor.lastLowerBarID, frozenSwingID: descriptor.frozenSwingID,
            direction: descriptor.direction, breakBarID: "unknown-break", breakBarEnd: descriptor.breakBarEnd,
            higherTimeframeContextCutoff: descriptor.higherTimeframeContextCutoff, sourceIDs: descriptor.sourceIDs)
        let unknown = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote], contexts: [f.context],
            provenance: f.provenance, asOf: f.asOf, configuration: f.config,
            window: window, cursor: cursor, candidate: unknownCandidate)
        #expect(unknown.state == .rejected)
        #expect(unknown.reasonCodes.contains("candidate_break_unknown"))
    }

    @Test func bearishStructureProducesShortBreakDescriptor() {
        let f = fixture()
        func reflect(_ bar: GBPJPYTrendPullbackBar) -> GBPJPYTrendPullbackBar {
            GBPJPYTrendPullbackBar(id: bar.id, instrument: bar.instrument, provider: bar.provider,
                startTime: bar.startTime, open: 360 - bar.open, high: 360 - bar.low,
                low: 360 - bar.high, close: 360 - bar.close, complete: bar.complete)
        }
        let lower = f.lower.map(reflect), higher = f.higher.map(reflect)
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: lower[0].id, lastLowerBarID: lower[8].id)
        let events = GBPJPYTrendPullbackV1.discoverBreakEvents(lowerBars: lower, higherBars: higher,
            contexts: [f.context], asOf: f.asOf, window: window,
            cursor: GBPJPYTrendPullbackEventCursor(consumedKeys: []), configuration: f.config)
        #expect(events.map(\.breakBarID) == ["l6"])
        #expect(events[0].direction == .short)
        #expect(events[0].frozenSwingID == "l3")
    }

    @Test func unrelatedBarsPastWindowDoNotChangeEventDigest() {
        let f = fixture()
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: "l0", lastLowerBarID: "l8")
        let cursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let descriptor = discover(f.lower, fixture: f, window: window, cursor: cursor, asOf: f.asOf)[0]
        let laterAsOf = end(f.lower[8]).addingTimeInterval(70)
        let base = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: f.provenance, asOf: laterAsOf, configuration: f.config,
            window: window, cursor: cursor, candidate: descriptor)
        let unrelated = GBPJPYTrendPullbackBar(id: "outside-window", instrument: "GBP/JPY", provider: "synthetic",
            startTime: f.lower[8].startTime.addingTimeInterval(60), open: 181.4, high: 181.5,
            low: 181.3, close: 181.4, complete: true)
        let changedProvenance = GBPJPYTrendPullbackProvenance(environment: "practice", buildID: "synthetic-build",
            codeDigest: "synthetic-code", snapshotDigest: "new-snapshot", lineageIsProviderNative: true,
            quoteWindowComplete: true, quoteSamplingPolicy: "synthetic-complete")
        let withUnrelated = evaluate(lowerBars: f.lower + [unrelated], higherBars: f.higher, quotes: [], contexts: [f.context],
            provenance: changedProvenance, asOf: laterAsOf, configuration: f.config,
            window: window, cursor: cursor, candidate: descriptor)
        #expect(withUnrelated.state == base.state)
        #expect(withUnrelated.eventID == base.eventID)
        #expect(withUnrelated.inputDigest == base.inputDigest)
        #expect(withUnrelated.snapshotDigest != base.snapshotDigest)
    }

    @Test func crossingSessionIdentityExpiresCandidateInsteadOfCarryingItForward() {
        let f = fixture(sessionAtTouch: "next-session")
        let next = GBPJPYTrendPullbackContext(sessionID: "next-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "next-context",
            sourceIDs: ["next-session-source"], measuredAt: f.lower[7].startTime.addingTimeInterval(1),
            sessionOpen: f.lower[7].startTime.addingTimeInterval(1), sessionClose: f.lower[7].startTime.addingTimeInterval(20_000))
        let decision = evaluate(lowerBars: f.lower, higherBars: f.higher, quotes: [f.quote],
            contexts: [f.context, next], provenance: f.provenance, asOf: f.asOf, configuration: f.config)
        #expect(decision.state == .expired)
        #expect(decision.reasonCodes.contains("SESSION_CLOSED"))
    }
}
