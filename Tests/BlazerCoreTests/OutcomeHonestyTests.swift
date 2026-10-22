import Foundation
import Testing
@testable import BlazerCore

// A guessed result must never count as a confirmed one. UNRESOLVED rows are recorded so the
// event is not lost, but they are excluded from confirmed statistics and from promotion math.

private func row(_ outcome: String, source: String) -> LedgerRow {
    LedgerRow(
        timestamp: Date(timeIntervalSince1970: 1_792_633_000),
        pair: "EUR/USD",
        hash: "hash",
        score: 80,
        side: "TAP LOW",
        veto: false,
        drift: 0,
        outcome: outcome,
        outcomeEventID: "event-1",
        labelSource: source
    )
}

@Test func unresolvedRowsAreExcludedFromConfirmedStats() {
    let rows = [
        row("HIT", source: "venue-confirmed"),
        row("MISS", source: "venue-confirmed"),
        row("UNRESOLVED", source: "operator-unsure"),
    ]
    #expect(OutcomeStats.tally(rows) == OutcomeStats(hits: 1, misses: 1))
    #expect(OutcomeStats.confirmedTally(rows) == OutcomeStats(hits: 1, misses: 1))
}

@Test func unresolvedOutcomeRoundTrips() {
    #expect(DeskOutcome.unresolved.rawValue == "UNRESOLVED")
    #expect(DeskOutcome(rawValue: "UNRESOLVED") == .unresolved)
}
