import Foundation

/// Only a broker-confirmed event may contribute to performance. Synthetic fixtures prove the
/// evaluator is deterministic; they are never evidence of an outcome.
public enum OTCOutcomeAuthority: String, Codable, Sendable, Equatable {
    case brokerConfirmed
    case unconfirmed
    case syntheticTestFixture
}

public struct OTCReplayOutcome: Codable, Sendable, Equatable {
    public let signalSnapshotID: String
    public let instrumentID: String
    public let horizonStart: Date
    /// End of the measured 60-second window. Required so an outcome cannot claim an arbitrary
    /// horizon that happens to look favourable.
    public let horizonEnd: Date
    public let entryDelaySeconds: TimeInterval
    public let entryPrice: Double
    public let exitPrice: Double
    public let payoutPercent: Double?
    public let authority: OTCOutcomeAuthority
    public let brokerEventID: String?
    public let provenance: String

    public init(
        signalSnapshotID: String,
        instrumentID: String,
        horizonStart: Date,
        horizonEnd: Date,
        entryDelaySeconds: TimeInterval,
        entryPrice: Double,
        exitPrice: Double,
        payoutPercent: Double? = nil,
        authority: OTCOutcomeAuthority,
        brokerEventID: String? = nil,
        provenance: String
    ) {
        self.signalSnapshotID = signalSnapshotID
        self.instrumentID = instrumentID
        self.horizonStart = horizonStart
        self.horizonEnd = horizonEnd
        self.entryDelaySeconds = entryDelaySeconds
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.payoutPercent = payoutPercent
        self.authority = authority
        self.brokerEventID = brokerEventID
        self.provenance = provenance
    }

    public var isUsablePerformanceEvidence: Bool {
        let horizon = horizonEnd.timeIntervalSince(horizonStart)
        return authority == .brokerConfirmed
            && !(brokerEventID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !provenance.localizedCaseInsensitiveContains("synthetic")
            && signalSnapshotID.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".")
            }
            && horizon > 0 && horizon <= 3_600
            && entryPrice.isFinite && entryPrice > 0
            && exitPrice.isFinite && exitPrice > 0
            && entryDelaySeconds.isFinite && entryDelaySeconds >= 0
            && entryDelaySeconds < horizon
            && (payoutPercent.map { $0.isFinite && $0 > 0 && $0 <= 100 } ?? true)
    }
}

public struct OTCWilsonInterval: Codable, Sendable, Equatable {
    public let wins: Int
    public let total: Int
    public let winRate: Double
    public let lower95: Double
    public let upper95: Double
}

public struct OTCDelayResult: Codable, Sendable, Equatable {
    public let delayBucketSeconds: Int
    public let outcomes: Int
    public let wins: Int
    public let flatOutcomes: Int
    public let isOverflow: Bool
    public let winRate: Double?
    public let lower95: Double?
    public let upper95: Double?
}

public struct OTCProviderAgreement: Codable, Sendable, Equatable {
    public let comparable: Int
    public let agreements: Int
    public let agreementRate: Double?
}

public struct OTCReplayConfiguration: Codable, Sendable, Equatable {
    public let delayBucketsSeconds: [Int]
    public let horizonToleranceSeconds: TimeInterval

    public init(delayBucketsSeconds: [Int] = [0, 5, 10, 15],
                horizonToleranceSeconds: TimeInterval = 5) {
        self.delayBucketsSeconds = delayBucketsSeconds.sorted().filter { $0 >= 0 }
        self.horizonToleranceSeconds = max(0, horizonToleranceSeconds)
    }

    public static let standard = OTCReplayConfiguration()
}

public struct OTCReplayReport: Codable, Sendable, Equatable {
    public let evaluated: Int
    public let accepted: Int
    public let overlappingSkipped: Int
    public let contaminatedSkipped: Int
    public let staleRefusals: Int
    public let feedUnavailableRefusals: Int
    public let highCount: Int
    public let lowCount: Int
    public let waitCount: Int
    public let highFrequency: Double
    public let lowFrequency: Double
    public let waitFrequency: Double
    public let coverage: Double
    public let decimationRate: Double
    public let staleRefusalRate: Double
    public let feedUnavailableRate: Double
    public let meanSignalDelaySeconds: Double?
    public let highResults: OTCWilsonInterval?
    public let lowResults: OTCWilsonInterval?
    public let payoutAdjustedExpectancy: Double?
    public let payoutCoverage: Int
    public let delaySensitivity: [OTCDelayResult]
    public let pinnedEngineAgreement: OTCProviderAgreement
    public let oandaProxyAgreement: OTCProviderAgreement
    public let directionalOutcomes: Int
    public let flatOutcomes: Int
    public let unconfirmedOutcomesExcluded: Int
    public let invalidConfirmedOutcomesExcluded: Int
    public let duplicateOutcomesExcluded: Int
    public let acceptedByInstrument: [String: Int]
    public let evaluatedByInstrument: [String: Int]
    public let effectiveSampleSize: Double
    public let nominalSampleSize: Int
    public let containsSyntheticData: Bool
    public let containsMixedConfigurations: Bool
    public let promotionEligible: Bool
    public let status: String
    public let caveats: [String]

    public var isMergeReadyEvidence: Bool { false }
}

/// Offline comparison harness. Signals are re-evaluated from frozen inputs under the configuration
/// that produced them, not trusted from the stored output, and overlapping 60-second horizons are
/// dropped per instrument before any outcome is counted.
public enum OTCResearchReplay {

    public static func run(
        records: [OTCResearchRecord],
        replayConfiguration: OTCReplayConfiguration = .standard,
        pinnedEvaluations: [String: OTCPinnedEngineEvaluation] = [:],
        oandaProxyDecisions: [String: OTCSignalDecision] = [:],
        outcomes: [OTCReplayOutcome] = []
    ) -> OTCReplayReport {
        let sorted = records.sorted {
            if $0.input.evaluatedAt != $1.input.evaluatedAt {
                return $0.input.evaluatedAt < $1.input.evaluatedAt
            }
            return $0.signal.sourceSnapshotID < $1.signal.sourceSnapshotID
        }

        var evaluated = 0
        var seenSnapshots = Set<String>()
        var contaminated = 0
        var staleRefusals = 0
        var feedUnavailable = 0
        var synthetic = false
        var contexts = Set<String>()
        var evaluatedByInstrument: [String: Int] = [:]
        var evaluatedSignals: [(record: OTCResearchRecord, signal: OTCResearchSignal)] = []

        for record in sorted {
            guard seenSnapshots.insert(record.input.snapshotID).inserted else { continue }
            evaluated += 1
            let instrumentID = record.input.instrument.instrumentID
            evaluatedByInstrument[instrumentID, default: 0] += 1
            contexts.insert(configurationKey(record.configuration))
            if record.input.verification == .syntheticTestFixture
                || record.input.provenance.localizedCaseInsensitiveContains("synthetic") {
                synthetic = true
            }
            let interval = TimeInterval(record.configuration.intervalSeconds)
            let futureCandle = record.input.candles.contains {
                $0.providerTimestamp.normalized.addingTimeInterval(interval)
                    > record.input.evaluatedAt.addingTimeInterval(0.001)
            }
            let futureQuote = record.input.quoteTimestamp > record.input.evaluatedAt.addingTimeInterval(0.001)
            guard !futureCandle, !futureQuote else {
                contaminated += 1
                continue
            }
            let signal = OTCResearchEvaluator.evaluate(
                record.input, configuration: record.configuration)
            if signal.vetoes.contains(where: isStaleVeto) { staleRefusals += 1 }
            if signal.vetoes.contains(.feedNotLive) { feedUnavailable += 1 }
            evaluatedSignals.append((record, signal))
        }

        // Non-overlap is an instrument-local property. A GBP/USD OTC signal must not suppress a
        // valid EUR/USD OTC horizon.
        var accepted: [(record: OTCResearchRecord, signal: OTCResearchSignal)] = []
        var overlapping = 0
        for group in Dictionary(grouping: evaluatedSignals, by: {
            $0.record.input.instrument.instrumentID
        }).values {
            var lastAcceptedAt: Date?
            for entry in group.sorted(by: {
                if $0.record.input.evaluatedAt != $1.record.input.evaluatedAt {
                    return $0.record.input.evaluatedAt < $1.record.input.evaluatedAt
                }
                return $0.record.input.snapshotID < $1.record.input.snapshotID
            }) {
                let horizon = Double(entry.record.configuration.horizonSeconds)
                if let lastAcceptedAt,
                   entry.record.input.evaluatedAt.timeIntervalSince(lastAcceptedAt) < horizon {
                    overlapping += 1
                    continue
                }
                lastAcceptedAt = entry.record.input.evaluatedAt
                accepted.append(entry)
            }
        }
        accepted.sort {
            if $0.record.input.evaluatedAt != $1.record.input.evaluatedAt {
                return $0.record.input.evaluatedAt < $1.record.input.evaluatedAt
            }
            return $0.signal.sourceSnapshotID < $1.signal.sourceSnapshotID
        }

        let high = accepted.filter { $0.signal.decision == .high }
        let low = accepted.filter { $0.signal.decision == .low }
        let wait = accepted.filter { $0.signal.decision == .wait }
        let acceptedCount = accepted.count
        var acceptedByInstrument: [String: Int] = [:]
        for entry in accepted {
            acceptedByInstrument[entry.record.input.instrument.instrumentID, default: 0] += 1
        }

        let delays = accepted.compactMap { entry -> Double? in
            guard let close = entry.signal.candleCloseTime else { return nil }
            return max(0, entry.record.input.evaluatedAt.timeIntervalSince(close))
        }

        let acceptedBySnapshot = Dictionary(
            accepted.map { ($0.record.input.snapshotID, $0.record) },
            uniquingKeysWith: { first, _ in first })
        let confirmed = outcomes.filter { $0.authority == .brokerConfirmed }
        let unconfirmedExcluded = outcomes.count - confirmed.count
        let invalidConfirmedExcluded = confirmed.filter {
            !$0.isUsablePerformanceEvidence
        }.count
        let usable = confirmed.filter { $0.isUsablePerformanceEvidence }
            .sorted {
                let left = $0.brokerEventID ?? ""
                let right = $1.brokerEventID ?? ""
                if left != right { return left < right }
                return $0.signalSnapshotID < $1.signalSnapshotID
            }
        if outcomes.contains(where: { $0.authority == .syntheticTestFixture }) {
            synthetic = true
        }

        struct Scored {
            let signal: OTCResearchSignal
            /// nil means the 60-second move was flat. Venue tie rules vary, so a flat is not
            /// silently counted as a loss.
            let win: Bool?
            let delay: TimeInterval
            let payout: Double?
        }
        var scored: [Scored] = []
        var seenEvents = Set<String>()
        var seenSignals = Set<String>()
        var duplicateOutcomes = 0
        for outcome in usable {
            // Match first. A row that does not describe this signal must not consume the
            // snapshot slot and hide a later valid settlement.
            guard let record = acceptedBySnapshot[outcome.signalSnapshotID],
                  record.input.instrument.instrumentID == outcome.instrumentID,
                  let signal = accepted.first(where: {
                      $0.record.input.snapshotID == outcome.signalSnapshotID
                  })?.signal,
                  signal.decision.isDirectional,
                  outcome.horizonStart >= signal.evaluatedAt.addingTimeInterval(-0.001),
                  outcome.horizonStart.timeIntervalSince(signal.evaluatedAt)
                    <= replayConfiguration.horizonToleranceSeconds,
                  abs(outcome.horizonEnd.timeIntervalSince(outcome.horizonStart)
                        - Double(record.configuration.horizonSeconds)) <= 1,
                  let eventID = outcome.brokerEventID
            else { continue }
            guard seenEvents.insert(eventID).inserted else {
                duplicateOutcomes += 1
                continue
            }
            guard seenSignals.insert(outcome.signalSnapshotID).inserted else {
                duplicateOutcomes += 1
                continue
            }
            let win: Bool?
            if outcome.exitPrice > outcome.entryPrice { win = true }
            else if outcome.exitPrice < outcome.entryPrice { win = false }
            else { win = nil }
            scored.append(Scored(
                signal: signal, win: win,
                delay: outcome.entryDelaySeconds,
                payout: outcome.payoutPercent))
        }

        let directional = scored.filter { $0.win != nil }
        let flats = scored.count - directional.count
        let highScored = directional.filter { $0.signal.decision == .high }
        let lowScored = directional.filter { $0.signal.decision == .low }
        let highInterval = interval(wins: highScored.filter { $0.win == true }.count,
                                    total: highScored.count)
        let lowInterval = interval(wins: lowScored.filter { $0.win == true }.count,
                                   total: lowScored.count)

        let payouts = directional.compactMap(\.payout)
        let payoutExpectancy: Double?
        if !directional.isEmpty, payouts.count == directional.count,
           payouts.allSatisfy({ $0 > 0 && $0 <= 100 }) {
            let units = directional.map { entry -> Double in
                let payout = (entry.payout ?? 0) / 100
                return entry.win == true ? payout : -1
            }
            payoutExpectancy = units.reduce(0, +) / Double(units.count)
        } else {
            payoutExpectancy = nil
        }

        let buckets = replayConfiguration.delayBucketsSeconds
        let maximumBucket = buckets.last ?? 0
        func bucket(for delay: TimeInterval) -> (bucket: Int, overflow: Bool) {
            let value = buckets.last(where: { Double($0) <= delay }) ?? (buckets.first ?? 0)
            return (value, delay > Double(maximumBucket))
        }
        func delayResult(_ configured: Int, matching: [Scored],
                         overflow: Bool) -> OTCDelayResult {
            let directionalMatching = matching.filter { $0.win != nil }
            let wins = directionalMatching.filter { $0.win == true }.count
            let interval = interval(wins: wins, total: directionalMatching.count)
            return OTCDelayResult(
                delayBucketSeconds: configured,
                outcomes: matching.count,
                wins: wins,
                flatOutcomes: matching.count - directionalMatching.count,
                isOverflow: overflow,
                winRate: directionalMatching.isEmpty
                    ? nil : Double(wins) / Double(directionalMatching.count),
                lower95: interval?.lower95, upper95: interval?.upper95)
        }
        var delayResults = buckets.map { configured in
            let matching = scored.filter {
                let value = bucket(for: $0.delay)
                return value.bucket == configured && !value.overflow
            }
            return delayResult(configured, matching: matching, overflow: false)
        }
        let overflowEntries = scored.filter { bucket(for: $0.delay).overflow }
        if !overflowEntries.isEmpty, let maximumBucket = buckets.last {
            delayResults.append(delayResult(
                maximumBucket, matching: overflowEntries, overflow: true))
        }

        let pinned = agreement(
            accepted.compactMap { entry -> Bool? in
                guard let evaluation = pinnedEvaluations[entry.record.input.snapshotID],
                      evaluation.eligible else { return nil }
                return evaluation.decision == entry.signal.decision
            })
        let proxy = agreement(
            accepted.compactMap { entry -> Bool? in
                guard let decision = oandaProxyDecisions[entry.record.input.snapshotID] else { return nil }
                return decision == entry.signal.decision
            })

        let mixed = contexts.count > 1
        let status: String
        if synthetic {
            status = "SYNTHETIC OR MIXED FIXTURE — NOT EVIDENCE"
        } else if directional.isEmpty {
            status = "UNVERIFIED — NO BROKER-CONFIRMED 60s OUTCOMES"
        } else {
            status = "BROKER-CONFIRMED RESEARCH SAMPLE — NOT A PROMOTION"
        }

        var caveats: [String] = [
            "Research only. Signals cannot authorize an entry or inherit production eligibility.",
            "The deterministic score is a ranking of frozen features, not a calibrated win probability.",
            "60-second signals share overlapping feature windows; Wilson intervals assume independent samples and are optimistic."
        ]
        if synthetic {
            caveats.append("Synthetic fixtures are excluded from outcome performance and cannot establish an edge.")
        }
        if directional.isEmpty {
            caveats.append("No broker-confirmed directional outcomes matched accepted signals; performance is unavailable.")
        }
        if flats > 0 {
            caveats.append("Flat 60-second outcomes are excluded from win rates and payout expectancy because venue tie rules vary.")
        }
        if payoutExpectancy == nil {
            caveats.append("Payout-adjusted expectancy requires a valid vendor payout on every matched directional outcome.")
        }
        if mixed {
            caveats.append("The archive mixes engine, strategy, or configuration versions; per-record replay uses the frozen version.")
        }
        if pinnedEvaluations.isEmpty {
            caveats.append("No pinned-engine comparison inputs were supplied; agreement is unavailable.")
        } else if pinned.comparable == 0 {
            caveats.append("No archived input had a usable bid/ask spread for the pinned comparison arm.")
        }
        if directional.count > 0, directional.count <= 30 {
            caveats.append("The accepted non-overlapping directional sample is small; confidence intervals are wide.")
        }
        if invalidConfirmedExcluded > 0 {
            caveats.append("Broker-confirmed rows with an invalid horizon, delay, price, or event ID were excluded.")
        }
        if duplicateOutcomes > 0 {
            caveats.append("Duplicate broker event or signal outcomes were excluded from performance.")
        }

        return OTCReplayReport(
            evaluated: evaluated,
            accepted: acceptedCount,
            overlappingSkipped: overlapping,
            contaminatedSkipped: contaminated,
            staleRefusals: staleRefusals,
            feedUnavailableRefusals: feedUnavailable,
            highCount: high.count,
            lowCount: low.count,
            waitCount: wait.count,
            highFrequency: ratio(high.count, acceptedCount),
            lowFrequency: ratio(low.count, acceptedCount),
            waitFrequency: ratio(wait.count, acceptedCount),
            coverage: ratio(acceptedCount, evaluated),
            decimationRate: 1 - ratio(acceptedCount, evaluated),
            staleRefusalRate: ratio(staleRefusals, evaluated),
            feedUnavailableRate: ratio(feedUnavailable, evaluated),
            meanSignalDelaySeconds: delays.isEmpty ? nil : delays.reduce(0, +) / Double(delays.count),
            highResults: highInterval,
            lowResults: lowInterval,
            payoutAdjustedExpectancy: payoutExpectancy,
            payoutCoverage: payouts.count,
            delaySensitivity: delayResults,
            pinnedEngineAgreement: pinned,
            oandaProxyAgreement: proxy,
            directionalOutcomes: directional.count,
            flatOutcomes: flats,
            unconfirmedOutcomesExcluded: unconfirmedExcluded,
            invalidConfirmedOutcomesExcluded: invalidConfirmedExcluded,
            duplicateOutcomesExcluded: duplicateOutcomes,
            acceptedByInstrument: acceptedByInstrument,
            evaluatedByInstrument: evaluatedByInstrument,
            effectiveSampleSize: Double(directional.count),
            nominalSampleSize: evaluated,
            containsSyntheticData: synthetic,
            containsMixedConfigurations: mixed,
            promotionEligible: false,
            status: status,
            caveats: caveats)
    }

    private static func configurationKey(_ configuration: OTCResearchConfiguration) -> String {
        "\(configuration.engineVersion)|\(configuration.strategyVersion)|"
            + "\(configuration.horizonSeconds)|\(configuration.intervalSeconds)|"
            + "\(configuration.minimumCandles)|\(configuration.maximumQuoteAge)|"
            + "\(configuration.maximumCandleAge)|\(configuration.quoteFreshFor)|"
            + "\(configuration.quoteExpiresAfter)|\(configuration.directionalThreshold)"
    }

    private static func interval(wins: Int, total: Int) -> OTCWilsonInterval? {
        guard total > 0, wins >= 0, wins <= total else { return nil }
        let (lower, upper) = EdgeEvidence.wilsonScoreInterval(wins: wins, total: total)
        return OTCWilsonInterval(
            wins: wins, total: total,
            winRate: Double(wins) / Double(total),
            lower95: lower, upper95: upper)
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator > 0 ? Double(numerator) / Double(denominator) : 0
    }

    private static func agreement(_ values: [Bool]) -> OTCProviderAgreement {
        OTCProviderAgreement(
            comparable: values.count,
            agreements: values.filter { $0 }.count,
            agreementRate: values.isEmpty ? nil : Double(values.filter { $0 }.count) / Double(values.count))
    }

    private static func isStaleVeto(_ veto: OTCResearchVeto) -> Bool {
        veto == .staleQuote || veto == .staleCandles || veto == .futureCandles
            || veto == .futureQuote
    }
}
