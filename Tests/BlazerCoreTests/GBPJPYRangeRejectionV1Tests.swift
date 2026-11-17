import Foundation
import Testing
@testable import BlazerCore

struct GBPJPYRangeRejectionV1Tests {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                   hour: hour, minute: minute))!
    }

    private var config: GBPJPYRangeRejectionConfiguration {
        GBPJPYRangeRejectionConfiguration(version: "1.0", timeZoneIdentifier: "Europe/London",
            rangeStartHour: 8, rangeStartMinute: 0, rangeCutoffHour: 8, rangeCutoffMinute: 3,
            timeframeSeconds: 60, minimumRangePips: 2, maximumRangePips: 10,
            touchTolerancePips: 0.2, atrLookbackBars: 2, maximumEventRangeATR: 3,
            stopBufferATRMultiple: 2, targetPolicy: .rangeMidpoint, maximumSpreadPips: 2,
            maximumEventAgeSeconds: 180, maximumQuoteAgeSeconds: 10, cooldownSeconds: 60)
    }

    private func bar(_ id: String, _ time: Date, _ open: Double, _ high: Double,
                     _ low: Double, _ close: Double, complete: Bool = true) -> GBPJPYRangeRejectionBar {
        GBPJPYRangeRejectionBar(id: id, startTime: time, open: open, high: high,
                                low: low, close: close, complete: complete)
    }

    private func bars(_ day: Int = 9) -> [GBPJPYRangeRejectionBar] {
        let start = date(2026, 11, day, 8, 0)
        return [
            bar("r0", start, 200.00, 200.02, 199.98, 200.00),
            bar("r1", start.addingTimeInterval(60), 200.00, 200.02, 199.98, 200.00),
            bar("r2", start.addingTimeInterval(120), 200.00, 200.02, 199.98, 200.00),
            bar("a0", start.addingTimeInterval(180), 200.00, 200.01, 199.99, 200.00),
            bar("a1", start.addingTimeInterval(240), 200.00, 200.01, 199.99, 200.00),
            bar("touch", start.addingTimeInterval(300), 200.00, 200.01, 199.98, 200.005)
        ]
    }

    private func quote(_ at: Date, spread: Double = 0.001) -> GBPJPYRangeRejectionQuote {
        GBPJPYRangeRejectionQuote(sourceID: "fixture-feed", bid: 199.994,
                                  ask: 199.994 + spread, observedAt: at)
    }

    @Test func lowerBoundaryRejectionSignalsLongAtAskWithOrderedLevels() {
        let source = bars()
        let eventEnd = source.last!.startTime.addingTimeInterval(60)
        let result = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(result.state == .signal)
        #expect(result.direction == .long)
        #expect(result.entryPrice == 199.995)
        #expect(result.stopPrice! < result.entryPrice!)
        #expect(result.targetPrice! > result.entryPrice!)
        #expect(abs(result.stopPrice! - (199.98 - 2 * 0.02)) < 1e-9)
        #expect(result.timeframeSeconds == 60)
        #expect(result.eventBarID == "touch")
        #expect(result.sourceBarIDs.contains("r2"))
        #expect(result.sourceBarIDs.contains("a0"))
        #expect(result.sourceBarIDs.contains("a1"))
        #expect(result.quoteSourceID == "fixture-feed")
        #expect(result.sourceBarIDs.contains("touch"))
    }

    @Test func spreadAndExpansionVetoAreExplicitAndFutureBarsDoNotChangeEvidence() {
        let source = bars()
        let eventEnd = source.last!.startTime.addingTimeInterval(60)
        let baseline = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        let replay = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(replay == baseline)
        let reordered = GBPJPYRangeRejectionV1.evaluate(bars: Array(source.reversed()), quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(reordered.inputDigest == baseline.inputDigest)
        let future = bar("future", eventEnd, 199.99, 200.03, 199.97, 200.02)
        let withFuture = GBPJPYRangeRejectionV1.evaluate(bars: source + [future], quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(withFuture == baseline)
        let wideSpread = GBPJPYRangeRejectionV1.evaluate(bars: source,
            quote: quote(eventEnd, spread: 0.05), asOf: eventEnd, configuration: config)
        #expect(wideSpread.reasonCodes.contains("spread_exceeds_config"))

        let oldQuote = quote(eventEnd)
        let quoteStale = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: oldQuote,
            asOf: eventEnd.addingTimeInterval(11), configuration: config)
        #expect(quoteStale.reasonCodes.contains("fresh_post_confirmation_quote_required"))

        var expandedBars = Array(source.dropLast())
        expandedBars.append(bar("touch", source.last!.startTime, 200.00, 200.08, 200.00, 200.005))
        let expanded = GBPJPYRangeRejectionV1.evaluate(bars: expandedBars, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(expanded.reasonCodes.contains("atr_expansion_veto"))

        let outside = Array(source.dropLast()) + [
            bar("outside", source.last!.startTime, 200, 200.04, 199.98, 200.03)
        ]
        let closeOutside = GBPJPYRangeRejectionV1.evaluate(bars: outside, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(closeOutside.reasonCodes.contains("rejection_close_outside_range"))

        let upperBars = Array(source.dropLast()) + [
            bar("upper", source.last!.startTime, 200.01, 200.03, 200.00, 200.01)
        ]
        let upper = GBPJPYRangeRejectionV1.evaluate(bars: upperBars,
            quote: GBPJPYRangeRejectionQuote(sourceID: "fixture-feed", bid: 200.005,
                ask: 200.006, observedAt: eventEnd), asOf: eventEnd, configuration: config)
        #expect(upper.state == .signal)
        #expect(upper.direction == .short)
        #expect(upper.entryPrice == 200.005)

        let dualBars = Array(source.dropLast()) + [
            bar("dual", source.last!.startTime, 200, 200.03, 199.97, 200)
        ]
        let dual = GBPJPYRangeRejectionV1.evaluate(bars: dualBars, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(dual.reasonCodes.contains("ambiguous_two_boundary_rejection"))
    }

    @Test func ignoresIncompleteBarsAndRejectsStaleEventAndAnchorsLocalSessionAcrossDST() {
        let march = bars(30)
        let eventEnd = march.last!.startTime.addingTimeInterval(60)
        let baseline = GBPJPYRangeRejectionV1.evaluate(bars: march, quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        let incomplete = bar("partial", eventEnd, 200, 200.1, 199.9, 200, complete: false)
        let partial = GBPJPYRangeRejectionV1.evaluate(bars: march + [incomplete], quote: quote(eventEnd),
            asOf: eventEnd, configuration: config)
        #expect(partial == baseline)
        #expect(baseline.rangeStart == date(2026, 11, 30, 8, 0))

        let stale = GBPJPYRangeRejectionV1.evaluate(bars: march, quote: quote(eventEnd),
            asOf: eventEnd.addingTimeInterval(181), configuration: config)
        #expect(stale.reasonCodes.contains("event_stale"))
        let springStart = date(2026, 3, 30, 8, 0)
        let springBars = barsFor(start: springStart)
        let springEnd = springBars.last!.startTime.addingTimeInterval(60)
        let spring = GBPJPYRangeRejectionV1.evaluate(bars: springBars, quote: quote(springEnd),
            asOf: springEnd, configuration: config)
        #expect(spring.rangeStart == springStart)
        #expect(spring.state == .signal)
    }

    @Test func rejectsDSTBoundaryDurationMismatchForRealTransitionDates() {
        let transitionConfig = GBPJPYRangeRejectionConfiguration(version: "dst-test",
            timeZoneIdentifier: "Europe/London", rangeStartHour: 0, rangeStartMinute: 30,
            rangeCutoffHour: 2, rangeCutoffMinute: 30, timeframeSeconds: 60,
            minimumRangePips: 2, maximumRangePips: 20, touchTolerancePips: 0.2,
            atrLookbackBars: 2, maximumEventRangeATR: 3, stopBufferATRMultiple: 2,
            targetPolicy: .rangeMidpoint, maximumSpreadPips: 2, maximumEventAgeSeconds: 180,
            maximumQuoteAgeSeconds: 10, cooldownSeconds: 60)
        for day in [29, 25] {
            let transitionMonth = day == 29 ? 3 : 10
            let asOf = date(2026, transitionMonth, day, 4, 0)
            let result = GBPJPYRangeRejectionV1.evaluate(bars: [], quote: nil, asOf: asOf,
                configuration: transitionConfig)
            #expect(result.reasonCodes.contains("session_boundary_elapsed_duration_mismatch"))
        }
    }

    @Test func rejectsDuplicateAndOffGridPostRangeBarsAndHonorsQuoteAgeBoundary() {
        let source = bars()
        let eventEnd = source.last!.startTime.addingTimeInterval(60)
        let duplicate = GBPJPYRangeRejectionV1.evaluate(bars: source + [
            bar("duplicate-time", source[1].startTime, 200, 200.01, 199.99, 200)
        ], quote: quote(eventEnd), asOf: eventEnd, configuration: config)
        #expect(duplicate.reasonCodes.contains("duplicate_bar_identity_or_time"))

        let offGridBars = Array(source.dropLast()) + [
            bar("off-grid", source.last!.startTime.addingTimeInterval(30),
                200, 200.01, 199.98, 200.005)
        ]
        let offGridEnd = offGridBars.last!.startTime.addingTimeInterval(60)
        let offGrid = GBPJPYRangeRejectionV1.evaluate(bars: offGridBars,
            quote: quote(offGridEnd), asOf: offGridEnd, configuration: config)
        #expect(offGrid.reasonCodes.contains("post_range_bar_off_timeframe_grid"))

        let atBoundary = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: quote(eventEnd),
            asOf: eventEnd.addingTimeInterval(10), configuration: config)
        #expect(atBoundary.state == .signal)
        let beyondBoundary = GBPJPYRangeRejectionV1.evaluate(bars: source, quote: quote(eventEnd),
            asOf: eventEnd.addingTimeInterval(10.001), configuration: config)
        #expect(beyondBoundary.reasonCodes.contains("fresh_post_confirmation_quote_required"))
    }

    private func barsFor(start: Date) -> [GBPJPYRangeRejectionBar] {
        [
            bar("r0", start, 200, 200.02, 199.98, 200),
            bar("r1", start.addingTimeInterval(60), 200, 200.02, 199.98, 200),
            bar("r2", start.addingTimeInterval(120), 200, 200.02, 199.98, 200),
            bar("a0", start.addingTimeInterval(180), 200, 200.01, 199.99, 200),
            bar("a1", start.addingTimeInterval(240), 200, 200.01, 199.99, 200),
            bar("touch", start.addingTimeInterval(300), 200, 200.01, 199.98, 200.005)
        ]
    }
}
