import CryptoKit
import Foundation

/// Research candidates remain opt-in. Baseline uses the repaired engine contract.
public enum ScanPolicy: String, Codable, Sendable, CaseIterable {
    case baseline
    case continuation
    case reversal
    case regime
}

public struct ScanFeatures: Codable, Sendable {
    public var atr1m: Double
    public var atr5m: Double
    public var efficiency: Double
    public var slopeATR: Double
    public var spreadATR: Double
    public var rangeATR: Double
    public var bodyATR: Double
    public var upperWickShare: Double
    public var lowerWickShare: Double
    public var twoSidedSweep: Bool
    public var sweep: String?
    public var structureBreak: String?
    public var regime: String
}

/// Mechanical entry quality, shared by the desk and research runner; never picks a side.
public enum EntryQuality {
    public static let version = "entry-v1"
    public static let assumedPayout = 0.88
    public static let maxAgeSeconds = 8.0

    public static func veto(signal: EngineSignal, quote: LiveQuote?, at now: Date = Date()) -> String? {
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return "No actionable setup" }
        guard let quote, quote.asset == signal.asset,
              quote.bid.isFinite, quote.ask.isFinite, quote.bid > 0, quote.ask > quote.bid,
              quote.mid.isFinite, abs(quote.mid - (quote.bid + quote.ask) / 2) < 1e-8,
              quote.asOfMs.isFinite else { return "Entry quote unavailable" }
        let nowMs = now.timeIntervalSince1970 * 1000
        guard let signalTime = signal.asOfMs, signalTime.isFinite,
              nowMs - signalTime >= -1000, nowMs - signalTime <= maxAgeSeconds * 1000 else {
            return "Setup expired before entry"
        }
        guard nowMs - quote.asOfMs >= -1000, nowMs - quote.asOfMs <= maxAgeSeconds * 1000 else {
            return "Entry quote stale"
        }
        let atr = signal.features?.atr1m ?? 0
        guard atr.isFinite, atr > 0, quote.ask - quote.bid <= max(3 * Assets.pipScale(for: signal.asset), atr * 0.5) else {
            return "Entry spread too wide"
        }
        guard signal.price.isFinite, signal.price > 0,
              abs(quote.mid - signal.price) <= max(Assets.pipScale(for: signal.asset), atr * 0.25) else {
            return "Price left entry envelope"
        }
        return nil
    }
}

public enum ResearchResolution: String, Codable, Sendable {
    case hit, miss, tie, unresolved
}

/// OANDA midpoint observation, explicitly a proxy rather than a venue result.
public struct ResearchOutcome: Codable, Sendable {
    public let eventID: String
    public let horizon: Int
    public let targetExpiry: Date
    public let observedAt: Date
    public let quoteTimeMs: Double?
    public let exitPrice: Double?
    public let resolution: ResearchResolution
    public let reason: String?
    public let labelSource: String

    public static func resolve(eventID: String, horizon: Int, entryTime: Date, strike: Double,
                               side: String, quote: LiveQuote?, observedAt: Date,
                               labelSource: String = "oanda-midpoint-proxy") -> ResearchOutcome {
        let expiry = entryTime.addingTimeInterval(Double(horizon))
        var reason: String?
        var result = ResearchResolution.unresolved
        if !strike.isFinite || strike <= 0 || !["HIGH", "LOW"].contains(side) || ![60, 180, 300].contains(horizon) {
            reason = "Invalid entry"
        } else if let quote, quote.asOfMs.isFinite, quote.mid.isFinite,
                  quote.bid > 0, quote.ask > quote.bid,
                  abs(quote.mid - (quote.bid + quote.ask) / 2) < 1e-8 {
            let printTime = Date(timeIntervalSince1970: quote.asOfMs / 1000)
            // First post-expiry print within a bounded observation window; never label a later retry as expiry.
            if printTime < expiry || printTime.timeIntervalSince(expiry) > 2 ||
                observedAt < printTime || observedAt.timeIntervalSince(expiry) > 5 {
                reason = "No timely expiry observation"
            } else if quote.mid == strike {
                result = .tie
            } else {
                let wins = side == "HIGH" ? quote.mid > strike : quote.mid < strike
                result = wins ? .hit : .miss
            }
        } else {
            reason = "Expiry quote unavailable"
        }
        return ResearchOutcome(eventID: eventID, horizon: horizon, targetExpiry: expiry,
                               observedAt: observedAt,
                               quoteTimeMs: quote.flatMap { $0.asOfMs.isFinite ? $0.asOfMs : nil },
                               exitPrice: quote.flatMap { $0.mid.isFinite ? $0.mid : nil },
                               resolution: result, reason: reason, labelSource: labelSource)
    }
}

/// Local-only, reproducible frozen input. No credentials, account ID or live beam state.
public struct ResearchEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let inputDigest: String
    public let engineSHA: String
    public let policyVersion: String
    public let sourceKind: String
    public let capturedAt: Date
    public let input: StrategyEngine.MarketInput
    public let signal: EngineSignal
    public let entryTime: Date?
    public let entryPrice: Double?
    public let entryVeto: String?
    public let entryObservation: LiveQuote?
    public let assumedPayout: Double

    public init(input: StrategyEngine.MarketInput, signal: EngineSignal, sourceKind: String,
                capturedAt: Date, entryQuote: LiveQuote? = nil,
                engineSHA: String = EngineIdentity.pinnedSHA1) throws {
        id = UUID().uuidString
        inputDigest = try Self.digest(of: input)
        self.engineSHA = engineSHA
        policyVersion = "scan-research-v1/\(EntryQuality.version)"
        self.sourceKind = sourceKind
        self.capturedAt = capturedAt
        self.input = input
        self.signal = signal
        let veto = EntryQuality.veto(signal: signal, quote: entryQuote, at: capturedAt)
        entryVeto = veto
        entryObservation = entryQuote
        entryTime = veto == nil ? capturedAt : nil
        entryPrice = veto == nil ? entryQuote?.mid : nil
        assumedPayout = EntryQuality.assumedPayout
    }

    public static func digest(of input: StrategyEngine.MarketInput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(input)).map { String(format: "%02x", $0) }.joined()
    }
}
