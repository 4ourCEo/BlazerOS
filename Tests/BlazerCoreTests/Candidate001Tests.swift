import Foundation
import Testing
@testable import BlazerCore

private func candidateBar(_ index: Int, open: Double, high: Double, low: Double,
                          close: Double) -> Candidate001Candle {
    Candidate001Candle(time: Date(timeIntervalSince1970: Double(index * 60)),
        open: open, high: high, low: low, close: close)
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
