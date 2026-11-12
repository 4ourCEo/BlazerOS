import Foundation

/// Research-only auction-failure candidate. It uses completed OHLC candles only.
/// It does not infer absorption, footprint delta, volume-at-price, or gamma exposure.
public enum Candidate002Direction: String, Codable, Sendable, Equatable {
    case bullish, bearish
}

public enum Candidate002Environment: String, Codable, Sendable, Equatable {
    case trending, balanced, unavailable
}

public enum Candidate002TerminalState: String, Codable, Sendable, Equatable {
    case confirmed, invalidated, expired
}

public struct Candidate002Candle: Codable, Sendable, Equatable {
    public let time: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(time: Date, open: Double, high: Double, low: Double, close: Double,
                complete: Bool = true) {
        self.time = time; self.open = open; self.high = high; self.low = low
        self.close = close; self.complete = complete
    }

    public var isValid: Bool {
        time.timeIntervalSince1970.isFinite && complete
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
    }
}

public struct Candidate002Configuration: Codable, Sendable, Equatable {
    public let lookbackBars: Int
    public let confirmationBars: Int
    public let locationTolerance: Double
    public let fibonacciRatio: Double

    public init(lookbackBars: Int = 12, confirmationBars: Int = 2,
                locationTolerance: Double = 0.10, fibonacciRatio: Double = 0.705) {
        self.lookbackBars = lookbackBars; self.confirmationBars = confirmationBars
        self.locationTolerance = locationTolerance; self.fibonacciRatio = fibonacciRatio
    }
}

public struct Candidate002Candidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let direction: Candidate002Direction
    public let environment: Candidate002Environment
    public let fibonacciRatio: Double
    public let failedAt: Date
    public let confirmationAt: Date?
    public let invalidatedAt: Date?
    public let terminalState: Candidate002TerminalState
    public let orderFlowDataAvailable: Bool
}

public enum Candidate002Error: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidCandles
    case unavailableHigherTimeframe
}

public enum Candidate002Analyzer {
    public static let version = "candidate-002-auction-failure-v1"
    public static let unavailableCapabilities = [
        "order-flow absorption", "footprint delta", "volume-at-price", "gamma exposure"
    ]

    public static func analyze(
        candles: [Candidate002Candle],
        higherTimeframe: [Candidate002Candle],
        configuration: Candidate002Configuration = .init()
    ) throws -> [Candidate002Candidate] {
        guard configuration.lookbackBars >= 3, configuration.confirmationBars > 0,
              configuration.locationTolerance.isFinite, configuration.locationTolerance > 0,
              configuration.fibonacciRatio.isFinite, configuration.fibonacciRatio > 0,
              configuration.fibonacciRatio < 1 else { throw Candidate002Error.invalidConfiguration }
        guard candles.allSatisfy(\.isValid), higherTimeframe.allSatisfy(\.isValid),
              candles.count >= configuration.lookbackBars + 2 else {
            throw Candidate002Error.invalidCandles
        }
        guard !higherTimeframe.isEmpty else { throw Candidate002Error.unavailableHigherTimeframe }

        let environment = classifyEnvironment(higherTimeframe)
        var output: [Candidate002Candidate] = []
        for index in configuration.lookbackBars..<(candles.count - 1) {
            let prior = candles[(index - configuration.lookbackBars)..<index]
            let high = prior.map(\.high).max()!
            let low = prior.map(\.low).min()!
            let range = high - low
            guard range > 0 else { continue }
            let bar = candles[index]
            let failure: (Candidate002Direction, Double)?
            if bar.low < low && bar.close > low {
                failure = (.bullish, high - range * configuration.fibonacciRatio)
            } else if bar.high > high && bar.close < high {
                failure = (.bearish, low + range * configuration.fibonacciRatio)
            } else { failure = nil }
            guard let (direction, location) = failure,
                  abs(bar.close - location) <= range * configuration.locationTolerance else { continue }

            let end = min(candles.count - 1, index + configuration.confirmationBars)
            let confirmations = candles[(index + 1)...end]
            let confirmation = confirmations.first {
                direction == .bullish ? $0.close > bar.close : $0.close < bar.close
            }
            let invalidation = confirmations.first {
                direction == .bullish ? $0.close < low : $0.close > high
            }
            let terminal: Candidate002TerminalState
            if let confirmation, invalidation == nil || confirmation.time <= invalidation!.time {
                terminal = .confirmed
                output.append(Candidate002Candidate(
                    id: "\(bar.time.timeIntervalSince1970)-\(output.count)", version: version,
                    direction: direction, environment: environment,
                    fibonacciRatio: configuration.fibonacciRatio, failedAt: bar.time,
                    confirmationAt: confirmation.time, invalidatedAt: nil,
                    terminalState: terminal, orderFlowDataAvailable: false))
            } else if let invalidation {
                terminal = .invalidated
                output.append(Candidate002Candidate(
                    id: "\(bar.time.timeIntervalSince1970)-\(output.count)", version: version,
                    direction: direction, environment: environment,
                    fibonacciRatio: configuration.fibonacciRatio, failedAt: bar.time,
                    confirmationAt: nil, invalidatedAt: invalidation.time,
                    terminalState: terminal, orderFlowDataAvailable: false))
            } else {
                terminal = .expired
                output.append(Candidate002Candidate(
                    id: "\(bar.time.timeIntervalSince1970)-\(output.count)", version: version,
                    direction: direction, environment: environment,
                    fibonacciRatio: configuration.fibonacciRatio, failedAt: bar.time,
                    confirmationAt: nil, invalidatedAt: nil,
                    terminalState: terminal, orderFlowDataAvailable: false))
            }
        }
        return output
    }

    private static func classifyEnvironment(_ candles: [Candidate002Candle]) -> Candidate002Environment {
        guard let first = candles.first, let last = candles.last,
              let high = candles.map(\.high).max(), let low = candles.map(\.low).min(), high > low
        else { return .unavailable }
        let displacement = abs(last.close - first.open) / (high - low)
        return displacement >= 0.35 ? .trending : .balanced
    }
}
