import Foundation

/// The outcomes the desk is allowed to append. `unresolved` records that the operator
/// could not verify the venue result; it is deliberately excluded from confirmed statistics.
public enum DeskOutcome: String, Codable, Sendable, Equatable {
    case hit = "HIT"
    case miss = "MISS"
    case unresolved = "UNRESOLVED"
}

public struct OutcomeStats: Equatable, Sendable {
    public var hits: Int
    public var misses: Int

    public init(hits: Int, misses: Int) {
        self.hits = hits
        self.misses = misses
    }

    public static let empty = OutcomeStats(hits: 0, misses: 0)

    public static func tally(_ rows: [LedgerRow]) -> OutcomeStats {
        OutcomeStats(
            hits: rows.filter { $0.outcome == DeskOutcome.hit.rawValue }.count,
            misses: rows.filter { $0.outcome == DeskOutcome.miss.rawValue }.count
        )
    }

    /// Only rows the user confirmed against the venue. Reference/synthetic rows never
    /// contribute to the performance shown as confirmed.
    public static func confirmedTally(_ rows: [LedgerRow]) -> OutcomeStats {
        tally(rows.filter { $0.labelSource == "venue-confirmed" })
    }
}

/// One ledger row. `outcomeEventID` is the arm id and is not a CSV column.
public struct LedgerRow: Equatable, Sendable, Codable {
    public var timestamp: Date
    public var pair: String
    public var hash: String
    public var score: Int
    public var side: String
    public var veto: Bool
    public var drift: Double
    public var outcome: String
    public var outcomeEventID: String

    // V2 Measurement-First Metadata
    public var payout: Double?
    public var stake: Double?
    public var marketWindow: String?
    public var engineSHA: String?
    public var fullFingerprint: String?
    public var entryQuote: Double?
    public var expiryPrice: Double?
    public var labelSource: String?
    public var horizonSeconds: Int?
    public var enteredAt: Date?
    public var expiryObservedMs: Double?
    /// Handoff evidence captured when the manual entry was recorded.
    public var evaluationAgeMs: Double?
    public var recordingDelayMs: Double?
    public var remainingBeamMs: Double?

    /// Schema version this row was written with. Nil for rows read from v1/v2 files.
    public var schemaVersion: Int?

    /// Storage identity. Full pair-and-bars digest when present, short hash otherwise.
    public var identity: String {
        if let fullFingerprint, !fullFingerprint.isEmpty { return fullFingerprint }
        return hash
    }

    public init(
        timestamp: Date,
        pair: String,
        hash: String,
        score: Int,
        side: String,
        veto: Bool,
        drift: Double,
        outcome: String,
        outcomeEventID: String,
        payout: Double? = nil,
        stake: Double? = nil,
        marketWindow: String? = nil,
        engineSHA: String? = nil,
        fullFingerprint: String? = nil,
        entryQuote: Double? = nil,
        expiryPrice: Double? = nil,
        labelSource: String? = nil,
        horizonSeconds: Int? = nil,
        enteredAt: Date? = nil,
        expiryObservedMs: Double? = nil,
        evaluationAgeMs: Double? = nil,
        recordingDelayMs: Double? = nil,
        remainingBeamMs: Double? = nil,
        schemaVersion: Int? = nil
    ) {
        self.timestamp = timestamp
        self.pair = pair
        self.hash = hash
        self.score = score
        self.side = side
        self.veto = veto
        self.drift = drift
        self.outcome = outcome
        self.outcomeEventID = outcomeEventID
        self.payout = payout
        self.stake = stake
        self.marketWindow = marketWindow
        self.engineSHA = engineSHA
        self.fullFingerprint = fullFingerprint
        self.entryQuote = entryQuote
        self.expiryPrice = expiryPrice
        self.labelSource = labelSource
        self.horizonSeconds = horizonSeconds
        self.enteredAt = enteredAt
        self.expiryObservedMs = expiryObservedMs
        self.evaluationAgeMs = evaluationAgeMs
        self.recordingDelayMs = recordingDelayMs
        self.remainingBeamMs = remainingBeamMs
        self.schemaVersion = schemaVersion
    }
}

/// Outcome of a ledger read. Malformed lines are counted, never silently rewritten away.
public struct LedgerReadResult: Sendable, Equatable {
    public var rows: [LedgerRow]
    public var damagedLines: Int

    public init(rows: [LedgerRow], damagedLines: Int = 0) {
        self.rows = rows
        self.damagedLines = damagedLines
    }
}

/// Append-only scan ledger. One outcome per identity. A repeat claim does not add a row.
///
/// Schema history:
/// - v1: eight columns, identity is the 4-byte display hash.
/// - v2: eleven measurement columns appended under the v1 header. Ambiguous to readers.
/// - v3: every column declared in the header, explicit `schemaVersion`, full identity.
/// - v4: evaluation age, recording delay, and remaining beam persisted for handoff evidence.
///
/// Later versions keep every earlier column at its original index so existing files still parse.
public actor LedgerStore {
    public static let schemaVersion = 4

    /// v1 header, kept so older files and readers can still recognise the file.
    public static let legacyHeader = "timestamp,pair,hash,score,side,veto,drift,outcome"

    public static let csvHeader = "timestamp,pair,hash,score,side,veto,drift,outcome,"
        + "payout,stake,marketWindow,engineSHA,fullFingerprint,entryQuote,expiryPrice,"
        + "labelSource,horizonSeconds,enteredAt,expiryObservedMs,outcomeEventID,schemaVersion,"
        + "evaluationAgeMs,recordingDelayMs,remainingBeamMs"

    public static let columnCount = 24

    private let url: URL
    private var claimedIdentities: Set<String> = []
    private var claimedArms: Set<String> = []
    private var loaded = false

    public init(root: URL) {
        self.url = FileLocations.ledgerCSV(in: root)
    }

    /// `true` only when a new row was appended.
    @discardableResult
    public func record(_ row: LedgerRow) throws -> Bool {
        guard !row.identity.isEmpty, !row.outcomeEventID.isEmpty else { return false }
        try loadClaims()
        if claimedIdentities.contains(Self.identityKey(row)) || claimedArms.contains(row.outcomeEventID) {
            return false
        }
        claimedIdentities.insert(Self.identityKey(row))
        claimedArms.insert(row.outcomeEventID)
        do {
            var existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
            // Upgrade legacy header to v3 if needed. Keep the original bytes so a migration
            // never destroys evidence that a reader might still need.
            if !existing.isEmpty, let text = String(data: existing, encoding: .utf8) {
                if let firstNewline = text.firstIndex(of: "\n") {
                    let firstLine = String(text[..<firstNewline])
                    if firstLine != Self.csvHeader {
                        try Self.backupLegacyFileIfNeeded(url: url, data: existing)
                        let rest = String(text[text.index(after: firstNewline)...])
                        let upgraded = Self.csvHeader + "\n" + rest
                        existing = Data(upgraded.utf8)
                    }
                } else if text != Self.csvHeader {
                    try Self.backupLegacyFileIfNeeded(url: url, data: existing)
                    existing = Data((Self.csvHeader + "\n").utf8)
                }
            }

            if existing.isEmpty {
                existing.append(Data((Self.csvHeader + "\n").utf8))
            } else if existing.last != 0x0A {
                existing.append(0x0A)
            }
            existing.append(Data(line(for: row).utf8))
            try AtomicFile.write(existing, to: url)
            return true
        } catch {
            claimedIdentities.remove(Self.identityKey(row))
            claimedArms.remove(row.outcomeEventID)
            throw error
        }
    }

    public func rows() throws -> [LedgerRow] {
        try read().rows
    }

    /// Reads every valid row and reports how many lines could not be parsed.
    public func read() throws -> LedgerReadResult {
        try loadClaims()
        return parse(try text())
    }

    public func stats() throws -> OutcomeStats {
        OutcomeStats.tally(try rows())
    }

    /// True when this arm already has a row. Used to reconcile interrupted settlements.
    public func contains(outcomeEventID: String) throws -> Bool {
        try loadClaims()
        return claimedArms.contains(outcomeEventID)
    }

    private static func identityKey(_ row: LedgerRow) -> String {
        "\(row.identity)|\(row.pair)"
    }

    private func loadClaims() throws {
        if loaded { return }
        for row in parse(try text()).rows {
            claimedIdentities.insert(Self.identityKey(row))
            claimedArms.insert(row.outcomeEventID)
        }
        loaded = true
    }

    private func text() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func parse(_ text: String) -> LedgerReadResult {
        var parsed: [LedgerRow] = []
        var damaged = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { continue }
            // Any header generation starts with the v1 column names.
            if line.hasPrefix("timestamp,pair,hash,"), line.contains("score") { continue }
            guard let fields = Self.fields(in: line), fields.count >= 8 else {
                damaged += 1
                continue
            }
            guard let timestamp = Self.iso8601.date(from: fields[0]),
                let score = Int(fields[3]),
                fields[5] == "true" || fields[5] == "false",
                let drift = Double(fields[6]),
                !fields[2].isEmpty
            else {
                damaged += 1
                continue
            }

            // The original Mac ledger had nine columns and its ninth was `theirPrice`,
            // not the v2 `payout`. Never reinterpret a legacy price as a payout.
            let isLegacyNineColumn = fields.count == 9
            let payout = fields.count > 8 && !isLegacyNineColumn ? Double(fields[8]) : nil
            let stake = fields.count > 9 ? Double(fields[9]) : nil
            let marketWindow = fields.count > 10 && !fields[10].isEmpty ? fields[10] : nil
            let engineSHA = fields.count > 11 && !fields[11].isEmpty ? fields[11] : nil
            let fullFingerprint = fields.count > 12 && !fields[12].isEmpty ? fields[12] : nil
            let entryQuote = fields.count > 13
                ? Double(fields[13])
                : (isLegacyNineColumn ? Double(fields[8]) : nil)
            let expiryPrice = fields.count > 14 ? Double(fields[14]) : nil
            let version = fields.count > 20 ? Int(fields[20]) : nil
            // Pre-v3 rows have no arm id. Preserve one distinct event per historical row
            // instead of collapsing every outcome on a hash into the same pseudo-arm.
            let armID = fields.count > 19 && !fields[19].isEmpty
                ? fields[19]
                : "\(fields[2])-\(fields[0])"

            parsed.append(
                LedgerRow(
                    timestamp: timestamp,
                    pair: fields[1],
                    hash: fields[2],
                    score: score,
                    side: fields[4],
                    veto: fields[5] == "true",
                    drift: drift,
                    outcome: fields[7],
                    outcomeEventID: armID,
                    payout: payout,
                    stake: stake,
                    marketWindow: marketWindow,
                    engineSHA: engineSHA,
                    fullFingerprint: fullFingerprint,
                    entryQuote: entryQuote,
                    expiryPrice: expiryPrice,
                    labelSource: fields.count > 15 && !fields[15].isEmpty ? fields[15] : nil,
                    horizonSeconds: fields.count > 16 ? Int(fields[16]) : nil,
                    enteredAt: fields.count > 17 ? Self.iso8601.date(from: fields[17]) : nil,
                    expiryObservedMs: fields.count > 18 ? Double(fields[18]) : nil,
                    evaluationAgeMs: fields.count > 21 ? Double(fields[21]) : nil,
                    recordingDelayMs: fields.count > 22 ? Double(fields[22]) : nil,
                    remainingBeamMs: fields.count > 23 ? Double(fields[23]) : nil,
                    schemaVersion: version
                )
            )
        }
        return LedgerReadResult(rows: parsed, damagedLines: damaged)
    }

    /// Copies a pre-v3 ledger exactly once before the header is rewritten in place.
    private static func backupLegacyFileIfNeeded(url: URL, data: Data) throws {
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).pre-v3.bak")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try AtomicFile.write(data, to: backup)
    }

    /// Always writes a fixed-width v4 row so the header is truthful.
    private func line(for row: LedgerRow) -> String {
        let parts = [
            csv(Self.iso8601.string(from: row.timestamp)),
            csv(row.pair),
            csv(row.hash),
            csv(String(row.score)),
            csv(row.side),
            csv(row.veto ? "true" : "false"),
            csv(String(format: "%.4f", row.drift)),
            csv(row.outcome),
            csv(row.payout.map { String($0) } ?? ""),
            csv(row.stake.map { String($0) } ?? ""),
            csv(row.marketWindow ?? ""),
            csv(row.engineSHA ?? ""),
            csv(row.fullFingerprint ?? ""),
            csv(row.entryQuote.map { String($0) } ?? ""),
            csv(row.expiryPrice.map { String($0) } ?? ""),
            csv(row.labelSource ?? ""),
            csv(row.horizonSeconds.map { String($0) } ?? ""),
            csv(row.enteredAt.map { Self.iso8601.string(from: $0) } ?? ""),
            csv(row.expiryObservedMs.map { String($0) } ?? ""),
            csv(row.outcomeEventID),
            csv(String(Self.schemaVersion)),
            csv(row.evaluationAgeMs.map { String($0) } ?? ""),
            csv(row.recordingDelayMs.map { String($0) } ?? ""),
            csv(row.remainingBeamMs.map { String($0) } ?? ""),
        ]
        return parts.joined(separator: ",") + "\n"
    }

    private func csv(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// Quoted CSV. A broken quote returns nil so the line is skipped.
    static func fields(in line: String) -> [String]? {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if quoted {
                if character == "\"" {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = line.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        if quoted { return nil }
        fields.append(current)
        return fields
    }

    private static var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
