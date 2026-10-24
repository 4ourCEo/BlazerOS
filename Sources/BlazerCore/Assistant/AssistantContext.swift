import Foundation

// MARK: - Bounded, provenance-bearing context for the on-device assistant.
//
// The model receives only these frozen records. It never receives credentials, live quotes,
// or mutable desk state. Every feature result cites record IDs from this context.

public struct ScanRecordContext: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fullFingerprint: String
    public var pair: String
    public var engineCall: String
    public var score: Int
    public var evidence: String
    public var veto: String?
    public var evaluationTime: Date
    public var quoteMid: Double?
    public var spread: Double?
    public var m1Count: Int
    public var m5Count: Int
    public var engineSHA: String
    public var expirySeconds: Int
    public var isActionable: Bool
    public var blockingReason: String?
    public var recordedVerb: String

    public init(
        id: String, fullFingerprint: String, pair: String, engineCall: String,
        score: Int, evidence: String, veto: String?, evaluationTime: Date,
        quoteMid: Double?, spread: Double?, m1Count: Int, m5Count: Int,
        engineSHA: String, expirySeconds: Int, isActionable: Bool,
        blockingReason: String?, recordedVerb: String
    ) {
        self.id = id
        self.fullFingerprint = fullFingerprint
        self.pair = pair
        self.engineCall = engineCall
        self.score = score
        self.evidence = evidence
        self.veto = veto
        self.evaluationTime = evaluationTime
        self.quoteMid = quoteMid
        self.spread = spread
        self.m1Count = m1Count
        self.m5Count = m5Count
        self.engineSHA = engineSHA
        self.expirySeconds = expirySeconds
        self.isActionable = isActionable
        self.blockingReason = blockingReason
        self.recordedVerb = recordedVerb
    }

    /// Evidence lines as recorded, split for citation checks.
    public var evidenceLines: [String] {
        evidence
            .split(whereSeparator: { $0 == "·" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct ConfirmedEntryContext: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pair: String
    public var side: String
    public var outcome: String
    public var recordedAt: Date
    public var enteredAt: Date?
    public var horizonSeconds: Int?
    public var entryQuote: Double?
    public var expiryPrice: Double?
    public var stake: Double?
    public var payout: Double?
    public var lateEntry: Bool
    public var recordID: String

    public init(
        id: String, pair: String, side: String, outcome: String, recordedAt: Date,
        enteredAt: Date?, horizonSeconds: Int?, entryQuote: Double?, expiryPrice: Double?,
        stake: Double?, payout: Double?, lateEntry: Bool, recordID: String
    ) {
        self.id = id
        self.pair = pair
        self.side = side
        self.outcome = outcome
        self.recordedAt = recordedAt
        self.enteredAt = enteredAt
        self.horizonSeconds = horizonSeconds
        self.entryQuote = entryQuote
        self.expiryPrice = expiryPrice
        self.stake = stake
        self.payout = payout
        self.lateEntry = lateEntry
        self.recordID = recordID
    }
}

public struct PerformanceSummary: Codable, Sendable, Equatable {
    public var sampleSize: Int
    public var wins: Int
    public var losses: Int
    public var ties: Int
    public var unresolved: Int
    public var winRate: Double?
    public var breakEven: Double
    public var payoutBasis: String?
    public var expectancy: Double?
    public var confirmedOnly: Bool
    public var caveat: String

    public init(
        sampleSize: Int, wins: Int, losses: Int, ties: Int, unresolved: Int,
        winRate: Double?, breakEven: Double, expectancy: Double?,
        payoutBasis: String? = nil, confirmedOnly: Bool, caveat: String
    ) {
        self.sampleSize = sampleSize
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.unresolved = unresolved
        self.winRate = winRate
        self.breakEven = breakEven
        self.payoutBasis = payoutBasis
        self.expectancy = expectancy
        self.confirmedOnly = confirmedOnly
        self.caveat = caveat
    }

    public static let empty = PerformanceSummary(
        sampleSize: 0, wins: 0, losses: 0, ties: 0, unresolved: 0,
        winRate: nil, breakEven: 1.0 / (1.0 + EntryQuality.assumedPayout),
        expectancy: nil, confirmedOnly: true,
        caveat: "No venue-confirmed outcomes are available. No performance claim can be made."
    )
}

public struct ObservationGap: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case missingConfirmation
        case lateEntry
        case staleFeed
        case unresolvedExpiry
        case duplicateConfirmation
        case interruptedSave
    }

    public var id: String
    public var pair: String
    public var kind: Kind
    public var detail: String
    public var recordID: String

    public init(id: String, pair: String, kind: Kind, detail: String, recordID: String) {
        self.id = id
        self.pair = pair
        self.kind = kind
        self.detail = detail
        self.recordID = recordID
    }
}

public struct JournalNoteContext: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pair: String
    public var note: String
    public var createdAt: Date

    public init(id: String, pair: String, note: String, createdAt: Date) {
        self.id = id
        self.pair = pair
        self.note = note
        self.createdAt = createdAt
    }
}

public struct AssistantContext: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var scans: [ScanRecordContext]
    public var confirmedEntries: [ConfirmedEntryContext]
    public var research: ExecutionResearchSummary?
    public var performance: PerformanceSummary
    public var gaps: [ObservationGap]
    public var notes: [JournalNoteContext]

    public init(
        generatedAt: Date = Date(),
        scans: [ScanRecordContext] = [],
        confirmedEntries: [ConfirmedEntryContext] = [],
        performance: PerformanceSummary = .empty,
        research: ExecutionResearchSummary? = nil,
        gaps: [ObservationGap] = [],
        notes: [JournalNoteContext] = []
    ) {
        self.generatedAt = generatedAt
        self.scans = scans
        self.confirmedEntries = confirmedEntries
        self.research = research
        self.performance = performance
        self.gaps = gaps
        self.notes = notes
    }

    public static let empty = AssistantContext()

    public var allRecordIDs: Set<String> {
        var ids = Set<String>()
        for scan in scans { ids.insert(scan.id) }
        for entry in confirmedEntries {
            ids.insert(entry.id)
            ids.insert(entry.recordID)
        }
        for gap in gaps {
            ids.insert(gap.id)
            ids.insert(gap.recordID)
        }
        for note in notes { ids.insert(note.id) }
        return ids
    }

    /// Bounds context to the on-device model window. Evidence and notes are truncated;
    /// authoritative numbers remain in `performance` and the selected record.
    public func bounded(
        maxScans: Int,
        maxEntries: Int,
        maxGaps: Int,
        maxNotes: Int,
        maxText: Int = 180
    ) -> AssistantContext {
        func trim(_ value: String) -> String {
            guard value.count > maxText else { return value }
            return String(value.prefix(maxText)) + "…"
        }
        var copy = self
        copy.scans = scans.prefix(maxScans).map { scan in
            var item = scan
            item.evidence = trim(item.evidence)
            if let veto = item.veto { item.veto = trim(veto) }
            if let blocking = item.blockingReason { item.blockingReason = trim(blocking) }
            return item
        }
        copy.confirmedEntries = Array(confirmedEntries.prefix(maxEntries))
        copy.gaps = gaps.prefix(maxGaps).map { gap in
            var item = gap
            item.detail = trim(item.detail)
            return item
        }
        copy.notes = notes.prefix(maxNotes).map { note in
            var item = note
            item.note = trim(item.note)
            return item
        }
        return copy
    }

    /// Describes what a bounded context omitted. Used in diagnostics, never as model facts.
    public func selectionNotes(after bounded: AssistantContext) -> [String] {
        var notes: [String] = []
        if bounded.scans.count < scans.count {
            notes.append("scans \(bounded.scans.count)/\(scans.count)")
        }
        if bounded.confirmedEntries.count < confirmedEntries.count {
            notes.append("entries \(bounded.confirmedEntries.count)/\(confirmedEntries.count)")
        }
        if bounded.gaps.count < gaps.count {
            notes.append("gaps \(bounded.gaps.count)/\(gaps.count)")
        }
        if bounded.notes.count < notes.count {
            notes.append("notes \(bounded.notes.count)/\(notes.count)")
        }
        return notes
    }
}

public enum AssistantContextBuilder {
    /// Builds a bounded context. Only `venue-confirmed` rows count as performance.
    public static func make(
        journal: [JournalEntry],
        ledgerRows: [LedgerRow],
        observations: [ExecutionObservation] = [],
        now: Date = Date()
    ) -> AssistantContext {
        let sortedJournal = journal.sorted { $0.scannedAt > $1.scannedAt }
        let scanTimeByID = Dictionary(
            sortedJournal.map { ($0.id, $0.scannedAt) },
            uniquingKeysWith: { first, _ in first }
        )

        let scans = sortedJournal.prefix(40).map { entry -> ScanRecordContext in
            let ageMs = max(0, now.timeIntervalSince(entry.scannedAt) * 1000)
            let actionable = (entry.side == "CALL" || entry.side == "PUT")
                && entry.veto == nil
                && ageMs <= Timing.liveMs
            let blocking: String?
            if let veto = entry.veto, !veto.isEmpty {
                blocking = veto
            } else if ageMs > Timing.liveMs {
                blocking = "historical beam; the action window has closed"
            } else if entry.side == "WAIT" {
                blocking = "engine returned WAIT"
            } else {
                blocking = nil
            }
            return ScanRecordContext(
                id: entry.id,
                fullFingerprint: entry.fullFingerprint ?? entry.fingerprint,
                pair: entry.pair,
                engineCall: entry.side,
                score: entry.score,
                evidence: entry.why,
                veto: entry.veto,
                evaluationTime: entry.scannedAt,
                quoteMid: entry.evaluationQuote ?? entry.strike,
                spread: entry.evaluationSpread,
                m1Count: entry.m1Count ?? 0,
                m5Count: entry.m5Count ?? 0,
                engineSHA: entry.engineSHA ?? "unrecorded",
                expirySeconds: entry.expirySeconds ?? Timing.expirySec,
                isActionable: actionable,
                blockingReason: blocking,
                recordedVerb: entry.verb
            )
        }

        let confirmedRows = ledgerRows.filter { $0.labelSource == "venue-confirmed" }
        let confirmedEntries = confirmedRows
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(60)
            .map { row -> ConfirmedEntryContext in
                let scanTime = scanTimeByID[row.outcomeEventID]
                let late = row.enteredAt.map { entered in
                    guard let scanTime else { return false }
                    return entered.timeIntervalSince(scanTime) * 1000 > EntryQuality.maxAgeSeconds * 1000
                } ?? false
                return ConfirmedEntryContext(
                    id: row.outcomeEventID,
                    pair: row.pair,
                    side: row.side,
                    outcome: row.outcome,
                    recordedAt: row.timestamp,
                    enteredAt: row.enteredAt,
                    horizonSeconds: row.horizonSeconds,
                    entryQuote: row.entryQuote,
                    expiryPrice: row.expiryPrice,
                    stake: row.stake,
                    payout: row.payout,
                    lateEntry: late,
                    recordID: row.outcomeEventID
                )
            }

        // Calculate from the complete archive before bounding records for the model.
        let report = try? ExecutionIntelligence.report(rows: ledgerRows, journal: journal,
            observations: observations, asOf: now)
        let wins = report?.wins ?? 0
        let resolved = report?.resolved ?? 0
        let losses = resolved - wins
        let winRate = resolved > 0 ? Double(wins) / Double(resolved) : nil
        let performance = PerformanceSummary(
            sampleSize: resolved, wins: wins, losses: losses, ties: 0,
            unresolved: ledgerRows.filter { $0.outcome == "UNRESOLVED" || ($0.labelSource != "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)) }.count,
            winRate: winRate, breakEven: report?.breakEvenAtMinimumPayout ?? ExpectancyMath.breakEvenWinRate(),
            expectancy: report?.actualExpectancy,
            payoutBasis: report?.breakEvenAtMinimumPayout != nil ? "minimum recorded payout" : "assumed 88% payout; coverage incomplete",
            confirmedOnly: true,
            caveat: "INSUFFICIENT EVIDENCE. Actual unit expectancy requires recorded winning payouts; a loss contributes its full risk unit. Record selection is bounded for explanation; calculations use the complete supplied archive. Independence, policy stability and prospective validation remain unverified.")

        var gaps: [ObservationGap] = []
        for row in ledgerRows where row.labelSource != "venue-confirmed" && (row.outcome == "HIT" || row.outcome == "MISS") {
            gaps.append(ObservationGap(
                id: "gap-\(row.outcomeEventID)",
                pair: row.pair,
                kind: .missingConfirmation,
                detail: "Reference observation recorded as \(row.outcome); not a venue-confirmed result.",
                recordID: row.outcomeEventID
            ))
        }
        for item in confirmedEntries where item.lateEntry {
            gaps.append(ObservationGap(
                id: "late-\(item.recordID)",
                pair: item.pair,
                kind: .lateEntry,
                detail: "Entry was recorded after the 8-second action window.",
                recordID: item.recordID
            ))
        }
        for entry in sortedJournal where entry.outcome == nil
            && now.timeIntervalSince(entry.scannedAt) * 1000 > Timing.liveMs
            && entry.side != "WAIT" {
            gaps.append(ObservationGap(
                id: "unconfirmed-\(entry.id)",
                pair: entry.pair,
                kind: .missingConfirmation,
                detail: "The beam closed without a confirmed venue outcome.",
                recordID: entry.id
            ))
        }

        let notes = sortedJournal.compactMap { entry -> JournalNoteContext? in
            let text = [entry.voiceNote?.transcript, entry.lesson?.text]
                .compactMap { $0 }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return JournalNoteContext(
                id: entry.id,
                pair: entry.pair,
                note: text,
                createdAt: entry.voiceNote?.createdAt ?? entry.scannedAt
            )
        }.prefix(20)

        return AssistantContext(
            generatedAt: now,
            scans: scans,
            confirmedEntries: Array(confirmedEntries),
            performance: performance,
            research: report.map(ExecutionResearchSummary.init),
            gaps: Array(gaps.prefix(60)),
            notes: Array(notes)
        )
    }
}
