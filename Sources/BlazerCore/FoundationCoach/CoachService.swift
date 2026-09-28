import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Explains a sealed scan. Live quotes never enter this type.
public struct FoundationCoachService: TradingCoach, Sendable {
    public var allowsModel: Bool

    public init(allowsModel: Bool = true) {
        self.allowsModel = allowsModel
    }

    public func card(for brief: CoachBrief) async -> CoachExplanation {
        let sealed = PromptBuilder.sealedCard(brief)
        guard allowsModel else { return sealed }
        guard let generated = await generatedCard(for: brief), PromptBuilder.accepts(generated) else {
            return sealed
        }
        return generated
    }

    public func explain(seal: ParitySeal, evidence: String, question: String) async throws -> String {
        let spoken = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !spoken.isEmpty {
            return CoachIntelligence.synthesizeAnswer(seal: seal, evidence: evidence, question: spoken)
        }
        let brief = CoachBrief(pair: "Sealed", score: seal.score, evidence: evidence, hash: seal.fingerprint)
        return await card(for: brief).summary
    }

    public func tag(spoken: String, seal: ParitySeal) async throws -> JournalTags {
        JournalTags(
            emotion: "",
            discipline: "",
            setup: seal.fingerprint,
            lesson: spoken
        )
    }

    private func generatedCard(for brief: CoachBrief) async -> CoachExplanation? {
        #if canImport(FoundationModels)
        guard #available(macOS 26, iOS 26, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: PromptBuilder.instructions)
        do {
            let response = try await session.respond(to: PromptBuilder.prompt(for: brief))
            return PromptBuilder.parse(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
