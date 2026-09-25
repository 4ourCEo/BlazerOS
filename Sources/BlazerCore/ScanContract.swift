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
    public let score: Int
    public let evidence: String
    public let strike: Double
    public let fingerprint: String
    public let candleCount: Int
    public let candles: [Candle]
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
        candleCount: Int,
        candles: [Candle],
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
        self.candleCount = candleCount
        self.candles = candles
        self.scannedAt = scannedAt
        self.veto = veto
        self.driftPips = driftPips
    }
}

public enum ScanFingerprint {
    /// Stable fingerprint of the completed bars passed to scan-engine.js.
    /// Same bars → same hex. Not a secret. First 4 bytes of SHA-1, uppercase.
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
public enum BeamContract {
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

    public static func remainingMs(elapsedMs: Double) -> Double {
        max(0, Timing.liveMs - elapsedMs)
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
