import Foundation

/// Spoken note. Empty until speech exists. Persistence stores it; speech does not score.
public struct VoiceNote: Codable, Equatable, Sendable {
    public var transcript: String
    public var createdAt: Date

    public init(transcript: String, createdAt: Date) {
        self.transcript = transcript
        self.createdAt = createdAt
    }
}

public struct Emotion: Codable, Equatable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct Lesson: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct Tag: Codable, Equatable, Sendable {
    public var label: String

    public init(label: String) {
        self.label = label
    }
}

/// One committed scan the journal can reopen after quit. Bars live in the snapshot file.
public struct JournalEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var fingerprint: String
    public var pair: String
    public var score: Int
    public var side: String
    public var verb: String
    public var why: String
    public var strike: Double
    public var veto: String?
    public var scannedAt: Date
    public var voiceNote: VoiceNote?
    public var tag: Tag?
    public var emotion: Emotion?
    public var lesson: Lesson?
    public var outcome: String?

    public init(
        id: String,
        fingerprint: String,
        pair: String,
        score: Int,
        side: String,
        verb: String,
        why: String,
        strike: Double,
        veto: String?,
        scannedAt: Date,
        voiceNote: VoiceNote? = nil,
        tag: Tag? = nil,
        emotion: Emotion? = nil,
        lesson: Lesson? = nil,
        outcome: String? = nil
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.pair = pair
        self.score = score
        self.side = side
        self.verb = verb
        self.why = why
        self.strike = strike
        self.veto = veto
        self.scannedAt = scannedAt
        self.voiceNote = voiceNote
        self.tag = tag
        self.emotion = emotion
        self.lesson = lesson
        self.outcome = outcome
    }
}

/// JSONL journal. A bad line is skipped. Saving rewrites the recovered entries plus the change.
public actor JournalStore {
    private let url: URL

    public init(root: URL) {
        self.url = FileLocations.journal(in: root)
    }

    public func load() throws -> [JournalEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [JournalEntry] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(raw).data(using: .utf8),
                let entry = try? decoder.decode(JournalEntry.self, from: data),
                !entry.id.isEmpty
            else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// Inserts or replaces the entry with the same id. Other recovered entries stay.
    public func upsert(_ entry: JournalEntry) throws {
        var entries = try load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save(entries)
    }

    public func save(_ entries: [JournalEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for entry in entries {
            var line = try encoder.encode(entry)
            line.append(0x0A)
            data.append(line)
        }
        try AtomicFile.write(data, to: url)
    }
}
