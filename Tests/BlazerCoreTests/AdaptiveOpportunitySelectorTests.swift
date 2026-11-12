import Foundation
import Testing
@testable import BlazerCore

struct AdaptiveOpportunitySelectorTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func candidate(_ id: String, direction: AdaptiveDirection = .long,
                           score: Double = 80, observedOffset: TimeInterval = -1,
                           state: AdaptiveCandidateState = .eligible) -> AdaptiveOpportunityCandidate {
        AdaptiveOpportunityCandidate(id: id, strategyID: id, strategyVersion: "v1",
            instrument: "GBP/JPY", provider: "OANDA", direction: direction,
            observedAt: now.addingTimeInterval(observedOffset), evaluationStartedAt: now,
            evaluationCompletedAt: now.addingTimeInterval(0.1), state: state,
            entryReference: 190, provenance: "test", freshness: .fresh,
            spread: 0.01, spreadState: .accepted, rankingScore: score)
    }

    @Test func selectsHighestDeterministicResearchCandidate() {
        let result = AdaptiveOpportunitySelector.select([
            candidate("continuation", score: 70), candidate("orb", score: 90)], now: now)
        #expect(result.selectedCandidateID == "orb")
        #expect(!result.isNoTrade)
    }

    @Test func returnsNoTradeForStaleCandidate() {
        let result = AdaptiveOpportunitySelector.select([candidate("old", observedOffset: -20)], now: now)
        #expect(result.isNoTrade)
        #expect(result.noTradeReason == "no_eligible_candidate")
        #expect(result.candidates[0].rejectionReasons.contains("observation_expired"))
    }

    @Test func conflictingDirectionsProduceNoTradeAndPreserveDiagnostics() {
        let result = AdaptiveOpportunitySelector.select([
            candidate("long", direction: .long), candidate("short", direction: .short)], now: now)
        #expect(result.isNoTrade)
        #expect(result.candidates.allSatisfy { $0.rejectionReasons.contains("conflicting_direction") })
    }

    @Test func timingSeparatesCalculationFromPublicationLatency() {
        let result = AdaptiveOpportunitySelector.select([candidate("one")], now: now,
            decisionAt: now.addingTimeInterval(0.2))
        #expect(abs(result.timing.calculationLatency - 0.1) < 0.000001)
        #expect(result.timing.publicationLatency == nil)
    }

    @Test func orbAdapterPreservesResearchOnlyUnavailableDiagnostics() {
        let input = GoldenFixture.market()
        let started = now
        let decision = ORBDecision(stage: .rangeSealed, setupState: .watching,
                                   sessionStart: now, reason: "range_sealed")
        let adapted = AdaptiveOpportunityAdapters.orb(input, startedAt: started,
                                                       completedAt: now.addingTimeInterval(0.1),
                                                       decision: decision)
        #expect(adapted.strategyID == "ORB_BREAK_RETEST_V1")
        #expect(adapted.state == .rejected)
        #expect(adapted.rejectionReasons.contains("range_sealed"))
        #expect(adapted.provenance == "existing-orb-research")
    }

    @Test func orbAdapterRejectsNonExecutableSpread() {
        var input = GoldenFixture.market()
        input.spread = 0
        let decision = ORBDecision(stage: .rangeSealed, setupState: .watching,
                                   sessionStart: now, reason: "fixture")
        let adapted = AdaptiveOpportunityAdapters.orb(input, startedAt: now,
                                                       completedAt: now,
                                                       decision: decision)
        #expect(adapted.spreadState == .rejected)
    }

    @Test func unavailableCandidateRemainsUnavailableThroughSelection() {
        let unavailable = candidate("provider", state: .unavailable)
        let result = AdaptiveOpportunitySelector.select([unavailable], now: now)
        #expect(result.isNoTrade)
        #expect(result.noTradeReason == "candidate_unavailable")
        #expect(result.candidates.first?.state == .unavailable)
    }

    @Test func adaptiveNotificationDeduplicatesAndRejectsStalePublication() {
        let forming = candidate("forming")
        let notification = AdaptiveNotificationPlanner.plan(
            state: .opportunityForming, selectedCandidate: forming,
            instrument: "GBP/JPY", sourceTime: now, now: now)
        #expect(notification?.kind == .setupForming)
        #expect(notification?.deepLink.contains("opportunity") == true)
        #expect(AdaptiveNotificationPlanner.plan(
            state: .opportunityForming, selectedCandidate: forming,
            instrument: "GBP/JPY", sourceTime: now, now: now,
            previouslyDelivered: [notification!.id]) == nil)
        #expect(AdaptiveNotificationPlanner.plan(
            state: .actionableOpportunity, selectedCandidate: forming,
            instrument: "GBP/JPY", sourceTime: now.addingTimeInterval(-60),
            now: now) == nil)
    }
}
