import Foundation
import Testing
@testable import BlazerCore

@Test func policyFunnelPreservesInactivePolicyReasonsAndFeatureCoverage() throws {
    let input = GoldenFixture.market()
    let signal = EngineSignal(asset: input.asset, cabinetSide: "WAIT", call: "NONE",
        why: "No qualifying setup", price: input.lastPrice, asOfMs: input.evaluatedAtMs,
        source: input.source, policy: "reversal",
        features: ScanFeatures(atr1m: 1, atr5m: 1, efficiency: 0.5, slopeATR: 0,
            spreadATR: 0.1, rangeATR: 1, bodyATR: 0, upperWickShare: 0.2,
            lowerWickShare: 0.2, twoSidedSweep: false, sweep: nil,
            structureBreak: nil, regime: "range"),
        vetoes: ["No qualifying setup"])
    let event = try ResearchEvent(input: input, signal: signal,
        sourceKind: "oanda-proxy", capturedAt: Date(timeIntervalSince1970: 1_900_000_000),
        entryQuote: LiveQuote(asset: input.asset, bid: input.bid, ask: input.ask,
            mid: input.lastPrice, asOfMs: input.quoteAsOfMs ?? 0, source: "oanda"))
    let report = try #require(PolicyEligibilityDiagnostics.evaluate(events: [event]).first)
    #expect(report.policy == "reversal")
    #expect(report.totalObservations == 1)
    #expect(report.completeFeatureObservations == 1)
    #expect(report.directionalSignals == 0)
    #expect(report.acceptedEntries == 0)
    #expect(report.activity == .inactiveUnderObservedConditions)
    #expect(report.regimes["range"] == 1)
    #expect(report.engineReasons["No qualifying setup"] == 1)
}
