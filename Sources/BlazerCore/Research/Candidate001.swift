import Foundation

public struct Candidate001Candle: Codable, Sendable, Equatable {
    public let time: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(time: Date, open: Double, high: Double, low: Double, close: Double,
                complete: Bool = true) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.complete = complete
    }

    public var isValid: Bool {
        time.timeIntervalSince1970.isFinite && [open, high, low, close].allSatisfy {
            $0.isFinite && $0 > 0
        } && high >= max(open, close) && low <= min(open, close) && low <= high
            && complete
    }
}

public enum Candidate001Direction: String, Codable, Sendable, Equatable {
    case bullish, bearish
}

public enum Candidate001Structure: String, Codable, Sendable, Equatable {
    case higherHigh, higherLow, lowerHigh, lowerLow, bos, choch
}

public struct Candidate001StructureEvent: Codable, Sendable, Equatable {
    public let kind: Candidate001Structure
    public let direction: Candidate001Direction
    public let timestamp: Date
    public let price: Double
    public let confirmedAt: Date
}

public struct Candidate001FVG: Codable, Sendable, Equatable {
    public let direction: Candidate001Direction
    public let formedAt: Date
    public let lower: Double
    public let upper: Double
    public let midpoint: Double
    public let gapSize: Double
    public let mitigatedAt: Date?
    public let invalidatedAt: Date?
}

public struct Candidate001Fibonacci: Codable, Sendable, Equatable {
    public let direction: Candidate001Direction
    public let swingLow: Double
    public let swingHigh: Double
    public let level50: Double
    public let level618: Double
    public let anchoredAt: Date
}

public enum Candidate001State: String, Codable, Sendable, Equatable {
    case observe, structureConfirmed, fvgConfirmed, retracementEligible
    case candidateTriggered, expired, invalidated
}

public struct Candidate001StateTransition: Codable, Sendable, Equatable {
    public let state: Candidate001State
    public let timestamp: Date
}

public struct Candidate001Candidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let version: String
    public let direction: Candidate001Direction
    public let triggeredAt: Date?
    public let structure: [Candidate001StructureEvent]
    public let fvg: Candidate001FVG
    public let fibonacci: Candidate001Fibonacci
    public let m15Confirmed: Bool
    public let terminalState: Candidate001State
    public let transitions: [Candidate001StateTransition]
}

public struct Candidate001Configuration: Codable, Sendable, Equatable {
    public let swingLeftBars: Int
    public let swingRightBars: Int
    public let minimumFVGSize: Double
    public let expirationBars: Int
    public let requireM15Confirmation: Bool

    public init(swingLeftBars: Int = 2, swingRightBars: Int = 2,
                minimumFVGSize: Double = 0, expirationBars: Int = 5,
                requireM15Confirmation: Bool = false) {
        self.swingLeftBars = swingLeftBars
        self.swingRightBars = swingRightBars
        self.minimumFVGSize = minimumFVGSize
        self.expirationBars = expirationBars
        self.requireM15Confirmation = requireM15Confirmation
    }
}

public enum Candidate001Error: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidCandles
}

public enum Candidate001Analyzer {
    public static let version = "candidate-001-v1"

    public static func analyze(
        candles: [Candidate001Candle],
        m15Candles: [Candidate001Candle] = [],
        configuration: Candidate001Configuration = Candidate001Configuration()
    ) throws -> [Candidate001Candidate] {
        guard configuration.swingLeftBars > 0, configuration.swingRightBars > 0,
              configuration.minimumFVGSize.isFinite, configuration.minimumFVGSize >= 0,
              configuration.expirationBars > 0 else {
            throw Candidate001Error.invalidConfiguration
        }
        let bars = try validated(candles)
        let m15 = try validated(m15Candles)
        guard bars.count >= configuration.swingLeftBars + configuration.swingRightBars + 1
        else { return [] }

        var pivots: [(index: Int, high: Bool, price: Double, confirmedAt: Date)] = []
        var events: [Candidate001StructureEvent] = []
        var output: [Candidate001Candidate] = []
        var trend: Candidate001Direction?
        var lastHigh: (index: Int, price: Double, time: Date)?
        var lastLow: (index: Int, price: Double, time: Date)?

        for index in bars.indices {
            if let pivot = confirmedPivot(at: index, bars: bars, configuration: configuration) {
                pivots.append(pivot)
                if pivot.high {
                    if let previous = lastHigh {
                        let kind: Candidate001Structure
                        if pivot.price > previous.price {
                            kind = .higherHigh
                        } else {
                            kind = .lowerHigh
                        }
                        events.append(.init(kind: kind,
                            direction: kind == .higherHigh ? .bullish : .bearish,
                            timestamp: bars[pivot.index].time, price: pivot.price,
                            confirmedAt: pivot.confirmedAt))
                    }
                    lastHigh = (pivot.index, pivot.price, bars[pivot.index].time)
                } else {
                    if let previous = lastLow {
                        let kind: Candidate001Structure
                        if pivot.price > previous.price {
                            kind = .higherLow
                        } else {
                            kind = .lowerLow
                        }
                        events.append(.init(kind: kind,
                            direction: kind == .higherLow ? .bullish : .bearish,
                            timestamp: bars[pivot.index].time, price: pivot.price,
                            confirmedAt: pivot.confirmedAt))
                    }
                    lastLow = (pivot.index, pivot.price, bars[pivot.index].time)
                }
            }

            guard index >= 2 else { continue }
            let first = bars[index - 2]
            let third = bars[index]
            let bullishGap = third.low - first.high
            let bearishGap = first.low - third.high
            let direction: Candidate001Direction?
            let lower: Double
            let upper: Double
            let gap: Double
            if bullishGap >= configuration.minimumFVGSize && bullishGap > 0 {
                direction = .bullish; lower = first.high; upper = third.low; gap = bullishGap
            } else if bearishGap >= configuration.minimumFVGSize && bearishGap > 0 {
                direction = .bearish; lower = third.high; upper = first.low; gap = bearishGap
            } else {
                continue
            }
            guard let direction else { continue }
            let priorStructure = events.filter { $0.confirmedAt <= third.time }
            guard let confirmedStructure = priorStructure.last(where: {
                $0.kind == .higherHigh || $0.kind == .higherLow
                    || $0.kind == .lowerHigh || $0.kind == .lowerLow
            }), confirmedStructure.confirmedAt < third.time else {
                continue
            }
            let structureDirection = confirmedStructure.direction
            guard let reference = direction == .bullish ? lastHigh?.price : lastLow?.price else {
                continue
            }
            let broke = direction == .bullish ? third.close > reference : third.close < reference
            let structureKind: Candidate001Structure = broke && structureDirection != direction
                ? .choch : .bos
            let structure = Candidate001StructureEvent(kind: structureKind, direction: direction,
                timestamp: third.time, price: third.close, confirmedAt: third.time)
            events.append(structure)
            trend = direction

            guard let low = pivots.last(where: { !$0.high && $0.index < index }),
                  let high = pivots.last(where: { $0.high && $0.index < index }),
                  low.index < high.index || high.index < low.index else { continue }
            let fibDirection: Candidate001Direction = high.index > low.index ? .bullish : .bearish
            guard fibDirection == direction else { continue }
            let range = high.price - low.price
            guard range > 0 else { continue }
            let fibonacci = Candidate001Fibonacci(direction: direction, swingLow: low.price,
                swingHigh: high.price, level50: direction == .bullish
                    ? high.price - range * 0.5 : low.price + range * 0.5,
                level618: direction == .bullish
                    ? high.price - range * 0.618 : low.price + range * 0.618,
                anchoredAt: third.time)
            let midpoint = (lower + upper) / 2
            let inRetracement = midpoint >= min(fibonacci.level50, fibonacci.level618)
                && midpoint <= max(fibonacci.level50, fibonacci.level618)
            guard inRetracement else { continue }
            let windowEnd = min(index + configuration.expirationBars, bars.count - 1)
            guard index + 1 <= windowEnd else { continue }
            let window = Array((index + 1)...windowEnd)
            let triggerIndex = window.first { futureIndex in
                    let future = bars[futureIndex]
                    return direction == .bullish
                        ? future.low <= midpoint && future.close >= midpoint
                        : future.high >= midpoint && future.close <= midpoint
                }
            let invalidationIndex = window.first { futureIndex in
                let future = bars[futureIndex]
                return direction == .bullish ? future.close < lower : future.close > upper
            }
            let terminalIndex = triggerIndex ?? invalidationIndex ?? window.last
            guard let terminalIndex else { continue }
            let triggerBar = bars[terminalIndex]
            let completedM15 = m15.filter { $0.time <= triggerBar.time }
            let m15Confirmed = !completedM15.isEmpty
                && (direction == .bullish
                    ? completedM15.last!.close >= completedM15.last!.open
                    : completedM15.last!.close <= completedM15.last!.open)
            let terminalState: Candidate001State
            if triggerIndex != nil {
                guard !configuration.requireM15Confirmation || m15Confirmed else { continue }
                terminalState = .candidateTriggered
            } else {
                terminalState = invalidationIndex == nil ? .expired : .invalidated
            }
            var transitions = [
                Candidate001StateTransition(state: .observe, timestamp: first.time),
                Candidate001StateTransition(state: .structureConfirmed, timestamp: third.time),
                Candidate001StateTransition(state: .fvgConfirmed, timestamp: third.time),
                Candidate001StateTransition(state: .retracementEligible, timestamp: third.time),
            ]
            transitions.append(Candidate001StateTransition(state: terminalState, timestamp: triggerBar.time))
            output.append(Candidate001Candidate(id: "\(triggerBar.time.timeIntervalSince1970)-\(output.count)",
                version: version, direction: direction,
                triggeredAt: triggerIndex == nil ? nil : triggerBar.time,
                structure: [confirmedStructure, structure], fvg: Candidate001FVG(direction: direction,
                    formedAt: third.time, lower: lower, upper: upper, midpoint: midpoint,
                    gapSize: gap,
                    mitigatedAt: triggerIndex == nil ? nil : triggerBar.time,
                    invalidatedAt: terminalState == .invalidated ? triggerBar.time : nil),
                fibonacci: fibonacci, m15Confirmed: m15Confirmed,
                terminalState: terminalState, transitions: transitions))
        }
        _ = trend
        _ = events
        return output
    }

    private static func validated(_ candles: [Candidate001Candle]) throws -> [Candidate001Candle] {
        let sorted = candles.sorted { $0.time < $1.time }
        guard sorted.count == candles.count,
              zip(sorted, sorted.dropFirst()).allSatisfy({ $0.time < $1.time }),
              sorted.allSatisfy(\.isValid) else { throw Candidate001Error.invalidCandles }
        return sorted
    }

    private static func confirmedPivot(
        at index: Int, bars: [Candidate001Candle], configuration: Candidate001Configuration
    ) -> (index: Int, high: Bool, price: Double, confirmedAt: Date)? {
        let left = configuration.swingLeftBars
        let right = configuration.swingRightBars
        guard index >= left + right else { return nil }
        let candidate = index - right
        let bar = bars[candidate]
        let neighbors = bars[(candidate - left)..<(candidate + right + 1)]
        let high = neighbors.allSatisfy { bar.high >= $0.high }
            && neighbors.contains { $0.high < bar.high }
        let low = neighbors.allSatisfy { bar.low <= $0.low }
            && neighbors.contains { $0.low > bar.low }
        guard high != low else { return nil }
        return (candidate, high, high ? bar.high : bar.low, bars[index].time)
    }
}
