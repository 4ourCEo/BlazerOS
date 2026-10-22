import CryptoKit
import Foundation

/// The complete frozen market input that produced one scan.
///
/// The short `ScanFingerprint.hex` is a display label. Storage and deduplication must use
/// this identity instead: the engine evaluates both timeframes plus quote/spread and expiry,
/// so hashing only the M1 bars lets materially different decisions share a fingerprint.
public struct ScanInputSnapshot: Sendable, Equatable, Codable {
    public var pair: String
    public var m1: [Candle]
    public var m5: [Candle]
    public var bid: Double?
    public var ask: Double?
    public var spread: Double?
    public var expirySeconds: Int
    public var engineSHA: String
    public var policy: String

    public init(
        pair: String,
        m1: [Candle],
        m5: [Candle] = [],
        bid: Double? = nil,
        ask: Double? = nil,
        spread: Double? = nil,
        expirySeconds: Int = Timing.expirySec,
        engineSHA: String = EngineIdentity.loadedSHA1() ?? "unverified",
        policy: String = "baseline"
    ) {
        self.pair = pair
        self.m1 = m1
        self.m5 = m5
        self.bid = bid
        self.ask = ask
        self.spread = spread
        self.expirySeconds = expirySeconds
        self.engineSHA = engineSHA
        self.policy = policy
    }

    /// Full storage identity. Uppercase hex, 40 characters (SHA-1), same shape as the
    /// legacy `ScanFingerprint.full` identity so existing validators keep working.
    public var identity: String {
        let digest = Insecure.SHA1.hash(data: Data(canonicalText.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    /// Versioned, order-stable canonical text. Every input the engine can read is included.
    public var canonicalText: String {
        var text = "scan-input-v2\n"
        text += "pair:\(pair)\n"
        text += "engine:\(engineSHA)\n"
        text += "policy:\(policy)\n"
        text += "expiry:\(expirySeconds)\n"
        text += "bid:\(Self.number(bid))\n"
        text += "ask:\(Self.number(ask))\n"
        text += "spread:\(Self.number(spread))\n"
        text += "m1:\(m1.count)\n"
        for bar in m1 { text += Self.line(bar) }
        text += "m5:\(m5.count)\n"
        for bar in m5 { text += Self.line(bar) }
        return text
    }

    private static func line(_ bar: Candle) -> String {
        let time = bar.time.map { String(Int64($0.rounded())) } ?? ""
        return "\(time),\(number(bar.open)),\(number(bar.high)),\(number(bar.low)),\(number(bar.close))\n"
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.10g", value)
    }
}
