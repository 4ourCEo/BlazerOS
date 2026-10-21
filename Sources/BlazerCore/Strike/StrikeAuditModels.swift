import Foundation

// MARK: - AI Copilot data contracts (advisory only)
//
// The copilot receives system-computed numbers as CONTEXT and returns WORDS only. It never
// computes breakeven/moneyness/decay (those come from `StrikeMath`), never emits entry/exit
// price levels, and never produces a probability, EV, or confidence score. Its label is
// advisory and is rendered as "assistant opinion — not a validated edge."

public enum AIProvider: String, Sendable, Codable, CaseIterable {
    case deepseek
    case gemini

    /// Real-time model id. Never a reasoning model here (too slow for the 8s beam budget).
    public var modelID: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .gemini: return "gemini-2.5-flash"
        }
    }
}

/// Advisory label only. Never authoritative; downstream must present it as opinion.
public enum AdvisoryGate: String, Sendable, Codable, CaseIterable {
    case proceed = "PROCEED"
    case caution = "CAUTION"
    case pass = "PASS"

    /// Normalize any model string into a known gate (defaults to CAUTION — never a green light).
    public static func normalize(_ raw: String?) -> AdvisoryGate {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "PROCEED": return .proceed
        case "PASS": return .pass
        default: return .caution
        }
    }
}

/// Outbound context. All numeric fields are computed by Swift (`StrikeMath`/feeds), never the model.
public struct StrikeAuditRequest: Sendable, Equatable, Codable {
    public var symbol: String
    public var referenceSpot: Double
    public var contractStrike: Double
    public var strikeDistanceUSD: Double
    public var secondsRemaining: Int
    public var momentumDirection: String
    public var momentumScore: Int
    public var indicativeSide: String
    public var indicativeContractAsk: Double
    public var exchangeFee: Double
    /// System-computed breakeven (from `StrikeMath`), passed as context only.
    public var computedBreakeven: Double
    /// System-computed moneyness (from `StrikeMath`), passed as context only.
    public var computedMoneyness: String

    public init(
        symbol: String,
        referenceSpot: Double,
        contractStrike: Double,
        strikeDistanceUSD: Double,
        secondsRemaining: Int,
        momentumDirection: String,
        momentumScore: Int,
        indicativeSide: String,
        indicativeContractAsk: Double,
        exchangeFee: Double,
        computedBreakeven: Double,
        computedMoneyness: String
    ) {
        self.symbol = symbol
        self.referenceSpot = referenceSpot
        self.contractStrike = contractStrike
        self.strikeDistanceUSD = strikeDistanceUSD
        self.secondsRemaining = secondsRemaining
        self.momentumDirection = momentumDirection
        self.momentumScore = momentumScore
        self.indicativeSide = indicativeSide
        self.indicativeContractAsk = indicativeContractAsk
        self.exchangeFee = exchangeFee
        self.computedBreakeven = computedBreakeven
        self.computedMoneyness = computedMoneyness
    }

    /// Build from the deterministic assessment so the model's context can never disagree with
    /// the local math.
    public static func make(
        symbol: String,
        assessment: StrikeAssessment,
        spot: Double,
        strike: Double,
        entryPrice: Decimal,
        secondsRemaining: Int,
        momentumDirection: String,
        momentumScore: Int,
        side: StrikeSide,
        spec: StrikeContractSpec = .currentCrypto
    ) -> StrikeAuditRequest {
        StrikeAuditRequest(
            symbol: symbol,
            referenceSpot: spot,
            contractStrike: strike,
            strikeDistanceUSD: spot - strike,
            secondsRemaining: secondsRemaining,
            momentumDirection: momentumDirection,
            momentumScore: momentumScore,
            indicativeSide: side.rawValue,
            indicativeContractAsk: NSDecimalNumber(decimal: entryPrice).doubleValue,
            exchangeFee: NSDecimalNumber(decimal: spec.totalEntryFee).doubleValue,
            computedBreakeven: NSDecimalNumber(decimal: assessment.breakevenWinRate).doubleValue,
            computedMoneyness: assessment.moneyness.rawValue
        )
    }
}

/// Inbound advisory. WORDS ONLY — decoding is strict and any numeric claim is ignored.
public struct StrikeAuditAdvice: Sendable, Equatable, Codable {
    public var regimeSummary: String
    public var riskWarning: String
    public var checklist: [String]
    public var coachNote: String
    public var advisoryLabel: AdvisoryGate

    public init(
        regimeSummary: String,
        riskWarning: String,
        checklist: [String],
        coachNote: String,
        advisoryLabel: AdvisoryGate
    ) {
        self.regimeSummary = regimeSummary
        self.riskWarning = riskWarning
        self.checklist = checklist
        self.coachNote = coachNote
        self.advisoryLabel = advisoryLabel
    }

    enum CodingKeys: String, CodingKey {
        case regimeSummary = "regime_summary"
        case riskWarning = "risk_warning"
        case checklist
        case coachNote = "coach_note"
        case advisoryLabel = "advisory_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regimeSummary = (try? c.decode(String.self, forKey: .regimeSummary)) ?? ""
        riskWarning = (try? c.decode(String.self, forKey: .riskWarning)) ?? ""
        checklist = (try? c.decode([String].self, forKey: .checklist)) ?? []
        coachNote = (try? c.decode(String.self, forKey: .coachNote)) ?? ""
        advisoryLabel = AdvisoryGate.normalize(try? c.decode(String.self, forKey: .advisoryLabel))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(regimeSummary, forKey: .regimeSummary)
        try c.encode(riskWarning, forKey: .riskWarning)
        try c.encode(checklist, forKey: .checklist)
        try c.encode(coachNote, forKey: .coachNote)
        try c.encode(advisoryLabel.rawValue, forKey: .advisoryLabel)
    }

    /// Strict decode: returns nil on malformed JSON or a wholly empty payload.
    public static func decode(fromJSON data: Data) -> StrikeAuditAdvice? {
        guard let advice = try? JSONDecoder().decode(StrikeAuditAdvice.self, from: data) else {
            return nil
        }
        let empty = advice.regimeSummary.isEmpty
            && advice.riskWarning.isEmpty
            && advice.checklist.isEmpty
            && advice.coachNote.isEmpty
        return empty ? nil : advice
    }

    public static func decode(fromJSON text: String) -> StrikeAuditAdvice? {
        decode(fromJSON: Data(text.utf8))
    }
}

/// Deterministic prompt construction. Pure and testable; no I/O.
public enum StrikeAuditPrompt {
    public static let systemInstruction =
        "You are an advisory risk assistant for CFTC-regulated binary event contracts "
        + "($1.00 notional). You audit the setup; you do not predict price. "
        + "Output STRICT JSON only."

    public static func build(request r: StrikeAuditRequest) -> String {
        """
        Audit whether recent short-horizon momentum is viable across the remaining contract window.
        Return STRICT JSON only, matching exactly:
        {"regime_summary": string, "risk_warning": string, "checklist": [string], "coach_note": string, "advisory_label": "PROCEED"|"CAUTION"|"PASS"}

        Rules:
        - Do NOT output entry or exit price levels (no "buy at X" / "sell at Y").
        - Do NOT output probabilities, expected value, or confidence scores.
        - The numbers below are provided by the system; do not recompute them.
        - advisory_label is an opinion, not authorization.

        Context:
        - Asset: \(r.symbol)
        - Reference spot: \(r.referenceSpot) (proxy feed, NOT the venue settlement index)
        - Contract strike: \(r.contractStrike) (distance \(String(format: "%.2f", r.strikeDistanceUSD)))
        - Seconds remaining: \(r.secondsRemaining)
        - 60s momentum: \(r.momentumDirection) (score \(r.momentumScore)/100 — context only, not a probability)
        - Held side: \(r.indicativeSide)
        - Indicative ask: \(r.indicativeContractAsk)
        - Exchange fee: \(r.exchangeFee)
        - System-computed breakeven: \(r.computedBreakeven)
        - System-computed moneyness: \(r.computedMoneyness)
        """
    }
}
