import Foundation
import Testing
@testable import BlazerCore

private let clock = Date(timeIntervalSince1970: 1_790_000_000.123)

private func trendInput(down: Bool = false, asset: String = "EUR/USD") -> StrategyEngine.MarketInput {
    let sign = down ? -1.0 : 1.0
    let now = clock.timeIntervalSince1970 * 1000
    let pip = Assets.pipScale(for: asset)
    let start = asset == "XAU/USD" ? 2650.0 : 1.1
    let final = start + sign * 120 * pip * 3
    func bars(count: Int, step: Double, delta: Double, ending: Double) -> [StrategyEngine.CandlePayload] {
        (0..<count).map { i in
            let open = ending - sign * Double(count - i) * delta
            let close = open + sign * delta
            return .init(time: now - Double(count - i) * step, open: open,
                high: max(open, close) + pip * 0.1, low: min(open, close) - pip * 0.1, close: close)
        }
    }
    return .init(asset: asset, source: "test", candles1m: bars(count: 120, step: 60000, delta: pip, ending: final),
        candles5m: bars(count: 120, step: 300000, delta: pip * 3, ending: final),
        lastPrice: final, bid: final - pip * 0.1, ask: final + pip * 0.1, spread: pip * 0.2,
        expirySeconds: 60, quoteAsOfMs: now, evaluatedAtMs: now)
}

private func quote(_ input: StrategyEngine.MarketInput, time: Date = clock, mid: Double? = nil) -> LiveQuote {
    let price = mid ?? input.lastPrice
    let half = input.spread / 2
    return .init(asset: input.asset, bid: price - half, ask: price + half, mid: price,
                 asOfMs: time.timeIntervalSince1970 * 1000, source: "test")
}

@Test func goldenControlIsPreserved() async throws {
    let input = GoldenFixture.market()
    let current = try await StrategyEngine.evaluate(input: input).signal
    let control = try await StrategyEngine.evaluateControl(input: input).signal
    #expect(current.cabinetSide == control.cabinetSide)
    #expect(current.evidence == control.evidence)
    #expect(current.confidence == 68)
    #expect(EngineIdentity.bundleMatchesPin())
    #expect(current.policy == "baseline")
}

@Test func bullishAndBearishConvictionAreSymmetric() async throws {
    let up = try await StrategyEngine.evaluate(input: trendInput()).signal
    let down = try await StrategyEngine.evaluate(input: trendInput(down: true)).signal
    #expect(up.cabinetSide == "HIGH")
    #expect(down.cabinetSide == "LOW")
    #expect(up.confidence == down.confidence)
    #expect(up.strength == down.strength)
    #expect(up.directionScore! + down.directionScore! == 100)
    let commit = ScanKernel.commit(from: down, bars: [], scannedAt: clock)
    #expect(commit.score >= 72)
}

@Test func selectionUsesConvictionAfterFreshnessGate() async throws {
    let now = clock.timeIntervalSince1970 * 1000
    let weakerNewer = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH", why: "test",
        price: 1.1, confidence: 80, asOfMs: now, printMs: now - 60000)
    let strongerOlder = EngineSignal(asset: "GBP/USD", cabinetSide: "LOW", call: "TAP LOW", why: "test",
        price: 1.3, confidence: 96, asOfMs: now - 1000, printMs: now - 61000)
    let selected = try await StrategyEngine.pickDesk(signals: [weakerNewer, strongerOlder], trades: [],
        payoutPercent: 88, nowMs: now)
    #expect(selected.asset == "GBP/USD")
    var stale = strongerOlder
    stale.asOfMs = now - 9000
    let freshOnly = try await StrategyEngine.pickDesk(signals: [weakerNewer, stale], trades: [],
        payoutPercent: 88, nowMs: now)
    #expect(freshOnly.asset == "EUR/USD")
    let noFresh = try await StrategyEngine.pickDesk(signals: [stale], trades: [], payoutPercent: 88, nowMs: now)
    #expect(noFresh.asset == nil)
}

@Test func goldGateUsesSwiftPipUnits() {
    #expect(Assets.pipScale(for: "XAU/USD") == 0.1)
    let small = StrategyEngine.slippageGate(asset: "XAU/USD", side: "HIGH", strike: 2650,
        bid: 2649.95, ask: 2650.05)
    #expect(small.veto == false)
    #expect(abs(small.adverseDriftPips - 0.5) < 1e-6)
    let large = StrategyEngine.slippageGate(asset: "XAU/USD", side: "HIGH", strike: 2650,
        bid: 2649.85, ask: 2649.95)
    #expect(large.veto == true)
}

@Test func malformedInputFailsExplicitly() async throws {
    var input = trendInput()
    input.candles1m = []
    await #expect(throws: (any Error).self) { try await StrategyEngine.evaluate(input: input) }
    input = trendInput()
    input.candles5m[1].time = input.candles5m[0].time
    await #expect(throws: (any Error).self) { try await StrategyEngine.evaluate(input: input) }
}

@Test func challengersAreOptInAndStaleTriggersAreVetoed() async throws {
    var input = trendInput()
    let baseline = try await StrategyEngine.evaluate(input: input).signal
    #expect(baseline.policy == "baseline")
    input.policy = .continuation
    let continuation = try await StrategyEngine.evaluate(input: input).signal
    #expect(continuation.policy == "continuation")
    #expect(continuation.cabinetSide == "HIGH")
    #expect(continuation.features?.regime == "trend")
    input.evaluatedAtMs! += 9000
    let late = try await StrategyEngine.evaluate(input: input).signal
    #expect(late.cabinetSide == "WAIT")
    #expect(late.vetoes?.contains("Trigger candle too old") == true)
}

@Test func ambiguousSweepIsRejected() async throws {
    var input = trendInput()
    let index = input.candles1m.count - 1
    let prior = input.candles1m.suffix(11).dropLast()
    input.candles1m[index].low = prior.map(\.low).min()! - 0.0001
    input.candles1m[index].high = prior.map(\.high).max()! + 0.0001
    input.policy = .reversal
    let signal = try await StrategyEngine.evaluate(input: input).signal
    #expect(signal.features?.twoSidedSweep == true)
    #expect(signal.features?.sweep == nil)
    #expect(signal.cabinetSide == "WAIT")
}

@Test func reversalRequiresARangeReclaimRatherThanTrendContinuation() async throws {
    var input = trendInput()
    for i in input.candles5m.indices {
        input.candles5m[i].open = 1.1
        input.candles5m[i].close = 1.1
        input.candles5m[i].low = 1.0998
        input.candles5m[i].high = 1.1002
    }
    for i in input.candles1m.indices {
        input.candles1m[i].open = 1.1
        input.candles1m[i].close = i.isMultiple(of: 2) ? 1.10005 : 1.09995
        input.candles1m[i].low = 1.0998
        input.candles1m[i].high = 1.1002
    }
    let last = input.candles1m.count - 1
    input.candles1m[last].open = 1.0999
    input.candles1m[last].close = 1.10005
    input.candles1m[last].low = 1.0996
    input.candles1m[last].high = 1.1001
    input.lastPrice = 1.10005
    input.bid = input.lastPrice - input.spread / 2
    input.ask = input.lastPrice + input.spread / 2
    input.policy = .reversal
    let reversal = try await StrategyEngine.evaluate(input: input).signal
    #expect(reversal.features?.regime == "range")
    #expect(reversal.cabinetSide == "HIGH")
    input.policy = .regime
    let regimeRange = try await StrategyEngine.evaluate(input: input).signal
    #expect(regimeRange.cabinetSide == "HIGH")
    #expect(regimeRange.why == "Range sweep rejection")
    input.policy = .continuation
    #expect(try await StrategyEngine.evaluate(input: input).signal.cabinetSide == "WAIT")
}

@Test func regimeRouterRoutesTrendToContinuation() async throws {
    var input = trendInput()
    input.policy = .regime
    let signal = try await StrategyEngine.evaluate(input: input).signal
    #expect(signal.features?.regime == "trend")
    #expect(signal.cabinetSide == "HIGH")
    #expect(signal.why == "Trend continuation")
}

@Test func corruptResearchArchiveIsAnExplicitError() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let events = root.appendingPathComponent("events")
    try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
    try Data("broken".utf8).write(to: events.appendingPathComponent("event.json"))
    await #expect(throws: (any Error).self) { try await ResearchStore(root: root).events() }
}

@Test func entryGateRejectsStaleAndChasedPricesInBothDirections() async throws {
    for down in [false, true] {
        let input = trendInput(down: down)
        let signal = try await StrategyEngine.evaluate(input: input).signal
        #expect(EntryQuality.veto(signal: signal, quote: quote(input), at: clock) == nil)
        #expect(EntryQuality.veto(signal: signal, quote: quote(input, time: clock.addingTimeInterval(-9)), at: clock) == "Entry quote stale")
        #expect(EntryQuality.veto(signal: signal, quote: quote(input, mid: input.lastPrice + 0.01), at: clock) == "Price left entry envelope")
        #expect(EntryQuality.veto(signal: signal, quote: nil, at: clock) == "Entry quote unavailable")
    }
}

@Test func expiryDoesNotInventAResultFromOldOrLatePrices() {
    let input = trendInput()
    let expiry = clock.addingTimeInterval(60)
    func resolve(_ q: LiveQuote?, observed: Date = clock.addingTimeInterval(61)) -> ResearchOutcome {
        .resolve(eventID: "event", horizon: 60, entryTime: clock, strike: input.lastPrice,
            side: "HIGH", quote: q, observedAt: observed)
    }
    #expect(resolve(quote(input, time: expiry, mid: input.lastPrice + 0.0001)).resolution == .hit)
    #expect(resolve(quote(input, time: expiry, mid: input.lastPrice - 0.0001)).resolution == .miss)
    #expect(resolve(quote(input, time: expiry)).resolution == .tie)
    #expect(resolve(quote(input, time: expiry.addingTimeInterval(-1))).resolution == .unresolved)
    #expect(resolve(quote(input, time: expiry.addingTimeInterval(10)), observed: expiry.addingTimeInterval(10)).resolution == .unresolved)
    #expect(resolve(nil).resolution == .unresolved)
    #expect(resolve(quote(input, time: expiry), observed: expiry.addingTimeInterval(6)).resolution == .unresolved)
}

@Test func researchSurvivesRelaunchAndRetainsDistinctHorizons() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let input = trendInput()
    let signal = try await StrategyEngine.evaluate(input: input).signal
    let event = try ResearchEvent(input: input, signal: signal, sourceKind: "test", capturedAt: clock, entryQuote: quote(input))
    let store = ResearchStore(root: root)
    try await store.record(event)
    for horizon in [60, 180, 300] {
        let expiry = clock.addingTimeInterval(Double(horizon))
        try await store.record(ResearchOutcome.resolve(eventID: event.id, horizon: horizon, entryTime: clock,
            strike: input.lastPrice, side: "HIGH", quote: quote(input, time: expiry), observedAt: expiry))
    }
    let restored = ResearchStore(root: root)
    let events = try await restored.events()
    #expect(events.count == 1)
    #expect(abs(events[0].capturedAt.timeIntervalSince(clock)) < 0.00001)
    #expect(events[0].input.candles5m == input.candles5m)
    #expect(events[0].entryObservation == quote(input))
    #expect(try await restored.outcomes().count == 3)
    let replay = try await StrategyEngine.evaluate(input: events[0].input).signal
    #expect(replay.cabinetSide == signal.cabinetSide)
    var changed = input
    changed.candles5m[0].high += 0.001
    let second = try ResearchEvent(input: changed, signal: signal, sourceKind: "test", capturedAt: clock)
    #expect(second.inputDigest != event.inputDigest)
    #expect(second.id != event.id)
    #expect(ResearchStore.defaultRoot() != FileLocations.applicationSupport())
    #expect(ResearchStore.defaultRoot() != ResearchStore.defaultRoot(synthetic: true))
}

@Test func ledgerPreservesOutcomeProvenanceAndArmID() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let row = LedgerRow(timestamp: clock, pair: "EUR/USD", hash: "12345678", score: 80, side: "HIGH",
        veto: false, drift: 0, outcome: "HIT", outcomeEventID: "unique-arm", labelSource: "oanda-midpoint-proxy",
        horizonSeconds: 180, enteredAt: clock, expiryObservedMs: clock.timeIntervalSince1970 * 1000)
    let store = LedgerStore(root: root)
    #expect(try await store.record(row))
    let loaded = try await LedgerStore(root: root).rows()
    #expect(loaded[0].outcomeEventID == row.outcomeEventID)
    #expect(loaded[0].labelSource == row.labelSource)
    #expect(loaded[0].horizonSeconds == 180)
    let record = CloudRecordMapper.makeRecord(from: row)
    #expect(CloudSecurityGate.validate(record: record))
    #expect(CloudRecordMapper.toLedgerRow(from: record)?.labelSource == row.labelSource)
}

@Test func ledgerRetryDoesNotEraseUnreadableHistory() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let url = FileLocations.ledgerCSV(in: root)
    try Data([0xff, 0xfe, 0xfd]).write(to: url)
    let row = LedgerRow(timestamp: clock, pair: "EUR/USD", hash: "12345678", score: 80, side: "HIGH",
        veto: false, drift: 0, outcome: "HIT", outcomeEventID: "arm")
    let store = LedgerStore(root: root)
    await #expect(throws: (any Error).self) { try await store.record(row) }
    await #expect(throws: (any Error).self) { try await store.record(row) }
    #expect(try Data(contentsOf: url) == Data([0xff, 0xfe, 0xfd]))
    try FileManager.default.removeItem(at: url)
    #expect(try await store.record(row))
}

@Test func unverifiedLabelsCannotCertifyAnEdge() {
    let rows = (0..<100).map { i in LedgerRow(timestamp: clock, pair: "EUR/USD", hash: "\(i)", score: 100,
        side: "HIGH", veto: false, drift: 0, outcome: "HIT", outcomeEventID: "\(i)", labelSource: "oanda-midpoint-proxy") }
    let stats = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: rows)
    #expect(!stats.isProvenEdge)
    #expect(stats.statusBadge.contains("UNVERIFIED"))
}
