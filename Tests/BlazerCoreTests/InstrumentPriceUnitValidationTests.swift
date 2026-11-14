import Foundation
import Testing
@testable import BlazerCore

struct InstrumentPriceUnitValidationTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    @Test func instrumentPipScalesConvertRawPriceDistances() {
        #expect(Assets.pipScale(for: "EUR/USD") == 0.0001)
        #expect(Assets.pipScale(for: "GBP/JPY") == 0.01)

        #expect(abs(0.0003 / Assets.pipScale(for: "EUR/USD") - 3) < 1e-12)
        #expect(abs(0.03 / Assets.pipScale(for: "GBP/JPY") - 3) < 1e-12)
    }

    @Test func orbSpreadLimitIsAnAbsolutePriceDistanceNotPips() {
        let configuration = ORBConfiguration()

        // Keep this raw-price comparison explicit: maximumSpread is not a pip value.
        #expect(configuration.maximumSpread == 0.0003)
        #expect(abs(configuration.maximumSpread / Assets.pipScale(for: "EUR/USD") - 3) < 1e-12)
        #expect(abs(configuration.maximumSpread / Assets.pipScale(for: "GBP/JPY") - 0.03) < 1e-12)
    }

    @Test func v3PlansValidateTheRawSpreadValueForEachInstrument() {
        let euroPlan = plan(instrument: "EUR/USD", entry: 1.1000, stop: 1.0990, target: 1.1020)
        let sterlingYenPlan = plan(instrument: "GBP/JPY", entry: 190.00, stop: 189.90, target: 190.20)

        #expect(euroPlan.validation().isEmpty)
        #expect(sterlingYenPlan.validation().isEmpty)
        #expect(euroPlan.maxSpread == sterlingYenPlan.maxSpread)
        #expect(euroPlan.maxSpread == ORBConfiguration().maximumSpread)
    }

    @Test func v3ReplayUsesRawDistanceSoTheSameLimitHasDifferentPipMeaning() {
        let euroPlan = plan(instrument: "EUR/USD", entry: 1.1000, stop: 1.0990, target: 1.1020)
        let sterlingYenPlan = plan(instrument: "GBP/JPY", entry: 190.00, stop: 189.90, target: 190.20)

        let euroWithin = archiveEntry(for: euroPlan, spread: 0.0002)
        let euroOutside = archiveEntry(for: euroPlan, spread: 0.0004)
        let sterlingYenWithin = archiveEntry(for: sterlingYenPlan, spread: 0.0002)
        let sterlingYenOutside = archiveEntry(for: sterlingYenPlan, spread: 0.0004)

        #expect(ORBArchiveStructuralReplay.evaluate(plan: euroPlan, candles: [euroWithin]).entryQuoteWithinPlanMaxSpread == true)
        #expect(ORBArchiveStructuralReplay.evaluate(plan: euroPlan, candles: [euroOutside]).entryQuoteWithinPlanMaxSpread == false)
        #expect(ORBArchiveStructuralReplay.evaluate(plan: sterlingYenPlan, candles: [sterlingYenWithin]).entryQuoteWithinPlanMaxSpread == true)
        #expect(ORBArchiveStructuralReplay.evaluate(plan: sterlingYenPlan, candles: [sterlingYenOutside]).entryQuoteWithinPlanMaxSpread == false)

        #expect(abs(0.0002 / Assets.pipScale(for: "GBP/JPY") - 0.02) < 1e-12)
        #expect(abs(0.0004 / Assets.pipScale(for: "GBP/JPY") - 0.04) < 1e-12)
    }

    private func plan(instrument: String, entry: Double, stop: Double, target: Double) -> V3TradePlan {
        V3TradePlan(id: "unit-\(instrument)", instrument: instrument,
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "unit-test",
            state: .validated, side: .long, entryPrice: entry, stopPrice: stop,
            targetPrice: target, units: 1, maxSpread: ORBConfiguration().maximumSpread,
            riskFraction: 0.01, createdAt: now)
    }

    private func archiveEntry(for plan: V3TradePlan, spread: Double) -> OandaBidAskCandle {
        let bid = plan.entryPrice - spread / 2
        let ask = plan.entryPrice + spread / 2
        return OandaBidAskCandle(instrument: plan.instrument, granularity: "M1",
            sourceTime: plan.createdAt.addingTimeInterval(-60), complete: true,
            bidOpen: bid, bidHigh: bid, bidLow: bid, bidClose: bid,
            askOpen: ask, askHigh: ask, askLow: ask, askClose: ask)
    }
}
