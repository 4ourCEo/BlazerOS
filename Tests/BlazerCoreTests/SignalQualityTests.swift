import Foundation
import Testing
@testable import BlazerCore

private func qualitySignal(asOf: Date, side: String = "HIGH", vetoes: [String]? = nil) -> EngineSignal {
    EngineSignal(asset: "EUR/USD", cabinetSide: side, call: side == "HIGH" ? "CALL" : "PUT",
        why: "fixture", price: 1.1, asOfMs: asOf.timeIntervalSince1970 * 1000,
        vetoes: vetoes)
}

private func completeEvidence() -> SignalQualityEvidence {
    SignalQualityEvidence(feedHealthy: true, completedM1Bars: 120, completedM5Bars: 24,
        marketOpen: true, spreadWithinConstraint: true, slippageWithinConstraint: true,
        higherTimeframeAligned: true, trendOrRange: "trend", directionalInstability: 0.2)
}

@Test func qualityClassificationDoesNotChangeEngineDirection() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let signal = qualitySignal(asOf: now)
    let assessment = SignalQualityEvaluator.assess(signal: signal, quote: nil,
        evidence: completeEvidence(), at: now)
    #expect(assessment.classification == .conditional)
    #expect(signal.cabinetSide == "HIGH")
    #expect(!assessment.unavailableInputs.isEmpty)
}

@Test func completeVerifiedContextIsSupported() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let quote = LiveQuote(asset: "EUR/USD", bid: 1.0999, ask: 1.1001,
        mid: 1.1, asOfMs: now.timeIntervalSince1970 * 1000, source: "fixture")
    let assessment = SignalQualityEvaluator.assess(signal: qualitySignal(asOf: now),
        quote: quote, evidence: completeEvidence(), at: now)
    #expect(assessment.classification == .supported)
    #expect(assessment.policyVersion == SignalQualityAssessment.policyVersion)
}

@Test func failedObservedConstraintIsRejectedNotConditional() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var evidence = completeEvidence()
    evidence.spreadWithinConstraint = false
    let assessment = SignalQualityEvaluator.assess(signal: qualitySignal(asOf: now),
        quote: nil, evidence: evidence, at: now)
    #expect(assessment.classification == .rejected)
    #expect(assessment.reasons.contains { $0.contains("spread constraint") })
}

@Test func missingDirectionIsUnavailable() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let assessment = SignalQualityEvaluator.assess(signal: qualitySignal(asOf: now, side: "WAIT"),
        quote: nil, evidence: completeEvidence(), at: now)
    #expect(assessment.classification == .unavailable)
    #expect(assessment.unavailableInputs == ["direction"])
}

@Test func staleSignalIsRejectedWithoutReplacingTheSignal() {
    let now = Date(timeIntervalSince1970: 1_800_000_010)
    let signalTime = now.addingTimeInterval(-EntryQuality.maxAgeSeconds - 1)
    let signal = qualitySignal(asOf: signalTime, side: "LOW")
    let assessment = SignalQualityEvaluator.assess(signal: signal, quote: nil,
        evidence: completeEvidence(), at: now)
    #expect(assessment.classification == .rejected)
    #expect(signal.cabinetSide == "LOW")
}
