import Foundation
import Testing
@testable import BlazerCore
@testable import LightningDesk

// Advisory copilot: models, prompt, strict decode, and the async actor (via an injected
// transport). The copilot returns words only and is never authoritative.

private struct StubTransport: LLMTransport {
    let handler: @Sendable (URL, [String: String], Data) throws -> Data
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        try handler(url, headers, body)
    }
}

private func sampleRequest() -> StrikeAuditRequest {
    let entry = Decimal.strikeMoney("0.58")
    let assessment = StrikeAssessment.evaluate(
        spot: 68_420, strike: 68_400, entryPrice: entry, secondsRemaining: 210
    )
    return StrikeAuditRequest.make(
        symbol: "BTC",
        assessment: assessment,
        spot: 68_420,
        strike: 68_400,
        entryPrice: entry,
        secondsRemaining: 210,
        momentumDirection: "BULLISH",
        momentumScore: 82,
        side: .yes
    )
}

@Test func requestCarriesSystemComputedNumbersNotModelMath() {
    let req = sampleRequest()
    #expect(req.symbol == "BTC")
    #expect(req.strikeDistanceUSD == 20)
    #expect(req.computedBreakeven == 0.60)     // from StrikeMath, not the model
    #expect(req.computedMoneyness == "ITM")    // from StrikeMath, not the model
    #expect(req.indicativeSide == "YES")
    #expect(req.exchangeFee == 0.02)
}

@Test func promptDemandsStrictJsonAndForbidsPriceTargets() {
    let prompt = StrikeAuditPrompt.build(request: sampleRequest())
    #expect(prompt.contains("regime_summary"))
    #expect(prompt.contains("advisory_label"))
    #expect(prompt.contains("BTC"))
    #expect(prompt.lowercased().contains("do not recompute"))
    #expect(prompt.contains("Do NOT output entry or exit price levels"))
    #expect(prompt.contains("System-computed breakeven: 0.6"))
}

@Test func decodeValidAdvice() {
    let json = #"{"regime_summary":"Trending","risk_warning":"Late decay risk","checklist":["a","b"],"coach_note":"ok","advisory_label":"PROCEED"}"#
    let advice = StrikeAuditAdvice.decode(fromJSON: json)
    #expect(advice?.regimeSummary == "Trending")
    #expect(advice?.riskWarning == "Late decay risk")
    #expect(advice?.checklist == ["a", "b"])
    #expect(advice?.advisoryLabel == .proceed)
}

@Test func decodeRejectsMalformedOrEmpty() {
    #expect(StrikeAuditAdvice.decode(fromJSON: "not json") == nil)
    #expect(StrikeAuditAdvice.decode(fromJSON: "{}") == nil)
    #expect(StrikeAuditAdvice.decode(fromJSON: #"{"checklist":[]}"#) == nil)
}

@Test func advisoryLabelDefaultsToCautionNeverGreenLight() {
    #expect(AdvisoryGate.normalize("PROCEED") == .proceed)
    #expect(AdvisoryGate.normalize("proceed") == .proceed)
    #expect(AdvisoryGate.normalize("PASS") == .pass)
    #expect(AdvisoryGate.normalize("REDUCE_SIZE") == .caution)
    #expect(AdvisoryGate.normalize(nil) == .caution)
    #expect(AdvisoryGate.normalize("garbage") == .caution)
}

@Test func buildRequestDeepSeekShape() throws {
    let payload = try LLMStrikeAuditor.buildRequest(
        request: sampleRequest(), provider: .deepseek, apiKey: "sk-test"
    )
    #expect(payload.url.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(payload.headers["Authorization"] == "Bearer sk-test")
    let body = String(decoding: payload.body, as: UTF8.self)
    #expect(body.contains("deepseek-chat"))
    #expect(body.contains("json_object"))
}

@Test func buildRequestGeminiShape() throws {
    let payload = try LLMStrikeAuditor.buildRequest(
        request: sampleRequest(), provider: .gemini, apiKey: "g-key"
    )
    #expect(payload.url.absoluteString.contains("generativelanguage.googleapis.com"))
    #expect(payload.url.absoluteString.contains("gemini-2.5-flash"))
    #expect(payload.url.absoluteString.contains("key=") == false)
    #expect(payload.headers["x-goog-api-key"] == "g-key")
    #expect(payload.headers["Authorization"] == nil)
    let body = String(decoding: payload.body, as: UTF8.self)
    #expect(body.contains("responseMimeType"))
}

@Test func extractContentFromBothEnvelopes() throws {
    let deepseek = #"{"choices":[{"message":{"content":"{\"regime_summary\":\"x\"}"}}]}"#
    let d = try LLMStrikeAuditor.extractContent(data: Data(deepseek.utf8), provider: .deepseek)
    #expect(d.contains("regime_summary"))

    let gemini = #"{"candidates":[{"content":{"parts":[{"text":"{\"regime_summary\":\"y\"}"}]}}]}"#
    let g = try LLMStrikeAuditor.extractContent(data: Data(gemini.utf8), provider: .gemini)
    #expect(g.contains("regime_summary"))
}

@Test func auditReturnsAdviceThroughInjectedTransport() async throws {
    let envelope = #"{"choices":[{"message":{"content":"{\"regime_summary\":\"Trending\",\"risk_warning\":\"w\",\"checklist\":[\"a\"],\"coach_note\":\"c\",\"advisory_label\":\"CAUTION\"}"}}]}"#
    let auditor = LLMStrikeAuditor(transport: StubTransport { _, _, _ in Data(envelope.utf8) })
    let advice = try await auditor.audit(request: sampleRequest(), provider: .deepseek, apiKey: "k")
    #expect(advice.regimeSummary == "Trending")
    #expect(advice.advisoryLabel == .caution)
}

@Test func auditThrowsOnUnparseableAdviceSoCallerFallsBack() async throws {
    let envelope = #"{"choices":[{"message":{"content":"totally not json"}}]}"#
    let auditor = LLMStrikeAuditor(transport: StubTransport { _, _, _ in Data(envelope.utf8) })
    await #expect(throws: LLMAuditorError.invalidAdvice) {
        _ = try await auditor.audit(request: sampleRequest(), provider: .deepseek, apiKey: "k")
    }
}
