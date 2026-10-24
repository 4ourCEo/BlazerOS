import Foundation
import Testing
@testable import BlazerCore

private func sampleScan(
    id: String = "scan-1",
    call: String = "CALL",
    score: Int = 78,
    evidence: String = "Trend is up (+18) · Sweep",
    veto: String? = nil,
    actionable: Bool = true,
    blocking: String? = nil
) -> ScanRecordContext {
    ScanRecordContext(
        id: id,
        fullFingerprint: String(repeating: "A", count: 40),
        pair: "EUR/USD",
        engineCall: call,
        score: score,
        evidence: evidence,
        veto: veto,
        evaluationTime: Date(timeIntervalSince1970: 1_700_000_000),
        quoteMid: 1.1,
        spread: 0.0002,
        m1Count: 80,
        m5Count: 40,
        engineSHA: EngineIdentity.pinnedSHA1,
        expirySeconds: 60,
        isActionable: actionable,
        blockingReason: blocking,
        // Must agree with engineCall. A hardcoded TAP HIGH here made the fixture contradict
        // itself and sent the real model the wrong direction.
        recordedVerb: actionable ? AssistantValidation.canonicalDecision(call) : "WAIT"
    )
}

private func sampleContext(scan: ScanRecordContext) -> AssistantContext {
    AssistantContext(
        generatedAt: Date(),
        scans: [scan],
        confirmedEntries: [],
        performance: PerformanceSummary(
            sampleSize: 2, wins: 1, losses: 1, ties: 0, unresolved: 0,
            winRate: 0.5, breakEven: 1.0 / 1.88, expectancy: 0.5 * 0.88 - 0.5,
            confirmedOnly: true, caveat: "Small sample."
        ),
        gaps: [],
        notes: []
    )
}

private struct FakeEngine: OnDeviceModelEngine {
    var availabilityValue: AssistantAvailability = .ready
    var data: Data?
    var failure: AssistantFailure?
    var delay: TimeInterval = 0

    func availability() async -> AssistantAvailability { availabilityValue }

    func generate(
        feature: AssistantFeature, instructions: String, prompt: String,
        context: AssistantContext, timeout: TimeInterval
    ) async throws -> Data {
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if let failure { throw failure }
        guard let data else { throw AssistantFailure.generationFailed("no fixture") }
        return data
    }
}

private actor ConcurrencyProbeEngine: OnDeviceModelEngine {
    private var inFlight = 0
    private(set) var maxInFlight = 0
    let data: Data

    init(data: Data) { self.data = data }

    func availability() async -> AssistantAvailability { .ready }

    func generate(
        feature: AssistantFeature, instructions: String, prompt: String,
        context: AssistantContext, timeout: TimeInterval
    ) async throws -> Data {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        try await Task.sleep(nanoseconds: 60_000_000)
        return data
    }
}

#if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
@available(macOS 26.0, iOS 26.0, *)
private func scanExplanationData(
    decision: String = "CALL",
    score: Int = 78,
    summary: String = "The engine called CALL.",
    evidence: [String] = ["Trend is up (+18)"],
    gate: String = "",
    note: String = "This restates the frozen record."
) throws -> Data {
    let dto = GeneratedScanExplanation(
        summary: summary,
        decision: decision,
        score: score,
        evidenceUsed: evidence,
        blockingGate: gate,
        missingEvidence: [],
        coachNote: note
    )
    return try JSONEncoder().encode(dto)
}

@available(macOS 26.0, iOS 26.0, *)
private func debriefData(
    summary: String,
    behavioral: [String] = [],
    citations: [String] = ["scan-1"]
) throws -> Data {
    let object: [String: Any] = [
        "summary": summary,
        "behavioralObservations": behavioral,
        "citations": citations,
    ]
    return try JSONSerialization.data(withJSONObject: object)
}
#endif

private func sampleDebriefContext(expectancy: Double? = 0.88) -> AssistantContext {
    let scan = sampleScan()
    let performance = PerformanceSummary(
        sampleSize: 1, wins: 1, losses: 0, ties: 0, unresolved: 11,
        winRate: 1.0, breakEven: 1.0 / 1.88, expectancy: expectancy,
        confirmedOnly: true,
        caveat: "Small confirmed sample (n=1). Descriptive only; not evidence of a stable edge."
    )
    let gaps = [
        ObservationGap(
            id: "gap-event-1", pair: "EUR/USD", kind: .missingConfirmation,
            detail: "No venue confirmation was recorded.", recordID: "event-1"
        ),
        ObservationGap(
            id: "late-scan-1", pair: "EUR/USD", kind: .lateEntry,
            detail: "Entry was recorded after the beam.", recordID: "scan-1"
        ),
    ]
    return AssistantContext(
        generatedAt: Date(), scans: [scan], confirmedEntries: [],
        performance: performance, gaps: gaps, notes: []
    )
}

@Test func availableEngineProducesModelOrigin() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let scan = sampleScan()
        let engine = FakeEngine(data: try scanExplanationData())
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
        #expect(result.origin == .appleOnDevice)
        #expect(result.value.decision == "CALL")
        #expect(result.value.score == 78)
        #expect(result.diagnostic.validationIssues.isEmpty)
    }
    #endif
}

@Test func contradictoryScoreIsRejectedAndFallsBack() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let scan = sampleScan()
        let engine = FakeEngine(data: try scanExplanationData(score: 99))
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
        #expect(result.origin == .deterministicFallback)
        #expect(result.diagnostic.validationIssues.contains { $0.contains("score") })
        #expect(result.value.score == 78)
    }
    #endif
}

@Test func fullRecordedEvidenceStringIsAccepted() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let scan = sampleScan()
        let engine = FakeEngine(
            data: try scanExplanationData(evidence: ["Trend is up (+18) · Sweep"])
        )
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
        #expect(result.origin == .appleOnDevice)
        #expect(result.diagnostic.validationIssues.isEmpty)
    }
    #endif
}

@Test func inventedEvidenceIsStillRejected() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let scan = sampleScan()
        let engine = FakeEngine(
            data: try scanExplanationData(evidence: ["Trend is up (+18) · Invented"])
        )
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
        #expect(result.origin == .deterministicFallback)
        #expect(result.diagnostic.validationIssues.contains {
            $0.contains("evidence is not in the frozen record")
        })
    }
    #endif
}

@Test func debriefDerivesStructuredFieldsFromContext() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let context = sampleDebriefContext()
        let engine = FakeEngine(data: try debriefData(
            summary: "One confirmed win and no confirmed losses out of one. Expectancy is positive only in this small sample; descriptive only.",
            citations: ["scan-1", "gap-event-1"]
        ))
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.debrief(context: context)
        #expect(result.origin == .appleOnDevice)
        #expect(result.diagnostic.validationIssues.isEmpty)
        #expect(result.value.sampleSize == 1)
        #expect(result.value.wins == 1)
        #expect(result.value.losses == 0)
        #expect(result.value.unresolved == 11)
        #expect(result.value.expectancy == 0.88)
        #expect(result.value.missingConfirmations == ["event-1"])
        #expect(result.value.lateEntries == ["scan-1"])
        #expect(result.value.staleInterruptions.isEmpty)
    }
    #endif
}

@Test func allRecordIDsIncludesLocalEntryAndGapIDs() {
    let context = sampleDebriefContext()
    #expect(context.allRecordIDs.contains("event-1"))
    #expect(context.allRecordIDs.contains("gap-event-1"))
    #expect(context.allRecordIDs.contains("late-scan-1"))
    #expect(context.allRecordIDs.contains("scan-1"))
}

@Test func debriefRejectsUnknownCitation() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let context = sampleDebriefContext()
        let engine = FakeEngine(data: try debriefData(
            summary: "One confirmed win in a small sample.",
            citations: ["not-a-record"]
        ))
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.debrief(context: context)
        #expect(result.origin == .deterministicFallback)
        #expect(result.diagnostic.validationIssues.contains { $0.contains("unknown citation") })
    }
    #endif
}

@Test func unavailableModelReturnsLabelledFallback() async {
    let scan = sampleScan()
    let engine = FakeEngine(availabilityValue: .unavailable(.appleIntelligenceNotEnabled))
    let assistant = DeskAssistant(engine: engine)
    let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
    #expect(result.origin == .deterministicFallback)
    #expect(result.diagnostic.failure?.contains("unavailable") == true)
    #expect(result.value.decision == scan.engineCall)
}

@Test func timedOutGenerationFallsBack() async {
    let scan = sampleScan()
    let engine = FakeEngine(delay: 2)
    let assistant = DeskAssistant(engine: engine)
    let result = await assistant.explainScan(scan, context: sampleContext(scan: scan), timeout: 0.15)
    #expect(result.origin == .deterministicFallback)
    #expect(result.diagnostic.failure?.contains("timed out") == true)
}

@Test func cancelledGenerationFallsBack() async {
    let scan = sampleScan()
    let engine = FakeEngine(delay: 5)
    let assistant = DeskAssistant(engine: engine)
    let task = Task {
        await assistant.explainScan(scan, context: sampleContext(scan: scan), timeout: 10)
    }
    try? await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    let result = await task.value
    #expect(result.origin == .deterministicFallback)
    #expect(result.value.decision == scan.engineCall)
}

@Test func refusedGenerationFallsBack() async {
    let scan = sampleScan()
    let engine = FakeEngine(failure: .generationFailed("guardrail refusal"))
    let assistant = DeskAssistant(engine: engine)
    let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
    #expect(result.origin == .deterministicFallback)
    #expect(result.diagnostic.failure?.contains("guardrail") == true)
}

@Test func unsupportedPercentageClaimIsRejected() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let scan = sampleScan()
        let engine = FakeEngine(data: try scanExplanationData(summary: "This setup has a 60% win rate."))
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
        #expect(result.origin == .deterministicFallback)
        #expect(result.diagnostic.validationIssues.contains { $0.contains("claim") || $0.contains("number") })
    }
    #endif
}

@Test func concurrentRequestsAreSerialized() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let data = try scanExplanationData()
        let probe = ConcurrencyProbeEngine(data: data)
        let assistant = DeskAssistant(engine: probe)
        let scan = sampleScan()
        let context = sampleContext(scan: scan)
        async let first = assistant.explainScan(scan, context: context)
        async let second = assistant.explainScan(scan, context: context)
        _ = await first
        _ = await second
        #expect(await probe.maxInFlight == 1)
    }
    #endif
}

@Test func comparisonAlwaysUsesDeterministicDifferences() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let left = sampleScan(id: "left")
        let right = sampleScan(id: "right", call: "PUT", score: 22, evidence: "Trend is down")
        let dto = GeneratedComparison(
            leftID: "left", rightID: "right",
            explanation: "The decisions and scores differ.",
            limitations: "No causal claim.",
            citations: ["left", "right"]
        )
        let engine = FakeEngine(data: try JSONEncoder().encode(dto))
        let assistant = DeskAssistant(engine: engine)
        let result = await assistant.compare(left, right)
        #expect(result.origin == .appleOnDevice)
        #expect(result.value.differences == ScanComparisonEngine.differences(left, right))
        #expect(result.value.differences.contains { $0.field == "decision" })
    }
    #endif
}

@Test func assistantContextCountsOnlyVenueConfirmedPerformance() {
    let scanDate = Date(timeIntervalSince1970: 1_700_000_000)
    let journal = JournalEntry(
        id: "arm-1", fingerprint: "ABCD1234", fullFingerprint: String(repeating: "A", count: 40),
        pair: "EUR/USD", score: 78, side: "CALL", verb: "TAP HIGH", why: "Trend is up",
        strike: 1.1, veto: nil, scannedAt: scanDate, engineSHA: "engine",
        expirySeconds: 60, m1Count: 80, m5Count: 40, evaluationQuote: 1.1,
        evaluationSpread: 0.0002
    )
    func row(_ outcome: String, _ label: String, _ id: String) -> LedgerRow {
        LedgerRow(
            timestamp: scanDate, pair: "EUR/USD", hash: "ABCD1234", score: 78,
            side: "CALL", veto: false, drift: 0, outcome: outcome,
            outcomeEventID: id, labelSource: label,
            horizonSeconds: 60, enteredAt: scanDate.addingTimeInterval(2)
        )
    }
    let context = AssistantContextBuilder.make(
        journal: [journal],
        ledgerRows: [
            row("HIT", "venue-confirmed", "arm-1"),
            row("HIT", "oanda-midpoint-proxy", "ref-1"),
            row("MISS", "synthetic", "syn-1"),
        ],
        now: scanDate.addingTimeInterval(120)
    )
    #expect(context.performance.sampleSize == 1)
    #expect(context.performance.wins == 1)
    #expect(context.performance.unresolved == 2)
    #expect(context.performance.confirmedOnly)
    #expect(context.gaps.contains { $0.kind == .missingConfirmation })
}

@Test func selectionNotesDescribeOmittedRecords() {
    let scan = sampleScan()
    let context = AssistantContext(
        scans: (0..<10).map { index in var s = scan; s.id = "\(index)"; return s },
        confirmedEntries: [], performance: .empty, gaps: [], notes: []
    )
    let bounded = context.bounded(maxScans: 2, maxEntries: 0, maxGaps: 0, maxNotes: 0)
    let notes = context.selectionNotes(after: bounded)
    #expect(notes.contains { $0.hasPrefix("scans 2/10") })
}

@Test func requestStateSeparatesCapabilityFromRequestFailure() {
    let scan = sampleScan()
    let fallback = ScanExplanation.fallback(for: scan)
    func result(_ failure: String?) -> AssistantResult<ScanExplanation> {
        AssistantResult(
            value: fallback,
            origin: .deterministicFallback,
            diagnostic: AssistantDiagnostic(
                feature: .scanExplanation, origin: .deterministicFallback,
                availability: "ready", failure: failure, latencyMs: 1,
                schemaVersion: "s", promptVersion: "p", recordIDs: [scan.id]
            )
        )
    }
    #expect(result("context too large").requestState == .contextTooLarge)
    #expect(result("cancelled").requestState == .cancelled)
    #expect(result("timed out").requestState == .timedOut)
    #expect(result("rejected output: score").requestState == .invalidOutput)
    #expect(result(nil).requestState == .basicFallback)
}

@Test func boundedContextFitsTheModelWindow() throws {
    let scan = sampleScan(evidence: String(repeating: "Trend is up (+18) · ", count: 12))
    let scans = (0..<40).map { index in
        var copy = scan
        copy.id = "scan-\(index)"
        return copy
    }
    let entries = (0..<60).map { index in
        ConfirmedEntryContext(
            id: "entry-\(index)", pair: "EUR/USD", side: "CALL", outcome: "HIT",
            recordedAt: Date(), enteredAt: Date(), horizonSeconds: 60,
            entryQuote: 1.1, expiryPrice: 1.1001, stake: nil, payout: nil,
            lateEntry: false, recordID: "entry-\(index)"
        )
    }
    let gaps = (0..<60).map { index in
        ObservationGap(
            id: "gap-\(index)", pair: "EUR/USD", kind: .missingConfirmation,
            detail: String(repeating: "reference observation ", count: 12),
            recordID: "entry-\(index)"
        )
    }
    let notes = (0..<20).map { index in
        JournalNoteContext(id: "note-\(index)", pair: "EUR/USD",
                           note: String(repeating: "reflection ", count: 30), createdAt: Date())
    }
    let context = AssistantContext(
        scans: scans, confirmedEntries: entries,
        performance: .empty, gaps: gaps, notes: notes
    )
    let bounded = context.bounded(maxScans: 4, maxEntries: 8, maxGaps: 8, maxNotes: 3)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(bounded)
    #expect(data.count < 12_000)
}

private struct BudgetEngine: OnDeviceModelEngine {
    let data: Data
    var alwaysOver = false

    func availability() async -> AssistantAvailability { .ready }

    func estimate(
        feature: AssistantFeature, instructions: String, prompt: String,
        context: AssistantContext
    ) async -> ModelTokenEstimate? {
        let fits = !alwaysOver && context.scans.count <= 1 && context.confirmedEntries.count <= 4
        return ModelTokenEstimate(
            inputTokens: fits ? 400 : 5_000,
            contextSize: 4_096,
            outputReserve: ModelBudgetPolicy.outputReserve(for: feature),
            safetyMargin: ModelBudgetPolicy.safetyMargin,
            method: "test"
        )
    }

    func generate(
        feature: AssistantFeature, instructions: String, prompt: String,
        context: AssistantContext, timeout: TimeInterval
    ) async throws -> Data { data }
}

@Test func oversizedContextRetriesOnceWithCompactedContext() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let dto = GeneratedCoachAnswer(
            answer: "The latest saved scan is WAIT.", citations: ["scan-0"],
            limitations: "Single frozen record."
        )
        let engine = BudgetEngine(data: try JSONEncoder().encode(dto))
        let assistant = DeskAssistant(engine: engine)
        let scans = (0..<4).map { index in
            var scan = sampleScan()
            scan.id = "scan-\(index)"
            return scan
        }
        let context = AssistantContext(
            generatedAt: Date(), scans: scans,
            performance: .empty, gaps: [], notes: []
        )
        let result = await assistant.answer("Explain the latest WAIT.", context: context)
        #expect(result.origin == .appleOnDevice)
        #expect(result.diagnostic.retryCount == 1)
        #expect(result.diagnostic.omitted?.isEmpty == false)
        #expect(result.diagnostic.contextTokens != nil)
    }
    #endif
}

@Test func contextThatCannotFitReturnsContextFailure() async throws {
    let engine = BudgetEngine(data: Data("{}".utf8), alwaysOver: true)
    let assistant = DeskAssistant(engine: engine)
    let scan = sampleScan()
    let context = sampleContext(scan: scan)
    // explainScan has no smaller context: the selected record is mandatory.
    // The budget engine reports over-limit even for one scan only when entries exceed 4.
    var wide = context
    wide.confirmedEntries = (0..<10).map { index in
        ConfirmedEntryContext(
            id: "entry-\(index)", pair: "EUR/USD", side: "CALL", outcome: "HIT",
            recordedAt: Date(), enteredAt: Date(), horizonSeconds: 60,
            entryQuote: 1.1, expiryPrice: 1.1001, stake: nil, payout: nil,
            lateEntry: false, recordID: "entry-\(index)"
        )
    }
    let result = await assistant.answer("Explain.", context: wide)
    #expect(result.origin == .deterministicFallback)
    #expect(result.requestState == .contextTooLarge)
}

@Test func realEngineReportsExactTokenCountWhenAvailable() async {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    #if compiler(>=6.4)
    if #available(macOS 26.4, iOS 26.4, *) {
        let engine = SystemModelEngine()
        guard await engine.availability() == .ready else { return }
        let scan = sampleScan()
        let context = sampleContext(scan: scan)
        let estimate = await engine.estimate(
            feature: .scanExplanation,
            instructions: AssistantPrompts.instructions(for: .scanExplanation),
            prompt: AssistantPrompts.records(context),
            context: context
        )
        print("FM_BUDGET \(String(describing: estimate))")
        #expect(estimate != nil)
        if let estimate {
            if estimate.method == "exact" {
                #expect(estimate.contextSize > 0)
                #expect(estimate.fits)
            } else {
                #expect(estimate.method == "estimated")
                #expect(estimate.contextSize > 0)
                #expect(estimate.fits == (estimate.required <= estimate.contextSize))
            }
        }
    }
    #endif
    #endif
}

@Test func zeroOrNegativeModelContextUsesBoundedFallbackCapacity() {
    #expect(ModelBudgetPolicy.effectiveContextSize(reported: 0) == 4_096)
    #expect(ModelBudgetPolicy.effectiveContextSize(reported: -1) == 4_096)
    #expect(ModelBudgetPolicy.effectiveContextSize(reported: 8_192) == 8_192)
}

@Test func realModelCompactsAnOversizedContextOnce() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.4, iOS 26.4, *) {
        let assistant = DeskAssistant.appleOnDevice()
        guard await assistant.availability() == .ready else { return }
        let scans = (0..<30).map { index in
            var scan = sampleScan(evidence: String(repeating: "Trend is up (+18) · ", count: 8))
            scan.id = "scan-\(index)"
            return scan
        }
        let entries = (0..<40).map { index in
            ConfirmedEntryContext(
                id: "entry-\(index)", pair: "EUR/USD", side: "CALL", outcome: "HIT",
                recordedAt: Date(), enteredAt: Date(), horizonSeconds: 60,
                entryQuote: 1.1, expiryPrice: 1.1001, stake: nil, payout: nil,
                lateEntry: false, recordID: "entry-\(index)"
            )
        }
        let context = AssistantContext(
            scans: scans, confirmedEntries: entries,
            performance: .empty, gaps: [], notes: []
        )
        let fullPrompt = AssistantPrompts.records(context)
        let fullEstimate = await SystemModelEngine().estimate(
            feature: .coachAnswer,
            instructions: AssistantPrompts.instructions(for: .coachAnswer),
            prompt: fullPrompt,
            context: context
        )
        print("FM_COMPACT_FULL \(String(describing: fullEstimate)) chars=\(fullPrompt.count)")
        let result = await assistant.answer("Summarize the latest saved scan.", context: context, timeout: 40)
        print("FM_COMPACT state=\(result.requestState.rawValue) retry=\(result.diagnostic.retryCount ?? -1) tokens=\(result.diagnostic.contextTokens ?? -1) omitted=\(result.diagnostic.omitted ?? [])")
        #expect(result.requestState != .contextTooLarge)
        #expect((result.diagnostic.retryCount ?? 0) <= 1)
    }
    #endif
}

@Test func realAppleOnDeviceEngineGenerates() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let engine = SystemModelEngine()
        let availability = await engine.availability()
        guard availability == .ready else { return }
        let scan = sampleScan(
            call: "WAIT", score: 44, evidence: "Range is tight",
            actionable: false, blocking: "Range is tight"
        )
        let context = sampleContext(scan: scan)
        let prompt = """
        Explain this frozen scan. Restate the decision and score. No other numbers.
        \(AssistantPrompts.records(context))
        """
        let data = try await engine.generate(
            feature: .scanExplanation,
            instructions: AssistantPrompts.instructions(for: .scanExplanation),
            prompt: prompt,
            context: context,
            timeout: 30
        )
        let dto = try JSONDecoder().decode(GeneratedScanExplanation.self, from: data)
        print("FM_RAW availability=\(availability) decision=\(dto.decision) score=\(dto.score) summary=\(dto.summary)")
        #expect(dto.decision.uppercased() == "WAIT")
        #expect(dto.score == 44)
        #expect(!dto.summary.isEmpty)
    }
    #endif
}

@Test func realAppleOnDeviceServiceIsSafeOnLiveOutput() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let assistant = DeskAssistant.appleOnDevice()
        let availability = await assistant.availability()
        guard availability == .ready else {
            return // Recorded in diagnostics; no model is available in this environment.
        }
        let scan = sampleScan(call: "WAIT", score: 44, evidence: "Range is tight", actionable: false, blocking: "Range is tight")
        let result = await assistant.explainScan(scan, context: sampleContext(scan: scan), timeout: 30)
        print("FM_SERVICE availability=\(availability) origin=\(result.origin.rawValue) decision=\(result.value.decision) score=\(result.value.score) latencyMs=\(result.diagnostic.latencyMs) issues=\(result.diagnostic.validationIssues)")
        // The service may reject a live output for semantic reasons; it must then return the
        // deterministic fallback with the same sealed decision and score.
        #expect(result.value.decision == "WAIT")
        #expect(result.value.score == 44)
        #expect(result.diagnostic.validationIssues.isEmpty || result.origin == .deterministicFallback)
    }
    #endif
}

@Test func realAppleOnDeviceAcceptsAnActionableLowDecision() async throws {
    #if canImport(FoundationModels) && !BLAZER_DISABLE_FOUNDATION_MODELS
    if #available(macOS 26.0, iOS 26.0, *) {
        let assistant = DeskAssistant.appleOnDevice()
        let availability = await assistant.availability()
        guard availability == .ready else {
            return // No on-device model in this environment; recorded in diagnostics.
        }
        // Production records store TAP LOW, not PUT. This is the exact shape that used to
        // fail validation because the generation guide named a different vocabulary.
        let scan = sampleScan(
            call: "TAP LOW",
            score: 96,
            evidence: "Trend is down (-18) · Broke the prior low (-16) · Fall is extended (-12)",
            actionable: true
        )
        let result = await assistant.explainScan(
            scan,
            context: sampleContext(scan: scan),
            timeout: 30
        )
        print("FM_ACTIONABLE origin=\(result.origin.rawValue) decision=\(result.value.decision) score=\(result.value.score) issues=\(result.diagnostic.validationIssues)")

        // Whether the model answers or the service falls back, the sealed direction and score
        // must survive. A model answer is only allowed through when it validates cleanly.
        #expect(AssistantValidation.canonicalDecision(result.value.decision) == "TAP LOW")
        #expect(result.value.score == 96)
        if result.origin == .appleOnDevice {
            #expect(result.diagnostic.validationIssues.isEmpty)
        }
    }
    #endif
}
