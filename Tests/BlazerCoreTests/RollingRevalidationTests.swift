import Foundation
import Testing
@testable import BlazerCore

private let rollingStart = Date(timeIntervalSince1970: 1_800_000_000)
private func rollingBaseline() -> RollingRevalidationBaseline {
    .init(parentFullFingerprint: "parent-fingerprint", originalScanAt: rollingStart, marketAsset: "EUR/USD", side: "HIGH",
          entryReference: 100, maximumAbsoluteDisplacement: 2, expirySeconds: 60,
          engineVersion: "engine-a", policyVersion: "policy-a", sourceID: "feed-a",
          venueID: "venue-a", instrumentID: "EURUSD")
}
private func rollingInput(age: Double = 1, quoteAge: Double = 0.5, price: Double = 101,
                          side: String = "HIGH", qualified: Bool = true, source: String = "feed-a",
                          venue: String = "venue-a", instrument: String = "EURUSD",
                          asset: String = "EUR/USD", expirySeconds: Int = 60,
                          locks: RollingRevalidationLocks = .init(
                            entry: false, settlement: false, activePosition: false, awaitingOutcome: false),
                          digest: String = "updated-digest") -> RollingRevalidationInput {
    let evaluated = rollingStart.addingTimeInterval(age)
    return .init(marketAsset: asset, quotePrice: price, quoteTimestamp: evaluated.addingTimeInterval(-quoteAge),
                 receivedAt: evaluated, evaluatedAt: evaluated, side: side, qualified: qualified,
                 updatedInputDigest: digest, sourceID: source, venueID: venue, instrumentID: instrument,
                 expirySeconds: expirySeconds, locks: locks)
}
private func check(_ input: RollingRevalidationInput, window: RollingRevalidationWindow = .seconds20) -> RollingRevalidationResult {
    RollingRevalidation.evaluate(baseline: rollingBaseline(), window: window, input: input,
                                 engineVersion: "engine-a", policyVersion: "policy-a")
}

@Test func rollingRevalidationAcceptsResearchCandidateWithoutEntryAuthority() {
    let result = check(rollingInput())
    #expect(result.acceptedForResearch)
    #expect(result.researchOnly)
    #expect(!result.mayAuthorizeEntry)
    #expect(result.parentFullFingerprint == "parent-fingerprint")
}

@Test func ageUsesSelectedWindowAndCannotResurrectAfterTwentySeconds() {
    #expect(check(rollingInput(age: 8), window: .seconds8).acceptedForResearch)
    #expect(check(rollingInput(age: 8.01), window: .seconds8).rejectionReasons.contains(.originalScanTooOld))
    #expect(check(rollingInput(age: 8.01), window: .seconds12).acceptedForResearch)
    #expect(check(rollingInput(age: 20), window: .seconds20).acceptedForResearch)
    #expect(check(rollingInput(age: 20.01), window: .seconds20).rejectionReasons.contains(.originalScanTooOld))
}

@Test func rejectsSideQualificationIdentityExpiryAndLocks() {
    #expect(check(rollingInput(side: "LOW")).rejectionReasons.contains(.sideMismatch))
    #expect(check(rollingInput(qualified: false)).rejectionReasons.contains(.notQualified))
    #expect(check(rollingInput(source: "other")).rejectionReasons.contains(.sourceMismatch))
    #expect(check(rollingInput(venue: "other")).rejectionReasons.contains(.venueMismatch))
    #expect(check(rollingInput(instrument: "GBPUSD")).rejectionReasons.contains(.instrumentMismatch))
    #expect(check(rollingInput(expirySeconds: 180)).rejectionReasons.contains(.expiryMismatch))
    #expect(check(rollingInput(asset: "EURUSD_otc")).rejectionReasons.contains(.assetMismatch))
    let lockSets: [RollingRevalidationLocks] = [
        .init(entry: true, settlement: false, activePosition: false, awaitingOutcome: false),
        .init(entry: false, settlement: true, activePosition: false, awaitingOutcome: false),
        .init(entry: false, settlement: false, activePosition: true, awaitingOutcome: false),
        .init(entry: false, settlement: false, activePosition: false, awaitingOutcome: true)
    ]
    #expect(lockSets.allSatisfy { !check(rollingInput(locks: $0)).acceptedForResearch })
}

@Test func rejectsStaleAndInvalidOrOutsideEnvelopeQuotes() {
    #expect(check(rollingInput(quoteAge: 2.01)).rejectionReasons.contains(.staleQuote))
    #expect(check(rollingInput(price: 102.01)).rejectionReasons.contains(.priceOutsideEnvelope))
    #expect(check(rollingInput(price: .infinity)).rejectionReasons.contains(.invalidQuote))
    let reversedTimeline = RollingRevalidationInput(marketAsset: "EUR/USD", quotePrice: 101,
        quoteTimestamp: rollingStart.addingTimeInterval(2), receivedAt: rollingStart.addingTimeInterval(1),
        evaluatedAt: rollingStart.addingTimeInterval(1), side: "HIGH", qualified: true,
        updatedInputDigest: "digest", sourceID: "feed-a", venueID: "venue-a", instrumentID: "EURUSD",
        expirySeconds: 60, locks: .init(entry: false, settlement: false, activePosition: false, awaitingOutcome: false))
    #expect(check(reversedTimeline).rejectionReasons.contains(.quoteTimestampInFuture))
}

@Test func checkpointIdentityIsDeterministicDistinctAndParentIsImmutable() {
    let baseline = rollingBaseline()
    let input = rollingInput()
    let first = RollingRevalidation.evaluate(baseline: baseline, window: .seconds12, input: input,
        engineVersion: "engine-a", policyVersion: "policy-a")
    let repeatResult = RollingRevalidation.evaluate(baseline: baseline, window: .seconds12, input: input,
        engineVersion: "engine-a", policyVersion: "policy-a")
    let otherCheckpoint = RollingRevalidation.evaluate(baseline: baseline, window: .seconds16,
        input: rollingInput(age: 2), engineVersion: "engine-a", policyVersion: "policy-a")
    let locked = RollingRevalidation.evaluate(baseline: baseline, window: .seconds12,
        input: rollingInput(locks: .init(entry: true, settlement: false, activePosition: false, awaitingOutcome: false)),
        engineVersion: "engine-a", policyVersion: "policy-a")
    #expect(first == repeatResult)
    #expect(first.identity != otherCheckpoint.identity)
    #expect(first.identity != locked.identity)
    #expect(first.parentFullFingerprint == baseline.parentFullFingerprint)
    #expect(baseline.originalScanAt == rollingStart)
}

@Test func rollingCheckpointsPersistOnlyToResearchArchive() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-rolling-research-\(UUID().uuidString)")
    let store = ResearchStore(root: root)
    let result = check(rollingInput())
    try await store.record(result)
    try await store.record(result)
    #expect(try await store.rollingRevalidationResults() == [result])
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("ledger.csv").path))
}

@Test func revalidationCallsPinnedDeterministicEngineOnFreshInput() async throws {
    let boot = await StrategyEngine.boot()
    #expect(boot.ok)
    let evaluatedAt = rollingStart.addingTimeInterval(12)
    let nowMs = evaluatedAt.timeIntervalSince1970 * 1_000
    let pip = 0.0001
    let final = 1.136
    func bars(count: Int, step: Double, delta: Double) -> [StrategyEngine.CandlePayload] {
        (0..<count).map { index in
            let open = final - Double(count - index) * delta
            let close = open + delta
            return .init(time: nowMs - Double(count - index) * step, open: open,
                         high: close + pip * 0.1, low: open - pip * 0.1, close: close)
        }
    }
    let marketInput = StrategyEngine.MarketInput(
        asset: "EUR/USD", source: "feed-a", candles1m: bars(count: 120, step: 60_000, delta: pip),
        candles5m: bars(count: 120, step: 300_000, delta: pip * 3), lastPrice: final,
        bid: final - pip * 0.1, ask: final + pip * 0.1, spread: pip * 0.2,
        expirySeconds: 60, quoteAsOfMs: nowMs, evaluatedAtMs: nowMs
    )
    let engine = EngineIdentity.loadedSHA1() ?? "unverified"
    let baseline = RollingRevalidationBaseline(
        parentFullFingerprint: "frozen-original", originalScanAt: evaluatedAt.addingTimeInterval(-12),
        marketAsset: "EUR/USD", side: "HIGH", entryReference: final,
        maximumAbsoluteDisplacement: pip, expirySeconds: 60, engineVersion: engine,
        policyVersion: "baseline", sourceID: "feed-a", venueID: "reference", instrumentID: "EUR/USD"
    )
    let result = try await RollingRevalidation.revalidate(
        baseline: baseline, window: .seconds12, marketInput: marketInput,
        sourceID: "feed-a", venueID: "reference", instrumentID: "EUR/USD",
        receivedAt: evaluatedAt, evaluatedAt: evaluatedAt,
        locks: .init(entry: false, settlement: false, activePosition: false, awaitingOutcome: false)
    )
    #expect(result.engineVersion == engine)
    #expect(result.policyVersion == "baseline")
    #expect(result.parentFullFingerprint == "frozen-original")
    #expect(result.researchOnly)
    #expect(!result.mayAuthorizeEntry)

    var futureInput = marketInput
    futureInput.candles1m[futureInput.candles1m.count - 1].time = nowMs + 1
    let futureResult = try await RollingRevalidation.revalidate(
        baseline: baseline, window: .seconds12, marketInput: futureInput,
        sourceID: "feed-a", venueID: "reference", instrumentID: "EUR/USD",
        receivedAt: evaluatedAt, evaluatedAt: evaluatedAt,
        locks: .init(entry: false, settlement: false, activePosition: false, awaitingOutcome: false)
    )
    #expect(!futureResult.acceptedForResearch)
    #expect(futureResult.rejectionReasons.contains(.invalidMarketData))

    var incompleteInput = marketInput
    incompleteInput.candles1m[incompleteInput.candles1m.count - 1].time = nowMs - 30_000
    let incompleteResult = try await RollingRevalidation.revalidate(
        baseline: baseline, window: .seconds12, marketInput: incompleteInput,
        sourceID: "feed-a", venueID: "reference", instrumentID: "EUR/USD",
        receivedAt: evaluatedAt, evaluatedAt: evaluatedAt,
        locks: .init(entry: false, settlement: false, activePosition: false, awaitingOutcome: false)
    )
    #expect(!incompleteResult.acceptedForResearch)
    #expect(incompleteResult.rejectionReasons.contains(.invalidMarketData))
}
