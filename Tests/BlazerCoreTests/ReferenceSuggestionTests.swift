import Foundation
import Testing
@testable import BlazerCore

// The OANDA reference label may suggest HIT/MISS, but it must never settle a trade by
// itself. These pin that only hit/miss resolutions produce a suggestion.

private func outcome(_ resolution: ResearchResolution, reason: String? = nil) -> ResearchOutcome {
    ResearchOutcome(
        eventID: "arm-1",
        horizon: 60,
        targetExpiry: Date(timeIntervalSince1970: 1_792_633_000),
        observedAt: Date(timeIntervalSince1970: 1_792_633_001),
        quoteTimeMs: 1_792_633_000_500,
        exitPrice: 1.1,
        resolution: resolution,
        reason: reason,
        labelSource: "oanda-midpoint-proxy"
    )
}

@Test func referenceLabelsSuggestWithoutSettling() {
    #expect(outcome(.hit).deskSuggestion == .hit)
    #expect(outcome(.miss).deskSuggestion == .miss)
    #expect(outcome(.tie).deskSuggestion == nil)
    #expect(outcome(.unresolved, reason: "No timely expiry observation").deskSuggestion == nil)
}

@Test func referenceSuggestionIsNeverAVenueConfirmation() {
    // The label source is explicit, so a persisted suggestion cannot be mistaken for a
    // broker settlement when the ledger is audited.
    #expect(outcome(.hit).labelSource == "oanda-midpoint-proxy")
}
