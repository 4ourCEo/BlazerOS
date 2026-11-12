import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import BlazerCore

struct ORBBreakRetestV1Tests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func bar(_ id: String, _ start: Date, open: Double, high: Double,
                     low: Double, close: Double) -> ORBBar {
        ORBBar(id: id, instrument: "EUR/USD", sourceTime: start,
               endTime: start.addingTimeInterval(60), open: open, high: high,
               low: low, close: close)
    }

    private func openingRange(_ year: Int = 2026, _ month: Int = 11,
                              _ day: Int = 6) -> [ORBBar] {
        let start = date(year, month, day, 9, 30)
        return (0..<5).map { index in
            bar("r\(index)", start.addingTimeInterval(Double(index * 60)),
                open: 1.102, high: 1.105, low: 1.100, close: 1.102)
        }
    }

    @Test func confirmsLongBreakRetestAndCreatesCompletePlan() {
        let start = date(2026, 11, 6, 9, 35)
        let bars = openingRange() + [
            bar("break", start, open: 1.104, high: 1.107, low: 1.103, close: 1.106),
            bar("retest", start.addingTimeInterval(60), open: 1.1055, high: 1.106,
                low: 1.1049, close: 1.1052),
            bar("confirm", start.addingTimeInterval(120), open: 1.1052, high: 1.107,
                low: 1.105, close: 1.106)
        ]
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                                  asOf: start.addingTimeInterval(180))
        #expect(decision.stage == .setupConfirmed)
        #expect(decision.setupState == .confirmed)
        #expect(decision.direction == .long)
        #expect(decision.candidate?.plan.side == .long)
        #expect(decision.candidate?.plan.rewardRisk == 2)
        #expect(decision.candidate?.plan.validation().isEmpty == true)
    }

    @Test func confirmsShortBreakRetestWithExecutablePlanLevels() {
        let start = date(2026, 11, 6, 9, 35)
        let range = openingRange().map { bar($0.id, $0.sourceTime, open: 1.102,
                                             high: 1.105, low: 1.100, close: 1.102) }
        let bars = range + [
            bar("break", start, open: 1.101, high: 1.102, low: 1.098, close: 1.099),
            bar("retest", start.addingTimeInterval(60), open: 1.099, high: 1.10005,
                low: 1.0985, close: 1.0998),
            bar("confirm", start.addingTimeInterval(120), open: 1.0998, high: 1.0999,
                low: 1.098, close: 1.099)
        ]
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                                  asOf: start.addingTimeInterval(180))
        #expect(decision.stage == .setupConfirmed)
        #expect(decision.direction == .short)
        #expect(decision.candidate?.plan.stopPrice ?? 0 > decision.candidate?.plan.entryPrice ?? 1)
        #expect(decision.candidate?.plan.targetPrice ?? 1 < decision.candidate?.plan.entryPrice ?? 0)
    }

    @Test func missingOpeningBarIsUnresolvedNotASetup() {
        var bars = openingRange()
        bars.remove(at: 2)
        let asOf = date(2026, 11, 6, 9, 36)
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars, asOf: asOf)
        #expect(decision.stage == .unavailable)
        #expect(decision.setupState == .unresolved)
        #expect(decision.reason == "opening_range_missing_or_out_of_order")
    }

    @Test func futureBarsCannotCreateLookaheadSetup() {
        let start = date(2026, 11, 6, 9, 35)
        let bars = openingRange() + [
            bar("future-break", start, open: 1.104, high: 1.107, low: 1.103, close: 1.106),
            bar("future-retest", start.addingTimeInterval(60), open: 1.1055, high: 1.106,
                low: 1.1049, close: 1.1052),
            bar("future-confirm", start.addingTimeInterval(120), open: 1.1052, high: 1.107,
                low: 1.105, close: 1.106)
        ]
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                                  asOf: start.addingTimeInterval(60))
        #expect(decision.candidate == nil)
        #expect(decision.stage == .retestPending)
    }

    @Test func failedRetestInvalidatesSetup() {
        let start = date(2026, 11, 6, 9, 35)
        let bars = openingRange() + [
            bar("break", start, open: 1.104, high: 1.107, low: 1.103, close: 1.106),
            bar("failed-retest", start.addingTimeInterval(60), open: 1.104,
                high: 1.105, low: 1.102, close: 1.1048)
        ]
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                                  asOf: start.addingTimeInterval(120))
        #expect(decision.stage == .invalidated)
        #expect(decision.setupState == .invalidated)
    }

    @Test func daylightSavingSessionStillAnchorsAtNineThirtyEastern() {
        let start = date(2026, 3, 9, 9, 35)
        let bars = openingRange(2026, 3, 9) + [
            bar("break", start, open: 1.104, high: 1.107, low: 1.103, close: 1.106)
        ]
        let decision = ORBBreakRetestV1.evaluate(instrument: "EUR/USD", bars: bars,
                                                  asOf: start.addingTimeInterval(60))
        #expect(decision.sessionStart == date(2026, 3, 9, 9, 30))
        #expect(decision.stage == .retestPending)
    }

    @Test func notificationsAreStageBoundDeepLinkedAndDeduplicated() {
        let decision = ORBDecision(stage: .retestPending, setupState: .confirmed,
                                   sessionStart: date(2026, 11, 6, 9, 30),
                                   reason: "retest_waiting")
        let sourceTime = date(2026, 11, 6, 9, 37)
        let notification = ORBNotificationPlanner.plan(for: decision, instrument: "EUR/USD",
                                                       sourceTime: sourceTime)
        #expect(notification?.stage == .retestPending)
        #expect(notification?.deepLink.contains("ORB_BREAK_RETEST_V1") == true)
        #expect(ORBNotificationPlanner.plan(for: decision, instrument: "EUR/USD",
                                            sourceTime: sourceTime,
                                            previouslyDelivered: [notification!.id]) == nil)
    }

    @Test func remoteNotificationEnvelopeRejectsStaleOrMismatchedAlerts() {
        let issued = date(2026, 11, 6, 9, 37)
        let notification = ORBNotification(instrument: "EUR/USD", strategyVersion: "ORB_BREAK_RETEST_V1",
                                            stage: .setupConfirmed, sourceTime: issued)
        let envelope = ORBRemoteNotificationEnvelope(eventID: "event-1", planID: "plan-1",
            instrument: "EUR/USD", strategyVersion: "ORB_BREAK_RETEST_V1", stage: .setupConfirmed,
            sourceTime: issued, issuedAt: issued, expiresAt: issued.addingTimeInterval(60),
            deepLink: notification.deepLink, keyID: "apns-key-1", signature: "signed-payload")
        #expect(envelope.validation(now: issued.addingTimeInterval(10)).isEmpty)
        #expect(envelope.validation(now: issued.addingTimeInterval(121)).contains("stale_alert"))
        let bad = ORBRemoteNotificationEnvelope(eventID: envelope.eventID, planID: envelope.planID,
            instrument: "GBP/USD", strategyVersion: envelope.strategyVersion, stage: envelope.stage,
            sourceTime: envelope.sourceTime, issuedAt: envelope.issuedAt, expiresAt: envelope.expiresAt,
            deepLink: envelope.deepLink, keyID: envelope.keyID, signature: envelope.signature)
        #expect(bad.validation(now: issued.addingTimeInterval(10)).contains("deep_link_mismatch"))
    }

    @Test func remoteNotificationSignatureVerificationRejectsTampering() {
        let issued = date(2026, 11, 6, 9, 37)
        let notification = ORBNotification(instrument: "EUR/USD", strategyVersion: "ORB_BREAK_RETEST_V1",
                                            stage: .setupConfirmed, sourceTime: issued)
        let unsigned = ORBRemoteNotificationEnvelope(eventID: "event-2", planID: "plan-2",
            instrument: "EUR/USD", strategyVersion: "ORB_BREAK_RETEST_V1", stage: .setupConfirmed,
            sourceTime: issued, issuedAt: issued, expiresAt: issued.addingTimeInterval(60),
            deepLink: notification.deepLink, keyID: "key-1", signature: "")
        #if canImport(CryptoKit)
        let key = Data("m5-test-key".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: unsigned.signingPayload, using: SymmetricKey(data: key))
        let signed = ORBRemoteNotificationEnvelope(eventID: unsigned.eventID, planID: unsigned.planID,
            instrument: unsigned.instrument, strategyVersion: unsigned.strategyVersion, stage: unsigned.stage,
            sourceTime: unsigned.sourceTime, issuedAt: unsigned.issuedAt, expiresAt: unsigned.expiresAt,
            deepLink: unsigned.deepLink, keyID: unsigned.keyID, signature: Data(mac).base64EncodedString())
        #expect(ORBRemoteNotificationAuthenticator.verify(signed, key: key))
        #expect(!ORBRemoteNotificationAuthenticator.verify(signed, key: Data("wrong".utf8)))
        #else
        #expect(!ORBRemoteNotificationAuthenticator.verify(unsigned, key: Data("m5-test-key".utf8)))
        #endif
    }
}
