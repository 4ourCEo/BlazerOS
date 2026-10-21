import Foundation

public enum AssistantValidation {
    public static let forbiddenClaims = [
        "probability", "win rate", "expectancy", "guaranteed",
        "broker confirmed", "broker settlement", "settled by", "price target",
        "risk-free", "sure win"
    ]

    public static func containsForbiddenClaim(
        _ text: String,
        allowWinRate: Bool = false,
        allowExpectancy: Bool = false
    ) -> String? {
        let lower = text.lowercased()
        if lower.contains("$") { return "currency amount" }
        if lower.contains("broker confirmed") || lower.contains("broker settlement") {
            return "claimed broker confirmation"
        }
        return forbiddenClaims.first {
            if allowWinRate && $0 == "win rate" { return false }
            if allowExpectancy && $0 == "expectancy" { return false }
            return lower.contains($0)
        }
    }

    public static func containsDigit(_ text: String) -> Bool {
        text.contains { $0.isNumber }
    }

    /// Digits are allowed only for the sealed score, the configured expiry, and the
    /// eight-second window. Everything else is treated as an invented number.
    public static func containsUnsupportedNumber(_ text: String, allowed: [Int] = []) -> Bool {
        var value = text.lowercased()
        let timingPhrases = [
            "8-second", "8 second", "eight-second", "eight second",
            "60-second", "60 second", "3-minute", "3 minute", "5-minute", "5 minute",
        ]
        for phrase in timingPhrases {
            value = value.replacingOccurrences(of: phrase, with: "")
        }
        for number in allowed {
            value = value.replacingOccurrences(of: "score \(number)", with: "")
            value = value.replacingOccurrences(of: "\(number)", with: "")
        }
        return containsDigit(value)
    }

    /// Allows a percentage only when it matches a deterministic performance value.
    public static func containsUnsupportedPercentage(_ text: String, performance: PerformanceSummary) -> Bool {
        guard text.contains("%") else { return false }
        let allowed = [performance.winRate, performance.breakEven, performance.expectancy]
            .compactMap { $0 }
            .map { $0 * 100 }
        let numbers = percentages(in: text)
        guard !numbers.isEmpty else { return true }
        return numbers.contains { value in
            allowed.contains { abs($0 - value) <= 0.15 }
        } == false
    }

    private static func percentages(in text: String) -> [Double] {
        var values: [Double] = []
        var digits = ""
        for character in text {
            if character.isNumber || character == "." {
                digits.append(character)
            } else if character == "%", !digits.isEmpty {
                if let value = Double(digits) { values.append(value) }
                digits = ""
            } else {
                digits = ""
            }
        }
        return values
    }

    public static func validate(
        _ explanation: ScanExplanation,
        against scan: ScanRecordContext
    ) -> [String] {
        var issues: [String] = []
        if explanation.decision.uppercased() != scan.engineCall.uppercased() {
            issues.append("decision \(explanation.decision) does not match sealed \(scan.engineCall)")
        }
        if explanation.score != scan.score {
            issues.append("score \(explanation.score) does not match sealed \(scan.score)")
        }
        let allowedEvidence = Set(scan.evidenceLines)
        let fullEvidence = scan.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let joinedEvidence = scan.evidenceLines.joined(separator: " · ")
        for cited in explanation.evidenceUsed {
            let value = cited.trimmingCharacters(in: .whitespacesAndNewlines)
            if allowedEvidence.contains(value) || value == fullEvidence || value == joinedEvidence {
                continue
            }
            issues.append("evidence is not in the frozen record: \(cited)")
        }
        if !scan.evidenceLines.isEmpty && explanation.evidenceUsed.isEmpty {
            issues.append("no recorded evidence was cited")
        }
        if scan.isActionable {
            if let gate = explanation.blockingGate, !gate.isEmpty {
                issues.append("actionable scan was given a blocking gate")
            }
        } else if (explanation.blockingGate ?? "").isEmpty {
            issues.append("blocked scan has no blocking gate")
        }
        if containsUnsupportedNumber(
            explanation.summary,
            allowed: [scan.score, scan.expirySeconds, Int(Timing.liveMs / 1000)]
        ) { issues.append("summary contains an invented number") }
        if containsUnsupportedNumber(
            explanation.coachNote,
            allowed: [scan.score, scan.expirySeconds, Int(Timing.liveMs / 1000)]
        ) { issues.append("coach note contains an invented number") }
        for text in [explanation.summary, explanation.coachNote] {
            if let claim = containsForbiddenClaim(text) {
                issues.append("unsupported claim: \(claim)")
            }
        }
        for missing in explanation.missingEvidence where containsUnsupportedNumber(missing) {
            issues.append("missing evidence contains an invented number")
        }
        return issues
    }

    public static func validate(_ answer: CoachAnswer, context: AssistantContext) -> [String] {
        var issues: [String] = []
        let known = context.allRecordIDs
        for citation in answer.citations where !known.contains(citation) {
            issues.append("unknown citation \(citation)")
        }
        if !context.scans.isEmpty && answer.citations.isEmpty {
            issues.append("no record citation")
        }
        if let claim = containsForbiddenClaim(
            answer.answer,
            allowWinRate: context.performance.sampleSize > 0,
            allowExpectancy: context.performance.expectancy != nil
        ) {
            issues.append("unsupported claim: \(claim)")
        }
        if containsUnsupportedPercentage(answer.answer, performance: context.performance) {
            issues.append("percentage does not match deterministic performance")
        }
        if answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("empty answer")
        }
        return issues
    }

    public static func validate(_ debrief: SessionDebrief, context: AssistantContext) -> [String] {
        var issues: [String] = []
        let p = context.performance
        if debrief.sampleSize != p.sampleSize { issues.append("sample size mismatch") }
        if debrief.wins != p.wins { issues.append("wins mismatch") }
        if debrief.losses != p.losses { issues.append("losses mismatch") }
        if debrief.ties != p.ties { issues.append("ties mismatch") }
        if debrief.unresolved != p.unresolved { issues.append("unresolved mismatch") }
        if debrief.citations.contains(where: { !context.allRecordIDs.contains($0) }) {
            issues.append("unknown citation")
        }
        func allowedGapReferences(_ kind: ObservationGap.Kind) -> Set<String> {
            var values = Set<String>()
            for gap in context.gaps where gap.kind == kind {
                values.insert(gap.id)
                values.insert(gap.recordID)
            }
            return values
        }
        let missingReferences = allowedGapReferences(.missingConfirmation)
        let lateReferences = allowedGapReferences(.lateEntry)
        let staleReferences = allowedGapReferences(.staleFeed)
        if debrief.missingConfirmations.contains(where: { !missingReferences.contains($0) }) {
            issues.append("unknown missing-confirmation reference")
        }
        if debrief.lateEntries.contains(where: { !lateReferences.contains($0) }) {
            issues.append("unknown late-entry reference")
        }
        if debrief.staleInterruptions.contains(where: { !staleReferences.contains($0) }) {
            issues.append("unknown stale-interruption reference")
        }
        if let claim = containsForbiddenClaim(
            debrief.summary,
            allowWinRate: p.sampleSize > 0,
            allowExpectancy: p.expectancy != nil
        ) {
            issues.append("unsupported claim: \(claim)")
        }
        if containsUnsupportedPercentage(debrief.summary, performance: p) {
            issues.append("percentage does not match deterministic performance")
        }
        return issues
    }

    public static func validate(_ draft: JournalDraft) -> [String] {
        var issues: [String] = []
        if draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("empty summary")
        }
        if draft.lesson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("empty lesson")
        }
        if draft.emotion.lowercased().contains("feels") || draft.emotion.lowercased().contains("feel ") {
            // Emotions are user-stated; the draft may only echo a stated emotion.
            issues.append("inferred emotion")
        }
        return issues
    }

    public static func validate(
        _ comparison: ScanComparison,
        left: ScanRecordContext,
        right: ScanRecordContext
    ) -> [String] {
        var issues: [String] = []
        if comparison.leftID != left.id { issues.append("left ID mismatch") }
        if comparison.rightID != right.id { issues.append("right ID mismatch") }
        let known = Set([left.id, right.id])
        if comparison.citations.contains(where: { !known.contains($0) }) {
            issues.append("unknown citation")
        }
        if let claim = containsForbiddenClaim(comparison.explanation) {
            issues.append("unsupported claim: \(claim)")
        }
        if containsUnsupportedPercentage(comparison.explanation, performance: .empty) {
            issues.append("unsupported percentage")
        }
        return issues
    }

    public static func validate(
        _ suggestions: [ResearchSuggestion],
        context: AssistantContext
    ) -> [String] {
        var issues: [String] = []
        let known = context.allRecordIDs
        for suggestion in suggestions {
            if suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("empty suggestion title")
            }
            if suggestion.proposedExperiment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("suggestion has no experiment")
            }
            if suggestion.acceptanceCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || suggestion.rejectionCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("suggestion has no acceptance/rejection criteria")
            }
            if suggestion.supportingRecordIDs.isEmpty {
                issues.append("suggestion has no supporting records")
            }
            if suggestion.supportingRecordIDs.contains(where: { !known.contains($0) }) {
                issues.append("suggestion cites an unknown record")
            }
            let joined = [suggestion.rationale, suggestion.proposedExperiment, suggestion.title]
                .joined(separator: " ").lowercased()
            for forbidden in ["activate", "promote", "live strategy", "change production", "automatic"] {
                if joined.contains(forbidden) { issues.append("suggestion proposes \(forbidden)") }
            }
        }
        return issues
    }
}
