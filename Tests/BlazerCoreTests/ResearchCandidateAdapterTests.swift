import Foundation
import Testing
@testable import BlazerCore

private func adapterM5(_ time: Double, open: Double = 1.0, high: Double = 1.2,
                       low: Double = 0.8, close: Double = 1.1) -> StrategyEngine.CandlePayload {
    StrategyEngine.CandlePayload(time: time, open: open, high: high, low: low, close: close)
}

private func auctionFailureMarketInput(now: Date, m15StartOffsetMs: Double) -> StrategyEngine.MarketInput {
    let start = now.addingTimeInterval(-14 * 60)
    var m1: [StrategyEngine.CandlePayload] = (0..<12).map { index in
        let priceTime = (start.addingTimeInterval(Double(index * 60)).timeIntervalSince1970) * 1_000
        return StrategyEngine.CandlePayload(time: priceTime, open: 150.05,
            high: 150.10, low: 150.00, close: 150.05)
    }
    m1.append(StrategyEngine.CandlePayload(
        time: (start.addingTimeInterval(12 * 60).timeIntervalSince1970) * 1_000,
        open: 150.04, high: 150.06, low: 149.99, close: 150.03))
    m1.append(StrategyEngine.CandlePayload(
        time: (start.addingTimeInterval(13 * 60).timeIntervalSince1970) * 1_000,
        open: 150.03, high: 150.06, low: 150.02, close: 150.04))
    m1.append(StrategyEngine.CandlePayload(
        time: (start.addingTimeInterval(14 * 60).timeIntervalSince1970) * 1_000,
        open: 150.04, high: 150.06, low: 150.03, close: 150.05))
    let bucket = floor(now.timeIntervalSince1970 / 900) * 900 * 1_000 + m15StartOffsetMs
    let m5 = (0..<3).map { index in
        StrategyEngine.CandlePayload(time: bucket + Double(index * 300_000),
            open: 150.05, high: 150.10, low: 150.00, close: 150.05)
    }
    return StrategyEngine.MarketInput(asset: "USD/JPY", source: "oanda-live",
        candles1m: m1, candles5m: m5, lastPrice: 150.05, bid: 150.04, ask: 150.05,
        spread: 0.01, expirySeconds: 60,
        quoteAsOfMs: now.timeIntervalSince1970 * 1_000,
        evaluatedAtMs: now.timeIntervalSince1970 * 1_000, policy: .baseline)
}

private func candidate001AdapterMarketInput() -> StrategyEngine.MarketInput {
    let now = Date()
    let origin = floor(now.timeIntervalSince1970 / 900) * 900 - 1_800
    var rows = Array(repeating: [1.0, 1.02, 0.99, 1.0], count: 15)
    rows[2] = [0.99, 1.01, 0.98, 1.0]
    rows[4] = [1.03, 1.05, 1.0, 1.04]
    rows[8] = [1.0, 1.04, 0.99, 1.02]
    rows[10] = [1.05, 1.10, 1.03, 1.09]
    rows[11] = [1.03, 1.04, 1.02, 1.035]
    rows[12] = [1.045, 1.07, 1.045, 1.06]
    rows[13] = [1.06, 1.13, 1.05, 1.12]
    rows[14] = [1.05, 1.06, 1.044, 1.047]
    let candles1m = rows.enumerated().map { index, row in
        StrategyEngine.CandlePayload(time: (origin + Double(index * 60)) * 1_000,
            open: row[0], high: row[1], low: row[2], close: row[3])
    }
    let candles5m = [
        StrategyEngine.CandlePayload(time: origin * 1_000,
            open: 1.0, high: 1.02, low: 0.99, close: 1.01),
        StrategyEngine.CandlePayload(time: (origin + 300) * 1_000,
            open: 1.01, high: 1.03, low: 1.0, close: 1.02),
        StrategyEngine.CandlePayload(time: (origin + 600) * 1_000,
            open: 1.02, high: 1.04, low: 1.01, close: 1.03),
    ]
    let nowMs = now.timeIntervalSince1970 * 1_000
    return StrategyEngine.MarketInput(asset: "EUR/USD", source: "oanda-live",
        candles1m: candles1m, candles5m: candles5m, lastPrice: 1.047,
        bid: 1.0469, ask: 1.047, spread: 0.0001, expirySeconds: 60,
        quoteAsOfMs: nowMs, evaluatedAtMs: nowMs, policy: .baseline)
}

@Test func oldCandidateArchiveDecodesWithoutNewProvenanceFields() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let candidate = AdaptiveOpportunityCandidate(id: "old", strategyID: "legacy",
        strategyVersion: "v1", instrument: "EUR/USD", provider: "OANDA_LIVE",
        direction: .wait, evaluationStartedAt: date, evaluationCompletedAt: date,
        state: .rejected, provenance: "old-record", freshness: .fresh,
        spreadState: .unavailable)
    let encoded = try JSONEncoder().encode(candidate)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "effectiveConfigurationSHA256")
    object.removeValue(forKey: "evaluatorCodeSHA256")
    object.removeValue(forKey: "adapterCodeSHA256")
    object.removeValue(forKey: "selectorCodeSHA256")
    let oldJSON = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(AdaptiveOpportunityCandidate.self, from: oldJSON)
    #expect(decoded.effectiveConfigurationSHA256 == nil)
    #expect(decoded.evaluatorCodeSHA256 == nil)
    #expect(decoded.adapterCodeSHA256 == nil)
    #expect(decoded.selectorCodeSHA256 == nil)
}

@Test func signalFreshnessGateStartsAtM1CloseAndIncludesOnlyTheTTLBoundary() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let close = start.addingTimeInterval(60)
    let ttl: TimeInterval = 300
    #expect(!AdaptiveOpportunityAdapters.eventIsWithinSignalTTL(
        start: start, asOf: close.addingTimeInterval(-0.001), ttlSeconds: ttl))
    #expect(AdaptiveOpportunityAdapters.eventIsWithinSignalTTL(
        start: start, asOf: close, ttlSeconds: ttl))
    #expect(AdaptiveOpportunityAdapters.eventIsWithinSignalTTL(
        start: start, asOf: close.addingTimeInterval(ttl), ttlSeconds: ttl))
    #expect(!AdaptiveOpportunityAdapters.eventIsWithinSignalTTL(
        start: start, asOf: close.addingTimeInterval(ttl + 0.001), ttlSeconds: ttl))
}

@Test func candidate001AdapterTTLUsesSameIdentifiedEventAtEveryBoundary() throws {
    let fullInput = candidate001AdapterMarketInput()
    let m1 = fullInput.candles1m.map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let m15 = AdaptiveOpportunityAdapters.aggregateM15(fullInput.candles5m).map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let adapterConfiguration = Candidate001Configuration(requireM15Confirmation: true,
        signalFreshnessSeconds: 300)
    let identifiedEvent = try #require(Candidate001Analyzer.analyze(candles: m1,
        m15Candles: m15, configuration: adapterConfiguration).first {
            $0.terminalState == .candidateTriggered && $0.direction == .bullish
                && $0.m15Confirmed
        })
    let eventID = "candidate001:\(identifiedEvent.id)"
    let triggerStart = try #require(identifiedEvent.triggeredAt)
    let availableAt = triggerStart.addingTimeInterval(60)
    let origin = Date(timeIntervalSince1970: fullInput.candles1m[0].time / 1_000)
    let expectedM15Start = Candidate001Analyzer.expectedLatestCompletedM15Start(
        m1Close: availableAt)
    #expect(expectedM15Start == origin)
    #expect(m15.contains { $0.time == expectedM15Start })
    let ttl = TimeInterval(adapterConfiguration.resolvedSignalFreshnessSeconds)
    let boundedInput = StrategyEngine.MarketInput(asset: fullInput.asset,
        source: fullInput.source,
        candles1m: fullInput.candles1m.filter { $0.time <= triggerStart.timeIntervalSince1970 * 1_000 },
        candles5m: fullInput.candles5m.filter { $0.time < availableAt.timeIntervalSince1970 * 1_000 },
        lastPrice: fullInput.lastPrice, bid: fullInput.bid, ask: fullInput.ask,
        spread: fullInput.spread, expirySeconds: fullInput.expirySeconds,
        quoteAsOfMs: fullInput.quoteAsOfMs, evaluatedAtMs: fullInput.evaluatedAtMs,
        policy: fullInput.policy)
    let containsEvent: (Date) -> Bool = { asOf in
        let inputAtAsOf = StrategyEngine.MarketInput(asset: boundedInput.asset,
            source: boundedInput.source, candles1m: boundedInput.candles1m,
            candles5m: boundedInput.candles5m, lastPrice: boundedInput.lastPrice,
            bid: boundedInput.bid, ask: boundedInput.ask, spread: boundedInput.spread,
            expirySeconds: boundedInput.expirySeconds,
            quoteAsOfMs: asOf.timeIntervalSince1970 * 1_000,
            evaluatedAtMs: asOf.timeIntervalSince1970 * 1_000, policy: boundedInput.policy)
        return AdaptiveOpportunityAdapters.evaluateCandidate001(inputAtAsOf, asOf: asOf,
            startedAt: asOf).contains { $0.id == eventID }
    }

    #expect(containsEvent(availableAt))
    #expect(!containsEvent(availableAt.addingTimeInterval(-0.001)))
    #expect(containsEvent(availableAt.addingTimeInterval(ttl)))
    #expect(!containsEvent(availableAt.addingTimeInterval(ttl + 0.001)))
}

@Test func detailedCandidate001AdapterPreservesExpiredRawRecognition() throws {
    let input = candidate001AdapterMarketInput()
    let m1 = input.candles1m.map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let m15 = AdaptiveOpportunityAdapters.aggregateM15(input.candles5m).map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let raw = try #require(Candidate001Analyzer.analyze(candles: m1, m15Candles: m15,
        configuration: Candidate001Configuration(requireM15Confirmation: true,
            signalFreshnessSeconds: 300)).first {
                $0.terminalState == .candidateTriggered && $0.m15Confirmed
            })
    let trigger = try #require(raw.triggeredAt)
    let asOf = trigger.addingTimeInterval(60 + 301)
    let detailed = AdaptiveOpportunityAdapters.evaluateCandidate001DetailedResult(
        input, asOf: asOf, startedAt: asOf)
    guard case .completed(let candidates, let diagnostics) = detailed else {
        Issue.record("Candidate001 detailed adapter unexpectedly failed")
        return
    }
    #expect(candidates.isEmpty)
    #expect(diagnostics.contains {
        $0.candidateID == "candidate001:\(raw.id)"
            && $0.rawState == Candidate001State.candidateTriggered.rawValue
            && $0.reasonCode == "entry_window_expired"
    })
}

@Test func detailedCandidate001AdapterPreservesMissingM15Confirmation() throws {
    var input = candidate001AdapterMarketInput()
    input.candles5m[2] = StrategyEngine.CandlePayload(time: input.candles5m[2].time,
        open: 1.10, high: 1.18, low: 0.90, close: 0.95)
    let m1 = input.candles1m.map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let m15 = AdaptiveOpportunityAdapters.aggregateM15(input.candles5m).map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let raw = try #require(Candidate001Analyzer.analyze(candles: m1, m15Candles: m15,
        configuration: Candidate001Configuration(requireM15Confirmation: false,
            signalFreshnessSeconds: 300)).first {
                $0.terminalState == .candidateTriggered && !$0.m15Confirmed
            })
    let detailed = AdaptiveOpportunityAdapters.evaluateCandidate001DetailedResult(
        input, asOf: raw.triggeredAt!.addingTimeInterval(60), startedAt: Date())
    guard case .completed(let candidates, let diagnostics) = detailed else {
        Issue.record("Candidate001 detailed adapter unexpectedly failed")
        return
    }
    #expect(candidates.isEmpty)
    #expect(diagnostics.contains {
        $0.candidateID == "candidate001:\(raw.id)"
            && $0.rawState == Candidate001State.candidateTriggered.rawValue
            && $0.reasonCode == "m15_confirmation_missing"
    })
}

@Test func candidateAdapterIDsAreNamespacedForSameEventTimestamp() throws {
    let input1 = candidate001AdapterMarketInput()
    let m1 = input1.candles1m.map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let m15 = AdaptiveOpportunityAdapters.aggregateM15(input1.candles5m).map {
        Candidate001Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let raw1 = try #require(Candidate001Analyzer.analyze(candles: m1, m15Candles: m15,
        configuration: Candidate001Configuration(requireM15Confirmation: true,
            signalFreshnessSeconds: 300)).first {
                $0.terminalState == .candidateTriggered && $0.m15Confirmed
            })
    let trigger = try #require(raw1.triggeredAt)
    let collisionTime = trigger.timeIntervalSince1970
    let now = Date(timeIntervalSince1970: collisionTime + 120)
    let input2 = auctionFailureMarketInput(now: now, m15StartOffsetMs: -1_800_000)
    let raw2Bars = input2.candles1m.map {
        Candidate002Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let raw2M15 = AdaptiveOpportunityAdapters.aggregateM15(input2.candles5m).map {
        Candidate002Candle(time: Date(timeIntervalSince1970: $0.time / 1_000),
            open: $0.open, high: $0.high, low: $0.low, close: $0.close)
    }
    let raw2 = try #require(Candidate002Analyzer.analyze(candles: raw2Bars,
        higherTimeframe: raw2M15, configuration: Candidate002Configuration(
            signalFreshnessSeconds: 120)).first { $0.terminalState == .confirmed })
    #expect(raw1.id == raw2.id)

    let adapted1 = AdaptiveOpportunityAdapters.evaluateCandidate001(input1,
        asOf: trigger.addingTimeInterval(60), startedAt: trigger)
    let adapted2 = AdaptiveOpportunityAdapters.evaluateCandidate002(input2,
        asOf: now, startedAt: now)
    let id1 = try #require(adapted1.first?.id)
    let id2 = try #require(adapted2.first?.id)
    #expect(id1 == "candidate001:\(raw1.id)")
    #expect(id2 == "candidate002:\(raw2.id)")
    #expect(id1 != id2)
}

@Test func auctionFailureAdapterBuildsRangeAnchoredStructuralPlan() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    // The failed M1 bar closes at `now - 60s`; this is its exact latest fully
    // completed M15 interval, rather than the still-forming interval at `now`.
    let input = auctionFailureMarketInput(now: now, m15StartOffsetMs: -1_800_000)

    let candidates = AdaptiveOpportunityAdapters.evaluateCandidate002(input, asOf: now, startedAt: now)
    #expect(candidates.count == 1)
    #expect(candidates.first?.direction == .long)
    #expect(candidates.first?.state == .eligible)
    #expect(candidates.first?.plan?.validation().isEmpty == true)
    #expect(abs((candidates.first?.plan?.stopPrice ?? 0) - 149.98) < 1e-9)
    #expect(abs((candidates.first?.plan?.targetPrice ?? 0) - 150.1) < 1e-9)
}

@Test func auctionFailureAdapterRejectsMissingExpectedM15InsteadOfUsingOlderWindow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let input = auctionFailureMarketInput(now: now, m15StartOffsetMs: -2_700_000)
    let candidates = AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now, startedAt: now)

    #expect(candidates.count == 1)
    #expect(candidates[0].state == .rejected)
    #expect(candidates[0].direction == .wait)
    #expect(candidates[0].rejectionReasons == ["m15_context_unavailable"])
    #expect(candidates[0].entryReference == nil)
    #expect(candidates[0].plan == nil)
}

@Test func auctionFailureAdapterReportsRejectedWaitWhenM15AggregationIsUnavailable() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let input = auctionFailureMarketInput(now: now, m15StartOffsetMs: .nan)
    let candidates = AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now, startedAt: now)

    #expect(candidates.count == 1)
    #expect(candidates[0].state == .rejected)
    #expect(candidates[0].direction == .wait)
    #expect(candidates[0].rejectionReasons == ["m15_context_unavailable"])
    #expect(candidates[0].entryReference == nil)
    #expect(candidates[0].plan == nil)
}

@Test func auctionFailureAdapterPublishesOnlyAfterConfirmationCloseAndHonorsTTL() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let input = auctionFailureMarketInput(now: now, m15StartOffsetMs: -1_800_000)
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now.addingTimeInterval(-0.001), startedAt: now).isEmpty)

    let atClose = AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now, startedAt: now)
    #expect(atClose.count == 1)
    #expect(atClose[0].state == .eligible)

    let ttl = TimeInterval(Candidate002Configuration(signalFreshnessSeconds: 120)
        .resolvedSignalFreshnessSeconds)
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now.addingTimeInterval(ttl), startedAt: now).count == 1)
    #expect(AdaptiveOpportunityAdapters.evaluateCandidate002(input,
        asOf: now.addingTimeInterval(ttl + 0.001), startedAt: now).isEmpty)
}

@Test func m15AggregationRequiresExactEpochAlignedTripleAndUsesOHLCEnvelope() {
    let input = [
        adapterM5(0, open: 1.0, high: 1.15, low: 0.95, close: 1.05),
        adapterM5(300_000, open: 1.05, high: 1.20, low: 1.00, close: 1.10),
        adapterM5(600_000, open: 1.10, high: 1.18, low: 0.90, close: 1.12),
        adapterM5(900_000, open: 1.12, high: 1.25, low: 1.05, close: 1.20),
        adapterM5(1_200_000, open: 1.20, high: 1.30, low: 1.10, close: 1.25),
        adapterM5(1_500_000, open: 1.25, high: 1.28, low: 1.15, close: 1.22),
        // Three adjacent bars in the same 15-minute bucket, but offset by two minutes.
        adapterM5(1_920_000), adapterM5(2_220_000), adapterM5(2_520_000),
    ]

    let aggregated = AdaptiveOpportunityAdapters.aggregateM15(input)
    #expect(aggregated.count == 2)
    #expect(aggregated[0].time == 0)
    #expect(aggregated[0].open == 1.0)
    #expect(aggregated[0].high == 1.20)
    #expect(aggregated[0].low == 0.90)
    #expect(aggregated[0].close == 1.12)
    #expect(aggregated[1].time == 900_000)
    #expect(aggregated[1].open == 1.12)
    #expect(aggregated[1].high == 1.30)
    #expect(aggregated[1].low == 1.05)
    #expect(aggregated[1].close == 1.22)
}

@Test func m15AggregationRejectsDuplicateMissingAndFractionalMillisecondWindows() {
    let duplicate = [adapterM5(0), adapterM5(300_000), adapterM5(300_000)]
    let missing = [adapterM5(0), adapterM5(300_000), adapterM5(900_000)]
    let fractional = [adapterM5(0), adapterM5(300_000.5), adapterM5(600_000)]

    #expect(AdaptiveOpportunityAdapters.aggregateM15(duplicate).isEmpty)
    #expect(AdaptiveOpportunityAdapters.aggregateM15(missing).isEmpty)
    #expect(AdaptiveOpportunityAdapters.aggregateM15(fractional).isEmpty)
}

@Test func m15AggregationRejectsMalformedOHLCWithoutDroppingValidNeighbor() {
    let malformed = [
        adapterM5(0), adapterM5(300_000, high: 0.9), adapterM5(600_000),
    ]
    let validNeighbor = [adapterM5(900_000), adapterM5(1_200_000), adapterM5(1_500_000)]

    let aggregated = AdaptiveOpportunityAdapters.aggregateM15(malformed + validNeighbor)
    #expect(aggregated.count == 1)
    #expect(aggregated.first?.time == 900_000)
}

@Test func m15AggregationRejectsNonfiniteAndOutOfRangeTimesWithoutTrapping() {
    let valid = [adapterM5(0), adapterM5(300_000), adapterM5(600_000)]
    let malformed = [
        adapterM5(.nan), adapterM5(.infinity), adapterM5(-.infinity),
        adapterM5(Double.greatestFiniteMagnitude),
    ]

    let aggregated = AdaptiveOpportunityAdapters.aggregateM15(valid + malformed)
    #expect(aggregated.count == 1)
    #expect(aggregated.first?.time == 0)
}
