import CryptoKit
import Foundation

/// Immutable bars + quote captured at SCAN. The live feed must not mutate this.
public struct ScanSnapshot: Sendable, Equatable {
    public var asset: String
    public var candles: [Candle]
    public var quoteMid: Double
    public var scannedAt: Date

    public init(asset: String, candles: [Candle], quoteMid: Double, scannedAt: Date) {
        self.asset = asset
        self.candles = candles
        self.quoteMid = quoteMid
        self.scannedAt = scannedAt
    }
}

/// One engine pass. Frozen fields stay until the next SCAN.
/// Brakes may set `veto` and `driftPips` only.
public struct ScanCommit: Sendable {
    public let asset: String
    public let engineCall: String
    /// Side-neutral directional score: `max(directionScore, 100 - directionScore)`.
    /// It is not a calibrated win probability and never carries direction by itself.
    public let score: Int
    public let evidence: String
    public let strike: Double
    /// Short display fingerprint. Shown in the UI and written to the legacy column.
    public let fingerprint: String
    /// Full frozen-input SHA-1 (pair, M1, M5, quote/spread, expiry, engine, policy).
    /// Storage identity for the ledger and snapshot archive.
    public let fullFingerprint: String
    public let candleCount: Int
    public let candles: [Candle]
    /// M5 bars the engine evaluated. Stored so a snapshot can reproduce the decision.
    public let m5Candles: [Candle]
    public let bid: Double?
    public let ask: Double?
    public let spread: Double?
    public let expirySeconds: Int
    public let engineSHA: String
    public let policy: String
    public let scannedAt: Date
    public var veto: String?
    public var driftPips: Double?

    public init(
        asset: String,
        engineCall: String,
        score: Int,
        evidence: String,
        strike: Double,
        fingerprint: String,
        fullFingerprint: String? = nil,
        candleCount: Int,
        candles: [Candle],
        m5Candles: [Candle] = [],
        bid: Double? = nil,
        ask: Double? = nil,
        spread: Double? = nil,
        expirySeconds: Int = Timing.expirySec,
        engineSHA: String = EngineIdentity.pinnedSHA1,
        policy: String = "baseline",
        scannedAt: Date,
        veto: String? = nil,
        driftPips: Double? = nil
    ) {
        self.asset = asset
        self.engineCall = engineCall
        self.score = score
        self.evidence = evidence
        self.strike = strike
        self.fingerprint = fingerprint
        self.fullFingerprint = fullFingerprint ?? ScanInputSnapshot(
            pair: asset,
            m1: candles,
            m5: m5Candles,
            bid: bid,
            ask: ask,
            spread: spread,
            expirySeconds: expirySeconds,
            engineSHA: engineSHA,
            policy: policy
        ).identity
        self.candleCount = candleCount
        self.candles = candles
        self.m5Candles = m5Candles
        self.bid = bid
        self.ask = ask
        self.spread = spread
        self.expirySeconds = expirySeconds
        self.engineSHA = engineSHA
        self.policy = policy
        self.scannedAt = scannedAt
        self.veto = veto
        self.driftPips = driftPips
    }

    /// The exact frozen input this commit was built from.
    public var inputSnapshot: ScanInputSnapshot {
        ScanInputSnapshot(
            pair: asset,
            m1: candles,
            m5: m5Candles,
            bid: bid,
            ask: ask,
            spread: spread,
            expirySeconds: expirySeconds,
            engineSHA: engineSHA,
            policy: policy
        )
    }
}

public enum ScanFingerprint {
    /// Stable fingerprint of the completed bars passed to scan-engine.js.
    /// Same bars → same hex. Not a secret. First 4 bytes of SHA-1, uppercase.
    /// Display only. Never use this as a storage or deduplication identity: 4 bytes
    /// collide, and the pair is not part of the digest.
    public static func hex(candles: [Candle]) -> String {
        var text = ""
        text.reserveCapacity(candles.count * 48)
        for bar in candles {
            let time = bar.time.map { String(Int($0)) } ?? ""
            text += "\(time),\(bar.bodyOpen),\(bar.bodyHigh),\(bar.bodyLow),\(bar.close)\n"
        }
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        let bytes = Array(digest)
        return bytes.prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    /// Full SHA-1 over the pair and the completed bars. Storage identity.
    /// Two scans that differ only by pair are distinct. Uppercase hex, 40 characters.
    public static func full(pair: String, candles: [Candle]) -> String {
        var text = "pair:\(pair)\n"
        text.reserveCapacity(candles.count * 48)
        for bar in candles {
            let time = bar.time.map { String(Int($0)) } ?? ""
            text += "\(time),\(bar.bodyOpen),\(bar.bodyHigh),\(bar.bodyLow),\(bar.close)\n"
        }
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// True when a stored identity carries enough entropy to be a real identity.
    public static func isFullIdentity(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy { $0.isHexDigit }
    }
}

/// Declarative veto rows. The engine side stays on SIDE. This does not rescore.
public enum ExecutionGate {
    public struct Row: Equatable, Sendable {
        public var code: String
        public var detail: String

        public init(code: String, detail: String) {
            self.code = code
            self.detail = detail
        }
    }

    public static func rows(engineCall: String, score: Int, veto: String, driftPips: Double?) -> [Row] {
        var vetoRows = [
            Row(code: "VETO", detail: veto),
            Row(code: "SIDE", detail: engineCall),
            Row(code: "SCORE", detail: "\(score)"),
        ]
        if let driftPips {
            vetoRows.append(Row(code: "DRIFT", detail: String(format: "%.1f pips", driftPips)))
        }
        return vetoRows
    }
}

/// Hero verb for an armed beam. A veto is WAIT. Rail end is EXPIRED.
/// A cached scan is HISTORY: it can never produce an actionable verb.
public enum BeamContract {
    public static let historicalVerb = "HISTORICAL"

    public static func verb(cabinetSide: String, elapsedMs: Double, vetoed: Bool) -> String {
        if vetoed { return "WAIT" }
        switch cabinetSide {
        case "HIGH":
            return elapsedMs <= Timing.liveMs ? "TAP HIGH" : "EXPIRED"
        case "LOW":
            return elapsedMs <= Timing.liveMs ? "TAP LOW" : "EXPIRED"
        default:
            return "WAIT"
        }
    }

    public static func verb(cabinetSide: String, elapsedMs: Double, vetoed: Bool, historical: Bool) -> String {
        if historical { return vetoed ? "WAIT" : historicalVerb }
        return verb(cabinetSide: cabinetSide, elapsedMs: elapsedMs, vetoed: vetoed)
    }

    public static func remainingMs(elapsedMs: Double) -> Double {
        max(0, Timing.liveMs - elapsedMs)
    }

    public static func remainingMs(elapsedMs: Double, historical: Bool) -> Double {
        historical ? 0 : remainingMs(elapsedMs: elapsedMs)
    }
}

/// Feed integrity gate only. Never computes a side, wick %, pip floor, or ATR floor.
/// The JavaScriptCore strategy engine already owns spread.
public enum MechanicalLifters {
    /// `false` when the bar is incomplete or a real spread is missing → WAIT.
    /// `true` → allow the engine verdict through unchanged.
    public static func verifyLift(barComplete: Bool, spread: Double?) -> Bool {
        guard barComplete else { return false }
        guard let spread, spread.isFinite, spread > 0 else { return false }
        return true
    }
}

/// One HIT or MISS per armed scan. The key is the frozen fingerprint plus the arm id.
/// A second call for that same arm does not write again — including after CloudKit replay.
public struct OutcomeTerminal: Sendable {
    private var settled: Set<String> = []

    public init() {}

    public mutating func claim(scanHash: String, outcomeEventID: String) -> Bool {
        guard !outcomeEventID.isEmpty else { return false }
        let key = "\(scanHash)+\(outcomeEventID)"
        if settled.contains(key) { return false }
        settled.insert(key)
        return true
    }
}
