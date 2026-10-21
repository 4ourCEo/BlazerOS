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
        recordedVerb: actionable ? "TAP HIGH" : "WAIT"
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

#if canImport(FoundationModels)
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
#endif

@Test func availableEngineProducesModelOrigin() async throws {
    #if canImport(FoundationModels)
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
    #if canImport(FoundationModels)
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

@Test func unavailableModelReturnsLabelledFallback() async {
    let scan = sampleScan()
    let engine = FakeEngine(availabilityValue: .unavailable(.appleIntelligenceNotEnabled))
    let assistant = DeskAssistant(engine: engine)
    let result = await assistant.explainScan(scan, context: sampleContext(scan: scan))
    #expect(result.origin == .deterministicFallback)
    #expect(result.diagnostic.failure == "unavailable")
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
    #if canImport(FoundationModels)
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
    #if canImport(FoundationModels)
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
    #if canImport(FoundationModels)
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

@Test func realAppleOnDeviceEngineGenerates() async throws {
    #if canImport(FoundationModels)
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
    #if canImport(FoundationModels)
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
