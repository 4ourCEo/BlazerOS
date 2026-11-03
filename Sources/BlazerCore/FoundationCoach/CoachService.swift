import Foundation

/// Explains a sealed scan. Live quotes never enter this type.
///
/// When a `DeskAssistant` and bounded `AssistantContext` are supplied, questions are answered
/// by Apple’s on-device model. Otherwise the deterministic, clearly-labelled basic explanation
/// is returned.
public struct FoundationCoachService: TradingCoach, Sendable {
    public var allowsModel: Bool
    public var assistant: DeskAssistant?
    public var context: AssistantContext?

    public init(
        allowsModel: Bool = true,
        assistant: DeskAssistant? = nil,
        context: AssistantContext? = nil
    ) {
        self.allowsModel = allowsModel
        self.assistant = assistant
        self.context = context
    }

    public func card(for brief: CoachBrief) async -> CoachExplanation {
        // The card path is deterministic by design. Grounded model explanations use
        // `DeskAssistant.explainScan` and render authoritative numbers from code.
        PromptBuilder.sealedCard(brief)
    }

    public func explain(seal: ParitySeal, evidence: String, question: String) async throws -> String {
        let spoken = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if allowsModel, let assistant, let context {
            let scan = ScanRecordContext(
                id: seal.fingerprint,
                fullFingerprint: seal.fingerprint,
                pair: "Sealed",
                engineCall: seal.side,
                score: seal.score,
                evidence: evidence,
                veto: nil,
                evaluationTime: Date(),
                quoteMid: seal.strike,
                spread: nil,
                m1Count: seal.candleCount,
                m5Count: 0,
                engineSHA: seal.engineSHA1,
                expirySeconds: 60,
                isActionable: seal.side == "HIGH" || seal.side == "LOW",
                blockingReason: nil,
                recordedVerb: "sealed"
            )
            let result = await assistant.explainScan(scan, context: context)
            if result.isModelGenerated {
                return "\(result.value.summary) \(result.value.coachNote)"
            }
            return "Basic explanation. \(result.value.summary) \(result.value.coachNote)"
        }
        if !spoken.isEmpty {
            return "Basic explanation. " + CoachIntelligence.synthesizeAnswer(
                seal: seal, evidence: evidence, question: spoken
            )
        }
        let brief = CoachBrief(pair: "Sealed", score: seal.score, evidence: evidence, hash: seal.fingerprint)
        return "Basic explanation. " + (await card(for: brief).summary)
    }

    public func tag(spoken: String, seal: ParitySeal) async throws -> JournalTags {
        JournalTags(
            emotion: "",
            discipline: "",
            setup: seal.fingerprint,
            lesson: spoken
        )
    }
}
