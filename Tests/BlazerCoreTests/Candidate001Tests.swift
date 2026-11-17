import Foundation
import Testing
@testable import BlazerCore

private func candidateBar(_ index: Int, open: Double, high: Double, low: Double,
                          close: Double) -> Candidate001Candle {
    Candidate001Candle(time: Date(timeIntervalSince1970: Double(index * 60)),
        open: open, high: high, low: low, close: close)
}

private struct Candidate001FixtureRandom {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Double(state >> 11) / Double(1 << 53)
    }
}

@Test func candidate001RejectsIncompleteAndNonIncreasingBars() {
    let bar = candidateBar(0, open: 1, high: 1.1, low: 0.9, close: 1)
    #expect(throws: Candidate001Error.invalidCandles) {
        try Candidate001Analyzer.analyze(candles: [bar, bar])
    }
    let incomplete = Candidate001Candle(time: Date(timeIntervalSince1970: 60),
        open: 1, high: 1.1, low: 0.9, close: 1, complete: false)
    #expect(throws: Candidate001Error.invalidCandles) {
        try Candidate001Analyzer.analyze(candles: [bar, incomplete])
    }
}

@Test func candidate001SignalTTLResolvesLegacyConfigurationAndRejectsInvalidOverrides() throws {
    let legacy = Candidate001Configuration(expirationBars: 3)
    let encoded = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(Candidate001Configuration.self, from: encoded)
    let explicit = Candidate001Configuration(expirationBars: 3, signalFreshnessSeconds: 180)
    #expect(decoded.signalFreshnessSeconds == nil)
    #expect(decoded.resolvedSignalFreshnessSeconds == 180)
    #expect(explicit.resolvedSignalFreshnessSeconds == decoded.resolvedSignalFreshnessSeconds)
    #expect(throws: Candidate001Error.invalidConfiguration) {
        try Candidate001Analyzer.analyze(candles: [], configuration:
            Candidate001Configuration(signalFreshnessSeconds: 0))
    }
}

@Test func candidate001FVGIsNotObservableBeforeThirdCompletedCandle() throws {
    let bars = [
        candidateBar(0, open: 1.00, high: 1.01, low: 0.99, close: 1.00),
        candidateBar(1, open: 1.02, high: 1.04, low: 1.02, close: 1.03),
        candidateBar(2, open: 1.06, high: 1.08, low: 1.06, close: 1.07),
    ]
    let result = try Candidate001Analyzer.analyze(candles: bars)
    #expect(result.isEmpty)
    #expect(result.allSatisfy { $0.fvg.formedAt >= bars[2].time })
}

@Test func candidate001RecordsTerminalLifecycleStateForUntriggeredSetups() throws {
    let bars = (0..<8).map { index in
        candidateBar(index, open: 1.00 + Double(index) * 0.01,
            high: 1.01 + Double(index) * 0.01,
            low: 0.99 + Double(index) * 0.01,
            close: 1.00 + Double(index) * 0.01)
    }
    let result = try Candidate001Analyzer.analyze(
        candles: bars,
        configuration: Candidate001Configuration(expirationBars: 2)
    )
    #expect(result.allSatisfy {
        [.expired, .invalidated, .candidateTriggered].contains($0.terminalState)
    })
    #expect(result.allSatisfy { $0.transitions.last?.state == $0.terminalState })
}

@Test func candidate001M15ConfirmationUsesOnlyCompletedCandlesAtTriggerTime() throws {
    let bars = (0..<12).map { index in
        let price = 1.00 + Double(index) * 0.01
        return candidateBar(index, open: price, high: price + 0.012,
            low: price - 0.002, close: price + 0.01)
    }
    let completedM15 = [
        Candidate001Candle(time: Date(timeIntervalSince1970: 0),
            open: 1, high: 1.1, low: 0.99, close: 1.05),
        Candidate001Candle(time: Date(timeIntervalSince1970: 900),
            open: 1.05, high: 1.2, low: 1.04, close: 1.15),
    ]
    let futureBearishM15 = Candidate001Candle(
        time: Date(timeIntervalSince1970: 3_600),
        open: 1.2, high: 1.21, low: 1.0, close: 1.01
    )
    let withoutFuture = try Candidate001Analyzer.analyze(
        candles: bars, m15Candles: completedM15,
        configuration: Candidate001Configuration(requireM15Confirmation: true)
    )
    let withFuture = try Candidate001Analyzer.analyze(
        candles: bars, m15Candles: completedM15 + [futureBearishM15],
        configuration: Candidate001Configuration(requireM15Confirmation: true)
    )
    #expect(withFuture == withoutFuture)
}

@Test func candidate001ExpectedM15WindowChangesOnlyWhenThePriorIntervalCloses() {
    let before = Date(timeIntervalSince1970: 10 * 3_600 + 14 * 60 + 59)
    let boundary = Date(timeIntervalSince1970: 10 * 3_600 + 15 * 60)
    let after = Date(timeIntervalSince1970: 10 * 3_600 + 15 * 60 + 1)

    #expect(Candidate001Analyzer.expectedLatestCompletedM15Start(m1Close: before)
        == Date(timeIntervalSince1970: 10 * 3_600 - 15 * 60))
    #expect(Candidate001Analyzer.expectedLatestCompletedM15Start(m1Close: boundary)
        == Date(timeIntervalSince1970: 10 * 3_600))
    #expect(Candidate001Analyzer.expectedLatestCompletedM15Start(m1Close: after)
        == Date(timeIntervalSince1970: 10 * 3_600))
}

@Test func candidate001DoesNotUseFutureClosingOrOlderFallbackM15Confirmation() {
    let olderBearish = Candidate001Candle(time: Date(timeIntervalSince1970: 9 * 3_600 + 45 * 60),
        open: 1.1, high: 1.2, low: 1.0, close: 1.05)
    let futureClosingBullish = Candidate001Candle(time: Date(timeIntervalSince1970: 10 * 3_600),
        open: 1.05, high: 1.2, low: 1.04, close: 1.15)
    let olderBullish = Candidate001Candle(time: Date(timeIntervalSince1970: 9 * 3_600 + 45 * 60),
        open: 1.0, high: 1.2, low: 0.9, close: 1.1)

    let beforeIntervalClose = Date(timeIntervalSince1970: 10 * 3_600 + 14 * 60 + 59)
    let atIntervalClose = Date(timeIntervalSince1970: 10 * 3_600 + 15 * 60)
    #expect(!Candidate001Analyzer.m15Confirms(.bullish, atM1Close: beforeIntervalClose,
        m15Candles: [olderBearish, futureClosingBullish]))
    #expect(Candidate001Analyzer.m15Confirms(.bullish, atM1Close: atIntervalClose,
        m15Candles: [olderBearish, futureClosingBullish]))
    #expect(!Candidate001Analyzer.m15Confirms(.bullish, atM1Close: atIntervalClose,
        m15Candles: [olderBullish]))
}

@Test func candidate001M15SuppressionOnlyRemovesAnOtherwiseTriggeredSetup() throws {
    var random = Candidate001FixtureRandom(state: 783)
    var price = 1.1
    let values: [[Double]] = (0..<60).map { _ in
        let open = price
        let close = open + random.next() * 0.004 - 0.002
        let high = max(open, close) + 0.0002 + random.next() * 0.0013
        let low = min(open, close) - 0.0002 - random.next() * 0.0013
        price = close
        return [open, high, low, close]
    }
    let bars = values.enumerated().map { index, row in
        candidateBar(index, open: row[0], high: row[1], low: row[2], close: row[3])
    }
    let base = Candidate001Configuration(swingLeftBars: 1, swingRightBars: 1,
        expirationBars: 3, requireM15Confirmation: false)
    let unfiltered = try Candidate001Analyzer.analyze(candles: bars, configuration: base)
    let target = try #require(unfiltered.first {
        $0.terminalState == .candidateTriggered && $0.direction == .bearish
            && $0.triggeredAt.map {
                let start = $0.timeIntervalSince1970
                return start >= 2_640 && start < 3_540
            } == true
    })
    let targetStart = try #require(target.triggeredAt)
    #expect(targetStart.timeIntervalSince1970 >= 2_640)
    #expect(targetStart.timeIntervalSince1970 < 3_540)

    let m15Config = Candidate001Configuration(swingLeftBars: 1, swingRightBars: 1,
        expirationBars: 3, requireM15Confirmation: true)
    let olderBearish = Candidate001Candle(time: Date(timeIntervalSince1970: 900),
        open: 1.1, high: 1.2, low: 1.0, close: 1.05)
    let matchingBearish = Candidate001Candle(time: Date(timeIntervalSince1970: 1_800),
        open: 1.1, high: 1.2, low: 1.0, close: 1.05)
    let opposingBullish = Candidate001Candle(time: Date(timeIntervalSince1970: 1_800),
        open: 1.0, high: 1.1, low: 0.9, close: 1.05)
    let futureBullish = Candidate001Candle(time: Date(timeIntervalSince1970: 2_700),
        open: 1.0, high: 1.1, low: 0.9, close: 1.05)
    let futureBearish = Candidate001Candle(time: Date(timeIntervalSince1970: 2_700),
        open: 1.0, high: 1.1, low: 0.9, close: 1.05)
    let olderFallback = try Candidate001Analyzer.analyze(candles: bars,
        m15Candles: [olderBearish, futureBearish], configuration: m15Config)
    let opposing = try Candidate001Analyzer.analyze(candles: bars,
        m15Candles: [opposingBullish, futureBearish], configuration: m15Config)
    let confirmed = try Candidate001Analyzer.analyze(candles: bars,
        m15Candles: [matchingBearish, futureBullish], configuration: m15Config)

    #expect(!olderFallback.contains { $0.triggeredAt == targetStart })
    #expect(!opposing.contains { $0.triggeredAt == targetStart })
    #expect(confirmed.contains {
        $0.triggeredAt == targetStart && $0.terminalState == .candidateTriggered
            && $0.m15Confirmed
    })
}
