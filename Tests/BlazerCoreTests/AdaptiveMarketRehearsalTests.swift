import Foundation
import Testing
@testable import BlazerCore

struct AdaptiveMarketRehearsalTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func gbpJpySnapshot(m1Count: Int = 80, m5Count: Int = 24,
                                m5OffsetSeconds: Double = 0) -> StrategyEngine.MarketInput {
        let m1Base = floor(now.timeIntervalSince1970 / 60) * 60 - Double(m1Count * 60)
        let m5Base = floor(now.timeIntervalSince1970 / 900) * 900 - Double(m5Count * 300)
        let m1 = (0..<m1Count).map { index in
            let time = (m1Base + Double(index * 60)) * 1_000
            return StrategyEngine.CandlePayload(time: time, open: 190.05,
                high: 190.10, low: 190.00, close: 190.05)
        }
        let m5 = (0..<m5Count).map { index in
            let time = (m5Base + Double(index * 300) + m5OffsetSeconds) * 1_000
            return StrategyEngine.CandlePayload(time: time, open: 190.05,
                high: 190.10, low: 190.00, close: 190.05)
        }
        return StrategyEngine.MarketInput(asset: "GBP/JPY", source: "oanda",
            candles1m: m1, candles5m: m5, lastPrice: 190.05, bid: 190.04,
            ask: 190.05, spread: 0.01, expirySeconds: 60,
            quoteAsOfMs: now.timeIntervalSince1970 * 1_000,
            evaluatedAtMs: now.timeIntervalSince1970 * 1_000, policy: .baseline)
    }

    private func londonPracticeSnapshot(quoteAge: TimeInterval = 1, retest: Bool = true) ->
        (StrategyEngine.MarketInput, Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let open = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 8))!
        var candles: [StrategyEngine.CandlePayload] = []
        for index in 0..<21 {
            let start = open.addingTimeInterval(Double(index * 60))
            let opening: Double, high: Double, low: Double, closing: Double
            switch index {
            case 0..<5: (opening, high, low, closing) = (190.05, 190.10, 190.00, 190.05)
            case 19: (opening, high, low, closing) = (190.10, 190.16, 190.10, 190.16)
            case 20 where retest: (opening, high, low, closing) = (190.11, 190.13, 190.10, 190.12)
            case 20: (opening, high, low, closing) = (190.16, 190.18, 190.14, 190.17)
            default: (opening, high, low, closing) = (190.05, 190.08, 190.02, 190.05)
            }
            candles.append(.init(time: start.timeIntervalSince1970 * 1_000,
                open: opening, high: high, low: low, close: closing))
        }
        let quoteAt = open.addingTimeInterval(21 * 60 + 2)
        let receivedAt = quoteAt.addingTimeInterval(quoteAge)
        let m5 = (0..<24).map { index in
            StrategyEngine.CandlePayload(time: open.addingTimeInterval(Double(index * 300))
                .timeIntervalSince1970 * 1_000, open: 190.05, high: 190.10,
                low: 190.00, close: 190.05)
        }
        let input = StrategyEngine.MarketInput(asset: "GBP/JPY", source: "oanda",
            candles1m: candles, candles5m: m5, lastPrice: 190.12, bid: 190.11,
            ask: 190.12, spread: 0.01, expirySeconds: 60,
            quoteAsOfMs: quoteAt.timeIntervalSince1970 * 1_000,
            evaluatedAtMs: receivedAt.timeIntervalSince1970 * 1_000, policy: .baseline)
        return (input, quoteAt, receivedAt)
    }

    @Test func rehearsalRecordPreservesDecisionStatesAndInputIdentity() throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "candidate", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .wait, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now.addingTimeInterval(0.1), state: .rejected,
            rejectionReasons: ["no_setup"], entryReference: nil, provenance: "test",
            freshness: .fresh, spread: input.spread, spreadState: .accepted)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now.addingTimeInterval(0.1), candidates: [candidate], decision: decision,
            decisionState: .noOpportunity,
            horizonEvidence: [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: 60,
                state: .awaitingEvidence, reason: "fixture")], environment: .oandaPractice)
        #expect(record.validation().isEmpty)
        #expect(record.decisionState == .noOpportunity)
        #expect(record.environment == .oandaPractice)
        #expect(record.inputDigest == (try ResearchEvent.digest(of: input)))
    }

    @Test func actionableStateRequiresSelectedCandidate() throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "candidate", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .wait, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .rejected, provenance: "test",
            freshness: .fresh, spread: input.spread, spreadState: .accepted)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now, candidates: [candidate], decision: decision,
            decisionState: .actionableOpportunity, horizonEvidence: [])
        #expect(record.validation().contains("actionable_decision_missing_candidate"))
    }

    @Test func horizonIsNotPresentedAsSupportedWithoutEvidence() throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "candidate", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .eligible, entryReference: input.lastPrice,
            horizonsSeconds: [60, 180, 300], evidenceReferences: [], provenance: "test",
            freshness: .fresh, spread: input.spread, spreadState: .accepted, rankingScore: 1)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now, candidates: [candidate], decision: decision,
            decisionState: .actionableOpportunity,
            horizonEvidence: [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                state: .awaitingEvidence, reason: "no evidence")])
        #expect(record.selectedHorizonSeconds == nil)
        #expect(record.selectedHorizonEvidenceState == .awaitingEvidence)
    }

    @Test func selectedHorizonRequiresRecordedResearchEvidence() throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "candidate", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .eligible, entryReference: input.lastPrice,
            horizonsSeconds: [60, 180, 300], evidenceReferences: ["research:sample"], provenance: "test",
            freshness: .fresh, spread: input.spread, spreadState: .accepted, rankingScore: 1)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now, candidates: [candidate], decision: decision,
            decisionState: .actionableOpportunity,
            horizonEvidence: [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: 60,
                state: .supportedByResearch, evidenceReferences: candidate.evidenceReferences,
                reason: "fixture evidence")])
        #expect(record.selectedHorizonSeconds == 60)
        #expect(record.selectedHorizonEvidenceState == .supportedByResearch)
    }

    @Test func decisionStateDoesNotTreatUnsafeCandidateAsForming() {
        let stale = AdaptiveOpportunityCandidate(id: "stale", strategyID: "test",
            strategyVersion: "v1", instrument: "EUR/USD", provider: "oanda",
            direction: .long, observedAt: now.addingTimeInterval(-30),
            evaluationStartedAt: now, evaluationCompletedAt: now, state: .rejected,
            rejectionReasons: ["observation_expired"], provenance: "test",
            freshness: .stale, spread: 0.01, spreadState: .accepted)
        let decision = AdaptiveOpportunitySelector.select([stale], now: now)
        #expect(AdaptiveMarketRehearsal.decisionState(for: decision) == .noOpportunity)
    }

    @Test func decisionStateRetainsDevelopingSetup() {
        let forming = AdaptiveOpportunityCandidate(id: "forming", strategyID: "test",
            strategyVersion: "v1", instrument: "EUR/USD", provider: "oanda",
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .rejected,
            rejectionReasons: ["breakout_confirmation_pending"], provenance: "test",
            freshness: .fresh, spread: 0.01, spreadState: .accepted)
        let decision = AdaptiveOpportunitySelector.select([forming], now: now)
        #expect(AdaptiveMarketRehearsal.decisionState(for: decision) == .opportunityForming)
    }

    @Test func selectedCandidateWithoutCompletePlanIsConfirmedButNotActionable() {
        let candidate = AdaptiveOpportunityCandidate(id: "confirmed", strategyID: "candidate001",
            strategyVersion: "v2", instrument: "GBP/JPY", provider: "oanda",
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .eligible, entryReference: 190.1,
            provenance: "fixture", freshness: .fresh, spread: 0.01,
            spreadState: .accepted, rankingScore: 1)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        #expect(decision.selectedCandidateID == candidate.id)
        #expect(AdaptiveMarketRehearsal.decisionState(for: decision) == .confirmedOpportunity)

        let invalidPlan = V3TradePlan(id: "invalid-plan", instrument: "GBP/JPY",
            strategyID: "candidate002", strategyVersion: "v2", engineVersion: "engine",
            sourceObservationID: "observation", state: .draft, side: .long,
            entryPrice: 190.1, stopPrice: 190.2, targetPrice: 190.3,
            units: 1, maxSpread: 0.03, riskFraction: 0.01, createdAt: now)
        let invalidPlanCandidate = AdaptiveOpportunityCandidate(id: "invalid-plan-candidate",
            strategyID: "candidate002", strategyVersion: "v2", instrument: "GBP/JPY",
            provider: "oanda", direction: .long, observedAt: now,
            evaluationStartedAt: now, evaluationCompletedAt: now,
            state: .eligible, entryReference: 190.1, plan: invalidPlan,
            provenance: "fixture", freshness: .fresh, spread: 0.01,
            spreadState: .accepted, rankingScore: 1)
        let invalidDecision = AdaptiveOpportunitySelector.select([invalidPlanCandidate], now: now)
        #expect(invalidDecision.selectedCandidateID == nil)
        #expect(AdaptiveMarketRehearsal.decisionState(for: invalidDecision) == .confirmedOpportunity)
    }

    @Test func adaptiveRehearsalPersistsAndReloadsDeterministically() async throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "persisted", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .wait, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now.addingTimeInterval(0.1), state: .rejected,
            rejectionReasons: ["no_setup"], provenance: "fixture",
            freshness: .fresh, spread: input.spread, spreadState: .accepted)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now.addingTimeInterval(0.2), candidates: [candidate], decision: decision,
            decisionState: .noOpportunity,
            horizonEvidence: [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: nil,
                state: .awaitingEvidence, reason: "fixture")])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("adaptive-replay-\(UUID().uuidString)", isDirectory: true)
        let store = ResearchStore(root: root)
        try await store.record(record)
        try await store.record(record)
        let reloaded = try await ResearchStore(root: root).adaptiveRehearsals()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.id == record.id)
        #expect(reloaded.first?.inputDigest == record.inputDigest)
        #expect(reloaded.first?.decision.selectedCandidateID == nil)
        #expect(reloaded.first?.validation().isEmpty == true)
    }

    @Test func nativeProjectionExpiresAStaleSelectedDecision() throws {
        let input = GoldenFixture.market()
        let candidate = AdaptiveOpportunityCandidate(id: "selected", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: "oanda",
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .eligible, entryReference: input.lastPrice,
            horizonsSeconds: [60], evidenceReferences: ["research:fixture"], provenance: "fixture",
            freshness: .fresh, spread: input.spread, spreadState: .accepted, rankingScore: 1)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now, candidates: [candidate], decision: decision,
            decisionState: .actionableOpportunity,
            horizonEvidence: [AdaptiveHorizonEvidence(candidateID: candidate.id, horizonSeconds: 60,
                state: .supportedByResearch, evidenceReferences: candidate.evidenceReferences,
                reason: "fixture")])
        let projection = AdaptiveResearchProjection(record: record, now: now.addingTimeInterval(9))
        #expect(projection.decisionState == .noOpportunity)
        #expect(projection.horizonSeconds == nil)
        #expect(projection.invalidationReason == "decision_expired_or_stale")
        #expect(projection.requiresManualExecution)
    }

    @Test func unavailableCandidateProducesUnavailableNativeState() {
        let candidate = AdaptiveOpportunityCandidate(id: "provider", strategyID: "test",
            strategyVersion: "v1", instrument: "EUR/USD", provider: "oanda",
            direction: .wait, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .unavailable,
            rejectionReasons: ["provider_unavailable"], provenance: "fixture",
            freshness: .missing, spreadState: .unavailable)
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        #expect(AdaptiveMarketRehearsal.decisionState(for: decision) == .unavailable)
    }

    @Test func existingSnapshotEvaluationPersistsWithoutProviderRefetch() async throws {
        let input = GoldenFixture.market()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("adaptive-snapshot-\(UUID().uuidString)", isDirectory: true)
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            input, observedAt: now, receivedAt: now.addingTimeInterval(0.1),
            environment: .oandaLive, store: ResearchStore(root: root))
        #expect(result.record.inputDigest == (try ResearchEvent.digest(of: input)))
        #expect(result.record.provider == input.source)
        #expect(result.record.validation().isEmpty)
        #expect(result.record.environment == .oandaLive)
        #expect(try await ResearchStore(root: root).adaptiveRehearsals().count == 1)
    }

    @Test func engineCandidatesDoNotInventHorizonEvidence() async throws {
        let input = GoldenFixture.market()
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            input, observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        let engineCandidates = result.record.candidates.filter {
            $0.provenance.hasPrefix("existing-javascriptcore-")
        }
        #expect(!engineCandidates.isEmpty)
        #expect(engineCandidates.allSatisfy { $0.horizonsSeconds.isEmpty && $0.evidenceReferences.isEmpty })
        #expect(result.record.horizonEvidence.filter {
            engineCandidates.map(\.id).contains($0.candidateID)
        }.allSatisfy { $0.state == .awaitingEvidence })
        #expect(result.record.selectedHorizonSeconds == nil)
    }

    @Test func snapshotTimingSeparatesCandidateSelectionAndPersistence() async throws {
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            GoldenFixture.market(), observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        #expect(result.timing.candidateEvaluationMs >= 0)
        #expect(result.timing.selectionMs >= 0)
        #expect(result.timing.totalMs >= result.timing.candidateEvaluationMs)
    }

    @Test func gbpJpySnapshotRunsExistingResearchEvaluatorsAndRecordsNoSetup() async throws {
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            gbpJpySnapshot(), observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        let outcomes = try #require(result.record.evaluatorOutcomes)
        #expect(outcomes.map(\.evaluatorID) == ["londonBreakRetest", "trendPullback", "rangeRejection",
            "candidate001", "candidate002"])
        let unconfigured = outcomes.filter { $0.state == .notConfigured }
        #expect(unconfigured.count == 2)
        #expect(unconfigured.allSatisfy { $0.timeframe == "UNCONFIGURED" })
        #expect(unconfigured.allSatisfy { $0.reasonCode == "profile_not_configured" })
        let london = try #require(outcomes.first { $0.evaluatorID == "londonBreakRetest" })
        #expect(london.timeframe == "M1")
        #expect(london.state == .conditionsNotMet)
        #expect(london.reasonCode == "practice_environment_required")
        let configured = outcomes.filter { $0.state != .notConfigured }
        let otherConfigured = configured.filter { $0.evaluatorID != "londonBreakRetest" }
        #expect(otherConfigured.allSatisfy { $0.timeframe == "M1+M15" })
        #expect(otherConfigured.allSatisfy { $0.state == .completed })
        #expect(otherConfigured.allSatisfy { $0.candidateIDs.isEmpty && $0.reasonCode == "no_candidate" })
    }

    @Test func gbpJpySnapshotDistinguishesInsufficientHistoryFromNoSetup() async throws {
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            gbpJpySnapshot(m5OffsetSeconds: 60), observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        let outcomes = try #require(result.record.evaluatorOutcomes)
        #expect(outcomes.count == 5)
        #expect(outcomes.filter { $0.state == .notConfigured }.count == 2)
        #expect(outcomes.first { $0.evaluatorID == "londonBreakRetest" }?.timeframe == "M1")
        let configured = outcomes.filter { $0.state != .notConfigured }
        let otherConfigured = configured.filter { $0.evaluatorID != "londonBreakRetest" }
        #expect(otherConfigured.allSatisfy { $0.state == .dataUnavailable })
        #expect(otherConfigured.allSatisfy { $0.reasonCode == "m15_context_unavailable" })
    }

    @Test func londonPracticeSnapshotProducesTechnicalSetupWithNoOrderPlan() async throws {
        let (input, quoteAt, receivedAt) = londonPracticeSnapshot()
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(input,
            observedAt: quoteAt, receivedAt: receivedAt, environment: .oandaPractice)
        let london = try #require(result.record.candidates.first {
            $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID
        })
        #expect(london.state == .eligible)
        #expect(london.plan == nil)
        #expect(london.observedAt == quoteAt)
        #expect(london.stopReference != nil)
        #expect(london.targetReference != nil)
        #expect(london.effectiveConfigurationSHA256 == AdaptiveOpportunityAdapters
            .effectiveConfiguration(strategyID: london.strategyID, instrument: "GBP/JPY")?.sha256())
        #expect(result.record.decision.selectedCandidateID == london.id)
        #expect(AdaptiveMarketRehearsal.decisionState(for: result.record.decision) == .actionableOpportunity)
    }

    @Test func londonProfileRejectsStaleQuoteAndNeverRunsInLiveEnvironment() async throws {
        let (input, quoteAt, receivedAt) = londonPracticeSnapshot(quoteAge: 4)
        let stale = try await AdaptiveMarketRehearsal.evaluateSnapshot(input,
            observedAt: quoteAt, receivedAt: receivedAt, environment: .oandaPractice)
        #expect(stale.record.evaluatorOutcomes?.first { $0.evaluatorID == "londonBreakRetest" }?.reasonCode == "quote_stale")
        #expect(!stale.record.candidates.contains { $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID })

        let (freshInput, freshQuote, freshReceived) = londonPracticeSnapshot()
        let live = try await AdaptiveMarketRehearsal.evaluateSnapshot(freshInput,
            observedAt: freshQuote, receivedAt: freshReceived, environment: .oandaLive)
        #expect(live.record.evaluatorOutcomes?.first { $0.evaluatorID == "londonBreakRetest" }?.reasonCode == "practice_environment_required")
        #expect(!live.record.candidates.contains { $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID })
    }

    @Test func londonRetestDiagnosticRemainsVisibleAsForming() async throws {
        let (input, _, receivedAt) = londonPracticeSnapshot(retest: false)
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(input,
            observedAt: receivedAt.addingTimeInterval(-1), receivedAt: receivedAt,
            environment: .oandaPractice)
        let forming = try #require(result.record.candidates.first {
            $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID
        })
        #expect(forming.state == .rejected)
        #expect(forming.rejectionReasons == ["retest_confirmation_pending"])
        #expect(result.record.evaluatorOutcomes?.first { $0.evaluatorID == "londonBreakRetest" }?.reasonCode == "waiting_for_retest")
        #expect(result.record.decisionState == .opportunityForming)

        let (refreshedInput, _, refreshedAt) = londonPracticeSnapshot(quoteAge: 2, retest: false)
        let refreshed = try await AdaptiveMarketRehearsal.evaluateSnapshot(refreshedInput,
            observedAt: refreshedAt.addingTimeInterval(-2), receivedAt: refreshedAt,
            environment: .oandaPractice)
        let refreshedCandidate = try #require(refreshed.record.candidates.first {
            $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID
        })
        #expect(refreshedCandidate.id == forming.id)
        #expect(refreshedCandidate.observedAt == forming.observedAt)
    }

    @Test func londonSessionBoundariesUseLocalDateAndFailClosed() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        for (hour, minute, expectedReason) in [(7, 59, "waiting_for_range"), (12, 0, "session_closed")] {
            let instant = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17,
                hour: hour, minute: minute))!
            let oneMinute = (0..<80).map { index in
                StrategyEngine.CandlePayload(time: instant.addingTimeInterval(Double(index - 80) * 60)
                    .timeIntervalSince1970 * 1_000, open: 190.05, high: 190.10,
                    low: 190.00, close: 190.05)
            }
            let fiveMinute = (0..<24).map { index in
                StrategyEngine.CandlePayload(time: instant.addingTimeInterval(Double(index - 24) * 300)
                    .timeIntervalSince1970 * 1_000, open: 190.05, high: 190.10,
                    low: 190.00, close: 190.05)
            }
            let input = StrategyEngine.MarketInput(asset: "GBP/JPY", source: "oanda",
                candles1m: oneMinute, candles5m: fiveMinute, lastPrice: 190.1, bid: 190.09,
                ask: 190.10, spread: 0.01, expirySeconds: 60,
                quoteAsOfMs: instant.timeIntervalSince1970 * 1_000)
            let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(input,
                observedAt: instant, receivedAt: instant, environment: .oandaPractice)
            #expect(result.record.evaluatorOutcomes?.first { $0.evaluatorID == "londonBreakRetest" }?.reasonCode == expectedReason)
            #expect(!result.record.candidates.contains { $0.strategyID == GBPJPYLondonBreakRetestV1.strategyID })
        }
    }

    @Test func recognizedExpiredCandidateIsConditionsNotMetInsteadOfNoSetup() async throws {
        var input = gbpJpySnapshot()
        var candles = input.candles1m
        candles[77] = StrategyEngine.CandlePayload(time: candles[77].time,
            open: 190.04, high: 190.06, low: 189.99, close: 190.03)
        candles[78] = StrategyEngine.CandlePayload(time: candles[78].time,
            open: 190.03, high: 190.05, low: 190.01, close: 190.02)
        candles[79] = StrategyEngine.CandlePayload(time: candles[79].time,
            open: 190.02, high: 190.05, low: 190.01, close: 190.02)
        input.candles1m = candles
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            input, observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        let outcome = try #require(result.record.evaluatorOutcomes?.first {
            $0.evaluatorID == "candidate002"
        })
        #expect(outcome.state == .conditionsNotMet)
        #expect(outcome.reasonCode == "confirmation_window_expired")
        #expect(outcome.rawDiagnostics?.first?.rawState == Candidate002TerminalState.expired.rawValue)
        #expect(outcome.rawDiagnostics?.first?.reasonCode == "confirmation_window_expired")
        #expect(result.record.decisionState == .conditionsNotMet)
    }

    @Test func gbpJpyPositiveReplayCandidateReachesRecordWithPlan() async throws {
        let minuteStart = floor(now.timeIntervalSince1970 / 60) * 60 - 80 * 60
        var m1 = (0..<80).map { index in
            StrategyEngine.CandlePayload(time: (minuteStart + Double(index * 60)) * 1_000,
                open: 190.05, high: 190.10, low: 190.00, close: 190.05)
        }
        m1[77] = StrategyEngine.CandlePayload(time: m1[77].time, open: 190.04,
            high: 190.06, low: 189.99, close: 190.03)
        m1[78] = StrategyEngine.CandlePayload(time: m1[78].time, open: 190.03,
            high: 190.06, low: 190.02, close: 190.04)
        m1[79] = StrategyEngine.CandlePayload(time: m1[79].time, open: 190.04,
            high: 190.06, low: 190.03, close: 190.05)
        let m5Start = floor(now.timeIntervalSince1970 / 900) * 900 - 24 * 300
        let m5 = (0..<24).map { index in
            StrategyEngine.CandlePayload(time: (m5Start + Double(index * 300)) * 1_000,
                open: 190.05, high: 190.10, low: 190.00, close: 190.05)
        }
        let input = StrategyEngine.MarketInput(asset: "GBP/JPY", source: "oanda",
            candles1m: m1, candles5m: m5, lastPrice: 190.05, bid: 190.04,
            ask: 190.05, spread: 0.01, expirySeconds: 60,
            quoteAsOfMs: now.timeIntervalSince1970 * 1_000,
            evaluatedAtMs: now.timeIntervalSince1970 * 1_000, policy: .baseline)
        let result = try await AdaptiveMarketRehearsal.evaluateSnapshot(
            input, observedAt: now, receivedAt: now.addingTimeInterval(0.1))
        let outcome = try #require(result.record.evaluatorOutcomes?.first {
            $0.evaluatorID == "candidate002"
        })
        #expect(outcome.state == .completed)
        #expect(!outcome.candidateIDs.isEmpty)
        let candidate = try #require(result.record.candidates.first {
            $0.id == outcome.candidateIDs.first
        })
        #expect(candidate.strategyID == "CANDIDATE_002_AUCTION_FAILURE")
        #expect(candidate.plan != nil)
        #expect(candidate.state == .eligible)
        #expect(candidate.plan?.validation().isEmpty == true)
        #expect(result.record.decision.candidates.contains { $0.id == candidate.id })
    }

    @Test func adaptiveProjectionCarriesPlanFieldsAndExplicitMissingValues() throws {
        let input = gbpJpySnapshot()
        let plan = V3TradePlan(id: "plan", instrument: "GBP/JPY", strategyID: "test",
            strategyVersion: "v1", engineVersion: "engine", sourceObservationID: "observation",
            state: .draft, side: .long, entryPrice: 190.05, stopPrice: 189.95,
            targetPrice: 190.25, units: 1, maxSpread: 0.03, riskFraction: 0.01,
            createdAt: now)
        let candidate = AdaptiveOpportunityCandidate(id: "candidate", strategyID: "test",
            strategyVersion: "v1", instrument: input.asset, provider: input.source,
            direction: .long, observedAt: now, evaluationStartedAt: now,
            evaluationCompletedAt: now, state: .eligible, entryReference: 190.05,
            plan: plan, provenance: "fixture", freshness: .fresh,
            spread: input.spread, spreadState: .accepted)
        let outcome = AdaptiveStrategyEvaluationOutcome(evaluatorID: "test-evaluator",
            strategyID: "test", strategyVersion: "v1", timeframe: "M1",
            state: .completed, candidateIDs: [candidate.id])
        let decision = AdaptiveOpportunitySelector.select([candidate], now: now)
        let record = try AdaptiveMarketRehearsalRecord(input: input, observedAt: now,
            receivedAt: now, candidates: [candidate], decision: decision,
            decisionState: .actionableOpportunity, horizonEvidence: [],
            evaluatorOutcomes: [outcome])
        let projection = AdaptiveResearchProjection(record: record, now: now)
        #expect(projection.timeframe == "M1")
        #expect(projection.entryPrice == 190.05)
        #expect(projection.stopPrice == 189.95)
        #expect(projection.targetPrice == 190.25)
        #expect(projection.remainingReasons == [])
        #expect(projection.unavailableFields == [])
    }

    @Test func boundedDiagnosticFailsClosedWithoutCredentials() async {
        let diagnostic = await AdaptiveMarketRehearsal.runBounded(
            asset: "EUR/USD",
            session: OandaSession(token: "", accountId: ""),
            timeout: .milliseconds(50))
        #expect(diagnostic.state == .credentialsMissing)
        #expect(diagnostic.result == nil)
    }
}
