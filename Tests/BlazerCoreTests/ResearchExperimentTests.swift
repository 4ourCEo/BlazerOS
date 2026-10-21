import Foundation
import Testing
@testable import BlazerCore

private func input(_ asset: String = "EUR/USD") -> StrategyEngine.MarketInput {
    StrategyEngine.MarketInput(
        asset: asset, source: "test", candles1m: [], candles5m: [],
        lastPrice: 1.1, bid: 1.0999, ask: 1.1001, spread: 0.0002,
        expirySeconds: 60
    )
}

private func event(
    index: Int,
    side: String,
    policy: String = "baseline",
    accepted: Bool
) throws -> ResearchEvent {
    let now = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
    let signal = EngineSignal(
        asset: "EUR/USD", cabinetSide: side,
        call: side == "HIGH" ? "CALL" : (side == "LOW" ? "PUT" : "WAIT"),
        why: "test", price: 1.1, entryPrice: 1.1,
        confidence: side == "WAIT" ? 0 : 76,
        asOfMs: now.timeIntervalSince1970 * 1000,
        policy: policy,
        features: ScanFeatures(
            atr1m: 0.0005, atr5m: 0.0005, efficiency: 0, slopeATR: 0,
            spreadATR: 0, rangeATR: 0, bodyATR: 0, upperWickShare: 0,
            lowerWickShare: 0, twoSidedSweep: false, sweep: nil,
            structureBreak: nil, regime: "test"
        )
    )
    let quote = LiveQuote(
        asset: "EUR/USD", bid: 1.0999, ask: 1.1001, mid: 1.1,
        asOfMs: now.timeIntervalSince1970 * 1000, source: "test"
    )
    let event = try ResearchEvent(
        input: input(), signal: signal, sourceKind: "synthetic",
        capturedAt: now, entryQuote: accepted ? quote : nil
    )
    return event
}

@Test func chronologicalExperimentIncludesBothDirectionsAndHeldOutCohort() throws {
    var events: [ResearchEvent] = []
    var outcomes: [ResearchOutcome] = []
    for index in 0..<10 {
        let side = index.isMultiple(of: 2) ? "HIGH" : "LOW"
        let captured = try event(index: index, side: side, accepted: true)
        events.append(captured)
        outcomes.append(
            ResearchOutcome(
                eventID: captured.id, horizon: 60,
                targetExpiry: captured.capturedAt.addingTimeInterval(60),
                observedAt: captured.capturedAt.addingTimeInterval(61),
                quoteTimeMs: captured.capturedAt.addingTimeInterval(61).timeIntervalSince1970 * 1000,
                exitPrice: 1.1005,
                resolution: index < 7 ? .hit : .miss,
                reason: nil,
                labelSource: "synthetic"
            )
        )
    }
    let experiment = ResearchExperiment(
        name: "test", policy: "baseline", engineSHA: EngineIdentity.pinnedSHA1,
        splitFraction: 0.7, acceptanceCriteria: "a", rejectionCriteria: "r"
    )
    let report = ResearchEvaluator.evaluate(experiment: experiment, events: events, outcomes: outcomes)
    #expect(report.train.candidates == 7)
    #expect(report.test.candidates == 3)
    #expect(report.train.highSignals > 0)
    #expect(report.train.lowSignals > 0)
    #expect(report.highLowBalanced)
    #expect(report.train.winRate == 1.0)
    #expect(report.test.winRate == 0.0)
}

@Test func experimentStoreRoundTripsVersionedRecords() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-experiment-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let store = ResearchStore(root: root)
    let experiment = ResearchExperiment(
        name: "baseline holdout", policy: "baseline",
        engineSHA: EngineIdentity.pinnedSHA1,
        acceptanceCriteria: "positive held-out expectancy",
        rejectionCriteria: "non-positive held-out expectancy"
    )
    try await store.record(experiment)
    let loaded = try await store.experiments()
    #expect(loaded.count == 1)
    #expect(loaded[0].id == experiment.id)
    #expect(loaded[0].policy == experiment.policy)
    #expect(loaded[0].engineSHA == experiment.engineSHA)
}
