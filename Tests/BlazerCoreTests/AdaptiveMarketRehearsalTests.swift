import Foundation
import Testing
@testable import BlazerCore

struct AdaptiveMarketRehearsalTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

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
                state: .awaitingEvidence, reason: "fixture")])
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
        #expect(projection.isResearchOnly)
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
            store: ResearchStore(root: root))
        #expect(result.record.inputDigest == (try ResearchEvent.digest(of: input)))
        #expect(result.record.provider == input.source)
        #expect(result.record.validation().isEmpty)
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

    @Test func boundedDiagnosticFailsClosedWithoutCredentials() async {
        let diagnostic = await AdaptiveMarketRehearsal.runBounded(
            asset: "EUR/USD",
            session: OandaSession(token: "", accountId: ""),
            timeout: .milliseconds(50))
        #expect(diagnostic.state == .credentialsMissing)
        #expect(diagnostic.result == nil)
    }
}
