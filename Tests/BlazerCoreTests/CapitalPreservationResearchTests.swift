import Foundation
import Testing
@testable import BlazerCore

private let riskCutoff = Date(timeIntervalSince1970: 1_900_000_000)

private func riskRow(
    _ id: String,
    outcome: String,
    enteredAt: Date?,
    timestamp: Date? = nil,
    stake: Double? = 10,
    payout: Double? = 0.88,
    source: String = "venue-confirmed"
) -> LedgerRow {
    LedgerRow(
        timestamp: timestamp ?? riskCutoff,
        pair: "EUR/USD",
        hash: id,
        score: 80,
        side: "CALL",
        veto: false,
        drift: 0,
        outcome: outcome,
        outcomeEventID: id,
        payout: payout,
        stake: stake,
        labelSource: source,
        horizonSeconds: 60,
        enteredAt: enteredAt
    )
}

@Test func confirmedSessionRiskUsesActualStakesAndChronologicalLosses() throws {
    let start = riskCutoff.addingTimeInterval(-3_600)
    let rows = [
        riskRow("loss-2", outcome: "MISS", enteredAt: start.addingTimeInterval(120), stake: 20),
        riskRow("win", outcome: "HIT", enteredAt: start, stake: 10, payout: 0.90),
        riskRow("loss-1", outcome: "MISS", enteredAt: start.addingTimeInterval(60), stake: 15)
    ]
    let report = try CapitalPreservationReport.evaluate(
        rows: rows,
        asOf: riskCutoff,
        timeZoneIdentifier: "UTC",
        policy: CapitalPreservationPolicy(maximumSessionLoss: 20, maximumSessionDrawdown: 20,
            cooldownAfterConsecutiveLosses: 2)
    )

    #expect(report.confirmedResolved == 3)
    #expect(report.maximumConsecutiveLosses == 2)
    #expect(report.currentConsecutiveLosses == 2)
    #expect(report.cooldownSuggested == true)
    #expect(report.sessions.count == 1)
    #expect(report.sessions[0].netProfit == -26)
    #expect(report.sessions[0].maximumDrawdown == 35)
    #expect(report.sessions[0].sessionLossLimitReached == true)
    #expect(report.sessions[0].drawdownLimitReached == true)
    #expect(report.provenance == "venue-confirmed")
    #expect(report.authority.contains("does not enforce"))
}

@Test func incompleteCashInputsCannotLookLikeAContainedSession() throws {
    let rows = [
        riskRow("loss", outcome: "MISS", enteredAt: riskCutoff.addingTimeInterval(-60), stake: 10),
        riskRow("win-missing-stake", outcome: "HIT", enteredAt: riskCutoff.addingTimeInterval(-30), stake: nil)
    ]
    let report = try CapitalPreservationReport.evaluate(
        rows: rows,
        asOf: riskCutoff,
        timeZoneIdentifier: "UTC",
        policy: CapitalPreservationPolicy(maximumSessionLoss: 1, maximumSessionDrawdown: 1)
    )

    #expect(!report.cashCoverageComplete)
    #expect(report.excludedMissingCashInputs == 1)
    #expect(report.maximumDrawdown == nil)
    #expect(report.sessions[0].netProfit == nil)
    #expect(report.sessions[0].maximumDrawdown == nil)
    #expect(report.sessions[0].sessionLossLimitReached == nil)
    #expect(report.sessions[0].drawdownLimitReached == nil)
}

@Test func researchReportExcludesProxyDuplicateFutureAndUnclockedRecords() throws {
    let one = riskRow("duplicate", outcome: "HIT", enteredAt: riskCutoff.addingTimeInterval(-60))
    var conflict = one
    conflict.outcome = "MISS"
    let rows = [
        one, conflict,
        riskRow("proxy", outcome: "HIT", enteredAt: riskCutoff.addingTimeInterval(-40), source: "oanda-midpoint-proxy"),
        riskRow("future", outcome: "MISS", enteredAt: riskCutoff.addingTimeInterval(1), timestamp: riskCutoff.addingTimeInterval(1)),
        riskRow("no-entry-time", outcome: "MISS", enteredAt: nil)
    ]
    let report = try CapitalPreservationReport.evaluate(rows: rows, asOf: riskCutoff, timeZoneIdentifier: "UTC")

    #expect(report.confirmedResolved == 1)
    #expect(report.excludedDuplicateIDs == 1)
    #expect(report.excludedUnconfirmed == 1)
    #expect(report.excludedMissingEntryTime == 1)
    #expect(report.cashCoverageComplete == false)
    #expect(report.maximumDrawdown == nil)
}

@Test func allTimeDrawdownCarriesAcrossSessionBoundaries() throws {
    let firstEntry = riskCutoff.addingTimeInterval(-172_800)
    let rows = [
        riskRow("day-one-loss", outcome: "MISS", enteredAt: firstEntry, stake: 50),
        riskRow("day-two-loss", outcome: "MISS", enteredAt: firstEntry.addingTimeInterval(86_400), stake: 50)
    ]
    let report = try CapitalPreservationReport.evaluate(rows: rows, asOf: riskCutoff, timeZoneIdentifier: "UTC")
    #expect(report.maximumDrawdown == 100)
    #expect(report.sessions.count == 2)
    #expect(report.sessions.allSatisfy { $0.maximumDrawdown == 50 })
    #expect(report.maximumConsecutiveLosses == 2)
}

@Test func missingIdentityAndUnresolvedOutcomeWithholdRiskConclusions() throws {
    let rows = [
        riskRow("", outcome: "MISS", enteredAt: riskCutoff.addingTimeInterval(-60)),
        riskRow("unresolved", outcome: "UNRESOLVED", enteredAt: riskCutoff.addingTimeInterval(-30))
    ]
    let report = try CapitalPreservationReport.evaluate(rows: rows, asOf: riskCutoff, timeZoneIdentifier: "UTC")
    #expect(report.confirmedResolved == 0)
    #expect(report.excludedMissingIdentity == 1)
    #expect(report.excludedUnresolved == 1)
    #expect(report.cashCoverageComplete == false)
    #expect(report.maximumConsecutiveLosses == nil)
    #expect(report.currentConsecutiveLosses == nil)
    #expect(report.cooldownSuggested == nil)
}

@Test func fractionalPositionSizingSimulationUsesHistoricalPayoutAndFailsClosedOnMissingPayout() throws {
    let start = riskCutoff.addingTimeInterval(-120)
    let rows = [
        riskRow("w", outcome: "HIT", enteredAt: start, stake: 10, payout: 0.88),
        riskRow("l1", outcome: "MISS", enteredAt: start.addingTimeInterval(60), stake: 10),
        riskRow("l2", outcome: "MISS", enteredAt: start.addingTimeInterval(120), stake: 10)
    ]
    let result = try PositionSizingResearch.simulate(
        rows: rows, initialBankroll: 1_000, riskFraction: 0.01, asOf: riskCutoff
    )
    #expect(result.trades == 3)
    #expect(abs(result.endingBankroll - 988.72488) < 1e-8)
    #expect(abs(result.maximumDrawdown - 20.07512) < 1e-8)
    #expect(result.maximumConsecutiveLosses == 2)
    #expect(result.assumption.contains("Research-only"))

    let incomplete = [riskRow("missing", outcome: "HIT", enteredAt: start, payout: nil)]
    #expect(throws: CapitalPreservationError.incompleteConfirmedReturns) {
        try PositionSizingResearch.simulate(
            rows: incomplete, initialBankroll: 1_000, riskFraction: 0.01, asOf: riskCutoff
        )
    }
}

@Test func unresolvedConfirmedTradeWithholdsSequenceAndCashConclusions() throws {
    let start = riskCutoff.addingTimeInterval(-180)
    let rows = [
        riskRow("loss-1", outcome: "MISS", enteredAt: start),
        riskRow("unknown", outcome: "UNRESOLVED", enteredAt: start.addingTimeInterval(60)),
        riskRow("loss-2", outcome: "MISS", enteredAt: start.addingTimeInterval(120))
    ]
    let report = try CapitalPreservationReport.evaluate(
        rows: rows, asOf: riskCutoff, timeZoneIdentifier: "UTC")
    #expect(report.excludedUnresolved == 1)
    #expect(!report.cashCoverageComplete)
    #expect(report.maximumConsecutiveLosses == nil)
    #expect(report.currentConsecutiveLosses == nil)
    #expect(report.maximumDrawdown == nil)
    #expect(throws: CapitalPreservationError.incompleteConfirmedReturns) {
        try PositionSizingResearch.simulate(
            rows: rows, initialBankroll: 1_000, riskFraction: 0.01, asOf: riskCutoff)
    }
}

@Test func sessionLossThresholdLatchesAfterIntradayRecovery() throws {
    let start = riskCutoff.addingTimeInterval(-180)
    let rows = [
        riskRow("loss", outcome: "MISS", enteredAt: start, stake: 25),
        riskRow("recovery", outcome: "HIT", enteredAt: start.addingTimeInterval(60),
                stake: 50, payout: 0.88)
    ]
    let report = try CapitalPreservationReport.evaluate(
        rows: rows, asOf: riskCutoff, timeZoneIdentifier: "UTC",
        policy: CapitalPreservationPolicy(maximumSessionLoss: 20))
    #expect(report.sessions.first?.netProfit == 19)
    #expect(report.sessions.first?.sessionLossLimitReached == true)
}

@Test func positionSizingRejectsOverlappingHistoricalContracts() {
    let start = riskCutoff.addingTimeInterval(-180)
    let rows = [
        riskRow("first", outcome: "HIT", enteredAt: start),
        riskRow("overlap", outcome: "MISS", enteredAt: start.addingTimeInterval(30))
    ]
    #expect(throws: CapitalPreservationError.incompleteConfirmedReturns) {
        try PositionSizingResearch.simulate(
            rows: rows, initialBankroll: 1_000, riskFraction: 0.01, asOf: riskCutoff)
    }
}

@Test func invalidRiskPolicyCannotTriggerNumericallyUnboundedWarnings() {
    #expect(throws: CapitalPreservationError.invalidPolicy) {
        try CapitalPreservationReport.evaluate(
            rows: [], asOf: riskCutoff, timeZoneIdentifier: "UTC",
            policy: CapitalPreservationPolicy(maximumSessionLoss: .infinity)
        )
    }
    #expect(throws: CapitalPreservationError.invalidTimeZone) {
        try CapitalPreservationReport.evaluate(rows: [], asOf: riskCutoff, timeZoneIdentifier: "not/a-zone")
    }
    #expect(throws: CapitalPreservationError.invalidAsOf) {
        try CapitalPreservationReport.evaluate(
            rows: [], asOf: Date(timeIntervalSince1970: .nan), timeZoneIdentifier: "UTC"
        )
    }
}

@Test func invalidLedgerTimestampMakesRiskCoverageIncomplete() throws {
    let row = riskRow("nan-time", outcome: "MISS", enteredAt: riskCutoff.addingTimeInterval(-60))
    var invalid = row
    invalid.timestamp = Date(timeIntervalSince1970: .nan)
    let report = try CapitalPreservationReport.evaluate(
        rows: [invalid], asOf: riskCutoff, timeZoneIdentifier: "UTC"
    )
    #expect(report.excludedInvalidTimestamps == 1)
    #expect(report.cashCoverageComplete == false)
    #expect(report.maximumConsecutiveLosses == nil)
    #expect(report.maximumDrawdown == nil)
}

@Test func assistantReceivesOnlyBoundedConfirmedRiskFacts() throws {
    let entries = [
        riskRow("confirmed-loss", outcome: "MISS", enteredAt: riskCutoff.addingTimeInterval(-60), stake: 10),
        riskRow("proxy-win", outcome: "HIT", enteredAt: riskCutoff.addingTimeInterval(-30), source: "oanda-midpoint-proxy")
    ]
    let context = AssistantContextBuilder.make(
        journal: [], ledgerRows: entries, now: riskCutoff, sessionTimeZoneIdentifier: "UTC"
    )
    #expect(context.capitalPreservation?.confirmedResolved == 1)
    #expect(context.capitalPreservation?.provenance == "venue-confirmed")
    #expect(context.capitalPreservation?.maximumConsecutiveLosses == 1)
    #expect(context.capitalPreservation?.cashCoverageComplete == true)
    #expect(context.bounded(maxScans: 0, maxEntries: 0, maxGaps: 0, maxNotes: 0).capitalPreservation
        == context.capitalPreservation)
    #expect(SessionDebrief.fallback(context: context).summary.contains("drawdown was 10.00"))

    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as! [String: Any]
    legacy.removeValue(forKey: "capitalPreservation")
    let decoded = try JSONDecoder().decode(AssistantContext.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(decoded.capitalPreservation == nil)
}
