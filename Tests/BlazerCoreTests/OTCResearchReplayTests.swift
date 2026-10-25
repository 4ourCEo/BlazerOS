import Foundation
import Testing
@testable import BlazerCore

private let replayInstrument = OTCInstrumentCatalog.pocketOptionEURUSDOTC
private let replaySource = ShadowDataSourceIdentity(
    providerID: "test.otc.v1", displayName: "Test OTC", venueID: "otc",
    directBrokerConnection: false)
private let replayStart = Date(timeIntervalSince1970: 1_800_000_000)

private func replayCandles(endingAt end: Date, count: Int = 30) -> [ShadowCandle] {
    var bars: [ShadowCandle] = []
    var price = 1.1000
    let firstStart = end.addingTimeInterval(-Double(count) * 60)
    for index in 0..<count {
        let start = firstStart.addingTimeInterval(Double(index) * 60)
        let open = price
        let compressed = index >= count - 5
        let close = open + (compressed ? 0.00005 : 0.0002)
        let wick = compressed ? 0.00002 : 0.00015
        bars.append(ShadowCandle(
            identity: replayInstrument.identity, intervalSeconds: 60,
            providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: start.timeIntervalSince1970),
            open: open, high: max(open, close) + wick, low: min(open, close) - wick,
            close: close, complete: true))
        price = close
    }
    let lastStart = end.addingTimeInterval(-60)
    let open = bars[count - 2].close
    let close = open + 0.0004
    bars[count - 1] = ShadowCandle(
        identity: replayInstrument.identity, intervalSeconds: 60,
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: lastStart.timeIntervalSince1970),
        open: open, high: max(open, close) + 0.00003,
        low: min(open, close) - 0.00003, close: close, complete: true)
    return bars
}

private func replayInput(
    evaluatedAt: Date,
    candles: [ShadowCandle]? = nil,
    verification: ShadowVerificationState = .unverifiedVendorData,
    provenance: String = "Vendor-recorded OTC observation fixture"
) -> OTCResearchInput {
    let bars = candles ?? replayCandles(endingAt: evaluatedAt)
    let price = bars.last?.close ?? 1.1
    return OTCResearchInput(
        instrument: replayInstrument,
        source: replaySource,
        snapshotID: "otc-\(Int(evaluatedAt.timeIntervalSince1970))",
        quote: ShadowQuote(price: price, bid: price - 0.0001, ask: price + 0.0001),
        quoteTimestamp: evaluatedAt,
        receivedAt: evaluatedAt,
        candles: bars,
        payoutPercent: 80,
        marketOpen: true,
        connectionState: .live,
        verification: verification,
        provenance: provenance,
        evaluatedAt: evaluatedAt)
}

private func replayRecord(
    evaluatedAt: Date,
    candles: [ShadowCandle]? = nil,
    verification: ShadowVerificationState = .unverifiedVendorData
) -> OTCResearchRecord {
    let input = replayInput(
        evaluatedAt: evaluatedAt, candles: candles, verification: verification)
    return OTCResearchRecord(
        signal: OTCResearchEvaluator.evaluate(input), input: input)
}

@Test func replayDropsOverlappingHorizonsBeforeCountingSignals() {
    let records = [
        replayRecord(evaluatedAt: replayStart),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(30)),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(60)),
    ]
    let report = OTCResearchReplay.run(records: records)
    #expect(report.evaluated == 3)
    #expect(report.accepted == 2)
    #expect(report.overlappingSkipped == 1)
    #expect(report.contaminatedSkipped == 0)
    #expect(abs(report.coverage - 2.0 / 3.0) < 1e-12)
    #expect(report.highCount == 2)
    #expect(report.highFrequency == 1)
    #expect(report.effectiveSampleSize == 0)
    #expect(report.directionalOutcomes == 0)
    #expect(report.nominalSampleSize == 3)
    #expect(report.meanSignalDelaySeconds != nil)
    #expect(!report.promotionEligible)
}

@Test func replayRejectsSubMinuteHorizonOverlap() {
    let records = [
        replayRecord(evaluatedAt: replayStart),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(59)),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(61)),
    ]
    let report = OTCResearchReplay.run(records: records)
    #expect(report.evaluated == 3)
    #expect(report.accepted == 2)
    #expect(report.overlappingSkipped == 1)
}

@Test func replayRejectsFutureCandleContamination() {
    let contaminated = replayRecord(
        evaluatedAt: replayStart,
        candles: replayCandles(endingAt: replayStart.addingTimeInterval(60)))
    let report = OTCResearchReplay.run(records: [contaminated])
    #expect(report.evaluated == 1)
    #expect(report.contaminatedSkipped == 1)
    #expect(report.accepted == 0)
    #expect(report.status.contains("UNVERIFIED"))
}

@Test func replayCountsOnlyBrokerConfirmedOutcomes() {
    let records = [
        replayRecord(evaluatedAt: replayStart),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(120)),
    ]
    let first = records[0].input.snapshotID
    let second = records[1].input.snapshotID
    let outcomes = [
        OTCReplayOutcome(
            signalSnapshotID: first, instrumentID: replayInstrument.instrumentID,
            horizonStart: replayStart, horizonEnd: replayStart.addingTimeInterval(60),
            entryDelaySeconds: 0,
            entryPrice: 1.1000, exitPrice: 1.1005, payoutPercent: 80,
            authority: .brokerConfirmed, brokerEventID: "venue-1",
            provenance: "Pocket Option confirmed settlement"),
        OTCReplayOutcome(
            signalSnapshotID: second, instrumentID: replayInstrument.instrumentID,
            horizonStart: replayStart.addingTimeInterval(120),
            horizonEnd: replayStart.addingTimeInterval(180), entryDelaySeconds: 7,
            entryPrice: 1.1002, exitPrice: 1.1008, payoutPercent: 80,
            authority: .brokerConfirmed, brokerEventID: "venue-2",
            provenance: "Pocket Option confirmed settlement"),
        OTCReplayOutcome(
            signalSnapshotID: first, instrumentID: replayInstrument.instrumentID,
            horizonStart: replayStart, horizonEnd: replayStart.addingTimeInterval(60),
            entryDelaySeconds: 0,
            entryPrice: 1.1, exitPrice: 1.2,
            authority: .unconfirmed, provenance: "Proxy price, not settlement"),
    ]
    let report = OTCResearchReplay.run(records: records, outcomes: outcomes)
    #expect(report.directionalOutcomes == 2)
    #expect(report.highResults?.wins == 2)
    #expect(report.highResults?.total == 2)
    #expect(report.highResults?.winRate == 1)
    #expect(abs((report.payoutAdjustedExpectancy ?? 0) - 0.8) < 1e-12)
    #expect(report.payoutCoverage == 2)
    #expect(report.unconfirmedOutcomesExcluded == 1)
    #expect(report.delaySensitivity.first(where: { $0.delayBucketSeconds == 0 })?.outcomes == 1)
    #expect(report.delaySensitivity.first(where: { $0.delayBucketSeconds == 5 })?.outcomes == 1)
    #expect(report.status.contains("BROKER-CONFIRMED"))
    #expect(!report.promotionEligible)
    #expect(report.isMergeReadyEvidence == false)
}

private func confirmedOutcome(
    snapshotID: String,
    start: Date,
    delay: TimeInterval = 0,
    exitPrice: Double,
    eventID: String
) -> OTCReplayOutcome {
    OTCReplayOutcome(
        signalSnapshotID: snapshotID,
        instrumentID: replayInstrument.instrumentID,
        horizonStart: start,
        horizonEnd: start.addingTimeInterval(60),
        entryDelaySeconds: delay,
        entryPrice: 1.1000,
        exitPrice: exitPrice,
        payoutPercent: 80,
        authority: .brokerConfirmed,
        brokerEventID: eventID,
        provenance: "Pocket Option confirmed settlement")
}

@Test func replayDeduplicatesBrokerEventsAndRejectsPreSignalWindows() {
    let record = replayRecord(evaluatedAt: replayStart)
    let later = replayRecord(evaluatedAt: replayStart.addingTimeInterval(120))
    let snapshot = record.input.snapshotID
    let outcomes = [
        confirmedOutcome(snapshotID: snapshot, start: replayStart, exitPrice: 1.1005, eventID: "venue-1"),
        confirmedOutcome(snapshotID: snapshot, start: replayStart, exitPrice: 1.1005, eventID: "venue-1"),
        confirmedOutcome(snapshotID: snapshot, start: replayStart, exitPrice: 1.1005, eventID: "venue-2"),
        // A window that starts before the signal cannot be caused by it.
        confirmedOutcome(snapshotID: later.input.snapshotID,
                         start: replayStart.addingTimeInterval(115),
                         exitPrice: 1.2000, eventID: "venue-3"),
        confirmedOutcome(snapshotID: snapshot, start: replayStart, delay: 60,
                         exitPrice: 1.2000, eventID: "venue-4"),
    ]
    let report = OTCResearchReplay.run(records: [record, later], outcomes: outcomes)
    #expect(report.directionalOutcomes == 1)
    #expect(report.duplicateOutcomesExcluded == 2)
    #expect(report.unconfirmedOutcomesExcluded == 0)
    #expect(report.invalidConfirmedOutcomesExcluded == 1)
    #expect(report.highResults?.total == 1)
}

@Test func replayExcludesFlatOutcomesFromWinRatesAndExpectancy() {
    let record = replayRecord(evaluatedAt: replayStart)
    let report = OTCResearchReplay.run(
        records: [record],
        outcomes: [confirmedOutcome(
            snapshotID: record.input.snapshotID, start: replayStart,
            exitPrice: 1.1000, eventID: "venue-flat")])
    #expect(report.directionalOutcomes == 0)
    #expect(report.flatOutcomes == 1)
    #expect(report.highResults == nil)
    #expect(report.payoutAdjustedExpectancy == nil)
    #expect(report.caveats.contains { $0.contains("Flat") })
}

@Test func replayFlagsMixedConfigurationsAndUsesTheRecordedConfig() {
    let firstInput = replayInput(evaluatedAt: replayStart)
    let first = OTCResearchRecord(
        signal: OTCResearchEvaluator.evaluate(firstInput), input: firstInput)
    let secondTime = replayStart.addingTimeInterval(120)
    let secondInput = replayInput(evaluatedAt: secondTime)
    // A threshold of 100 must be replayed from the frozen record. Falling back to `.standard`
    // would turn this WAIT into a HIGH and change the counts.
    let secondConfig = OTCResearchConfiguration(directionalThreshold: 100)
    let secondSignal = OTCResearchEvaluator.evaluate(secondInput, configuration: secondConfig)
    #expect(secondSignal.decision == .wait)
    let second = OTCResearchRecord(
        signal: secondSignal, input: secondInput, configuration: secondConfig)

    let report = OTCResearchReplay.run(records: [first, second])
    #expect(report.containsMixedConfigurations)
    #expect(report.accepted == 2)
    #expect(report.highCount == 1)
    #expect(report.waitCount == 1)
    #expect(report.caveats.contains { $0.contains("mixes") })
}

@Test func syntheticOutcomesCannotBecomeEvidence() {
    let record = replayRecord(
        evaluatedAt: replayStart, verification: .syntheticTestFixture)
    let signal = record.signal
    #expect(signal.decision == .high)
    let outcome = OTCReplayOutcome(
        signalSnapshotID: record.input.snapshotID,
        instrumentID: replayInstrument.instrumentID,
        horizonStart: replayStart, horizonEnd: replayStart.addingTimeInterval(60),
        entryDelaySeconds: 0,
        entryPrice: 1.1, exitPrice: 1.2, payoutPercent: 80,
        authority: .syntheticTestFixture, brokerEventID: "fixture-1",
        provenance: "Synthetic documentation-only fixture")
    let report = OTCResearchReplay.run(records: [record], outcomes: [outcome])
    #expect(report.containsSyntheticData)
    #expect(report.directionalOutcomes == 0)
    #expect(report.unconfirmedOutcomesExcluded == 1)
    #expect(report.payoutAdjustedExpectancy == nil)
    #expect(report.status.contains("SYNTHETIC"))
    #expect(!report.promotionEligible)
}

@Test func replayReportsPinnedAndProxyAgreement() {
    let records = [
        replayRecord(evaluatedAt: replayStart),
        replayRecord(evaluatedAt: replayStart.addingTimeInterval(120)),
    ]
    let first = records[0].input.snapshotID
    let second = records[1].input.snapshotID
    let report = OTCResearchReplay.run(
        records: records,
        pinnedEvaluations: [
            first: OTCPinnedEngineEvaluation(
                eligible: true, decision: .high, score: 70, reason: nil,
                engineSHA: "test"),
            second: OTCPinnedEngineEvaluation(
                eligible: true, decision: .wait, score: 40, reason: nil,
                engineSHA: "test"),
        ],
        oandaProxyDecisions: [first: .high, second: .high])
    #expect(report.pinnedEngineAgreement.comparable == 2)
    #expect(report.pinnedEngineAgreement.agreements == 1)
    #expect(report.pinnedEngineAgreement.agreementRate == 0.5)
    #expect(report.oandaProxyAgreement.comparable == 2)
    #expect(report.oandaProxyAgreement.agreements == 2)
    #expect(report.oandaProxyAgreement.agreementRate == 1)
}

@Test func otcSignalStoreArchivesOnlyResearchRecords() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("otc-signal-store-\(UUID().uuidString)")
    let store = OTCResearchSignalStore(root: root)
    let record = replayRecord(evaluatedAt: replayStart)
    try await store.record(record)
    let restored = try await store.records()
    #expect(restored.count == 1)
    #expect(restored[0].signal == record.signal)
    #expect(restored[0].input == record.input)
    let latest = try await store.latest(for: replayInstrument.instrumentID)
    #expect(latest == record.signal)

    let badInput = OTCResearchInput(
        instrument: replayInstrument, source: replaySource, snapshotID: "bad/id",
        quote: record.input.quote, quoteTimestamp: replayStart, receivedAt: replayStart,
        candles: record.input.candles, payoutPercent: 80, marketOpen: true,
        connectionState: .live, verification: .unverifiedVendorData,
        provenance: "test", evaluatedAt: replayStart)
    let badRecord = OTCResearchRecord(
        signal: OTCResearchEvaluator.evaluate(badInput), input: badInput)
    await #expect(throws: OTCResearchStoreError.invalidRecord) {
        try await store.record(badRecord)
    }
}
