import Foundation

/// HIT or MISS. The only outcomes the desk is allowed to append.
public enum DeskOutcome: String, Codable, Sendable, Equatable {
    case hit = "HIT"
    case miss = "MISS"
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
}

/// One ledger row. `outcomeEventID` is the arm id and is not a CSV column.
public struct LedgerRow: Equatable, Sendable {
    public var timestamp: Date
    public var pair: String
    public var hash: String
    public var score: Int
    public var side: String
    public var veto: Bool
    public var drift: Double
    public var outcome: String
    public var outcomeEventID: String

    public init(
        timestamp: Date,
        pair: String,
        hash: String,
        score: Int,
        side: String,
        veto: Bool,
        drift: Double,
        outcome: String,
        outcomeEventID: String
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
    }
}

/// Append-only scan ledger. One outcome per fingerprint. A repeat claim does not add a row.
public actor LedgerStore {
    public static let csvHeader = "timestamp,pair,hash,score,side,veto,drift,outcome"

    private let url: URL
    private var claimedHashes: Set<String> = []
    private var claimedArms: Set<String> = []
    private var loaded = false

    public init(root: URL) {
        self.url = FileLocations.ledgerCSV(in: root)
    }

    /// `true` only when a new row was appended.
    @discardableResult
    public func record(_ row: LedgerRow) throws -> Bool {
        guard !row.hash.isEmpty, !row.outcomeEventID.isEmpty else { return false }
        try loadClaims()
        if claimedHashes.contains(row.hash) || claimedArms.contains(row.outcomeEventID) {
            return false
        }
        claimedHashes.insert(row.hash)
        claimedArms.insert(row.outcomeEventID)
        do {
            var existing = (try? Data(contentsOf: url)) ?? Data()
            if existing.isEmpty {
                existing.append(Data((Self.csvHeader + "\n").utf8))
            } else if existing.last != 0x0A {
                existing.append(0x0A)
            }
            existing.append(Data(line(for: row).utf8))
            try AtomicFile.write(existing, to: url)
            return true
        } catch {
            claimedHashes.remove(row.hash)
            claimedArms.remove(row.outcomeEventID)
            throw error
        }
    }

    public func rows() throws -> [LedgerRow] {
        try loadClaims()
        return parse(try text())
    }

    public func stats() throws -> OutcomeStats {
        OutcomeStats.tally(try rows())
    }

    private func loadClaims() throws {
        if loaded { return }
        loaded = true
        for row in parse(try text()) {
            claimedHashes.insert(row.hash)
            claimedArms.insert(row.outcomeEventID)
        }
    }

    private func text() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func parse(_ text: String) -> [LedgerRow] {
        var parsed: [LedgerRow] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if line.isEmpty { continue }
            if index == 0, line == Self.csvHeader { continue }
            guard let fields = Self.fields(in: line), fields.count == 8 || fields.count == 9 else { continue }
            guard let timestamp = Self.iso8601.date(from: fields[0]),
                let score = Int(fields[3]),
                fields[5] == "true" || fields[5] == "false",
                let drift = Double(fields[6]),
                !fields[2].isEmpty
            else { continue }
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
                    outcomeEventID: fields[2]
                )
            )
        }
        return parsed
    }

    private func line(for row: LedgerRow) -> String {
        [
            csv(Self.iso8601.string(from: row.timestamp)),
            csv(row.pair),
            csv(row.hash),
            csv(String(row.score)),
            csv(row.side),
            csv(row.veto ? "true" : "false"),
            csv(String(format: "%.4f", row.drift)),
            csv(row.outcome),
        ].joined(separator: ",") + "\n"
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
