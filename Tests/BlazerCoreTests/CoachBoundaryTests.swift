import Foundation
import Testing
import BlazerCore

@Test func coachRejectsPerformanceAndProbabilityClaims() {
    let brief = CoachBrief(pair: "EUR/USD", score: 76, evidence: "Sweep", hash: "ABCD1234")
    let bad = CoachExplanation(
        summary: "This setup has a 60% win rate.",
        confidence: "Sealed",
        bullets: ["Engine score 76"]
    )
    #expect(!PromptBuilder.accepts(bad, brief: brief))

    let expectancy = CoachExplanation(
        summary: "Positive expectancy confirmed.",
        confidence: "Sealed",
        bullets: ["Engine score 76"]
    )
    #expect(!PromptBuilder.accepts(expectancy, brief: brief))
}

@Test func coachRejectsARestatedScoreThatDoesNotMatchTheSeal() {
    let brief = CoachBrief(pair: "EUR/USD", score: 76, evidence: "Sweep", hash: "ABCD1234")
    let wrong = CoachExplanation(
        summary: "The engine returned a score of 92.",
        confidence: "Sealed",
        bullets: ["Engine score 92"]
    )
    #expect(!PromptBuilder.accepts(wrong, brief: brief))

    let right = CoachExplanation(
        summary: "The engine returned a score of 76.",
        confidence: "Sealed",
        bullets: ["Engine score 76"]
    )
    #expect(PromptBuilder.accepts(right, brief: brief))
}

@Test func coachDoesNotInventEvidenceWhenNoneWasRecorded() {
    let seal = ParitySeal(
        engineSHA1: "x",
        fingerprint: "ABCD1234",
        score: 76,
        side: "HIGH",
        strike: 1.1,
        candleCount: 60
    )
    let answer = CoachIntelligence.synthesizeAnswer(seal: seal, evidence: "", question: "why this setup?")
    #expect(answer.contains("No supporting evidence"))
    #expect(!answer.localizedCaseInsensitiveContains("trend alignment"))
    #expect(!answer.localizedCaseInsensitiveContains("wick rejection"))
}
