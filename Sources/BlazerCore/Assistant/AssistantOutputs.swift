import Foundation

public struct ScanExplanation: Codable, Sendable, Equatable {
    public var summary: String
    public var decision: String
    public var score: Int
    public var evidenceUsed: [String]
    public var blockingGate: String?
    public var missingEvidence: [String]
    public var coachNote: String
    public var recordID: String

    public init(
        summary: String, decision: String, score: Int, evidenceUsed: [String],
        blockingGate: String?, missingEvidence: [String], coachNote: String,
        recordID: String = ""
    ) {
        self.summary = summary
        self.decision = decision
        self.score = score
        self.evidenceUsed = evidenceUsed
        self.blockingGate = blockingGate
        self.missingEvidence = missingEvidence
        self.coachNote = coachNote
        self.recordID = recordID
    }

    public static func fallback(for scan: ScanRecordContext) -> ScanExplanation {
        let lines = scan.evidenceLines
        let summary: String
        if scan.engineCall == "WAIT" {
            summary = "The pinned engine returned WAIT for \(scan.pair)."
        } else {
            summary = "The pinned engine returned \(scan.engineCall) for \(scan.pair)."
        }
        let missing = lines.isEmpty
            ? ["No engine evidence was recorded for this scan."]
            : (scan.isActionable ? [] : ["The scan is historical; the action window has closed."])
        return ScanExplanation(
            summary: summary,
            decision: scan.engineCall,
            score: scan.score,
            evidenceUsed: lines,
            blockingGate: scan.blockingReason,
            missingEvidence: missing,
            coachNote: "This is a deterministic explanation. It restates the frozen record and does not predict price.",
            recordID: scan.id
        )
    }
}

public struct CoachAnswer: Codable, Sendable, Equatable {
    public var answer: String
    public var citations: [String]
    public var limitations: String

    public init(answer: String, citations: [String], limitations: String) {
        self.answer = answer
        self.citations = citations
        self.limitations = limitations
    }

    public static func fallback(question: String, context: AssistantContext) -> CoachAnswer {
        let lower = question.lowercased()
        let latest = context.scans.first
        let text: String
        if let latest, lower.contains("wait") || latest.engineCall == "WAIT" {
            let gate = latest.blockingReason ?? "the engine returned WAIT"
            text = "The latest saved scan for \(latest.pair) is \(latest.engineCall) with engine score \(latest.score). The recorded blocker is: \(gate)."
        } else if lower.contains("week") || lower.contains("perform") || lower.contains("result") {
            let p = context.performance
            if p.sampleSize == 0 {
                text = "There are no venue-confirmed outcomes yet, so no performance claim can be made."
            } else {
                let rate = p.winRate.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable"
                text = "Confirmed outcomes: \(p.wins) wins and \(p.losses) losses out of \(p.sampleSize). Descriptive win rate \(rate); break-even \(String(format: "%.1f%%", p.breakEven * 100)) (\(p.payoutBasis ?? "assumed payout"))."
            }
        } else if lower.contains("low"), let latest,
                  AssistantValidation.canonicalDecision(latest.engineCall) == "TAP LOW" {
            text = "The engine returned \(latest.engineCall). Engine score \(latest.score) is side-neutral conviction, not a win probability."
        } else if let latest {
            text = "The latest saved scan is \(latest.engineCall) on \(latest.pair) with engine score \(latest.score). \(latest.evidenceLines.first ?? "No evidence was recorded.")"
        } else {
            text = "No saved scans are available. Run a scan first."
        }
        return CoachAnswer(
            answer: text,
            citations: latest.map { [$0.id] } ?? [],
            limitations: "Basic deterministic explanation. Apple’s on-device model was not used."
        )
    }
}

public struct JournalDraft: Codable, Sendable, Equatable {
    public var summary: String
    public var emotion: String
    public var discipline: String
    public var lesson: String
    public var tags: [String]

    public init(summary: String, emotion: String, discipline: String, lesson: String, tags: [String]) {
        self.summary = summary
        self.emotion = emotion
        self.discipline = discipline
        self.lesson = lesson
        self.tags = tags
    }

    public static func fallback(note: String) -> JournalDraft {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        return JournalDraft(
            summary: String(first.prefix(180)),
            emotion: "not stated",
            discipline: "No deterministic discipline observation was derived.",
            lesson: trimmed,
            tags: []
        )
    }
}

public struct SessionDebrief: Codable, Sendable, Equatable {
    public var summary: String
    public var sampleSize: Int
    public var wins: Int
    public var losses: Int
    public var ties: Int
    public var unresolved: Int
    public var winRate: Double?
    public var expectancy: Double?
    public var missingConfirmations: [String]
    public var lateEntries: [String]
    public var staleInterruptions: [String]
    public var behavioralObservations: [String]
    public var citations: [String]

    public init(
        summary: String, sampleSize: Int, wins: Int, losses: Int, ties: Int,
        unresolved: Int, winRate: Double?, expectancy: Double?,
        missingConfirmations: [String], lateEntries: [String],
        staleInterruptions: [String], behavioralObservations: [String],
        citations: [String]
    ) {
        self.summary = summary
        self.sampleSize = sampleSize
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.unresolved = unresolved
        self.winRate = winRate
        self.expectancy = expectancy
        self.missingConfirmations = missingConfirmations
        self.lateEntries = lateEntries
        self.staleInterruptions = staleInterruptions
        self.behavioralObservations = behavioralObservations
        self.citations = citations
    }

    public static func fallback(context: AssistantContext) -> SessionDebrief {
        let p = context.performance
        let missing = context.gaps.filter { $0.kind == .missingConfirmation }.map(\.recordID)
        let late = context.gaps.filter { $0.kind == .lateEntry }.map(\.recordID)
        let stale = context.gaps.filter { $0.kind == .staleFeed }.map(\.recordID)
        let summary: String
        if p.sampleSize == 0 {
            summary = "No venue-confirmed outcomes are available. No performance claim can be made."
        } else {
            summary = "\(p.wins) confirmed wins and \(p.losses) confirmed losses out of \(p.sampleSize). \(p.caveat)"
        }
        return SessionDebrief(
            summary: summary,
            sampleSize: p.sampleSize, wins: p.wins, losses: p.losses, ties: p.ties,
            unresolved: p.unresolved, winRate: p.winRate, expectancy: p.expectancy,
            missingConfirmations: missing,
            lateEntries: late,
            staleInterruptions: stale,
            behavioralObservations: [],
            citations: Array(context.allRecordIDs).sorted()
        )
    }
}

public struct ComparisonDifference: Codable, Sendable, Equatable {
    public var field: String
    public var left: String
    public var right: String

    public init(field: String, left: String, right: String) {
        self.field = field
        self.left = left
        self.right = right
    }
}

public struct ScanComparison: Codable, Sendable, Equatable {
    public var leftID: String
    public var rightID: String
    public var differences: [ComparisonDifference]
    public var explanation: String
    public var limitations: String
    public var citations: [String]

    public init(
        leftID: String, rightID: String, differences: [ComparisonDifference],
        explanation: String, limitations: String, citations: [String]
    ) {
        self.leftID = leftID
        self.rightID = rightID
        self.differences = differences
        self.explanation = explanation
        self.limitations = limitations
        self.citations = citations
    }
}

public enum ScanComparisonEngine {
    public static func differences(_ left: ScanRecordContext, _ right: ScanRecordContext) -> [ComparisonDifference] {
        func add(_ field: String, _ a: String, _ b: String) -> ComparisonDifference? {
            a == b ? nil : ComparisonDifference(field: field, left: a, right: b)
        }
        var out: [ComparisonDifference] = []
        if let d = add("pair", left.pair, right.pair) { out.append(d) }
        if let d = add("decision", left.engineCall, right.engineCall) { out.append(d) }
        if let d = add("engine score", "\(left.score)", "\(right.score)") { out.append(d) }
        if let d = add("veto", left.veto ?? "none", right.veto ?? "none") { out.append(d) }
        if let d = add("evidence", left.evidence, right.evidence) { out.append(d) }
        if let d = add("quote", left.quoteMid.map { String(format: "%.5f", $0) } ?? "missing",
                      right.quoteMid.map { String(format: "%.5f", $0) } ?? "missing") { out.append(d) }
        if let d = add("spread", left.spread.map { String(format: "%.5f", $0) } ?? "missing",
                      right.spread.map { String(format: "%.5f", $0) } ?? "missing") { out.append(d) }
        if let d = add("M1 bars", "\(left.m1Count)", "\(right.m1Count)") { out.append(d) }
        if let d = add("M5 bars", "\(left.m5Count)", "\(right.m5Count)") { out.append(d) }
        if let d = add("engine identity", left.engineSHA, right.engineSHA) { out.append(d) }
        if let d = add("expiry", "\(left.expirySeconds)s", "\(right.expirySeconds)s") { out.append(d) }
        if let d = add("evaluation time", left.evaluationTime.description, right.evaluationTime.description) { out.append(d) }
        return out
    }

    public static func deterministic(_ left: ScanRecordContext, _ right: ScanRecordContext) -> ScanComparison {
        let diffs = differences(left, right)
        let explanation = diffs.isEmpty
            ? "The two frozen scans have the same recorded fields."
            : "The frozen scans differ in \(diffs.count) recorded field(s): \(diffs.map(\.field).joined(separator: ", "))."
        return ScanComparison(
            leftID: left.id,
            rightID: right.id,
            differences: diffs,
            explanation: explanation,
            limitations: "Deterministic field comparison. It does not establish which difference caused any outcome.",
            citations: [left.id, right.id]
        )
    }
}

public struct ResearchSuggestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var rationale: String
    public var supportingRecordIDs: [String]
    public var observedPattern: String
    public var uncertainty: String
    public var proposedExperiment: String
    public var acceptanceCriteria: String
    public var rejectionCriteria: String

    public init(
        id: String = UUID().uuidString,
        title: String, rationale: String, supportingRecordIDs: [String],
        observedPattern: String, uncertainty: String, proposedExperiment: String,
        acceptanceCriteria: String, rejectionCriteria: String
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.supportingRecordIDs = supportingRecordIDs
        self.observedPattern = observedPattern
        self.uncertainty = uncertainty
        self.proposedExperiment = proposedExperiment
        self.acceptanceCriteria = acceptanceCriteria
        self.rejectionCriteria = rejectionCriteria
    }
}
