import Foundation
import Testing
@testable import BlazerCore

// Production records store `TAP HIGH` / `TAP LOW`; guided generation has described the same
// decision as `CALL` / `PUT`. These tests pin the normalisation so the two vocabularies cannot
// drift apart again — the drift made every actionable scan fail validation on device.

private func sealedScan(call: String, score: Int = 96) -> ScanRecordContext {
    ScanRecordContext(
        id: "sealed-1",
        fullFingerprint: String(repeating: "A", count: 40),
        pair: "GBP/USD",
        engineCall: call,
        score: score,
        evidence: "Trend is down (-18) · Broke the prior low (-16)",
        veto: nil,
        evaluationTime: Date(timeIntervalSince1970: 1_792_632_910),
        quoteMid: 1.27,
        spread: 0.0002,
        m1Count: 120,
        m5Count: 120,
        engineSHA: EngineIdentity.pinnedSHA1,
        expirySeconds: 60,
        isActionable: true,
        blockingReason: nil,
        recordedVerb: call
    )
}

private func explanation(decision: String, score: Int = 96) -> ScanExplanation {
    ScanExplanation(
        summary: "Restates the sealed decision.",
        decision: decision,
        score: score,
        evidenceUsed: ["Trend is down (-18)"],
        blockingGate: nil,
        missingEvidence: [],
        coachNote: "No prediction is made.",
        recordID: "sealed-1"
    )
}

@Test func canonicalDecisionMapsBothVocabularies() {
    #expect(AssistantValidation.canonicalDecision("CALL") == "TAP HIGH")
    #expect(AssistantValidation.canonicalDecision("PUT") == "TAP LOW")
    #expect(AssistantValidation.canonicalDecision("tap low") == "TAP LOW")
    #expect(AssistantValidation.canonicalDecision("TAP HIGH") == "TAP HIGH")
    #expect(AssistantValidation.canonicalDecision("WAIT") == "WAIT")
    #expect(AssistantValidation.canonicalDecision("MAYBE") == "MAYBE")
}

@Test func validationAcceptsCallVocabularyForAHighSeal() {
    let issues = AssistantValidation.validate(
        explanation(decision: "CALL"),
        against: sealedScan(call: "TAP HIGH")
    )
    #expect(!issues.contains { $0.contains("decision") })
}

@Test func validationAcceptsPutVocabularyForALowSeal() {
    let issues = AssistantValidation.validate(
        explanation(decision: "PUT"),
        against: sealedScan(call: "TAP LOW")
    )
    #expect(!issues.contains { $0.contains("decision") })
}

@Test func validationRejectsTheOppositeDirection() {
    let issues = AssistantValidation.validate(
        explanation(decision: "CALL"),
        against: sealedScan(call: "TAP LOW")
    )
    #expect(issues.contains { $0.contains("does not match sealed") })
}

@Test func validationRejectsUnknownVocabulary() {
    let issues = AssistantValidation.validate(
        explanation(decision: "MAYBE"),
        against: sealedScan(call: "TAP LOW")
    )
    #expect(issues.contains { $0.contains("does not match sealed") })
}
