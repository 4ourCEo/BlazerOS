import CryptoKit
import Foundation

/// Full SHA-1 of the bundled scan-engine.js. Both apps must load this exact script.
public enum EngineIdentity {
    public static let pinnedSHA1 = "1a1d264d44eec606ded991cb4814df953bc07b34"

    public static func sha1Hex(of source: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func loadedSHA1() -> String? {
        guard let source = StrategyEngine.bundleSource() else { return nil }
        return sha1Hex(of: source)
    }

    /// True only when the script in this process matches the pin both desks ship.
    public static func bundleMatchesPin() -> Bool {
        loadedSHA1() == pinnedSHA1
    }
}

/// What a completed scan is allowed to prove. Recomputed on each device from frozen bars.
public struct ParitySeal: Sendable, Equatable, Codable {
    public var engineSHA1: String
    public var fingerprint: String
    public var score: Int
    public var side: String
    public var strike: Double
    public var candleCount: Int

    public init(
        engineSHA1: String,
        fingerprint: String,
        score: Int,
        side: String,
        strike: Double,
        candleCount: Int
    ) {
        self.engineSHA1 = engineSHA1
        self.fingerprint = fingerprint
        self.score = score
        self.side = side
        self.strike = strike
        self.candleCount = candleCount
    }

    public static func make(commit: ScanCommit, engineSHA1: String) -> ParitySeal {
        ParitySeal(
            engineSHA1: engineSHA1,
            fingerprint: commit.fingerprint,
            score: commit.score,
            side: commit.engineCall,
            strike: commit.strike,
            candleCount: commit.candleCount
        )
    }

    /// Same frozen bars on this device must reproduce the sealed fingerprint.
    public func matchesLocalBars(_ candles: [Candle]) -> Bool {
        ScanFingerprint.hex(candles: candles) == fingerprint && candles.count == candleCount
    }
}

/// The single screen state. Lightning Desk, Dynamic Island, Live Activity, and Watch render this.
/// They do not keep a second countdown or a second side.
public struct DeskFrame: Sendable, Equatable {
    public var pair: String
    public var feed: FeedStatus
    public var score: Int
    public var why: String
    public var strike: Double
    public var verb: String
    public var remainingMs: Double
    public var veto: String?
    public var fingerprint: String

    public init(
        pair: String,
        feed: FeedStatus,
        score: Int,
        why: String,
        strike: Double,
        verb: String,
        remainingMs: Double,
        veto: String?,
        fingerprint: String
    ) {
        self.pair = pair
        self.feed = feed
        self.score = score
        self.why = why
        self.strike = strike
        self.verb = verb
        self.remainingMs = remainingMs
        self.veto = veto
        self.fingerprint = fingerprint
    }

    public static func make(
        commit: ScanCommit,
        feed: FeedStatus,
        cabinetSide: String,
        elapsedMs: Double
    ) -> DeskFrame {
        let vetoed = commit.veto != nil
        return DeskFrame(
            pair: commit.asset,
            feed: feed,
            score: commit.score,
            why: commit.evidence,
            strike: commit.strike,
            verb: BeamContract.verb(cabinetSide: cabinetSide, elapsedMs: elapsedMs, vetoed: vetoed),
            remainingMs: BeamContract.remainingMs(elapsedMs: elapsedMs),
            veto: commit.veto,
            fingerprint: commit.fingerprint
        )
    }
}

/// Spoken note attached to a fingerprint. Tags are annotations. They are not scan inputs.
public struct JournalTags: Sendable, Equatable, Codable {
    public var emotion: String
    public var discipline: String
    public var setup: String
    public var lesson: String

    public init(emotion: String, discipline: String, setup: String, lesson: String) {
        self.emotion = emotion
        self.discipline = discipline
        self.setup = setup
        self.lesson = lesson
    }
}

public struct JournalNote: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var fingerprint: String
    public var spoken: String
    public var tags: JournalTags?
    public var createdAt: Date

    public init(id: String, fingerprint: String, spoken: String, tags: JournalTags?, createdAt: Date) {
        self.id = id
        self.fingerprint = fingerprint
        self.spoken = spoken
        self.tags = tags
        self.createdAt = createdAt
    }
}

/// Hands-free grammar. The kernel resolves `.scan`. Explain and performance read a seal; they do not rescore.
public enum VoiceCommand: Sendable, Equatable {
    case scan(pair: String)
    case explainWait
    case readPerformance
}

/// Records that may move through CloudKit.
public enum SyncDomain: String, Sendable, Codable, CaseIterable {
    case ledger
    case snapshot
    case journal
    case settings
    case replay
}

/// Things that must stay on the device that created them.
public enum DeviceLocal: String, Sendable, Codable, CaseIterable {
    case oandaToken
    case liveFeed
    case activeScan
}

/// Coach sits above the engine. It may explain a seal. It may not return a side or a score.
public protocol TradingCoach: Sendable {
    func explain(seal: ParitySeal, evidence: String, question: String) async throws -> String
    func tag(spoken: String, seal: ParitySeal) async throws -> JournalTags
}
