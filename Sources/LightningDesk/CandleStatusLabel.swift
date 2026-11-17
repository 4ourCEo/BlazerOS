import BlazerCore

/// Human-readable provenance for the bars currently shown in the desktop chart.
/// A recent bar cache is not itself proof that the broker quote feed is live.
enum CandleStatusLabel {
    static func make(feed: FeedStatus, isStale: Bool, count: Int) -> String {
        guard count > 0 else { return "No OANDA candles loaded" }
        if feed == .live && !isStale {
            return "Live OANDA candles · \(count) bars"
        }
        if isStale {
            return "Saved OANDA candles · stale · \(count) bars"
        }
        return "OANDA candles · last received · \(count) bars"
    }
}
