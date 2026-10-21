import Foundation

/// Deterministic Strike Options math. All money is exact base-10 `Decimal`.
///
/// This is the local, authoritative source of breakeven, moneyness, decay gates, and basis
/// warnings. A language model is never allowed to compute any value produced here — the AI
/// copilot receives these numbers as context and returns words only.
public enum StrikeMath: Sendable {

    /// Seconds below which a contract is in its late (theta-decay) window.
    public static let lateWindowSeconds: Int = 60

    /// Reference-vs-strike distance (in price units) within which settlement drift is flagged.
    public static let defaultBasisWarningBuffer: Double = 5.0

    /// Volatility- and pip-aware basis buffer. A fixed $5 is meaningless on BTC and far too
    /// wide on a 5-digit FX pair; this uses 5 pips or one basis point, whichever is larger.
    public static func basisBuffer(spot: Double, pipScale: Double) -> Double {
        max(abs(pipScale) * 5, abs(spot) * 0.0001)
    }

    // MARK: - Money

    /// Breakeven win rate for a contract bought at `entryPrice`, expressed as a probability.
    /// Formula: `entryPrice / contractValue + totalFee / contractValue`
    /// (For the $1.00 crypto contract this is exactly `entryPrice + $0.02`.)
    public static func breakevenWinRate(
        entryPrice: Decimal,
        spec: StrikeContractSpec = .currentCrypto
    ) -> Decimal {
        guard spec.contractValue != .zero else { return .zero }
        let entryFraction = entryPrice / spec.contractValue
        let feeFraction = spec.totalEntryFee / spec.contractValue
        return entryFraction + feeFraction
    }

    /// Net profit per contract if the position settles in the money.
    public static func netProfitIfWin(
        entryPrice: Decimal,
        spec: StrikeContractSpec = .currentCrypto
    ) -> Decimal {
        spec.contractValue - entryPrice - spec.totalEntryFee
    }

    /// Loss per contract if the position settles out of the money (entry + fees).
    public static func lossIfLose(
        entryPrice: Decimal,
        spec: StrikeContractSpec = .currentCrypto
    ) -> Decimal {
        entryPrice + spec.totalEntryFee
    }

    // MARK: - Moneyness

    public static func moneyness(
        spot: Double,
        strike: Double,
        atOrNearTolerance: Double = 0
    ) -> StrikeMoneyness {
        let delta = spot - strike
        if abs(delta) <= atOrNearTolerance { return .atTheMoney }
        return delta > 0 ? .inTheMoney : .outOfTheMoney
    }

    // MARK: - Decay gate

    public static func decayGate(
        secondsRemaining: Int,
        moneyness: StrikeMoneyness,
        lateWindowSeconds: Int = StrikeMath.lateWindowSeconds
    ) -> StrikeDecayGate {
        if secondsRemaining <= 0 { return .expired }
        if secondsRemaining < lateWindowSeconds {
            return moneyness == .inTheMoney ? .lateWindow : .blocked
        }
        return .open
    }

    // MARK: - Basis (reference index vs venue settlement index)

    public static func basisBuffer(spot: Double, strike: Double) -> Double {
        abs(spot - strike)
    }

    /// True when the reference price sits close enough to the strike that index drift between
    /// the reference feed and the venue settlement index could flip the outcome.
    public static func basisWarning(
        spot: Double,
        strike: Double,
        buffer: Double = StrikeMath.defaultBasisWarningBuffer
    ) -> Bool {
        basisBuffer(spot: spot, strike: strike) < buffer
    }
}

/// A fully deterministic, locally-computed assessment of a candidate strike contract.
/// The UI renders this regardless of whether the optional AI copilot is available.
public struct StrikeAssessment: Sendable, Equatable, Codable {
    public var moneyness: StrikeMoneyness
    public var decayGate: StrikeDecayGate
    public var breakevenWinRate: Decimal
    public var netProfitIfWin: Decimal
    public var lossIfLose: Decimal
    public var basisBuffer: Double
    public var basisWarning: Bool

    public init(
        moneyness: StrikeMoneyness,
        decayGate: StrikeDecayGate,
        breakevenWinRate: Decimal,
        netProfitIfWin: Decimal,
        lossIfLose: Decimal,
        basisBuffer: Double,
        basisWarning: Bool
    ) {
        self.moneyness = moneyness
        self.decayGate = decayGate
        self.breakevenWinRate = breakevenWinRate
        self.netProfitIfWin = netProfitIfWin
        self.lossIfLose = lossIfLose
        self.basisBuffer = basisBuffer
        self.basisWarning = basisWarning
    }

    public static func evaluate(
        spot: Double,
        strike: Double,
        entryPrice: Decimal,
        secondsRemaining: Int,
        spec: StrikeContractSpec = .currentCrypto,
        atOrNearTolerance: Double = 0,
        basisWarningBuffer: Double = StrikeMath.defaultBasisWarningBuffer
    ) -> StrikeAssessment {
        let m = StrikeMath.moneyness(spot: spot, strike: strike, atOrNearTolerance: atOrNearTolerance)
        return StrikeAssessment(
            moneyness: m,
            decayGate: StrikeMath.decayGate(secondsRemaining: secondsRemaining, moneyness: m),
            breakevenWinRate: StrikeMath.breakevenWinRate(entryPrice: entryPrice, spec: spec),
            netProfitIfWin: StrikeMath.netProfitIfWin(entryPrice: entryPrice, spec: spec),
            lossIfLose: StrikeMath.lossIfLose(entryPrice: entryPrice, spec: spec),
            basisBuffer: StrikeMath.basisBuffer(spot: spot, strike: strike),
            basisWarning: StrikeMath.basisWarning(spot: spot, strike: strike, buffer: basisWarningBuffer)
        )
    }
}
