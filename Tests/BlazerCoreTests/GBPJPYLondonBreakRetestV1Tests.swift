import Foundation
import Testing
@testable import BlazerCore

struct GBPJPYLondonBreakRetestV1Tests {
    private let codeDigest = String(repeating: "a", count: 64)
    private let snapshotDigest = String(repeating: "b", count: 64)

    private func date(_ iso: String = "2027-01-15T07:00:00Z") -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    private func configuration(minimumRange: Double = 10, maximumRange: Double = 40,
        minimumBreakout: Double = 5, tolerance: Double = 1, maximumRetestBars: Int = 3,
        maximumSpread: Double = 3, maximumQuoteAge: TimeInterval = 5,
        maximumSetupAge: TimeInterval = 600, cooldown: TimeInterval = 0,
        stopBuffer: Double = 0.2, targetR: Double = 2, atrLookback: Int = 3,
        atrMethod: GBPJPYLondonBreakRetestATRMethod = .simpleMeanTrueRangeV1,
        rangeDuration: Int = 300) -> GBPJPYLondonBreakRetestConfiguration {
        GBPJPYLondonBreakRetestConfiguration(version: "candidate-a-fixture-v1", pipSize: 0.01,
            rangeDurationSeconds: rangeDuration, minimumRangePips: minimumRange,
            maximumRangePips: maximumRange, minimumBreakoutPips: minimumBreakout,
            retestTolerancePips: tolerance, maximumRetestBars: maximumRetestBars,
            atrMethod: atrMethod, atrLookbackBars: atrLookback, stopBufferATRMultiple: stopBuffer,
            targetRMultiple: targetR, maximumSpreadPips: maximumSpread,
            maximumQuoteAgeSeconds: maximumQuoteAge, maximumSetupAgeSeconds: maximumSetupAge,
            cooldownSeconds: cooldown)
    }

    private func fixture(start: Date = Date(timeIntervalSince1970: 1_800_000_000),
                         direction: GBPJPYLondonBreakRetestDirection = .long,
                         retestClose: Double? = nil,
                         retestDistance: Double = 0) -> (bars: [GBPJPYLondonBreakRetestBar],
            session: GBPJPYLondonBreakRetestSession, quote: GBPJPYLondonBreakRetestQuote,
            provenance: GBPJPYLondonBreakRetestProvenance, asOf: Date) {
        let session = GBPJPYLondonBreakRetestSession(id: "london-2027-01-15",
            timeZoneIdentifier: "Europe/London", calendarDigest: "calendar-v1",
            opensAt: start, rangeStartsAt: start, rangeEndsAt: start.addingTimeInterval(300),
            closesAt: start.addingTimeInterval(1_200))
        let values: [(Double, Double, Double, Double)]
        if direction == .long {
            values = [
                (150.00, 150.08, 149.96, 150.02),
                (150.02, 150.10, 149.98, 150.05),
                (150.05, 150.09, 149.93, 150.00),
                (150.00, 150.07, 149.90, 149.98),
                (149.98, 150.06, 149.95, 150.01),
                (150.06, 150.30, 150.04, 150.25),
                (150.20, 150.22, 150.10 - retestDistance, retestClose ?? 150.15)
            ]
        } else {
            values = [
                (150.00, 150.08, 149.96, 150.02),
                (150.02, 150.10, 149.98, 150.05),
                (150.05, 150.09, 149.93, 150.00),
                (150.00, 150.07, 149.90, 149.98),
                (149.98, 150.06, 149.95, 150.01),
                (149.94, 149.96, 149.70, 149.75),
                (149.80, 149.90 + retestDistance, 149.72, retestClose ?? 149.85)
            ]
        }
        let bars = values.enumerated().map { index, value in
            GBPJPYLondonBreakRetestBar(id: "m1-\(index)", instrument: "GBP/JPY", provider: "OANDA",
                startTime: start.addingTimeInterval(Double(index * 60)), open: value.0,
                high: value.1, low: value.2, close: value.3)
        }
        let quote: GBPJPYLondonBreakRetestQuote
        if direction == .long {
            quote = GBPJPYLondonBreakRetestQuote(sourceID: "pricing-7", bid: 150.15, ask: 150.16,
                observedAt: start.addingTimeInterval(421))
        } else {
            quote = GBPJPYLondonBreakRetestQuote(sourceID: "pricing-7", bid: 149.84, ask: 149.85,
                observedAt: start.addingTimeInterval(421))
        }
        let provenance = GBPJPYLondonBreakRetestProvenance(provider: "OANDA", environment: "live",
            buildID: "build-fixture", codeDigest: codeDigest, snapshotDigest: snapshotDigest,
            lineageIsProviderNative: true)
        return (bars, session, quote, provenance, start.addingTimeInterval(421))
    }

    private func evaluate(_ f: (bars: [GBPJPYLondonBreakRetestBar],
        session: GBPJPYLondonBreakRetestSession, quote: GBPJPYLondonBreakRetestQuote,
        provenance: GBPJPYLondonBreakRetestProvenance, asOf: Date),
        configuration: GBPJPYLondonBreakRetestConfiguration? = nil,
        quote: GBPJPYLondonBreakRetestQuote? = nil,
        bars: [GBPJPYLondonBreakRetestBar]? = nil,
        session: GBPJPYLondonBreakRetestSession? = nil,
        provenance: GBPJPYLondonBreakRetestProvenance? = nil,
        asOf: Date? = nil, lastSignalAt: Date? = nil) -> GBPJPYLondonBreakRetestDecision {
        GBPJPYLondonBreakRetestV1.evaluate(bars: bars ?? f.bars,
            session: session ?? f.session, quote: quote ?? f.quote,
            provenance: provenance ?? f.provenance, asOf: asOf ?? f.asOf,
            configuration: configuration ?? self.configuration(), lastSignalAt: lastSignalAt)
    }

    @Test func longBreakoutRetestUsesAskAndCreatesStructuralReferences() {
        let f = fixture()
        let result = evaluate(f)
        #expect(result.state == .signal)
        #expect(result.direction == .long)
        #expect(result.reason == .setupReady)
        #expect(result.breakoutBarID == "m1-5")
        #expect(result.retestBarID == "m1-6")
        #expect(result.entryReference == f.quote.ask)
        #expect(result.stopReference! < result.entryReference!)
        #expect(result.targetReference! > result.entryReference!)
        #expect(abs((result.spreadPips ?? 0) - 1) < 1e-9)
        #expect(result.sourceBarIDs.suffix(2) == ["m1-5", "m1-6"])
    }

    @Test func shortBreakoutRetestUsesBidAndOrdersStopTargetCorrectly() {
        let f = fixture(direction: .short)
        let result = evaluate(f)
        #expect(result.state == .signal)
        #expect(result.direction == .short)
        #expect(result.entryReference == f.quote.bid)
        #expect(result.stopReference! > result.entryReference!)
        #expect(result.targetReference! < result.entryReference!)
    }

    @Test func candidateIsDeterministicAndConfigurationChangesDigest() {
        let f = fixture()
        let one = evaluate(f)
        let two = evaluate(f)
        let changed = evaluate(f, configuration: configuration(targetR: 3))
        let refreshedQuote = GBPJPYLondonBreakRetestQuote(sourceID: "pricing-8", bid: 150.16,
            ask: 150.17, observedAt: f.quote.observedAt.addingTimeInterval(1))
        let refreshed = evaluate(f, quote: refreshedQuote,
            asOf: f.asOf.addingTimeInterval(1))
        #expect(one == two)
        #expect(one.inputDigest.count == 64)
        #expect(one.configurationDigest != changed.configurationDigest)
        #expect(one.inputDigest != changed.inputDigest)
        #expect(one.id == two.id)
        #expect(one.id == refreshed.id)
        #expect(one.inputDigest != refreshed.inputDigest)
        #expect(one.calendarDigest == f.session.calendarDigest)
        #expect(one.provider == f.provenance.provider)
        #expect(one.sourceSnapshotDigest == f.provenance.snapshotDigest)
    }

    @Test func rejectsMissingOrInvalidRequiredConfiguration() {
        let f = fixture()
        let invalid = evaluate(f, configuration: configuration(minimumBreakout: .nan))
        #expect(invalid.state == .rejected)
        #expect(invalid.reason == .configurationInvalid)
        #expect(configuration(rangeDuration: 301).validationIssues().contains("range_duration_invalid"))
        let unknownATR = configuration(atrMethod: .unsupported("ATR_UNKNOWN"))
        #expect(unknownATR.validationIssues().contains("atr_method_unsupported"))
        #expect(evaluate(f, configuration: unknownATR).reason == .configurationInvalid)

        let encoder = JSONEncoder()
        let object = try! JSONSerialization.jsonObject(with: encoder.encode(configuration())) as! [String: Any]
        var missingMethod = object
        missingMethod.removeValue(forKey: "atrMethod")
        let data = try! JSONSerialization.data(withJSONObject: missingMethod)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(GBPJPYLondonBreakRetestConfiguration.self, from: data)
        }
    }

    @Test func canonicalDigestsPreserveDistinctNonconformingFloats() {
        let nanConfig = configuration(minimumBreakout: .nan)
        let positiveInfinityConfig = configuration(minimumBreakout: .infinity)
        let negativeInfinityConfig = configuration(minimumBreakout: -.infinity)
        #expect(nanConfig.digest() != positiveInfinityConfig.digest())
        #expect(nanConfig.digest() != negativeInfinityConfig.digest())
        #expect(positiveInfinityConfig.digest() != negativeInfinityConfig.digest())

        let f = fixture()
        func decision(bid: Double) -> GBPJPYLondonBreakRetestDecision {
            let invalid = GBPJPYLondonBreakRetestQuote(sourceID: "nonfinite", bid: bid,
                ask: 150.16, observedAt: f.quote.observedAt)
            return evaluate(f, quote: invalid)
        }
        let nan = decision(bid: .nan)
        let positiveInfinity = decision(bid: .infinity)
        let negativeInfinity = decision(bid: -.infinity)
        #expect(nan.inputDigest != positiveInfinity.inputDigest)
        #expect(nan.inputDigest != negativeInfinity.inputDigest)
        #expect(positiveInfinity.inputDigest != negativeInfinity.inputDigest)
    }

    @Test func rangeWidthAndBreakoutDistanceGatesAreExplicit() {
        let f = fixture()
        let narrow = evaluate(f, configuration: configuration(minimumRange: 21))
        #expect(narrow.reason == .rangeTooNarrow)
        let wide = evaluate(f, configuration: configuration(maximumRange: 19))
        #expect(wide.reason == .rangeTooWide)
        let notFarEnough = evaluate(f, configuration: configuration(minimumBreakout: 20))
        #expect(notFarEnough.state == .wait)
        #expect(notFarEnough.reason == .waitingForBreakout)
        let setupTooOld = evaluate(f, configuration: configuration(maximumSetupAge: 30))
        #expect(setupTooOld.state == .expired)
        #expect(setupTooOld.reason == .setupTooOld)
        let insufficientATR = evaluate(f, configuration: configuration(atrLookback: 8))
        #expect(insufficientATR.state == .wait)
        #expect(insufficientATR.reason == .rangeDataInvalid)
    }

    @Test func retestMustTouchBoundaryAndCloseOnBreakSideWithinLimit() {
        let missed = fixture(retestDistance: 0.1)
        let missedResult = evaluate(missed, configuration: configuration(maximumRetestBars: 3))
        #expect(missedResult.state == .wait)
        #expect(missedResult.reason == .waitingForRetest)

        let failed = fixture(retestClose: 150.10)
        let failedResult = evaluate(failed)
        #expect(failedResult.state == .rejected)
        #expect(failedResult.reason == .retestFailed)

        var timeout = Array(missed.bars.prefix(6))
        for index in 6...8 {
            timeout.append(GBPJPYLondonBreakRetestBar(id: "m1-\(index)", instrument: "GBP/JPY",
                provider: "OANDA", startTime: missed.session.opensAt.addingTimeInterval(Double(index * 60)),
                open: 150.2, high: 150.3, low: 150.2, close: 150.25))
        }
        let timedOut = evaluate(missed, configuration: configuration(maximumRetestBars: 2),
            bars: timeout, asOf: missed.session.opensAt.addingTimeInterval(541))
        #expect(timedOut.state == .expired)
        #expect(timedOut.reason == .retestExpired)
    }

    @Test func deepBoundaryPenetrationWithCloseBackInsideFailsInBothDirections() {
        let long = fixture(retestClose: 150.05, retestDistance: 0.15)
        let longResult = evaluate(long)
        #expect(longResult.state == .rejected)
        #expect(longResult.reason == .retestFailed)

        let short = fixture(direction: .short, retestClose: 149.95, retestDistance: 0.15)
        let shortResult = evaluate(short)
        #expect(shortResult.state == .rejected)
        #expect(shortResult.reason == .retestFailed)
    }

    @Test func requiresCausalChronologyAndFreshPostRetestQuote() {
        let f = fixture()
        let equalCloseQuote = GBPJPYLondonBreakRetestQuote(sourceID: "q", bid: 150.15, ask: 150.16,
            observedAt: f.session.opensAt.addingTimeInterval(420))
        #expect(evaluate(f, quote: equalCloseQuote).reason == .quoteNotAfterRetest)
        let futureQuote = GBPJPYLondonBreakRetestQuote(sourceID: "q", bid: 150.15, ask: 150.16,
            observedAt: f.asOf.addingTimeInterval(1))
        #expect(evaluate(f, quote: futureQuote).reason == .quoteInvalid)
        let staleQuote = GBPJPYLondonBreakRetestQuote(sourceID: "q", bid: 150.15, ask: 150.16,
            observedAt: f.session.opensAt.addingTimeInterval(421))
        #expect(evaluate(f, quote: staleQuote,
            asOf: f.session.opensAt.addingTimeInterval(430)).reason == .quoteStale)

        let breakoutClose = f.bars[5].startTime.addingTimeInterval(60)
        let retestClose = f.bars[6].startTime.addingTimeInterval(60)
        #expect(f.session.rangeEndsAt <= breakoutClose)
        #expect(breakoutClose < retestClose)
        #expect(retestClose < f.quote.observedAt)
        #expect(f.quote.observedAt <= f.asOf)

        var futureBars = f.bars
        futureBars[6] = GBPJPYLondonBreakRetestBar(id: "m1-6", instrument: "GBP/JPY", provider: "OANDA",
            startTime: f.bars[6].startTime, open: 150.20, high: 150.22, low: 150.10,
            close: 150.15, complete: false)
        let causal = evaluate(f, bars: futureBars, asOf: f.session.opensAt.addingTimeInterval(400))
        #expect(causal.state == .wait)
        #expect(causal.reason == .waitingForRetest)
    }

    @Test func rejectsDuplicateGappedMalformedAndFutureCompletedBars() {
        let f = fixture()
        var duplicate = f.bars
        duplicate[6] = GBPJPYLondonBreakRetestBar(id: duplicate[5].id, instrument: "GBP/JPY",
            provider: "OANDA", startTime: duplicate[6].startTime, open: 150.2, high: 150.22,
            low: 150.1, close: 150.15)
        #expect(evaluate(f, bars: duplicate).reason == .rangeDataInvalid)

        var gapped = f.bars
        gapped[6] = GBPJPYLondonBreakRetestBar(id: "m1-6", instrument: "GBP/JPY", provider: "OANDA",
            startTime: f.bars[6].startTime.addingTimeInterval(60), open: 150.2, high: 150.22,
            low: 150.1, close: 150.15)
        #expect(evaluate(f, bars: gapped).reason == .rangeDataInvalid)

        var malformed = f.bars
        malformed[4] = GBPJPYLondonBreakRetestBar(id: "m1-4", instrument: "GBP/JPY", provider: "OANDA",
            startTime: f.bars[4].startTime, open: 150, high: 149, low: 150.1, close: 150)
        #expect(evaluate(f, bars: malformed).reason == .rangeDataInvalid)

        let atClose = evaluate(f, asOf: f.session.closesAt)
        #expect(atClose.state == .expired)
        #expect(atClose.reason == .sessionClosed)
        #expect(evaluate(f, asOf: f.session.closesAt.addingTimeInterval(1)).reason == .sessionClosed)
    }

    @Test func quoteSpreadProvenanceAndCooldownFailClosed() {
        let f = fixture()
        let wideSpread = GBPJPYLondonBreakRetestQuote(sourceID: "q", bid: 150.10, ask: 150.15,
            observedAt: f.quote.observedAt)
        #expect(evaluate(f, configuration: configuration(maximumSpread: 2),
            quote: wideSpread).reason == .spreadTooWide)
        let badQuote = GBPJPYLondonBreakRetestQuote(sourceID: "q", bid: .nan, ask: 150.16,
            observedAt: f.quote.observedAt)
        #expect(evaluate(f, quote: badQuote).reason == .quoteInvalid)

        let badProvenance = GBPJPYLondonBreakRetestProvenance(provider: "OANDA", environment: "live",
            buildID: "build-fixture", codeDigest: "bad", snapshotDigest: snapshotDigest,
            lineageIsProviderNative: false)
        #expect(evaluate(f, provenance: badProvenance).reason == .provenanceInvalid)
        #expect(evaluate(f, configuration: configuration(cooldown: 60),
            lastSignalAt: f.asOf.addingTimeInterval(-30)).reason == .cooldownActive)
    }

    @Test func sessionMustBeLondonAndAbsoluteDSTBoundariesAreHonored() {
        let winter = fixture(start: date("2027-01-15T07:00:00Z"))
        #expect(evaluate(winter).state == .signal)
        let summer = fixture(start: date("2027-07-15T06:00:00Z"))
        #expect(evaluate(summer).state == .signal)

        let utcSession = GBPJPYLondonBreakRetestSession(id: winter.session.id,
            timeZoneIdentifier: "UTC", calendarDigest: "calendar-v1",
            opensAt: winter.session.opensAt, rangeStartsAt: winter.session.rangeStartsAt,
            rangeEndsAt: winter.session.rangeEndsAt, closesAt: winter.session.closesAt)
        #expect(evaluate(winter, session: utcSession).reason == .sessionInvalid)

        let crossDate = GBPJPYLondonBreakRetestSession(id: "cross-date",
            timeZoneIdentifier: "Europe/London", calendarDigest: "calendar-v1",
            opensAt: date("2027-01-15T23:00:00Z"), rangeStartsAt: date("2027-01-15T23:00:00Z"),
            rangeEndsAt: date("2027-01-15T23:05:00Z"), closesAt: date("2027-01-16T00:00:00Z"))
        #expect(evaluate(winter, session: crossDate).reason == .sessionInvalid)
    }
}
