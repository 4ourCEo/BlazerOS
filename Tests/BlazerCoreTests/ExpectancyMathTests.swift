import Foundation
import Testing
@testable import BlazerCore

@Test func breakEvenWinRateIsMathematicallyExact() {
    let be88 = ExpectancyMath.breakEvenWinRate(payoutRatio: 0.88)
    // 1 / (1 + 0.88) = 1 / 1.88 ≈ 0.53191489
    #expect(abs(be88 - (1.0 / 1.88)) < 1e-6)
    #expect(abs(be88 - 0.531915) < 1e-5)

    let be80 = ExpectancyMath.breakEvenWinRate(payoutRatio: 0.80)
    #expect(abs(be80 - (1.0 / 1.80)) < 1e-6)

    let be100 = ExpectancyMath.breakEvenWinRate(payoutRatio: 1.00)
    #expect(abs(be100 - 0.50) < 1e-6)
}

@Test func expectancyCalculatesPositiveAndNegativeEV() {
    // Under break-even (50% win rate at 88% payout) -> negative EV
    let ev50 = ExpectancyMath.expectedValue(winRate: 0.50, payoutRatio: 0.88)
    #expect(ev50 < 0)
    #expect(abs(ev50 - ((0.50 * 0.88) - 0.50)) < 1e-6) // -0.06

    // Exactly at break-even -> ~0 EV
    let be88 = ExpectancyMath.breakEvenWinRate(payoutRatio: 0.88)
    let evBreakEven = ExpectancyMath.expectedValue(winRate: be88, payoutRatio: 0.88)
    #expect(abs(evBreakEven) < 1e-6)

    // Above break-even (60% win rate at 88% payout) -> positive EV
    let ev60 = ExpectancyMath.expectedValue(winRate: 0.60, payoutRatio: 0.88)
    #expect(ev60 > 0)
    #expect(abs(ev60 - ((0.60 * 0.88) - 0.40)) < 1e-6) // +0.128
}

@Test func negativeExpectancyMandatesZeroStakeAndFlatPosture() {
    // If win rate is 50% (< 53.2% break-even), Kelly fraction is 0.0
    let kelly = ExpectancyMath.fullKellyFraction(winRate: 0.50, payoutRatio: 0.88)
    #expect(kelly == 0.0)

    let stake = ExpectancyMath.recommendedStake(bankroll: 10_000, winRate: 0.50, payoutRatio: 0.88)
    #expect(stake == 0.0)

    // Posture evaluation with sub-break-even win rate returns stayFlat
    let posture = ExpectancyMath.evaluatePosture(wins: 7, sampleSize: 20, payoutRatio: 0.88) // 35% win rate
    #expect(posture == .stayFlat)
}

@Test func positiveExpectancyCapsStakeAtRiskCeiling() {
    let bankroll = 10_000.0
    // At 65% win rate and 88% payout, EV is strong: (0.65 * 0.88) - 0.35 = +0.222
    let stake = ExpectancyMath.recommendedStake(
        bankroll: bankroll,
        winRate: 0.65,
        payoutRatio: 0.88,
        fraction: 0.25,
        maxRiskCeiling: 0.02
    )
    // Full Kelly = 0.222 / 0.88 ≈ 0.25227
    // Quarter Kelly = ~0.063 (6.3%), clamped by maxRiskCeiling to 2% = 200.0
    #expect(stake <= bankroll * 0.02)
    #expect(stake == 200.0)
}

@Test func coachSynthesizesBasicMathAndExpectancyIntelligence() {
    let seal = ParitySeal(
        engineSHA1: "e816768e3cc07c577bdada4b70c12abf2c2143ea",
        fingerprint: "A1B2C3D4",
        score: 82,
        side: "HIGH",
        strike: 1.0850,
        candleCount: 120
    )

    // Basic math inquiry
    let mathAnswer = CoachIntelligence.synthesizeAnswer(
        seal: seal,
        evidence: "Trend is up",
        question: "Why do 90% of traders fail? What is the basic math?"
    )
    #expect(mathAnswer.contains("Expectancy"))
    #expect(mathAnswer.contains("53.2%"))

    // Flat is a position inquiry
    let flatAnswer = CoachIntelligence.synthesizeAnswer(
        seal: seal,
        evidence: "Chop observed",
        question: "Should I stay flat in this chop?"
    )
    #expect(flatAnswer.contains("Flat is a position"))
    #expect(flatAnswer.contains("capital preservation"))

    // Risk / sizing inquiry
    let riskAnswer = CoachIntelligence.synthesizeAnswer(
        seal: seal,
        evidence: "Trend is up",
        question: "What lot size or risk should I use?"
    )
    #expect(riskAnswer.contains("fixed risk limit"))
    #expect(riskAnswer.contains("does not size stakes"))
}

@Test func bootstrapStressTestSimulatesExpectancyAndDrawdown() {
    // 60 wins out of 100 trials (60% observed rate)
    guard let result = ExpectancyMath.bootstrapStressTest(wins: 60, sampleSize: 100, iterations: 500, payoutRatio: 0.88) else {
        #expect(Bool(false), "Bootstrap returned nil")
        return
    }

    #expect(result.iterations == 500)
    #expect(result.sampleSize == 100)
    #expect(result.observedWinRate == 0.60)
    // Median simulated win rate should be very close to 60%
    #expect(abs(result.medianWinRate - 0.60) < 0.05)
    // 5th percentile lower bound should be less than median, 95th greater than median
    #expect(result.p5WinRate <= result.medianWinRate)
    #expect(result.p95WinRate >= result.medianWinRate)
    // Max drawdown must be positive
    #expect(result.maxDrawdownWorstCase >= result.maxDrawdownMedian)
    #expect(result.maxDrawdownMedian > 0)
    // Profitable runs rate should be predominantly positive for 60% win rate
    #expect(result.positiveEVRate > 0.80)
}


@Test func numericGuardsPreserveExplicitFiniteRiskConfiguration() {
    let custom = ExpectancyMath.recommendedStake(bankroll: 10_000, winRate: 0.65,
        payoutRatio: 0.88, fraction: 0.25, maxRiskCeiling: 0.05)
    #expect(custom == 500)
    let overflow = ExpectancyMath.recommendedStake(bankroll: 1e300, winRate: 1,
        payoutRatio: 0.88, fraction: 1e300, maxRiskCeiling: 1e300)
    #expect(overflow == 0)
}
