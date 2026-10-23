import CryptoKit
import Foundation

/// Local research telemetry only. An attempt is never a trade or a confirmed outcome.
public struct ExecutionObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let armID: String
    public let pair: String
    public let fingerprint: String
    public let regime: String?
    public let policy: String?
    public let kind: String
    public let reason: String?
    public let observedAt: Date
    public let scanToRecordMs: Double?
    public let quoteAgeMs: Double?
    public let spread: Double?
    public let strikeDisplacement: Double?
    public let remainingWindowMs: Double?

    public init(armID: String, commit: ScanCommit, quote: LiveQuote?,
                kind: String, reason: String? = nil, regime: String? = nil, now: Date = Date()) {
        id = UUID().uuidString
        self.armID = armID
        pair = commit.asset
        fingerprint = commit.fullFingerprint
        self.regime = regime
        policy = commit.policy
        self.kind = kind
        self.reason = reason
        observedAt = now
        let age = now.timeIntervalSince(commit.scannedAt) * 1000
        scanToRecordMs = age.isFinite && age >= 0 ? age : nil
        remainingWindowMs = scanToRecordMs.map { max(0, Timing.liveMs - $0) }
        if let quote, quote.asset == commit.asset, quote.asOfMs.isFinite,
           quote.bid.isFinite, quote.ask.isFinite, quote.mid.isFinite,
           quote.bid > 0, quote.ask > quote.bid {
            let quoteAge = now.timeIntervalSince1970 * 1000 - quote.asOfMs
            quoteAgeMs = quoteAge.isFinite && quoteAge >= 0 ? quoteAge : nil
            spread = (quote.ask - quote.bid).isFinite ? quote.ask - quote.bid : nil
            let displacement = quote.mid - commit.strike
            strikeDisplacement = displacement.isFinite ? displacement : nil
        } else {
            quoteAgeMs = nil; spread = nil; strikeDisplacement = nil
        }
    }
}

public actor ExecutionObservationStore {
    private let url: URL
    public init(root: URL) { url = root.appendingPathComponent("execution-observations.jsonl") }
    public func load() throws -> [ExecutionObservation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        // Surface corruption; don't make missing telemetry look like good coverage.
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try decoder.decode(ExecutionObservation.self, from: Data($0.utf8))
        }
    }
    public func record(_ observation: ExecutionObservation) throws {
        var records = try load()
        guard !records.contains(where: { $0.id == observation.id }) else { return }
        records.append(observation)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for record in records { data.append(try encoder.encode(record)); data.append(10) }
        try AtomicFile.write(data, to: url)
    }
}

public struct ExecutionQualitySummary: Codable, Sendable, Equatable {
    public var recordedEntries: Int
    public var rejectedAttempts: Int
    public var closedScansWithoutRecordedEntry: Int
    public var meanScanToRecordMs: Double?
    public var meanQuoteAgeMs: Double?
    public var meanSpread: Double?
    public var meanAbsoluteDisplacement: Double?
    public var meanRemainingWindowMs: Double?
    public var timingCoverage: Int
    public var quoteCoverage: Int
    public var referenceComparisons: Int
    public var referenceDisagreements: Int
}

public struct VerifiedCohort: Codable, Sendable, Equatable {
    public var key: String
    public var resolved: Int
    public var wins: Int
    public var payoutCoverage: Int
    public var actualExpectancy: Double?
    public var meanScanToRecordMs: Double? = nil
    public var meanSpread: Double? = nil
    public var meanAbsoluteDisplacement: Double? = nil
}

public struct ResearchFinding: Codable, Sendable, Equatable {
    public var hypothesis: String
    public var recordIDs: [String]
    public var evidence: String
    public var experiment: String
    public var limitation: String
}

/// Deterministic read-only report. No strategy or promotion authority.
public struct EdgeVerificationReport: Codable, Sendable, Equatable {
    public var schemaVersion = "edge-verification-v1"
    public var inputDigest: String
    public var asOf: Date
    public var status = "INSUFFICIENT EVIDENCE"
    public var resolved: Int
    public var wins: Int
    public var candidateBlocks: Int
    public var effectiveSampleSize: Double
    public var lower95: Double?
    public var upper95: Double?
    public var payoutCoverage: Int
    public var actualExpectancy: Double?
    public var breakEvenAtMinimumPayout: Double?
    public var duplicateOrConflictingIDs: Int
    public var excludedUnconfirmed: Int
    public var quality: ExecutionQualitySummary
    public var cohorts: [VerifiedCohort]
    public var chronologicalSplitAt: Date?
    public var chronologicalCohorts: [VerifiedCohort]
    public var findings: [ResearchFinding]
    public var limitations: [String]
}

public enum ExecutionIntelligence {
    private static func mean(_ values: [Double]) -> Double? {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else { return nil }
        return finite.reduce(0) { $0 + $1 / Double(finite.count) }
    }
    private static func validPayout(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 1e100 else { return nil }
        return value
    }
    /// Strict read-only loader shared by both report commands. Corruption aborts export.
    public static func loadReport(root: URL, asOf: Date, splitAt: Date? = nil) async throws -> EdgeVerificationReport {
        guard FileManager.default.fileExists(atPath: root.path) else { throw ScanError.failed("Desk archive does not exist") }
        let read = try await LedgerStore(root: root).read()
        guard read.damagedLines == 0 else { throw ScanError.failed("Damaged ledger lines: \(read.damagedLines)") }
        let decoder = JSONDecoder()
        let journal: [JournalEntry] = try decodeLines(root.appendingPathComponent(FileLocations.journalFileName), decoder: decoder)
        let observations = try await ExecutionObservationStore(root: root.appendingPathComponent("Research/execution-quality")).load()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let references: [ResearchOutcome] = try decodeLines(root.appendingPathComponent("Research/oanda-proxy/" + ReferenceOutcomeStore.fileName), decoder: decoder)
        return try report(rows: read.rows, journal: journal, observations: observations,
                          references: references, splitAt: splitAt, asOf: asOf)
    }
    private static func decodeLines<T: Decodable>(_ url: URL, decoder: JSONDecoder) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try decoder.decode(T.self, from: Data($0.utf8))
        }
    }
    public static func report(rows: [LedgerRow], journal: [JournalEntry] = [],
                              observations: [ExecutionObservation] = [],
                              references: [ResearchOutcome] = [], splitAt: Date? = nil, asOf: Date) throws -> EdgeVerificationReport {
        // Conflicting repeated arm IDs are excluded, not arbitrarily selected.
        let groups = Dictionary(grouping: rows.filter { $0.timestamp <= asOf }, by: \.outcomeEventID)
        let unique = groups.values.filter { $0.count == 1 }.compactMap(\.first)
            .filter { !$0.outcomeEventID.isEmpty && $0.timestamp <= asOf }
            .sorted { $0.timestamp == $1.timestamp ? $0.outcomeEventID < $1.outcomeEventID : $0.timestamp < $1.timestamp }
        let confirmed = unique.filter { $0.labelSource == "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome) }
        let wins = confirmed.filter { $0.outcome == "HIT" }.count
        let payoutCoverage = confirmed.filter { validPayout($0.payout) != nil }.count
        let payoutsComplete = !confirmed.isEmpty && payoutCoverage == confirmed.count
        func expectancy(_ cohort: [LedgerRow]) -> Double? {
            guard !cohort.isEmpty, cohort.allSatisfy({ validPayout($0.payout) != nil }) else { return nil }
            return cohort.reduce(0.0) { $0 + ($1.outcome == "HIT" ? $1.payout! : -1) } / Double(cohort.count)
        }
        let clustered = EvidenceClustering.adjust(confirmed.compactMap { row in
            guard let entered = row.enteredAt, entered <= asOf else { return nil }
            return ClusteredObservation(pair: row.pair, capturedAtMs: entered.timeIntervalSince1970 * 1000,
                                        won: row.outcome == "HIT")
        }, bucketMs: Double(max(60, confirmed.compactMap(\.horizonSeconds).max() ?? 60)) * 1000)
        let latestEntries = observations.filter { $0.kind == "manual-entry" && $0.observedAt <= asOf }
        let attempts = observations.filter { $0.kind == "rejected" && $0.observedAt <= asOf }
        let entryIDs = Set(unique.compactMap { $0.enteredAt != nil ? $0.outcomeEventID : nil })
            .union(latestEntries.map(\.armID))
        let journalByID = Dictionary(grouping: journal, by: \.id)
        let referenceByID = Dictionary(grouping: references, by: \.eventID)
        var comparisons = 0, disagreements = 0
        for row in confirmed {
            let matches = referenceByID[row.outcomeEventID, default: []].filter {
                guard let entered = row.enteredAt, let horizon = row.horizonSeconds,
                      [60, 180, 300].contains(horizon),
                      let printMs = $0.quoteTimeMs, printMs.isFinite,
                      let exit = $0.exitPrice, exit.isFinite, exit > 0 else { return false }
                let printTime = Date(timeIntervalSince1970: printMs / 1000)
                return $0.horizon == horizon && $0.observedAt <= asOf
                    && $0.labelSource == "oanda-midpoint-proxy"
                    && abs($0.targetExpiry.timeIntervalSince(entered.addingTimeInterval(Double(horizon)))) < 1
                    && printTime >= $0.targetExpiry && printTime.timeIntervalSince($0.targetExpiry) <= 2
                    && $0.observedAt >= printTime && $0.observedAt.timeIntervalSince($0.targetExpiry) <= 5
            }
            if matches.count == 1, let suggested = matches.first?.deskSuggestion {
                comparisons += 1
                if suggested.rawValue != row.outcome { disagreements += 1 }
            }
        }
        let quality = ExecutionQualitySummary(
            recordedEntries: entryIDs.count, rejectedAttempts: attempts.count,
            closedScansWithoutRecordedEntry: journalByID.values.filter {
                guard $0.count == 1, let item = $0.first else { return false }
                return ["CALL", "PUT", "HIGH", "LOW"].contains(item.side)
                    && asOf.timeIntervalSince(item.scannedAt) * 1000 > Timing.liveMs && !entryIDs.contains(item.id)
            }.count,
            meanScanToRecordMs: mean(latestEntries.compactMap(\.scanToRecordMs)),
            meanQuoteAgeMs: mean(latestEntries.compactMap(\.quoteAgeMs)),
            meanSpread: Set(latestEntries.map(\.pair)).count == 1 ? mean(latestEntries.compactMap(\.spread)) : nil,
            meanAbsoluteDisplacement: Set(latestEntries.map(\.pair)).count == 1 ? mean(latestEntries.compactMap(\.strikeDisplacement).map(abs)) : nil,
            meanRemainingWindowMs: mean(latestEntries.compactMap(\.remainingWindowMs)),
            timingCoverage: latestEntries.compactMap(\.scanToRecordMs).count,
            quoteCoverage: latestEntries.compactMap(\.quoteAgeMs).count,
            referenceComparisons: comparisons, referenceDisagreements: disagreements)
        let entryByID = Dictionary(grouping: latestEntries, by: \.armID)
        func entry(_ row: LedgerRow) -> ExecutionObservation? {
            let matches = entryByID[row.outcomeEventID, default: []]
            guard matches.count == 1, let observation = matches.first,
                  observation.pair == row.pair, observation.fingerprint == row.fullFingerprint else { return nil }
            return observation
        }
        func cohort(_ key: String, _ rows: [LedgerRow]) -> VerifiedCohort {
            let telemetry = rows.compactMap(entry)
            return VerifiedCohort(key: key, resolved: rows.count, wins: rows.filter { $0.outcome == "HIT" }.count,
                payoutCoverage: rows.filter { validPayout($0.payout) != nil }.count, actualExpectancy: expectancy(rows),
                meanScanToRecordMs: mean(telemetry.compactMap(\.scanToRecordMs)),
                meanSpread: mean(telemetry.compactMap(\.spread)),
                meanAbsoluteDisplacement: mean(telemetry.compactMap(\.strikeDisplacement).map(abs)))
        }
        // Regimes and policy use captured metadata only. No retrospective inference.
        let cohorts = Dictionary(grouping: confirmed) {
            "\($0.pair)|\($0.horizonSeconds.map(String.init) ?? "unknown-expiry")|\($0.marketWindow ?? "unknown-window")|\($0.engineSHA ?? "unknown-engine")|\(entry($0)?.policy ?? "unknown-policy")|\(entry($0)?.regime ?? "unknown-regime")"
        }.map { key, rows in cohort(key, rows) }.sorted { $0.key < $1.key }
        var chronological: [VerifiedCohort] = []
        if let splitAt, splitAt < asOf {
            let train = confirmed.filter {
                guard let entered = $0.enteredAt, let horizon = $0.horizonSeconds, [60, 180, 300].contains(horizon) else { return false }
                return entered.addingTimeInterval(Double(horizon)) < splitAt
            }
            let test = confirmed.filter { $0.enteredAt.map { $0 >= splitAt } ?? false }
            chronological = [cohort("chronological-train", train), cohort("chronological-held-out", test)]
        }
        let slow = latestEntries.filter { ($0.scanToRecordMs ?? 0) > EntryQuality.maxAgeSeconds * 1000 }
        var findings: [ResearchFinding] = []
        if !slow.isEmpty {
            findings.append(ResearchFinding(hypothesis: "Recording delay may identify execution friction",
                recordIDs: Array(slow.map(\.armID).sorted().prefix(8)),
                evidence: "\(slow.count) entries recorded after the action window.",
                experiment: "Pre-register one timing comparison on a new prospective cohort; freeze engine, policy, expiry and payout. Compare confirmed returns using independent time blocks. Reject if held-out uncertainty includes no improvement.",
                limitation: "Recording time is not venue fill time. Association cannot establish causation; selection and multiple testing require independent review."))
        }
        if chronological.count == 2, let trainEV = chronological[0].actualExpectancy,
           let testEV = chronological[1].actualExpectancy, testEV < trainEV {
            findings.append(ResearchFinding(hypothesis: "Chronological returns deteriorated across the supplied cutoff",
                recordIDs: Array(confirmed.map(\.outcomeEventID).sorted().prefix(8)),
                evidence: "Held-out unit return is below training unit return at the supplied fixed split.",
                experiment: "Register a new future cutoff and one primary endpoint; compare unchanged engine/policy/expiry/regime cohorts against the frozen baseline. Do not tune on this held-out data.",
                limitation: "A supplied cutoff is not proof of prospective registration. Descriptive comparison; small samples, payout mix, missing data and repeated tests can explain deterioration."))
        }
        struct Inputs: Encodable {
            var rows: [String]; var journal: [String]; var observations: [String]
            var references: [String]; var splitAt: Date?; var asOf: Date
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func canonical<T: Encodable>(_ values: [T]) throws -> [String] {
            try values.map { String(decoding: try encoder.encode($0), as: UTF8.self) }.sorted()
        }
        let bytes = try encoder.encode(Inputs(rows: canonical(rows), journal: canonical(journal),
            observations: canonical(observations), references: canonical(references), splitAt: splitAt, asOf: asOf))
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return EdgeVerificationReport(inputDigest: digest, asOf: asOf, resolved: confirmed.count, wins: wins,
            candidateBlocks: clustered.blocks, effectiveSampleSize: clustered.effectiveSize,
            lower95: clustered.nominalSize == confirmed.count && !confirmed.isEmpty ? clustered.lower95 : nil,
            upper95: clustered.nominalSize == confirmed.count && !confirmed.isEmpty ? clustered.upper95 : nil,
            payoutCoverage: payoutCoverage, actualExpectancy: expectancy(confirmed),
            breakEvenAtMinimumPayout: payoutsComplete ? confirmed.compactMap { validPayout($0.payout) }.min().map { 1 / (1 + $0) } : nil,
            duplicateOrConflictingIDs: groups.values.filter { $0.count > 1 }.count,
            excludedUnconfirmed: unique.filter { $0.labelSource != "venue-confirmed" }.count,
            quality: quality, cohorts: cohorts, chronologicalSplitAt: splitAt, chronologicalCohorts: chronological, findings: findings,
            limitations: ["250 nominal rows do not establish 250 independent prime-window basket events.",
                clustered.caveat,
                "Actual expectancy requires recorded payouts for every resolved entry; missing payouts are never imputed here.",
                "No registered prospective stopping rule, independently verified dependence model or independent validation supplied. No promotion is authorized.",
                "Historical rows may lack entry telemetry, regime and policy metadata. Missingness and scan selection can bias results.",
                "Timing measures scan-to-record latency, not venue fill latency. Reference disagreement is descriptive, not a counterfactual profit claim.",
                "Market-window cohorts are not market regimes. Chronological, leakage-purged analysis is available separately through ResearchEvaluator; repeated holdout inspection remains exploratory."])
    }
}

/// Small bounded payload for on-device interpretation. All numbers originate in Swift.
public struct ExecutionResearchSummary: Codable, Sendable, Equatable {
    public let status: String
    public let resolved: Int
    public let candidateBlocks: Int
    public let effectiveSampleSize: Double
    public let payoutCoverage: Int
    public let quality: ExecutionQualitySummary
    public let nextHypothesis: String?
    public init(_ report: EdgeVerificationReport) {
        status = report.status; resolved = report.resolved; candidateBlocks = report.candidateBlocks
        effectiveSampleSize = report.effectiveSampleSize; payoutCoverage = report.payoutCoverage
        quality = report.quality; nextHypothesis = report.findings.first?.hypothesis
    }
}
