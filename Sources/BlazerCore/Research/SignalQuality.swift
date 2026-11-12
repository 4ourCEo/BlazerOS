import Foundation

/// Research-only classification of the evidence supporting an existing engine signal.
/// This is not a probability, score, recommendation, or entry authorization.
public enum SignalQualityClass: String, Codable, Sendable, Equatable {
    case supported
    case conditional
    case rejected
    case unavailable
}

/// Evidence supplied to the quality evaluator. Values are deliberately separated into
/// observed facts and calculated facts so a report cannot present a derived value as feed data.
public struct SignalQualityEvidence: Codable, Sendable, Equatable {
    public var feedHealthy: Bool?
    public var completedM1Bars: Int?
    public var completedM5Bars: Int?
    public var marketOpen: Bool?
    public var spreadWithinConstraint: Bool?
    public var slippageWithinConstraint: Bool?
    public var higherTimeframeAligned: Bool?
    public var trendOrRange: String?
    public var directionalInstability: Double?

    public init(
        feedHealthy: Bool? = nil,
        completedM1Bars: Int? = nil,
        completedM5Bars: Int? = nil,
        marketOpen: Bool? = nil,
        spreadWithinConstraint: Bool? = nil,
        slippageWithinConstraint: Bool? = nil,
        higherTimeframeAligned: Bool? = nil,
        trendOrRange: String? = nil,
        directionalInstability: Double? = nil
    ) {
        self.feedHealthy = feedHealthy
        self.completedM1Bars = completedM1Bars
        self.completedM5Bars = completedM5Bars
        self.marketOpen = marketOpen
        self.spreadWithinConstraint = spreadWithinConstraint
        self.slippageWithinConstraint = slippageWithinConstraint
        self.higherTimeframeAligned = higherTimeframeAligned
        self.trendOrRange = trendOrRange
        self.directionalInstability = directionalInstability
    }
}

public struct SignalQualityAssessment: Codable, Sendable, Equatable {
    public static let policyVersion = "signal-quality-shadow-v1"

    public let policyVersion: String
    public let classification: SignalQualityClass
    public let reasons: [String]
    public let observedInputs: [String]
    public let calculatedInputs: [String]
    public let unavailableInputs: [String]

    public init(
        classification: SignalQualityClass,
        reasons: [String],
        observedInputs: [String],
        calculatedInputs: [String],
        unavailableInputs: [String]
    ) {
        self.policyVersion = Self.policyVersion
        self.classification = classification
        self.reasons = reasons
        self.observedInputs = observedInputs
        self.calculatedInputs = calculatedInputs
        self.unavailableInputs = unavailableInputs
    }
}

/// Evaluates only the support around an already-produced deterministic signal.
/// It has no side-selection logic and is not called by `DeskEntryGate`.
public enum SignalQualityEvaluator {
    public static func assess(
        signal: EngineSignal,
        quote: LiveQuote?,
        evidence: SignalQualityEvidence = .init(),
        at now: Date = Date()
    ) -> SignalQualityAssessment {
        var reasons: [String] = []
        var observed: [String] = []
        var calculated: [String] = []
        var unavailable: [String] = []
        var rejected = false

        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else {
            return SignalQualityAssessment(classification: .unavailable,
                reasons: ["The deterministic signal has no actionable direction."],
                observedInputs: [], calculatedInputs: [], unavailableInputs: ["direction"])
        }
        guard let signalMs = signal.asOfMs, signalMs.isFinite,
              now.timeIntervalSince1970 * 1000 - signalMs >= -1000 else {
            return SignalQualityAssessment(classification: .unavailable,
                reasons: ["Signal timestamp is missing or invalid."], observedInputs: [],
                calculatedInputs: [], unavailableInputs: ["signal timestamp"])
        }

        let ageMs = now.timeIntervalSince1970 * 1000 - signalMs
        calculated.append("signal age: \(String(format: "%.0f", ageMs))ms")
        if ageMs > EntryQuality.maxAgeSeconds * 1000 {
            rejected = true
            reasons.append("Signal is outside the validated entry window.")
        } else {
            reasons.append("Signal is inside the validated entry window.")
        }

        if let vetoes = signal.vetoes, !vetoes.isEmpty {
            rejected = true
            reasons.append(contentsOf: vetoes.map { "Engine veto: \($0)" })
        }

        if let feedHealthy = evidence.feedHealthy {
            observed.append("feed healthy: \(feedHealthy)")
            if !feedHealthy { rejected = true; reasons.append("Feed health is not verified.") }
        } else { unavailable.append("feed health") }

        if let quote, quote.asset == signal.asset,
           quote.bid.isFinite, quote.ask.isFinite, quote.mid.isFinite,
           quote.bid > 0, quote.ask > quote.bid, quote.asOfMs.isFinite {
            observed.append("matching bid/ask quote")
            let quoteAge = now.timeIntervalSince1970 * 1000 - quote.asOfMs
            calculated.append("quote age: \(String(format: "%.0f", quoteAge))ms")
            if quoteAge > EntryQuality.maxAgeSeconds * 1000 || quoteAge < -1000 {
                rejected = true; reasons.append("Quote is stale or future-dated.")
            }
        } else { unavailable.append("matching quote") }

        func bool(_ value: Bool?, name: String, required: Bool = true) {
            guard let value else { unavailable.append(name); return }
            observed.append("\(name): \(value)")
            if required && !value { rejected = true; reasons.append("\(name) failed.") }
        }
        bool(evidence.marketOpen, name: "market open")
        bool(evidence.spreadWithinConstraint, name: "spread constraint")
        bool(evidence.slippageWithinConstraint, name: "slippage constraint")
        bool(evidence.higherTimeframeAligned, name: "higher-timeframe alignment", required: false)

        if let bars = evidence.completedM1Bars {
            calculated.append("completed M1 bars: \(bars)")
            if bars <= 0 { rejected = true; reasons.append("No completed M1 bars are available.") }
        } else { unavailable.append("completed M1 bars") }
        if let bars = evidence.completedM5Bars {
            calculated.append("completed M5 bars: \(bars)")
            if bars <= 0 { rejected = true; reasons.append("No completed M5 bars are available.") }
        } else { unavailable.append("completed M5 bars") }

        if let regime = evidence.trendOrRange, !regime.isEmpty {
            calculated.append("market regime: \(regime)")
        } else { unavailable.append("market regime") }
        if let instability = evidence.directionalInstability, instability.isFinite,
           instability >= 0, instability <= 1 {
            calculated.append("directional instability: \(String(format: "%.3f", instability))")
        } else { unavailable.append("directional instability") }

        let classification: SignalQualityClass
        if rejected { classification = .rejected }
        else if unavailable.isEmpty { classification = .supported }
        else { classification = .conditional }
        return SignalQualityAssessment(classification: classification, reasons: reasons,
            observedInputs: observed, calculatedInputs: calculated, unavailableInputs: unavailable)
    }
}
