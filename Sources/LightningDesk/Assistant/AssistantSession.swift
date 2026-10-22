import Combine
import Foundation
import BlazerCore

/// Owns every optional on-device assistant surface: feature state, generation, and the
/// operations that call `DeskAssistant`. Extracted from `LightningDeskModel` so the desk
/// model keeps execution state only.
///
/// The assistant is explanatory only. It never gates a trade, never produces numbers, and
/// every failure degrades to a deterministic fallback or to `nil`.
@MainActor
public final class AssistantSession: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var availability: AssistantAvailability = .unknown
    @Published public private(set) var status: AssistantStatus = .idle
    @Published public private(set) var origin: AssistantOrigin?
    @Published public private(set) var answer: CoachAnswer?
    @Published public private(set) var scanExplanation: ScanExplanation?
    @Published public private(set) var journalDraft: JournalDraft?
    @Published public private(set) var debrief: SessionDebrief?
    @Published public private(set) var comparison: ScanComparison?
    @Published public private(set) var research: [ResearchSuggestion] = []
    @Published public private(set) var error: String?
    @Published public private(set) var requestState: AssistantRequestState?

    /// Optional AI surfaces. The execution workflow remains usable when this is off.
    @Published public var enabled: Bool = UserDefaults.standard.object(forKey: "blazer.assistant_enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if !enabled { clearOutputs() }
        }
    }

    // MARK: - Dependencies

    private static let enabledKey = "blazer.assistant_enabled"
    private let assistant: DeskAssistant
    private var generation = 0

    /// Built by the desk model from its journal and ledger. Settable so the model can finish
    /// initialising before capturing itself; never nil, defaults to an empty context.
    public var contextProvider: () -> AssistantContext = { .empty }

    public init(diagnosticsURL: URL?) {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            assistant = DeskAssistant.appleOnDevice(diagnosticsURL: diagnosticsURL)
        } else {
            assistant = DeskAssistant(
                engine: UnavailableModelEngine(reason: .unsupportedOS),
                diagnosticsURL: diagnosticsURL
            )
        }
    }

    // MARK: - Availability

    public func refreshAvailability() async {
        if case .generating = status { return }
        status = .checking
        let value = await assistant.availability(force: true)
        availability = value
        if value.isReady {
            status = .idle
            error = nil
        } else {
            status = .unavailable(value.detail)
            error = value.detail
        }
    }

    /// The Coach service used by voice sessions. Carries the same context and enablement.
    public func coachService() -> FoundationCoachService {
        FoundationCoachService(
            allowsModel: enabled,
            assistant: assistant,
            context: contextProvider()
        )
    }

    public func diagnostics(limit: Int = 20) async -> [AssistantDiagnostic] {
        await assistant.recentDiagnostics(limit: limit)
    }

    /// Surface a model-owned failure (for example a failed journal annotation) in the
    /// assistant channel without taking ownership of that operation.
    public func setError(_ message: String?) {
        error = message
    }

    // MARK: - Operations

    public func ask(_ question: String) async {
        guard enabled else { error = "On-device assistant is off."; return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = contextProvider()
        let generation = begin(.coachAnswer)
        let result = await assistant.answer(trimmed, context: context)
        apply(result, generation: generation) { self.answer = $0 }
    }

    public func explainLatestScan() async {
        guard enabled else { error = "On-device assistant is off."; return }
        let context = contextProvider()
        guard let scan = context.scans.first else {
            error = "No saved scan is available to explain."
            return
        }
        let generation = begin(.scanExplanation)
        let result = await assistant.explainScan(scan, context: context)
        apply(result, generation: generation) { self.scanExplanation = $0 }
    }

    /// Explains a specific saved scan. Returns the explanation and its record only when the
    /// on-device model produced it, so callers never present a fallback as a model answer.
    public func explain(scanID: String) async -> (explanation: ScanExplanation, scan: ScanRecordContext)? {
        guard enabled else { return nil }
        let context = contextProvider()
        guard let scan = context.scans.first(where: { $0.id == scanID }) else { return nil }
        let generation = begin(.scanExplanation)
        let result = await assistant.explainScan(scan, context: context)
        guard generation == self.generation else { return nil }
        apply(result, generation: generation) { self.scanExplanation = $0 }
        return result.isModelGenerated ? (result.value, scan) : nil
    }

    public func requestDebrief() async {
        guard enabled else { error = "On-device assistant is off."; return }
        let context = contextProvider()
        let generation = begin(.sessionDebrief)
        let result = await assistant.debrief(context: context)
        apply(result, generation: generation) { self.debrief = $0 }
    }

    public func compareLatestScans() async {
        guard enabled else { error = "On-device assistant is off."; return }
        let context = contextProvider()
        guard context.scans.count >= 2 else {
            error = "At least two saved scans are required for a comparison."
            return
        }
        let generation = begin(.scanComparison)
        let result = await assistant.compare(context.scans[1], context.scans[0])
        apply(result, generation: generation) { self.comparison = $0 }
    }

    public func requestResearchSuggestions() async {
        guard enabled else { error = "On-device assistant is off."; return }
        let context = contextProvider()
        let generation = begin(.researchSuggestions)
        let result = await assistant.researchSuggestions(context: context)
        apply(result, generation: generation) { self.research = $0 }
    }

    public func draftJournalNote(_ note: String) async {
        guard enabled else { error = "On-device assistant is off."; return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = contextProvider()
        let generation = begin(.journalDraft)
        let result = await assistant.journalDraft(note: trimmed, context: context)
        apply(result, generation: generation) { self.journalDraft = $0 }
    }

    // MARK: - Generation and state

    private func begin(_ feature: AssistantFeature) -> Int {
        generation += 1
        status = .generating(feature)
        error = nil
        return generation
    }

    private func apply<Value>(
        _ result: AssistantResult<Value>,
        generation: Int,
        assign: (Value) -> Void
    ) {
        guard generation == self.generation else { return }
        assign(result.value)
        origin = result.origin
        requestState = result.requestState
        status = result.isModelGenerated ? .idle : .basicFallback
        error = result.isModelGenerated ? nil : result.diagnostic.failure
    }

    private func clearOutputs() {
        status = .idle
        answer = nil
        scanExplanation = nil
        journalDraft = nil
        debrief = nil
        comparison = nil
        research = []
        error = nil
        origin = nil
        requestState = nil
        generation += 1
    }

    /// Device-only diagnostic: prove Apple’s on-device model is available and generating.
    /// No execution state is touched. Invoked only with BLAZER_FM_SELFTEST=1 in DEBUG.
    public func runAssistantSelfTestForTesting() async {
        let availability = await assistant.availability(force: true)
        print("PHONE_FM_AVAIL \(availability)")
        guard availability.isReady else { return }
        let scan = ScanRecordContext(
            id: "phone-selftest",
            fullFingerprint: String(repeating: "A", count: 40),
            pair: "EUR/USD",
            engineCall: "WAIT",
            score: 44,
            evidence: "Trend is up (+18) · Range is tight",
            veto: nil,
            evaluationTime: Date(),
            quoteMid: 1.1,
            spread: 0.0002,
            m1Count: 80,
            m5Count: 40,
            engineSHA: "phone-selftest",
            expirySeconds: 60,
            isActionable: false,
            blockingReason: "Range is tight",
            recordedVerb: "WAIT"
        )
        let context = AssistantContext(
            generatedAt: Date(),
            scans: [scan],
            performance: .empty
        )
        let result = await assistant.explainScan(scan, context: context, timeout: 30)
        print("PHONE_FM_RESULT origin=\(result.origin.rawValue) decision=\(result.value.decision) score=\(result.value.score) latencyMs=\(result.diagnostic.latencyMs) issues=\(result.diagnostic.validationIssues)")
    }

    /// Device-only diagnostic: exercise the bounded Coach request with a full context.
    /// Uses the same `answer` path as the Coach panel. No execution state is touched.
    /// Invoked only with BLAZER_FM_COACH_SELFTEST=1 in DEBUG.
    public func runBoundedCoachSelfTestForTesting() async {
        let availability = await assistant.availability(force: true)
        print("PHONE_COACH_AVAIL ready=\(availability.isReady) detail=\(availability.detail)")
        guard availability.isReady else { return }
        let now = Date()
        func scan(at index: Int) -> ScanRecordContext {
            let first = index == 0
            let pair = first ? "EUR/USD" : "GBP/USD"
            let evaluationTime = now.addingTimeInterval(Double(-index * 120))
            let fingerprint = String(repeating: first ? "A" : "B", count: 40)
            return ScanRecordContext(
                id: "phone-coach-scan-\(index)",
                fullFingerprint: fingerprint,
                pair: pair,
                engineCall: "WAIT",
                score: 44 + index,
                evidence: "Completed M5 bars show a tight range. Spread widened before the evaluation. Momentum is not aligned with the higher-timeframe trend.",
                veto: first ? nil : "Spread above the pair ceiling.",
                evaluationTime: evaluationTime,
                quoteMid: 1.1 + Double(index) * 0.01,
                spread: 0.0002,
                m1Count: 80,
                m5Count: 40,
                engineSHA: "phone-selftest",
                expirySeconds: 60,
                isActionable: false,
                blockingReason: "Range is tight; no completed-bar displacement.",
                recordedVerb: "WAIT"
            )
        }
        let scans = [scan(at: 0), scan(at: 1)]

        func entry(at index: Int) -> ConfirmedEntryContext {
            let pair = index.isMultiple(of: 2) ? "EUR/USD" : "GBP/USD"
            let side = index.isMultiple(of: 2) ? "HIGH" : "LOW"
            let outcomes = ["MISS", "MISS", "HIT", "UNRESOLVED"]
            let recordedAt = now.addingTimeInterval(Double(-index * 600))
            let enteredAt = now.addingTimeInterval(Double(-index * 600 - 30))
            let entryQuote = 1.1 + Double(index) * 0.001
            let expiryPrice = 1.1005 + Double(index) * 0.001
            return ConfirmedEntryContext(
                id: "entry-\(index)",
                pair: pair,
                side: side,
                outcome: outcomes[index],
                recordedAt: recordedAt,
                enteredAt: enteredAt,
                horizonSeconds: 60,
                entryQuote: entryQuote,
                expiryPrice: expiryPrice,
                stake: 1,
                payout: 0.92,
                lateEntry: index == 3,
                recordID: "phone-coach-scan-\(index % 2)"
            )
        }
        let entries = [entry(at: 0), entry(at: 1), entry(at: 2), entry(at: 3)]

        func gap(at index: Int) -> ObservationGap {
            let kinds: [ObservationGap.Kind] = [
                .missingConfirmation, .lateEntry, .staleFeed, .unresolvedExpiry,
            ]
            let pair = index.isMultiple(of: 2) ? "EUR/USD" : "GBP/USD"
            return ObservationGap(
                id: "gap-\(index)",
                pair: pair,
                kind: kinds[index],
                detail: "The venue result was not captured before the app was backgrounded; the expiry observation remains unresolved.",
                recordID: "phone-coach-scan-\(index % 2)"
            )
        }
        let gaps = [gap(at: 0), gap(at: 1), gap(at: 2), gap(at: 3)]

        let notes = [
            JournalNoteContext(
                id: "note-0",
                pair: "EUR/USD",
                note: "Waited for the beam but the venue rejected the stake; recorded only after returning to the desk.",
                createdAt: now
            )
        ]
        let performance = PerformanceSummary(
            sampleSize: 3, wins: 1, losses: 2, ties: 0, unresolved: 1,
            winRate: 1.0 / 3.0, breakEven: 1.0 / (1.0 + EntryQuality.assumedPayout),
            expectancy: (1.0 / 3.0) * EntryQuality.assumedPayout - (2.0 / 3.0),
            confirmedOnly: true,
            caveat: "Small venue-confirmed sample. Descriptive only."
        )
        let context = AssistantContext(
            generatedAt: now, scans: scans, confirmedEntries: entries,
            performance: performance, gaps: gaps, notes: notes
        )
        print("PHONE_COACH_CONTEXT scans=\(context.scans.count) entries=\(context.confirmedEntries.count) gaps=\(context.gaps.count) notes=\(context.notes.count)")
        let started = Date()
        let result = await assistant.answer(
            "Why did the latest scan return WAIT, and what is missing from the record?",
            context: context,
            timeout: 30
        )
        let d = result.diagnostic
        let tokens = d.contextTokens.map(String.init) ?? "nil"
        let limit = d.contextLimit.map(String.init) ?? "nil"
        print("PHONE_COACH_RESULT origin=\(result.origin.rawValue) state=\(result.requestState.rawValue) latencyMs=\(String(format: "%.1f", d.latencyMs)) wallMs=\(String(format: "%.1f", Date().timeIntervalSince(started) * 1000)) tokens=\(tokens) limit=\(limit) method=\(d.contextMethod ?? "nil") retries=\(d.retryCount.map(String.init) ?? "nil") omitted=\(d.omitted?.count ?? 0) issues=\(d.validationIssues) failure=\(d.failure ?? "none") answerChars=\(result.value.answer.count) citations=\(result.value.citations)")

        let debriefStarted = Date()
        let debrief = await assistant.debrief(context: context, timeout: 30)
        let dd = debrief.diagnostic
        let debriefTokens = dd.contextTokens.map(String.init) ?? "nil"
        let debriefLimit = dd.contextLimit.map(String.init) ?? "nil"
        print("PHONE_DEBRIEF_RESULT origin=\(debrief.origin.rawValue) state=\(debrief.requestState.rawValue) latencyMs=\(String(format: "%.1f", dd.latencyMs)) wallMs=\(String(format: "%.1f", Date().timeIntervalSince(debriefStarted) * 1000)) tokens=\(debriefTokens) limit=\(debriefLimit) method=\(dd.contextMethod ?? "nil") retries=\(dd.retryCount.map(String.init) ?? "nil") omitted=\(dd.omitted?.count ?? 0) issues=\(dd.validationIssues) failure=\(dd.failure ?? "none") summary=\(debrief.value.summary)")

        let compare = await assistant.compare(scans[0], scans[1], timeout: 30)
        print("PHONE_COMPARE_RESULT origin=\(compare.origin.rawValue) state=\(compare.requestState.rawValue) issues=\(compare.diagnostic.validationIssues) failure=\(compare.diagnostic.failure ?? "none") citations=\(compare.value.citations)")

        let draft = await assistant.journalDraft(
            note: "I waited for the beam and recorded the entry after returning from the broker.",
            context: context,
            timeout: 30
        )
        print("PHONE_DRAFT_RESULT origin=\(draft.origin.rawValue) state=\(draft.requestState.rawValue) issues=\(draft.diagnostic.validationIssues) failure=\(draft.diagnostic.failure ?? "none") summaryChars=\(draft.value.summary.count)")

        let research = await assistant.researchSuggestions(context: context, timeout: 40)
        print("PHONE_RESEARCH_RESULT origin=\(research.origin.rawValue) state=\(research.requestState.rawValue) issues=\(research.diagnostic.validationIssues) failure=\(research.diagnostic.failure ?? "none") suggestions=\(research.value.count)")
    }
}
