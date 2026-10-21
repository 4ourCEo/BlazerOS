import Foundation

/// The only fields the coach may see. No bid, ask, or candle series.
public struct CoachBrief: Sendable, Equatable {
    public var pair: String
    public var score: Int
    public var evidence: String
    public var hash: String

    public init(pair: String, score: Int, evidence: String, hash: String) {
        self.pair = pair
        self.score = score
        self.evidence = evidence
        self.hash = hash
    }
}

/// Explanation of a seal. It has no side and no score of its own.
public struct CoachExplanation: Sendable, Equatable {
    public var summary: String
    public var confidence: String
    public var bullets: [String]

    public init(summary: String, confidence: String, bullets: [String]) {
        self.summary = summary
        self.confidence = confidence
        self.bullets = bullets
    }
}

/// Builds the coach prompt and the sealed fallback. Both stay on the four brief fields.
public enum PromptBuilder {
    public static let allowedConfidence: Set<String> = ["Sealed", "Limited"]

    public static let instructions = """
    Explain a sealed scan in plain language. Restate the engine score. Do not choose a direction. \
    Do not calculate a new score. Do not mention a live price. \
    Reply in exactly this shape:
    Summary: one sentence
    Confidence: Sealed
    Bullets: first | second | third
    Confidence is Sealed or Limited.
    """

    public static func prompt(for brief: CoachBrief) -> String {
        """
        Pair: \(brief.pair)
        Engine score: \(brief.score)
        Evidence: \(brief.evidence)
        Hash: \(brief.hash)
        """
    }

    /// Same brief always returns the same card. Used when the on-device model is absent or refused.
    public static func sealedCard(_ brief: CoachBrief) -> CoachExplanation {
        let summary: String
        if brief.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "Sealed scan \(brief.hash) on \(brief.pair)."
        } else {
            summary = brief.evidence
        }
        let confidence = brief.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Limited" : "Sealed"
        return CoachExplanation(
            summary: summary,
            confidence: confidence,
            bullets: [
                "Pair \(brief.pair)",
                "Engine score \(brief.score)",
                "Hash \(brief.hash)",
            ]
        )
    }

    /// Accepts a model reply only when it stays an explanation.
    public static func parse(_ text: String) -> CoachExplanation? {
        var summary = ""
        var confidence = ""
        var bullets: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if let value = line.dropPrefix("Summary:") {
                summary = value.trimmingCharacters(in: .whitespaces)
            } else if let value = line.dropPrefix("Confidence:") {
                confidence = value.trimmingCharacters(in: .whitespaces)
            } else if let value = line.dropPrefix("Bullets:") {
                bullets = value.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        let card = CoachExplanation(summary: summary, confidence: confidence, bullets: bullets)
        guard accepts(card) else { return nil }
        return card
    }

    public static func accepts(_ card: CoachExplanation) -> Bool {
        accepts(card, brief: nil)
    }

    /// Explanation-only validation. With a brief, any restated engine score must match it,
    /// and performance/probability claims are refused outright.
    public static func accepts(_ card: CoachExplanation, brief: CoachBrief?) -> Bool {
        guard allowedConfidence.contains(card.confidence) else { return false }
        guard !card.summary.isEmpty, !card.bullets.isEmpty else { return false }
        let joined = ([card.summary, card.confidence] + card.bullets).joined(separator: "\n")
        if joined.contains("TAP HIGH") || joined.contains("TAP LOW") { return false }
        if joined.localizedCaseInsensitiveContains("bid") || joined.localizedCaseInsensitiveContains("ask") {
            return false
        }
        // The coach may explain recorded facts; it may not invent performance evidence.
        for forbidden in ["win rate", "probability", "expectancy", "guaranteed", "positive edge", "%"] {
            if joined.localizedCaseInsensitiveContains(forbidden) { return false }
        }
        if let brief, let mentioned = scoreNumbers(in: joined), mentioned.contains(where: { $0 != brief.score }) {
            return false
        }
        return true
    }

    /// Extracts integers that follow the word "score" within a short distance.
    public static func scoreNumbers(in text: String) -> [Int]? {
        let pattern = "(?i)score[^0-9]{0,12}([0-9]{1,3})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }
        return matches.compactMap { match in
            guard let numberRange = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[numberRange])
        }
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
