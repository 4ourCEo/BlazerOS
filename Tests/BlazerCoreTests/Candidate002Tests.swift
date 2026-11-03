import Foundation
import Testing
@testable import BlazerCore

private func c(_ index: Int, _ open: Double, _ high: Double, _ low: Double, _ close: Double,
               complete: Bool = true) -> Candidate002Candle {
    Candidate002Candle(time: Date(timeIntervalSince1970: Double(index * 60)), open: open,
        high: high, low: low, close: close, complete: complete)
}

@Test func candidate002FindsConfirmedPriceStructureFailure() throws {
    var bars = (0..<12).map { c($0, 100, 101, 99, 100) }
    bars.append(c(12, 100, 100.5, 95, 99.3))
    bars.append(c(13, 99.3, 100, 99, 99.6))
    let higher = [c(0, 100, 101, 99, 100), c(1, 100, 102, 99, 101)]
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
    let higher = [c(0, 100, 101, 99, 100)]
    for ratio in [0.705, 0.788, 0.886] {
        let result = try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: higher,
            configuration: .init(fibonacciRatio: ratio))
        #expect(result.allSatisfy { $0.fibonacciRatio == ratio })
    }
}

@Test func candidate002RejectsIncompleteDataAndDoesNotFabricateOrderFlow() throws {
    let bars = (0..<14).map { c($0, 100, 101, 99, 100, complete: $0 != 13) }
    #expect(throws: Candidate002Error.invalidCandles) {
        try Candidate002Analyzer.analyze(candles: bars, higherTimeframe: [c(0, 100, 101, 99, 100)])
    }
    #expect(Candidate002Analyzer.unavailableCapabilities.contains("footprint delta"))
}
