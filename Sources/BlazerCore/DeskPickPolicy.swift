import Foundation

/// The Swift side of engine selection. It may only preserve a decline; it may never
/// turn an unavailable, stale, or silent engine pick into a directional one.
public enum DeskPickPolicy {
    public static let unavailableWhy = "No actionable engine pick"

    public static func unavailable(
        asset: String,
        price: Double,
        asOfMs: Double?,
        source: String?
    ) -> EngineSignal {
        EngineSignal(
            asset: asset,
            cabinetSide: "WAIT",
            call: "WAIT",
            why: unavailableWhy,
            price: price,
            entryPrice: price,
            invalidation: nil,
            confidence: 0,
            asOfMs: asOfMs,
            source: source
        )
    }

    /// A WAIT signal that carries only presentation context from the engine's base signal.
    public static func unavailable(basedOn base: EngineSignal) -> EngineSignal {
        unavailable(
            asset: base.asset,
            price: base.entryPrice ?? base.price,
            asOfMs: base.asOfMs,
            source: base.source
        )
    }

    /// True when a signal may be shown as TAP HIGH / TAP LOW.
    public static func isActionable(_ signal: EngineSignal, now: Date = Date()) -> Bool {
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return false }
        guard let asOfMs = signal.asOfMs, asOfMs.isFinite else { return false }
        let ageMs = now.timeIntervalSince1970 * 1000 - asOfMs
        return ageMs >= -1000 && ageMs <= EntryQuality.maxAgeSeconds * 1000
    }
}

/// A saved scan is history. It can be reviewed, but it can never keep rendering a live
/// TAP instruction after the 8-second beam has closed.
public enum SavedScanPresentation {
    public static let historicalWord = "HISTORICAL"

    /// Word to show for a journal row or widget. A confirmed outcome always wins.
    public static func word(
        outcome: String?,
        verb: String,
        scannedAt: Date,
        now: Date = Date()
    ) -> String {
        if let outcome, !outcome.isEmpty { return outcome }
        let ageMs = max(0, now.timeIntervalSince(scannedAt) * 1000)
        return ageMs > Timing.liveMs ? historicalWord : verb
    }

    /// True only while the saved instruction is still inside the live beam.
    public static func isLive(
        outcome: String?,
        scannedAt: Date,
        now: Date = Date()
    ) -> Bool {
        guard outcome == nil || outcome?.isEmpty == true else { return false }
        return now.timeIntervalSince(scannedAt) * 1000 <= Timing.liveMs
    }
}
