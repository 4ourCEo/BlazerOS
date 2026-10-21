import Foundation
import Testing
@testable import BlazerCore

// Tier 1 deterministic Strike math. Every number the UI shows for risk comes from here,
// not from a language model. These tests pin the authoritative $1.00 / $0.01 / $0.02 terms.

@Test func currentCryptoSpecMatchesAuthoritativeTerms() {
    let spec = StrikeContractSpec.currentCrypto
    #expect(spec.contractValue == Decimal.strikeMoney("1.00"))
    #expect(spec.tickSize == Decimal.strikeMoney("0.01"))
    #expect(spec.exchangeFee == Decimal.strikeMoney("0.02"))
    #expect(spec.technologyFee == .zero)
    #expect(spec.totalEntryFee == Decimal.strikeMoney("0.02"))
}

@Test func legacyTenDollarTermsAreNotTheDefault() {
    // $10 is legacy; the default template must be the current $1 crypto spec.
    #expect(StrikeContractSpec.currentCrypto.contractValue == Decimal.strikeMoney("1.00"))
    #expect(StrikeContractSpec.legacyRolling10.contractValue == Decimal.strikeMoney("10.00"))
    #expect(StrikeContractSpec.currentCrypto != StrikeContractSpec.legacyRolling10)
}

@Test func breakevenEqualsEntryPlusFeeExactly() {
    let spec = StrikeContractSpec.currentCrypto
    // $0.58 ask + $0.02 fee -> 0.60
    #expect(StrikeMath.breakevenWinRate(entryPrice: Decimal.strikeMoney("0.58"), spec: spec)
        == Decimal.strikeMoney("0.60"))
    // $0.50 ask -> 0.52
    #expect(StrikeMath.breakevenWinRate(entryPrice: Decimal.strikeMoney("0.50"), spec: spec)
        == Decimal.strikeMoney("0.52"))
    // $0.75 ask -> 0.77
    #expect(StrikeMath.breakevenWinRate(entryPrice: Decimal.strikeMoney("0.75"), spec: spec)
        == Decimal.strikeMoney("0.77"))
}

@Test func winAndLossAmountsAreExact() {
    let spec = StrikeContractSpec.currentCrypto
    #expect(StrikeMath.netProfitIfWin(entryPrice: Decimal.strikeMoney("0.58"), spec: spec)
        == Decimal.strikeMoney("0.40"))
    #expect(StrikeMath.lossIfLose(entryPrice: Decimal.strikeMoney("0.58"), spec: spec)
        == Decimal.strikeMoney("0.60"))
    // Deeply favored contract: $0.94 ask -> $0.04 net, $0.96 risk.
    #expect(StrikeMath.netProfitIfWin(entryPrice: Decimal.strikeMoney("0.94"), spec: spec)
        == Decimal.strikeMoney("0.04"))
    #expect(StrikeMath.lossIfLose(entryPrice: Decimal.strikeMoney("0.94"), spec: spec)
        == Decimal.strikeMoney("0.96"))
}

@Test func breakevenGeneralizesAcrossContractValue() {
    // $5.80 for a $10.00 legacy contract with $0.29 total fee -> 0.609
    let be = StrikeMath.breakevenWinRate(
        entryPrice: Decimal.strikeMoney("5.80"),
        spec: .legacyRolling10
    )
    #expect(be == Decimal.strikeMoney("0.609"))
}

@Test func moneynessClassification() {
    #expect(StrikeMath.moneyness(spot: 68_420, strike: 68_400) == .inTheMoney)
    #expect(StrikeMath.moneyness(spot: 68_380, strike: 68_400) == .outOfTheMoney)
    #expect(StrikeMath.moneyness(spot: 68_400, strike: 68_400) == .atTheMoney)
    // Inside the tolerance band counts as ATM (drift risk).
    #expect(StrikeMath.moneyness(spot: 68_403, strike: 68_400, atOrNearTolerance: 5) == .atTheMoney)
    #expect(StrikeMath.moneyness(spot: 68_406, strike: 68_400, atOrNearTolerance: 5) == .inTheMoney)
}

@Test func decayGateBlocksLateOutOfTheMoneyEntries() {
    #expect(StrikeMath.decayGate(secondsRemaining: 30, moneyness: .outOfTheMoney) == .blocked)
    #expect(StrikeMath.decayGate(secondsRemaining: 30, moneyness: .atTheMoney) == .blocked)
    #expect(StrikeMath.decayGate(secondsRemaining: 30, moneyness: .inTheMoney) == .lateWindow)
    #expect(StrikeMath.decayGate(secondsRemaining: 0, moneyness: .inTheMoney) == .expired)
    #expect(StrikeMath.decayGate(secondsRemaining: 300, moneyness: .inTheMoney) == .open)
    #expect(StrikeMath.decayGate(secondsRemaining: 60, moneyness: .inTheMoney) == .open)
}

@Test func basisWarningWhenReferenceSitsTooCloseToStrike() {
    #expect(StrikeMath.basisWarning(spot: 68_402, strike: 68_400) == true)
    #expect(StrikeMath.basisWarning(spot: 68_420, strike: 68_400) == false)
    #expect(StrikeMath.basisBuffer(spot: 68_380, strike: 68_400) == 20)
}

@Test func assessmentBundlesDeterministicValues() {
    let a = StrikeAssessment.evaluate(
        spot: 68_420,
        strike: 68_400,
        entryPrice: Decimal.strikeMoney("0.58"),
        secondsRemaining: 210
    )
    #expect(a.moneyness == .inTheMoney)
    #expect(a.decayGate == .open)
    #expect(a.breakevenWinRate == Decimal.strikeMoney("0.60"))
    #expect(a.netProfitIfWin == Decimal.strikeMoney("0.40"))
    #expect(a.lossIfLose == Decimal.strikeMoney("0.60"))
    #expect(a.basisWarning == false)
}

@Test func assessmentFlagsLateDecayedOutOfTheMoney() {
    // OTM by a hair (3 units), inside the late window, and close enough to the strike that
    // reference-vs-settlement drift could flip the outcome.
    let a = StrikeAssessment.evaluate(
        spot: 68_397,
        strike: 68_400,
        entryPrice: Decimal.strikeMoney("0.30"),
        secondsRemaining: 30
    )
    #expect(a.moneyness == .outOfTheMoney)
    #expect(a.decayGate == .blocked)
    #expect(a.basisWarning == true)
}
