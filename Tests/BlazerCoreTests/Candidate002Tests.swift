import Foundation
import Testing
@testable import BlazerCore

private func c(_ index: Int, _ open: Double, _ high: Double, _ low: Double, _ close: Double,
               complete: Bool = true) -> Candidate002Candle {
    Candidate002Candle(time: Date(timeIntervalSince1970: Double(index * 60)), open: open,
        high: high, low: low, close: close, complete: complete)
}

private func m15(_ start: TimeInterval, _ open: Double = 100, _ high: Double = 102,
                 _ low: Double = 99, _ close: Double = 101) -> Candidate002Candle {
    Candidate002Candle(time: Date(timeIntervalSince1970: start), open: open,
        high: high, low: low, close: close)
}

@Test func candidate002FindsConfirmedPriceStructureFailure() throws {
    var bars = (0..<12).map { c($0, 100, 101, 99, 100) }
    bars.append(c(12, 100, 100.5, 95, 99.3))
    bars.append(c(13, 99.3, 100, 99, 99.6))
    let higher = [m15(-900, 100, 101, 99, 100), m15(0, 100, 102, 99, 101)]
    let result = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: higher,
        configuration: .init(lookbackBars: 12, confirmationBars: 1, locationTolerance: 1.0,
            fibonacciRatio: 0.705))
    #expect(result.count == 1)
    #expect(result[0].direction == .bullish)
    #expect(result[0].terminalState == .confirmed)
    #expect(result[0].orderFlowDataAvailable == false)
}

@Test func candidate002TestsFibonacciLevelsIndependently() throws {
    let bars = (0..<14).map { c($0, 100, 101, 99, 100) }
    let higher = [m15(-900, 100, 101, 99, 100)]
    for ratio in [0.705, 0.788, 0.886] {
        let result = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: higher,
            configuration: .init(fibonacciRatio: ratio))
        #expect(result.allSatisfy { $0.fibonacciRatio == ratio })
    }
}

@Test func candidate002EnvironmentUsesOnlyCausalM15PrefixAtFailureClose() throws {
    var bars = (0..<12).map { c($0, 100, 101, 99, 100) }
    bars.append(c(12, 100, 100.5, 95, 99.3))
    bars.append(c(13, 99.3, 100, 99, 99.6))
    let earlierContext = [m15(-900, 100, 101, 99, 100)]
    let withFutureBars = earlierContext + [
        m15(0, 100, 102, 99, 101), m15(900, 101, 105, 100, 104),
    ]

    let withoutFuture = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: earlierContext,
        configuration: .init(lookbackBars: 12, confirmationBars: 1, locationTolerance: 1.0,
            fibonacciRatio: 0.705))
    let withFuture = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: withFutureBars,
        configuration: .init(lookbackBars: 12, confirmationBars: 1, locationTolerance: 1.0,
            fibonacciRatio: 0.705))
    #expect(withoutFuture.count == 1)
    #expect(withFuture == withoutFuture)
    #expect(withoutFuture[0].environment == .balanced)
}

@Test func candidate002MissingExpectedM15DoesNotFallBackToOlderContext() throws {
    var bars = (0..<12).map { c($0, 100, 101, 99, 100) }
    bars.append(c(12, 100, 100.5, 95, 99.3))
    bars.append(c(13, 99.3, 100, 99, 99.6))
    let olderButNotExpected = [m15(-1_800, 100, 101, 99, 100)]

    let result = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: olderButNotExpected,
        configuration: .init(lookbackBars: 12, confirmationBars: 1, locationTolerance: 1.0,
            fibonacciRatio: 0.705))
    #expect(result.count == 1)
    #expect(result[0].environment == .unavailable)
    #expect(result[0].terminalState == .confirmed)
}

@Test func candidate002EntirelyMissingM15ProducesUnavailableEnvironment() throws {
    var bars = (0..<12).map { c($0, 100, 101, 99, 100) }
    bars.append(c(12, 100, 100.5, 95, 99.3))
    bars.append(c(13, 99.3, 100, 99, 99.6))

    let result = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: [],
        configuration: .init(lookbackBars: 12, confirmationBars: 1, locationTolerance: 1.0,
            fibonacciRatio: 0.705))
    #expect(result.count == 1)
    #expect(result[0].environment == .unavailable)
    #expect(result[0].terminalState == .confirmed)
}

@Test func candidate002ExpectedM15WindowHonorsExactCloseBoundary() {
    let before = Date(timeIntervalSince1970: 10 * 3_600 + 14 * 60 + 59)
    let boundary = Date(timeIntervalSince1970: 10 * 3_600 + 15 * 60)
    let after = Date(timeIntervalSince1970: 10 * 3_600 + 15 * 60 + 1)

    #expect(Candidate002Analyzer.expectedLatestCompletedM15Start(m1Close: before)
        == Date(timeIntervalSince1970: 10 * 3_600 - 15 * 60))
    #expect(Candidate002Analyzer.expectedLatestCompletedM15Start(m1Close: boundary)
        == Date(timeIntervalSince1970: 10 * 3_600))
    #expect(Candidate002Analyzer.expectedLatestCompletedM15Start(m1Close: after)
        == Date(timeIntervalSince1970: 10 * 3_600))
}

@Test func candidate002SignalTTLResolvesLegacyConfigurationAndRejectsInvalidOverrides() throws {
    let legacy = Candidate002Configuration(confirmationBars: 3)
    let encoded = try JSONEncoder().encode(legacy)
    let decoded = try JSONDecoder().decode(Candidate002Configuration.self, from: encoded)
    let explicit = Candidate002Configuration(confirmationBars: 3, signalFreshnessSeconds: 180)
    #expect(decoded.signalFreshnessSeconds == nil)
    #expect(decoded.resolvedSignalFreshnessSeconds == 180)
    #expect(explicit.resolvedSignalFreshnessSeconds == decoded.resolvedSignalFreshnessSeconds)
    #expect(throws: Candidate002Error.invalidConfiguration) {
        try Candidate002Analyzer.analyze(candles: [], higherTimeframe: [],
            configuration: Candidate002Configuration(signalFreshnessSeconds: 0))
    }
}

@Test func candidate002RejectsIncompleteDataAndDoesNotFabricateOrderFlow() throws {
    let bars = (0..<14).map { c($0, 100, 101, 99, 100, complete: $0 != 13) }
    #expect(throws: Candidate002Error.invalidCandles) {
        try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: [c(0, 100, 101, 99, 100)])
    }
    #expect(Candidate002Analyzer.unavailableCapabilities.contains("footprint delta"))
}
