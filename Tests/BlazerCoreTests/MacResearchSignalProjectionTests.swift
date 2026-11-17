import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

private let macSignalInstrument = "EUR/USD"
private let macSignalStrategy = "ORB_BREAK_RETEST_V1"
private let macSignalVersion = "ORB_BREAK_RETEST_V1"

private func macSignalProfile(instrument: String = macSignalInstrument) -> StrategyResearchProfile {
    let config = AdaptiveOpportunityAdapters.effectiveConfiguration(
        strategyID: macSignalStrategy, instrument: instrument)!.sha256()!
    return .init(id: "ORB_BREAK_RETEST", version: macSignalVersion,
        family: "ORB research", status: .researchCandidate, sourceReferences: ["test"],
        decisionRole: .shadow,
        acceptedCandidateIdentities: [.init(strategyID: macSignalStrategy, strategyVersion: macSignalVersion)],
        configurationSHA256ByInstrument: [instrument: config],
        evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"],
        adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
        selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
}

private func macSignalCandidate(id: String = "orb-1", instrument: String = macSignalInstrument,
                                provider: String = "OANDA_LIVE", direction: AdaptiveDirection = .long,
                                state: AdaptiveCandidateState = .eligible,
                                freshness: AdaptiveFreshnessState = .fresh,
                                spreadState: AdaptiveSpreadState = .accepted,
                                observedAt: Date? = Date(timeIntervalSince1970: 1_000),
                                validUntil: Date? = Date(timeIntervalSince1970: 1_005),
                                configDigest: String? = nil,
                                evaluatorDigest: String? = nil,
                                adapterDigest: String? = nil,
                                selectorDigest: String? = nil,
                                plan: V3TradePlan? = nil,
                                reasons: [String] = []) -> AdaptiveOpportunityCandidate {
    let config = AdaptiveOpportunityAdapters.effectiveConfiguration(
        strategyID: macSignalStrategy, instrument: instrument)!.sha256()!
    return .init(id: id, strategyID: macSignalStrategy, strategyVersion: macSignalVersion,
        instrument: instrument, provider: provider, direction: direction, observedAt: observedAt,
        validUntil: validUntil, evaluationStartedAt: observedAt ?? Date(timeIntervalSince1970: 1_000),
        evaluationCompletedAt: Date(timeIntervalSince1970: 1_000), state: state,
        rejectionReasons: reasons, entryReference: nil, plan: plan,
        evidenceReferences: ["event-1", "bar-2"], provenance: "test",
        freshness: freshness, spreadState: spreadState,
        effectiveConfigurationSHA256: configDigest ?? config,
        evaluatorCodeSHA256: evaluatorDigest ?? StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"],
        adapterCodeSHA256: adapterDigest ?? StrategyImplementationDigests.adapterCodeSHA256,
        selectorCodeSHA256: selectorDigest ?? StrategyImplementationDigests.selectorCodeSHA256)
}

@Test func candidateValidUntilCodableAndLegacyArchiveDecodes() throws {
    let date = Date(timeIntervalSince1970: 1_000)
    let candidate = macSignalCandidate(observedAt: date, validUntil: date.addingTimeInterval(5))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
    let encoded = try encoder.encode(candidate)
    let decoded = try decoder.decode(AdaptiveOpportunityCandidate.self, from: encoded)
    #expect(decoded == candidate)

    var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    json.removeValue(forKey: "validUntil")
    let legacy = try JSONSerialization.data(withJSONObject: json)
    let oldCandidate = try decoder.decode(AdaptiveOpportunityCandidate.self, from: legacy)
    #expect(oldCandidate.validUntil == nil)
}

@Test func adapterDeadlinesUseQuoteAndConfiguredEventExpiryMinimum() {
    let event = Date(timeIntervalSince1970: 1_000)
    let quote = Date(timeIntervalSince1970: 1_100)
    let c001 = AdaptiveOpportunityAdapters.eventValidUntil(quoteAt: quote, eventStart: event, ttlSeconds: 300)
    let c002 = AdaptiveOpportunityAdapters.eventValidUntil(quoteAt: quote.addingTimeInterval(1_000), eventStart: event, ttlSeconds: 120)
    #expect(c001 == quote.addingTimeInterval(EntryQuality.maxAgeSeconds))
    #expect(c002 == event.addingTimeInterval(180))
    #expect(AdaptiveOpportunityAdapters.eventValidUntil(quoteAt: quote, eventStart: event, ttlSeconds: 300)
        == min(quote.addingTimeInterval(8), event.addingTimeInterval(360)))
}

@Test func candidateAdaptersReportAnalyzerFailureSeparatelyFromEmptyCompletion() {
    let duplicate = StrategyEngine.CandlePayload(time: 60, open: 1, high: 2, low: 0.5, close: 1)
    let input = StrategyEngine.MarketInput(asset: macSignalInstrument, source: "OANDA_LIVE",
        candles1m: [duplicate, duplicate], candles5m: [], lastPrice: 1, bid: 0.9, ask: 1.1,
        spread: 0.2, expirySeconds: 60, quoteAsOfMs: 1_000)
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate001Result(input, asOf: Date())
        == .failed("candidate001_analyzer_failed"))
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate002Result(input, asOf: Date())
        == .failed("candidate002_analyzer_failed"))

    let quietBars = (0..<14).map { index in
        StrategyEngine.CandlePayload(time: Double(index * 60_000), open: 1, high: 1.01,
            low: 0.99, close: 1)
    }
    let empty = StrategyEngine.MarketInput(asset: macSignalInstrument, source: "OANDA_LIVE",
        candles1m: quietBars, candles5m: [], lastPrice: 1, bid: 0.9, ask: 1.1,
        spread: 0.2, expirySeconds: 60, quoteAsOfMs: 1_000)
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate001Result(empty, asOf: Date()) == .completed([]))
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate002Result(empty, asOf: Date()) == .completed([]))
}

@Test func projectionRequiresExactShadowLiveCandidateAndAllowsInclusiveExpiry() {
    let now = Date(timeIntervalSince1970: 1_005)
    let source = String(repeating: "A", count: 40)
    let projected = MacResearchSignalProjector.project(candidates: [
        macSignalCandidate(observedAt: now.addingTimeInterval(-5), validUntil: now)
    ], profiles: [macSignalProfile()], instrument: macSignalInstrument,
        scanGeneration: 22, sourceInputIdentity: source, now: now)
    #expect(projected.count == 1)
    #expect(projected[0].validUntil == now)
    #expect(projected[0].scanGeneration == 22)
    #expect(projected[0].sourceInputIdentity == source)
    #expect(projected[0].evidenceReferences == ["event-1", "bar-2"])
}

#if os(macOS)
private func diagnosticCandidate(family: MacResearchEvaluatorFamily,
                                state: AdaptiveCandidateState = .rejected,
                                direction: AdaptiveDirection = .wait,
                                reasons: [String] = [], quote: Date,
                                validUntil: Date? = nil) -> AdaptiveOpportunityCandidate {
    let identity: (String, String) = switch family {
    case .orb: ("ORB_BREAK_RETEST_V1", "ORB_BREAK_RETEST_V1")
    case .candidate001: ("CANDIDATE_001_CHOCH_FVG_FIB", "candidate-001-v2")
    case .candidate002: ("CANDIDATE_002_AUCTION_FAILURE", "candidate-002-auction-failure-v2")
    }
    return .init(id: "diagnostic-\(family.rawValue)", strategyID: identity.0,
        strategyVersion: identity.1, instrument: "EUR/USD", provider: "OANDA_LIVE",
        direction: direction, observedAt: quote, validUntil: validUntil ?? quote.addingTimeInterval(
            family == .orb ? 5 : 8), evaluationStartedAt: quote,
        evaluationCompletedAt: quote, state: state, rejectionReasons: reasons,
        provenance: "test", freshness: .fresh, spreadState: .accepted)
}

@Test func macDiagnosticsDistinguishEmptyCompletionFromORBConditionsAndFailure() {
    let quote = Date(timeIntervalSince1970: 10_000)
    let orb = diagnosticCandidate(family: .orb, reasons: ["before_opening_range"], quote: quote)
    let result = MacResearchEvaluationDiagnosticProjector.project(candidates: [orb],
        failedFamilies: [.candidate002], visibleSignalIDs: [], quoteAsOf: quote,
        scanGeneration: 7, currentScanGeneration: 7, sourceInputIdentity: "snapshot-7",
        expectedSourceInputIdentity: "snapshot-7", now: quote.addingTimeInterval(1))
    #expect(result.map(\.family) == MacResearchEvaluatorFamily.allCases)
    #expect(result[0].state == .conditionsNotMet)
    #expect(result[0].detail == "Opening range has not formed")
    #expect(result[1].state == .completedNoCandidate)
    #expect(result[1].statusLabel == "Completed · no candidate emitted")
    #expect(result[2].state == .evaluationFailed)
    #expect(result[2].statusLabel == "Evaluation failed")
    #expect(result.allSatisfy { $0.sourceInputIdentity == "snapshot-7" && $0.scanGeneration == 7 })
    #expect(MacResearchEvaluationDiagnosticProjector.project(candidates: [orb], failedFamilies: [],
        visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 7, currentScanGeneration: 8,
        sourceInputIdentity: "snapshot-7", expectedSourceInputIdentity: "snapshot-7",
        now: quote).isEmpty)
    #expect(MacResearchEvaluationDiagnosticProjector.project(candidates: [orb], failedFamilies: [],
        visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 7, currentScanGeneration: 7,
        sourceInputIdentity: "stale-snapshot", expectedSourceInputIdentity: "snapshot-7",
        now: quote).isEmpty)
}

@Test func macDiagnosticsWithheldCandidatesExposeOnlyAllowlistedNonDirectionalLabels() {
    let quote = Date(timeIntervalSince1970: 10_000)
    let rejected = diagnosticCandidate(family: .candidate001, direction: .long,
        reasons: ["spread_rejected", "raw-secret-reason"], quote: quote)
    let orb = diagnosticCandidate(family: .orb, reasons: ["before_opening_range"], quote: quote)
    let legacy = AdaptiveOpportunityCandidate(id: "legacy-control", strategyID: "baseline",
        strategyVersion: "JSC_baseline", instrument: "EUR/USD", provider: "OANDA_LIVE",
        direction: .long, observedAt: quote, validUntil: quote.addingTimeInterval(8),
        evaluationStartedAt: quote, evaluationCompletedAt: quote, state: .eligible,
        provenance: "test", freshness: .fresh, spreadState: .accepted)
    let result = MacResearchEvaluationDiagnosticProjector.project(candidates: [rejected, orb, legacy],
        failedFamilies: [], visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 9,
        currentScanGeneration: 9, sourceInputIdentity: "exact-snapshot",
        expectedSourceInputIdentity: "exact-snapshot", now: quote.addingTimeInterval(1))
    #expect(result.count == 3)
    let candidate001 = result.first { $0.family == .candidate001 }
    #expect(candidate001?.state == .candidateWithheld)
    #expect(candidate001?.detail == "Spread filter rejected the candidate")
    #expect(!(candidate001?.statusLabel.contains("LONG") ?? true))
    #expect(!String(describing: candidate001).contains("raw-secret-reason"))
    #expect(!String(describing: candidate001).contains("diagnostic-Candidate001"))
}

@Test func macDiagnosticsShowEligibleCandidateOnlyWhenExactVisibleSignalExists() {
    let quote = Date(timeIntervalSince1970: 10_000)
    let candidate = diagnosticCandidate(family: .candidate002, state: .eligible,
        direction: .short, quote: quote)
    let shown = MacResearchEvaluationDiagnosticProjector.project(candidates: [candidate],
        failedFamilies: [], visibleSignalIDs: ["diagnostic-Candidate002"], quoteAsOf: quote,
        scanGeneration: 11, currentScanGeneration: 11, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote)
    let withheld = MacResearchEvaluationDiagnosticProjector.project(candidates: [candidate],
        failedFamilies: [], visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 11,
        currentScanGeneration: 11, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote)
    #expect(shown[2].state == .candidateShown)
    #expect(withheld[2].state == .candidateWithheld)
    #expect(shown[2].detail == nil && withheld[2].detail == nil)
}

@Test func macDiagnosticsFailClosedForInvalidFutureAndExpiredQuotes() {
    let quote = Date(timeIntervalSince1970: 10_000)
    func project(_ timestamp: Date?) -> [MacResearchEvaluationDiagnostic] {
        MacResearchEvaluationDiagnosticProjector.project(candidates: [], failedFamilies: [],
            visibleSignalIDs: [], quoteAsOf: timestamp, scanGeneration: 2,
            currentScanGeneration: 2, sourceInputIdentity: "snapshot",
            expectedSourceInputIdentity: "snapshot", now: quote)
    }
    #expect(project(nil).isEmpty)
    #expect(project(Date(timeIntervalSince1970: .infinity)).isEmpty)
    #expect(project(quote.addingTimeInterval(2)).isEmpty)
    #expect(project(quote.addingTimeInterval(1)).count == 3)
    let orbAtBoundary = MacResearchEvaluationDiagnosticProjector.project(candidates: [],
        failedFamilies: [], visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 2,
        currentScanGeneration: 2, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote.addingTimeInterval(5))
    #expect(orbAtBoundary[0].validUntil == quote.addingTimeInterval(5))
    #expect(orbAtBoundary[0].state == .conditionsNotMet)
    #expect(MacResearchEvaluationDiagnosticProjector.project(candidates: [], failedFamilies: [],
        visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 2,
        currentScanGeneration: 2, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote.addingTimeInterval(5.001)).map(\.family)
        == [.candidate001, .candidate002])
    #expect(MacResearchEvaluationDiagnosticProjector.project(candidates: [], failedFamilies: [],
        visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 2,
        currentScanGeneration: 2, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote.addingTimeInterval(8)).count == 2)
    #expect(MacResearchEvaluationDiagnosticProjector.project(candidates: [], failedFamilies: [],
        visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 2,
        currentScanGeneration: 2, sourceInputIdentity: "snapshot",
        expectedSourceInputIdentity: "snapshot", now: quote.addingTimeInterval(8.001)).isEmpty)
}

@Test func macDiagnosticReasonAllowlistUsesSafeFallback() {
    #expect(MacResearchEvaluationDiagnosticProjector.safeReasonLabel("spread_rejected")
        == "Spread filter rejected the candidate")
    #expect(MacResearchEvaluationDiagnosticProjector.safeReasonLabel("unrecognized-sensitive-code")
        == "Additional validation required")
}

@Test func macDiagnosticTreatsSameFamilyVersionMismatchAsWithheldWithoutIdentityLeak() {
    let quote = Date(timeIntervalSince1970: 10_000)
    let mismatched = AdaptiveOpportunityCandidate(id: "private-candidate-id",
        strategyID: "CANDIDATE_001_CHOCH_FVG_FIB", strategyVersion: "candidate-001-v999",
        instrument: "EUR/USD", provider: "OANDA_LIVE", direction: .long,
        observedAt: quote, validUntil: quote.addingTimeInterval(8),
        evaluationStartedAt: quote, evaluationCompletedAt: quote, state: .eligible,
        provenance: "test", freshness: .fresh, spreadState: .accepted)
    let result = MacResearchEvaluationDiagnosticProjector.project(candidates: [mismatched],
        failedFamilies: [], visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 12,
        currentScanGeneration: 12, sourceInputIdentity: "snapshot-12",
        expectedSourceInputIdentity: "snapshot-12", now: quote)
    let diagnostic = result.first { $0.family == .candidate001 }
    #expect(diagnostic?.state == .candidateWithheld)
    #expect(diagnostic?.detail == nil)
    #expect(!String(describing: diagnostic).contains("candidate-001-v999"))
    #expect(!String(describing: diagnostic).contains("private-candidate-id"))
}

@MainActor
@Test func macDiagnosticsClearOnRefreshBackgroundAndWithdrawal() async {
    let quote = Date()
    let diagnostics = MacResearchEvaluationDiagnosticProjector.project(candidates: [],
        failedFamilies: [], visibleSignalIDs: [], quoteAsOf: quote, scanGeneration: 1,
        currentScanGeneration: 1, sourceInputIdentity: "test-snapshot",
        expectedSourceInputIdentity: "test-snapshot", now: quote)
    let signal = MacResearchSignal(id: "test-signal", profileID: "test-profile",
        strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
        instrument: "EUR/USD", direction: .long, observedAt: quote,
        validUntil: quote.addingTimeInterval(5), reasons: [], evidenceReferences: [],
        sourceInputIdentity: "test-snapshot", scanGeneration: 1)
    let model = LightningDeskModel(storageRoot: FileManager.default.temporaryDirectory
        .appendingPathComponent("mac-diagnostic-lifecycle-\(UUID().uuidString)", isDirectory: true))

    model.installMacResearchStateForTesting(signals: [signal], diagnostics: diagnostics)
    #expect(model.macResearchSignals.count == 1 && model.macResearchEvaluationDiagnostics.count == 3)
    _ = model.beginLiveDecisionRefreshForTesting(for: "EUR/USD")
    #expect(model.macResearchSignals.isEmpty && model.macResearchEvaluationDiagnostics.isEmpty)

    model.installMacResearchStateForTesting(signals: [signal], diagnostics: diagnostics)
    model.handleAppBackgrounded(now: quote.addingTimeInterval(1))
    #expect(model.macResearchSignals.isEmpty && model.macResearchEvaluationDiagnostics.isEmpty)

    model.installMacResearchStateForTesting(signals: [signal], diagnostics: diagnostics)
    await model.withdrawLiveStrategyDecisionForTesting("EUR/USD", reason: "test_withdrawal")
    #expect(model.macResearchSignals.isEmpty && model.macResearchEvaluationDiagnostics.isEmpty)
    #expect(model.macResearchSignalStatus == .failed)
}
#endif

@Test func projectionRejectsExpiredUntrustedAndEmptyValidity() {
    let now = Date(timeIntervalSince1970: 1_005)
    let base = macSignalCandidate(observedAt: now.addingTimeInterval(-5))
    let candidates = [
        base,
        macSignalCandidate(id: "expired", observedAt: now.addingTimeInterval(-6), validUntil: now.addingTimeInterval(-0.001)),
        macSignalCandidate(id: "missing", observedAt: now.addingTimeInterval(-1), validUntil: nil)
    ]
    let result = MacResearchSignalProjector.project(candidates: candidates,
        profiles: [macSignalProfile()], instrument: macSignalInstrument, scanGeneration: 1,
        sourceInputIdentity: "input", now: now)
    #expect(result.map(\.id) == [base.id])
    #expect(MacResearchSignalProjector.project(candidates: [base], profiles: [macSignalProfile()],
        instrument: macSignalInstrument, scanGeneration: 1, sourceInputIdentity: "", now: now).isEmpty)
}

@Test func projectionRejectsProviderDirectionStateAndFutureSkew() {
    let now = Date(timeIntervalSince1970: 1_000)
    let invalid = [
        macSignalCandidate(id: "provider", provider: "OANDA_PRACTICE"),
        macSignalCandidate(id: "wait", direction: .wait),
        macSignalCandidate(id: "rejected", state: .rejected),
        macSignalCandidate(id: "spread", spreadState: .rejected),
        macSignalCandidate(id: "stale", freshness: .stale),
        macSignalCandidate(id: "future", observedAt: now.addingTimeInterval(1.001), validUntil: now.addingTimeInterval(2))
    ]
    #expect(MacResearchSignalProjector.project(candidates: invalid, profiles: [macSignalProfile()],
        instrument: macSignalInstrument, scanGeneration: 1, sourceInputIdentity: "input", now: now).isEmpty)
}

@Test func projectionRecomputesQuoteAgeAtInclusiveEightSecondBoundary() {
    let now = Date(timeIntervalSince1970: 2_000)
    let atLimit = macSignalCandidate(id: "at-limit", observedAt: now.addingTimeInterval(-8),
        validUntil: now.addingTimeInterval(1))
    let overLimitByOneMillisecond = macSignalCandidate(id: "over-limit",
        observedAt: now.addingTimeInterval(-8.001), validUntil: now.addingTimeInterval(1))
    let projected = MacResearchSignalProjector.project(
        candidates: [atLimit, overLimitByOneMillisecond], profiles: [macSignalProfile()],
        instrument: macSignalInstrument, scanGeneration: 1, sourceInputIdentity: "input", now: now)
    #expect(projected.map(\.id) == ["at-limit"])
}

@Test func projectionRejectsDigestAndExactInstrumentMismatches() {
    let now = Date(timeIntervalSince1970: 1_001)
    let invalid = [
        macSignalCandidate(id: "config", configDigest: String(repeating: "0", count: 64)),
        macSignalCandidate(id: "evaluator", evaluatorDigest: String(repeating: "0", count: 64)),
        macSignalCandidate(id: "adapter", adapterDigest: String(repeating: "0", count: 64)),
        macSignalCandidate(id: "selector", selectorDigest: String(repeating: "0", count: 64)),
        macSignalCandidate(id: "instrument", instrument: "GBP/USD")
    ]
    #expect(MacResearchSignalProjector.project(candidates: invalid, profiles: [macSignalProfile()],
        instrument: macSignalInstrument, scanGeneration: 1, sourceInputIdentity: "input", now: now).isEmpty)
}

@Test func projectionRetainsDistinctConflictingCandidatesWithoutPromotionProfile() {
    let now = Date(timeIntervalSince1970: 1_001)
    let candidates = [macSignalCandidate(id: "candidate-a"), macSignalCandidate(id: "candidate-b", direction: .short)]
    let projected = MacResearchSignalProjector.project(candidates: candidates,
        profiles: [macSignalProfile()], instrument: macSignalInstrument, scanGeneration: 4,
        sourceInputIdentity: "input", now: now)
    #expect(projected.map(\.id) == ["candidate-a", "candidate-b"])

    let live = StrategyResearchProfile(id: "ORB_BREAK_RETEST", version: macSignalVersion,
        family: "ORB research", status: .researchCandidate, sourceReferences: ["test"],
        decisionRole: .liveSignal,
        acceptedCandidateIdentities: [.init(strategyID: macSignalStrategy, strategyVersion: macSignalVersion)],
        configurationSHA256ByInstrument: macSignalProfile().configurationSHA256ByInstrument,
        evaluatorCodeSHA256: StrategyImplementationDigests.evaluatorCodeSHA256["ORB_BREAK_RETEST"],
        adapterCodeSHA256: StrategyImplementationDigests.adapterCodeSHA256,
        selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
    let visibleWithLiveRoleProfile = MacResearchSignalProjector.project(candidates: candidates, profiles: [live],
        instrument: macSignalInstrument, scanGeneration: 4, sourceInputIdentity: "input", now: now)
    #expect(visibleWithLiveRoleProfile.map(\.id) == ["candidate-a", "candidate-b"])
}

@Test func practiceResearchProjectsWithoutPromotionAndBindsProvider() {
    let now = Date(timeIntervalSince1970: 1_001)
    let practiceCandidate = macSignalCandidate(provider: "OANDA_PRACTICE")
    let projected = MacResearchSignalProjector.project(candidates: [practiceCandidate], profiles: [],
        instrument: macSignalInstrument, scanGeneration: 13, sourceInputIdentity: "practice-snapshot",
        now: now, source: .oandaPractice)
    #expect(projected.count == 1)
    #expect(projected[0].environment == .practice)
    #expect(projected[0].stage == .confirmed)
    #expect(projected[0].timeframe == "M1")
    #expect(projected[0].entryReference == nil)
    #expect(projected[0].profileID == "research:\(macSignalStrategy)")

    let genericOandaPractice = macSignalCandidate(provider: "OANDA")
    #expect(MacResearchSignalProjector.project(candidates: [genericOandaPractice], profiles: [],
        instrument: macSignalInstrument, scanGeneration: 13, sourceInputIdentity: "practice-snapshot",
        now: now, source: .oandaPractice).count == 1)

    #expect(MacResearchSignalProjector.project(candidates: [macSignalCandidate()], profiles: [],
        instrument: macSignalInstrument, scanGeneration: 13, sourceInputIdentity: "practice-snapshot",
        now: now, source: .oandaPractice).isEmpty)
    #expect(MacResearchSignalProjector.project(candidates: [practiceCandidate], profiles: [],
        instrument: macSignalInstrument, scanGeneration: 13, sourceInputIdentity: "live-snapshot",
        now: now, source: .oandaLive).isEmpty)
}

@Test func projectionKeepsFormingCandidatesAndAttachesOnlyValidatedPlanPreview() {
    let now = Date(timeIntervalSince1970: 1_001)
    let plan = V3TradePlan(id: "preview", instrument: macSignalInstrument,
        strategyID: macSignalStrategy, strategyVersion: macSignalVersion,
        engineVersion: "test", sourceObservationID: "observation", state: .draft,
        side: .long, entryPrice: 1.1, stopPrice: 1.0, targetPrice: 1.3,
        units: 1, maxSpread: 0.01, riskFraction: 0.01,
        evidenceIDs: ["plan-event"], createdAt: now)
    let candidates = [
        macSignalCandidate(id: "forming", state: .rejected,
            reasons: ["breakout_confirmed_retest_pending"]),
        macSignalCandidate(id: "with-plan", plan: plan)
    ]
    let projected = MacResearchSignalProjector.project(candidates: candidates,
        profiles: [], instrument: macSignalInstrument, scanGeneration: 2,
        sourceInputIdentity: "input", now: now)
    #expect(projected.map(\.id) == ["forming", "with-plan"])
    #expect(projected[0].stage == .forming)
    #expect(projected[0].planPreview == nil)
    #expect(projected[0].timeframe == "M1")
    #expect(projected[1].planPreview?.entryPrice == 1.1)
    #expect(projected[1].entryReference == 1.1)
    #expect(projected[1].stopPrice == 1.0)
    #expect(projected[1].targetPrice == 1.3)
    #expect(abs((projected[1].planPreview?.rewardRisk ?? 0) - 2) < 1e-9)

    let rejected = [
        macSignalCandidate(id: "risk-rejected", state: .rejected, reasons: ["invalid_long_structure"]),
        macSignalCandidate(id: "data-rejected", state: .rejected, reasons: ["m15_context_unavailable"]),
        macSignalCandidate(id: "unknown-rejected", state: .rejected, reasons: ["unknown"])
    ]
    #expect(MacResearchSignalProjector.project(candidates: rejected, profiles: [],
        instrument: macSignalInstrument, scanGeneration: 2, sourceInputIdentity: "input", now: now).isEmpty)
}
