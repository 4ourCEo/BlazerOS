import Foundation
import Testing
@testable import BlazerCore

private let replaySignalTime = Date(timeIntervalSince1970: 2_100_000_000)

private func replayInput() -> StrategyEngine.MarketInput {
    let bars = (0..<30).map { index in
        let time = replaySignalTime.addingTimeInterval(-Double((30 - index) * 60))
            .timeIntervalSince1970 * 1_000
        let open = 1.1000 + Double(index) * 0.00001
        return StrategyEngine.CandlePayload(time: time, open: open,
            high: open + 0.00003, low: open - 0.00001, close: open + 0.00002)
    }
    return StrategyEngine.MarketInput(asset: "EUR/USD", source: "oanda-history",
        candles1m: bars, candles5m: bars, lastPrice: 1.101,
        bid: 1.1009, ask: 1.1011, spread: 0.0002,
        expirySeconds: 60,
        quoteAsOfMs: replaySignalTime.timeIntervalSince1970 * 1_000,
        evaluatedAtMs: replaySignalTime.timeIntervalSince1970 * 1_000,
        policy: .baseline)
}

private let replayHigh: StrategyValidationEngine.Evaluator = { input in
    EngineSignal(asset: input.asset, cabinetSide: "HIGH", call: "CALL", why: "fixture",
        price: input.lastPrice, confidence: 0.8, asOfMs: input.evaluatedAtMs,
        source: input.source, policy: input.policy?.rawValue)
}

@Test func spotReplayRequiresBidAskAtEntryAndExitAndChargesAdditionalCost() async throws {
    let entry = replaySignalTime.addingTimeInterval(3)
    let exit = entry.addingTimeInterval(60)
    let observations = [
        ValidationPriceObservation(instrumentID: "oanda:EUR/USD", venueID: "OANDA",
            observedAt: entry, price: 1.1000, bid: 1.0999, ask: 1.1001,
            source: "oanda-history", authority: .oandaReference),
        ValidationPriceObservation(instrumentID: "oanda:EUR/USD", venueID: "OANDA",
            observedAt: exit, price: 1.1010, bid: 1.1009, ask: 1.1011,
            source: "oanda-history", authority: .oandaReference)
    ]
    let item = StrategyValidationCase(id: "spot", stage: .historicalReplay,
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, signalTimestamp: replaySignalTime,
        engineSHA: EngineIdentity.pinnedSHA1, input: replayInput(),
        signalPriceAuthority: .oandaReference, observations: observations,
        provenance: "authentic historical bid-ask fixture")
    let records = try await SpotFXHistoricalReplay.replay(cases: [item], strategyID: "baseline",
        configuration: .init(entryDelaySeconds: 3, horizonSeconds: 60,
            units: 100_000, additionalCostPerUnit: 0.00001), evaluator: replayHigh)
    let record = try #require(records.first)
    #expect(record.status == .valid)
    #expect(record.entryPrice == 1.1001)
    #expect(record.exitPrice == 1.1009)
    #expect(abs((record.grossPnl ?? .nan) - 80) < 0.000001)
    #expect(record.transactionCost == 1)
    #expect(abs((record.netPnl ?? .nan) - 79) < 0.000001)
}

@Test func spotReplayRefusesMidpointOnlyHistoricalOutcomes() async throws {
    let item = StrategyValidationCase(id: "midpoint-only", stage: .historicalReplay,
        instrumentID: "oanda:EUR/USD", engineAsset: "EUR/USD", venueID: "OANDA",
        marketKind: .standard, signalTimestamp: replaySignalTime,
        engineSHA: EngineIdentity.pinnedSHA1, input: replayInput(),
        observations: [
            ValidationPriceObservation(instrumentID: "oanda:EUR/USD", venueID: "OANDA",
                observedAt: replaySignalTime.addingTimeInterval(3), price: 1.1,
                source: "oanda-midpoint-proxy", authority: .oandaReference),
            ValidationPriceObservation(instrumentID: "oanda:EUR/USD", venueID: "OANDA",
                observedAt: replaySignalTime.addingTimeInterval(63), price: 1.101,
                source: "oanda-midpoint-proxy", authority: .oandaReference)
        ], provenance: "legacy midpoint archive")
    let records = try await SpotFXHistoricalReplay.replay(cases: [item], strategyID: "baseline",
        evaluator: replayHigh)
    let record = try #require(records.first)
    #expect(record.status == .unresolved)
    #expect(record.netPnl == nil)
    #expect(record.reason == "Executable bid/ask entry observation missing")
}
