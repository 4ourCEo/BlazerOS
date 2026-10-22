import CryptoKit
import Foundation

/// Full SHA-1 of the bundled scan-engine.js. Both apps must load this exact script.
public enum EngineIdentity {
    public static let pinnedSHA1 = "7c02e550e2e6ca656a258ceefc6083f098ff40b2"

    /// Outcome of hashing a candidate engine source against the pin.
    public enum Verification: Sendable, Equatable {
        case verified(sha: String)
        case mismatch(loaded: String, pinned: String)
        case unavailable

        public var isVerified: Bool {
            if case .verified = self { return true }
            return false
        }

        /// Operator-facing explanation. Never includes the script body.
        public var detail: String {
            switch self {
            case .verified(let sha):
                return "engine \(sha.prefix(12)) verified"
            case .mismatch(let loaded, let pinned):
                return "engine hash mismatch: loaded \(loaded.prefix(12)), pinned \(pinned.prefix(12))"
            case .unavailable:
                return "engine source unavailable"
            }
        }
    }

    public static func sha1Hex(of source: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verification for a candidate source. This is the only place the pin is compared.
    public static func verify(source: String) -> Verification {
        let sha = sha1Hex(of: source)
        return sha == pinnedSHA1 ? .verified(sha: sha) : .mismatch(loaded: sha, pinned: pinnedSHA1)
    }

    public static func loadedSHA1() -> String? {
        if let known = StrategyEngine.knownSHA { return known }
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
    public var isActionable: Bool

    public init(
        pair: String,
        feed: FeedStatus,
        score: Int,
        why: String,
        strike: Double,
        verb: String,
        remainingMs: Double,
        veto: String?,
        fingerprint: String,
        isActionable: Bool
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
        self.isActionable = isActionable
    }

    public static func make(
        commit: ScanCommit,
        feed: FeedStatus,
        cabinetSide: String,
        elapsedMs: Double,
        historical: Bool = false
    ) -> DeskFrame {
        let actionable = !historical && (cabinetSide == "HIGH" || cabinetSide == "LOW") && elapsedMs > 0 && BeamContract.remainingMs(elapsedMs: elapsedMs, historical: historical) > 0 && feed == .live && commit.veto == nil
        let verb = actionable || historical
            ? BeamContract.verb(
                cabinetSide: cabinetSide,
                elapsedMs: elapsedMs,
                vetoed: commit.veto != nil,
                historical: historical
            )
            : "WAIT"
        return DeskFrame(
            pair: commit.asset,
            feed: feed,
            score: commit.score,
            why: commit.evidence,
            strike: commit.strike,
            verb: verb,
            remainingMs: actionable ? BeamContract.remainingMs(elapsedMs: elapsedMs, historical: historical) : 0,
            veto: commit.veto,
            fingerprint: commit.fingerprint,
            isActionable: actionable
        )
    }
}

/// An executed 60-second binary options trade horizon.
public struct ActiveTrade: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var pair: String
    public var side: String
    public var strike: Double
    public var score: Int
    public var enteredAt: Date
    public var expiresAt: Date
    public var durationSec: Double
    public var currentPrice: Double?
    public var stake: Double?
    public var payout: Double?
    /// User-supplied broker entry price. Optional; never inferred.
    public var brokerEntryPrice: Double?
    /// Evaluation age and beam timing captured when the user recorded the manual entry.
    public var evaluationAgeMs: Double?
    public var remainingBeamMs: Double?
    public var recordingDelayMs: Double?
    public var fingerprint: String

    public init(
        id: String,
        pair: String,
        side: String,
        strike: Double,
        score: Int,
        enteredAt: Date = Date(),
        durationSec: Double = 60.0,
        currentPrice: Double? = nil,
        stake: Double? = nil,
        payout: Double? = nil,
        brokerEntryPrice: Double? = nil,
        evaluationAgeMs: Double? = nil,
        remainingBeamMs: Double? = nil,
        recordingDelayMs: Double? = nil,
        fingerprint: String
    ) {
        self.id = id
        self.pair = pair
        self.side = side
        self.strike = strike
        self.score = score
        self.enteredAt = enteredAt
        self.expiresAt = enteredAt.addingTimeInterval(durationSec)
        self.durationSec = durationSec
        self.currentPrice = currentPrice
        self.stake = stake
        self.payout = payout
        self.brokerEntryPrice = brokerEntryPrice
        self.evaluationAgeMs = evaluationAgeMs
        self.remainingBeamMs = remainingBeamMs
        self.recordingDelayMs = recordingDelayMs
        self.fingerprint = fingerprint
    }

    public var remainingMs: Double {
        max(0, expiresAt.timeIntervalSince(Date()) * 1000)
    }

    public var isExpired: Bool {
        remainingMs <= 0
    }

    public var pipDiff: Double? {
        guard let currentPrice else { return nil }
        let pip = Assets.pipScale(for: pair)
        if side == "HIGH" {
            return (currentPrice - strike) / pip
        } else {
            return (strike - currentPrice) / pip
        }
    }

    public var isInTheMoney: Bool? {
        guard let pipDiff else { return nil }
        return pipDiff > 0
    }
}

/// Typed failures for enforcing entry gates at confirmation time.
public enum EntryGateFailure: Error, Sendable, Equatable {
    case expiredBeam
    case staleFeed
    case vetoed(String)
    case notDirectional
    case historical
    case activePositionExists
    case noArmedBeam
    case unsupportedExpiry
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

/// Provenance and evidence for an observed outcome. Reference observations are not broker outcomes.
public struct OutcomeProvenance: Sendable, Equatable, Codable {
    public enum Kind: String, Codable, Sendable { case reference, confirmedBroker }
    public enum EvidenceType: String, Codable, Sendable { case completedM1Candle, lastQuote, none }
    public var kind: Kind
    public var evidenceType: EvidenceType
    public var evidenceAt: Date?
    public var confirmedAt: Date?
    public var confirmedBy: String?

    public init(kind: Kind, evidenceType: EvidenceType, evidenceAt: Date? = nil, confirmedAt: Date? = nil, confirmedBy: String? = nil) {
        self.kind = kind
        self.evidenceType = evidenceType
        self.evidenceAt = evidenceAt
        self.confirmedAt = confirmedAt
        self.confirmedBy = confirmedBy
    }
}
