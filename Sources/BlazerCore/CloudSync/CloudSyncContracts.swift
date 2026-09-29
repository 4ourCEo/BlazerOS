import CloudKit
import Foundation

/// Record types used in the private CloudKit database.
public enum CloudRecordType {
    public static let ledger = "BlazerLedger"
    public static let snapshot = "BlazerSnapshot"
    public static let journal = "BlazerJournal"
    public static let settings = "BlazerSettings"
}

/// Enforces that sensitive credentials, live quotes, and active scans never reach CloudKit.
public enum CloudSecurityGate {
    private static let forbiddenKeys: Set<String> = [
        "oandatoken", "token", "bearer", "authorization",
        "livefeed", "quote", "bid", "ask", "mid",
        "activescan", "beam",
    ]

    private static let tokenRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?i)\b[0-9a-f]{32,}\b"#)
    }()

    private static func words(in identifier: String) -> Set<String> {
        var result = Set<String>()
        let clean = identifier.lowercased().filter { $0.isLetter || $0.isNumber }
        if !clean.isEmpty {
            result.insert(clean)
        }
        var current = ""
        for char in identifier {
            if char.isLetter || char.isNumber {
                if char.isUppercase {
                    if !current.isEmpty {
                        result.insert(current.lowercased())
                        current = ""
                    }
                }
                current.append(char)
            } else {
                if !current.isEmpty {
                    result.insert(current.lowercased())
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            result.insert(current.lowercased())
        }
        return result
    }

    private static func containsTokenShape(_ text: String) -> Bool {
        guard let tokenRegex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return tokenRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    public static func validate(record: CKRecord) -> Bool {
        for key in record.allKeys() {
            let keyWords = words(in: key)
            if !forbiddenKeys.isDisjoint(with: keyWords) {
                return false
            }
            if let strVal = record[key] as? String {
                let valLower = strVal.lowercased()
                if valLower.contains("bearer ") || valLower.contains("oanda_token") {
                    return false
                }
                if key != "barsJSON" && containsTokenShape(strVal) {
                    return false
                }
            }
        }
        return true
    }

    public static func validate(row: LedgerRow) -> Bool {
        let fields = [row.side, row.pair, row.outcome]
        for field in fields {
            let fieldWords = words(in: field)
            if !forbiddenKeys.isDisjoint(with: fieldWords) {
                return false
            }
            if containsTokenShape(field) {
                return false
            }
        }
        return true
    }
}

/// Pure Swift mappings between local records and CloudKit CKRecord objects.
public enum CloudRecordMapper {
    public static func makeRecord(from row: LedgerRow, zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID
        if let zoneID {
            recordID = CKRecord.ID(recordName: "ledger_\(row.hash)", zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: "ledger_\(row.hash)")
        }
        let record = CKRecord(recordType: CloudRecordType.ledger, recordID: recordID)
        record["timestamp"] = row.timestamp as CKRecordValue
        record["pair"] = row.pair as CKRecordValue
        record["hash"] = row.hash as CKRecordValue
        record["score"] = Int64(row.score) as CKRecordValue
        record["side"] = row.side as CKRecordValue
        record["veto"] = (row.veto ? 1 : 0) as CKRecordValue
        record["drift"] = row.drift as CKRecordValue
        record["outcome"] = row.outcome as CKRecordValue
        record["outcomeEventID"] = row.outcomeEventID as CKRecordValue
        return record
    }

    public static func toLedgerRow(from record: CKRecord) -> LedgerRow? {
        guard record.recordType == CloudRecordType.ledger,
              let timestamp = record["timestamp"] as? Date,
              let pair = record["pair"] as? String,
              let hash = record["hash"] as? String,
              let score = record["score"] as? Int64,
              let side = record["side"] as? String,
              let vetoVal = record["veto"] as? Int64,
              let drift = record["drift"] as? Double,
              let outcome = record["outcome"] as? String
        else { return nil }

        let outcomeEventID = (record["outcomeEventID"] as? String) ?? hash
        return LedgerRow(
            timestamp: timestamp,
            pair: pair,
            hash: hash,
            score: Int(score),
            side: side,
            veto: vetoVal != 0,
            drift: drift,
            outcome: outcome,
            outcomeEventID: outcomeEventID
        )
    }

    public static func makeRecord(from snapshot: SnapshotRecord, zoneID: CKRecordZone.ID? = nil) -> CKRecord? {
        let recordID: CKRecord.ID
        if let zoneID {
            recordID = CKRecord.ID(recordName: "snap_\(snapshot.hash)", zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: "snap_\(snapshot.hash)")
        }
        let record = CKRecord(recordType: CloudRecordType.snapshot, recordID: recordID)
        record["hash"] = snapshot.hash as CKRecordValue
        record["pair"] = snapshot.pair as CKRecordValue
        record["strike"] = snapshot.strike as CKRecordValue
        record["score"] = Int64(snapshot.score) as CKRecordValue
        record["side"] = snapshot.side as CKRecordValue

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let barsData = try? encoder.encode(snapshot.bars),
              let barsString = String(data: barsData, encoding: .utf8) else {
            return nil
        }
        record["barsJSON"] = barsString as CKRecordValue
        return record
    }

    public static func toSnapshotRecord(from record: CKRecord) -> SnapshotRecord? {
        guard record.recordType == CloudRecordType.snapshot,
              let hash = record["hash"] as? String,
              let pair = record["pair"] as? String,
              let strike = record["strike"] as? Double,
              let score = record["score"] as? Int64,
              let side = record["side"] as? String,
              let barsJSON = record["barsJSON"] as? String,
              let barsData = barsJSON.data(using: .utf8)
        else { return nil }

        let decoder = JSONDecoder()
        guard let bars = try? decoder.decode([Candle].self, from: barsData) else {
            return nil
        }

        return SnapshotRecord(
            hash: hash,
            pair: pair,
            bars: bars,
            strike: strike,
            score: Int(score),
            side: side
        )
    }

    public static func makeRecord(from entry: JournalEntry, zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID
        if let zoneID {
            recordID = CKRecord.ID(recordName: "journal_\(entry.id)", zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: "journal_\(entry.id)")
        }
        let record = CKRecord(recordType: CloudRecordType.journal, recordID: recordID)
        record["id"] = entry.id as CKRecordValue
        record["fingerprint"] = entry.fingerprint as CKRecordValue
        record["pair"] = entry.pair as CKRecordValue
        record["score"] = Int64(entry.score) as CKRecordValue
        record["side"] = entry.side as CKRecordValue
        record["verb"] = entry.verb as CKRecordValue
        record["why"] = entry.why as CKRecordValue
        record["strike"] = entry.strike as CKRecordValue
        record["scannedAt"] = entry.scannedAt as CKRecordValue

        if let veto = entry.veto {
            record["veto"] = veto as CKRecordValue
        }
        if let outcome = entry.outcome {
            record["outcome"] = outcome as CKRecordValue
        }
        if let note = entry.voiceNote {
            record["voiceTranscript"] = note.transcript as CKRecordValue
            record["voiceCreatedAt"] = note.createdAt as CKRecordValue
        }
        if let tag = entry.tag {
            record["tagLabel"] = tag.label as CKRecordValue
        }
        if let lesson = entry.lesson {
            record["lessonText"] = lesson.text as CKRecordValue
        }
        return record
    }

    public static func toJournalEntry(from record: CKRecord) -> JournalEntry? {
        guard record.recordType == CloudRecordType.journal,
              let id = record["id"] as? String,
              let fingerprint = record["fingerprint"] as? String,
              let pair = record["pair"] as? String,
              let score = record["score"] as? Int64,
              let side = record["side"] as? String,
              let verb = record["verb"] as? String,
              let why = record["why"] as? String,
              let strike = record["strike"] as? Double,
              let scannedAt = record["scannedAt"] as? Date
        else { return nil }

        let veto = record["veto"] as? String
        let outcome = record["outcome"] as? String

        var voiceNote: VoiceNote?
        if let transcript = record["voiceTranscript"] as? String,
           let createdAt = record["voiceCreatedAt"] as? Date {
            voiceNote = VoiceNote(transcript: transcript, createdAt: createdAt)
        }

        var tag: Tag?
        if let tagLabel = record["tagLabel"] as? String {
            tag = Tag(label: tagLabel)
        }

        var lesson: Lesson?
        if let lessonText = record["lessonText"] as? String {
            lesson = Lesson(text: lessonText)
        }

        return JournalEntry(
            id: id,
            fingerprint: fingerprint,
            pair: pair,
            score: Int(score),
            side: side,
            verb: verb,
            why: why,
            strike: strike,
            veto: veto,
            scannedAt: scannedAt,
            voiceNote: voiceNote,
            tag: tag,
            emotion: nil,
            lesson: lesson,
            outcome: outcome
        )
    }
}
