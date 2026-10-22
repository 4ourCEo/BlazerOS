import Foundation
import Testing
@testable import BlazerCore

// Boundary contract for the pinned JS engine. These run in the package test target, so
// `swift test` — and CI — enforce them. The iPhone-only EngineParityTests file is not
// part of this target and therefore never ran on the main developer path.

private let clock = Date(timeIntervalSince1970: 1_790_000_000.123)

private func trendInput(down: Bool = false) -> StrategyEngine.MarketInput {
    let sign = down ? -1.0 : 1.0
    let now = clock.timeIntervalSince1970 * 1000
    let pip = Assets.pipScale(for: "EUR/USD")
    let final = 1.1 + sign * 120 * pip * 3
    func bars(count: Int, step: Double, delta: Double) -> [StrategyEngine.CandlePayload] {
        (0..<count).map { i in
            let open = final - sign * Double(count - i) * delta
            let close = open + sign * delta
            return .init(time: now - Double(count - i) * step, open: open,
                high: max(open, close) + pip * 0.1, low: min(open, close) - pip * 0.1, close: close)
        }
    }
    return .init(asset: "EUR/USD", source: "test",
        candles1m: bars(count: 120, step: 60000, delta: pip),
        candles5m: bars(count: 120, step: 300000, delta: pip * 3),
        lastPrice: final, bid: final - pip * 0.1, ask: final + pip * 0.1, spread: pip * 0.2,
        expirySeconds: 60, quoteAsOfMs: now, evaluatedAtMs: now)
}

// MARK: - Identity gate

@Test func engineBootsVerifiedAgainstPin() async {
    let boot = await StrategyEngine.boot()
    #expect(boot.ok, "\(boot.detail ?? "boot failed")")
    #expect(StrategyEngine.isPreflighted)
    #expect(StrategyEngine.engineHealth.sha == EngineIdentity.pinnedSHA1)
    #expect(StrategyEngine.loadedOrigin == "package-bundle")
    #expect(StrategyEngine.controlArtifactMatchesPin, "control artifact must still hash to controlSHA1")
}

@Test func tamperedEngineSourceIsRefusedBeforeAContextExists() {
    let original = StrategyEngine.bundleSource() ?? ""
    #expect(!original.isEmpty)

    let outcome = StrategyEngine.loadOutcome(source: original + "\n// tampered", origin: "test")
    #expect(outcome.context == nil)
    guard case .failed(let reason) = outcome.health else {
        Issue.record("Expected a failed health, got \(outcome.health)")
        return
    }
    #expect(reason.contains("hash mismatch"))
    #expect(outcome.error?.contains("hash mismatch") == true)
}

@Test func unverifiedSourceStillReportsTheLoadedHash() {
    let original = StrategyEngine.bundleSource() ?? ""
    let tampered = original + "\n// tampered"
    let expected = EngineIdentity.sha1Hex(of: tampered)
    guard case .mismatch(let loaded, let pinned) = EngineIdentity.verify(source: tampered) else {
        Issue.record("Expected a mismatch")
        return
    }
    #expect(loaded == expected)
    #expect(pinned == EngineIdentity.pinnedSHA1)
}

// MARK: - Sealed decisions

@Test func goldenDecisionIsSealed() async throws {
    let input = GoldenFixture.market()
    let result = try await StrategyEngine.evaluate(input: input)
    let bars = GoldenFixture.frozenBars(from: input)
    let commit = ScanKernel.commit(
        from: result.signal,
        bars: bars,
        scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(result.signal.cabinetSide == "WAIT")
    #expect(commit.engineCall == "WAIT")
    #expect(commit.fingerprint == "CE239CDB")
    #expect(commit.score == 68)
    #expect(!commit.evidence.isEmpty)
}

@Test func trendDecisionsAreSealed() async throws {
    let up = try await StrategyEngine.evaluate(input: trendInput()).signal
    let down = try await StrategyEngine.evaluate(input: trendInput(down: true)).signal

    #expect(up.cabinetSide == "HIGH")
    #expect(up.call == "TAP HIGH")
    #expect(up.confidence == 96)
    #expect(down.cabinetSide == "LOW")
    #expect(down.call == "TAP LOW")
    #expect(down.confidence == 96)
}

// MARK: - Input and contract validation

@Test func malformedInputIsRejectedBeforeTheEngineSeesIt() async {
    var empty = trendInput()
    empty.candles1m = []
    await #expect(throws: ScanError.self) { try await StrategyEngine.evaluate(input: empty) }

    var badOHLC = trendInput()
    badOHLC.candles1m[10].close = badOHLC.candles1m[10].high + 1
    await #expect(throws: ScanError.self) { try await StrategyEngine.evaluate(input: badOHLC) }

    var duplicated = trendInput()
    duplicated.candles1m[10].time = duplicated.candles1m[9].time
    await #expect(throws: ScanError.self) { try await StrategyEngine.evaluate(input: duplicated) }

    var nonFinite = trendInput()
    nonFinite.bid = .nan
    await #expect(throws: ScanError.self) { try await StrategyEngine.evaluate(input: nonFinite) }
}

@Test func contractViolationsAreRejectedWithContractErrors() throws {
    let input = trendInput()

    var signal = EngineSignal(asset: "EUR/USD", cabinetSide: "BUY", call: "TAP HIGH", why: "x", price: 1.1)
    #expect(throws: ScanError.self) {
        try StrategyEngine.validate(result: StrategyEngine.EvaluateResult(signal: signal, candles: nil, source: nil), for: input)
    }

    signal.cabinetSide = "HIGH"
    signal.call = "WAIT"
    #expect(throws: ScanError.self) {
        try StrategyEngine.validate(result: StrategyEngine.EvaluateResult(signal: signal, candles: nil, source: nil), for: input)
    }

    signal.call = "TAP HIGH"
    signal.confidence = 140
    #expect(throws: ScanError.self) {
        try StrategyEngine.validate(result: StrategyEngine.EvaluateResult(signal: signal, candles: nil, source: nil), for: input)
    }

    signal.confidence = 80
    signal.directionScore = 200
    #expect(throws: ScanError.self) {
        try StrategyEngine.validate(result: StrategyEngine.EvaluateResult(signal: signal, candles: nil, source: nil), for: input)
    }
}

// MARK: - Slippage gate

@Test func slippageGateFailsClosedWithAReason() {
    let invalid = StrategyEngine.slippageGate(
        asset: "EUR/USD", side: "HIGH", strike: .nan, bid: 1.0850, ask: 1.0852
    )
    #expect(invalid.veto)
    #expect(invalid.reason == "Invalid quote")

    let valid = StrategyEngine.slippageGate(
        asset: "EUR/USD", side: "HIGH", strike: 1.0850, bid: 1.0849, ask: 1.0851
    )
    #expect(valid.veto == false)
    #expect(valid.reason == nil)
}

// MARK: - Control artifact

@Test func controlArtifactIsPinnedAndEvaluates() async throws {
    #expect(StrategyEngine.controlArtifactMatchesPin)

    let input = GoldenFixture.market()
    let control = try await StrategyEngine.evaluateControl(input: input).signal
    let current = try await StrategyEngine.evaluate(input: input).signal

    #expect(control.policy == "control")
    #expect(control.cabinetSide == current.cabinetSide)
    #expect(control.features != nil, "control borrows the shared input feature block")
}
