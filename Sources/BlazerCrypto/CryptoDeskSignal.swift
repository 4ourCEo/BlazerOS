import BlazerCore
import Foundation

/// Adapter from the Swift crypto engine to the shared desk contracts.
///
/// The crypto engine is not the pinned JavaScript engine, so its identity is a version
/// string. Its score is already side-neutral conviction; it must never be shipped to the
/// ledger as a 0...1 fraction.
public enum CryptoDeskSignal {
    public static let engineIdentity = "crypto-engine-v1"
    public static let policy = "crypto-v1"

    /// Build the `EngineSignal` the desk freezes. All fields required by `EntryQuality`
    /// (evaluation time, ATR, quote) are populated here, not in the view layer.
    public static func make(
        asset: String,
        batch: CryptoCandleBatch,
        now: Date = Date()
    ) -> EngineSignal {
        let result = CryptoEngine.evaluate(batch: batch, asset: asset)
        let pip = CTAssets.pipScale(for: asset)
        let atrPrice = result.atrPips * pip
        // The crypto engine emits a magnitude (0…100+), not a centred directional score.
        // Map it onto the documented contract: direction 50 ± magnitude/2, strength = magnitude.
        // Clamping here keeps both fields inside 0…100 for every consumer and ledger row.
        let rawMagnitude = result.side == "HIGH"
            ? result.highScore
            : (result.side == "LOW" ? result.lowScore : 0)
        let magnitude = Double(min(100, max(0, rawMagnitude)))
        let directionScore: Double = result.side == "HIGH"
            ? 50 + magnitude / 2
            : (result.side == "LOW" ? 50 - magnitude / 2 : 50)
        let features = ScanFeatures(
            atr1m: atrPrice,
            atr5m: atrPrice,
            efficiency: 0,
            slopeATR: 0,
            spreadATR: atrPrice > 0 ? batch.spread / atrPrice : 0,
            rangeATR: 0,
            bodyATR: 0,
            upperWickShare: 0,
            lowerWickShare: 0,
            twoSidedSweep: false,
            sweep: nil,
            structureBreak: nil,
            regime: "crypto"
        )
        return EngineSignal(
            asset: asset,
            cabinetSide: result.side,
            call: result.side == "HIGH" ? "CALL" : (result.side == "LOW" ? "PUT" : "WAIT"),
            why: result.why,
            price: batch.mid.isFinite ? batch.mid : 0,
            entryPrice: batch.mid.isFinite ? batch.mid : 0,
            confidence: Double(result.conviction),
            opportunity: Double(result.conviction),
            evidence: result.evidence.joined(separator: " · "),
            asOfMs: now.timeIntervalSince1970 * 1000,
            printMs: now.timeIntervalSince1970 * 1000,
            source: "crypto:\(batch.source)",
            directionScore: directionScore,
            strength: magnitude,
            policy: policy,
            features: features
        )
    }

    /// Deterministic desk gates for crypto. These are ceilings, not edge claims.
    public static func veto(
        asset: String,
        batch: CryptoCandleBatch,
        signal: EngineSignal
    ) -> String? {
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return nil }
        if batch.source == "kraken-synthetic-spread" {
            return "Synthetic spread; no verified quote for entry"
        }
        let pip = CTAssets.pipScale(for: asset)
        let spreadPips = batch.spread / max(pip, .leastNonzeroMagnitude)
        if spreadPips > CTAssets.maxSpreadPips(for: asset) {
            return "Spread \(String(format: "%.1f", spreadPips))p above \(Int(CTAssets.maxSpreadPips(for: asset)))p ceiling"
        }
        guard let atr = signal.features?.atr1m, atr > 0 else {
            return "ATR unavailable"
        }
        let atrPips = atr / max(pip, .leastNonzeroMagnitude)
        if atrPips > CTAssets.maxATRPips(for: asset) {
            return "ATR \(String(format: "%.0f", atrPips))p above \(Int(CTAssets.maxATRPips(for: asset)))p ceiling"
        }
        guard let confidence = signal.confidence, confidence.isFinite, (0...100).contains(confidence),
              CryptoCandle.isValidQuote(bid: batch.bid, ask: batch.ask), atr.isFinite else {
            return "Invalid market data"
        }
        let conviction = Int(confidence.rounded())
        if conviction < CTAssets.minConviction {
            return "Conviction \(conviction) below \(CTAssets.minConviction) gate"
        }
        return nil
    }
}
