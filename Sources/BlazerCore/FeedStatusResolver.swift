import Foundation

/// One LIVE / STALE / ERROR decision. Views paint this. They do not invent a second live check.
public enum FeedStatusResolver {
    public static func resolve(
        marketOpen: Bool,
        sessionReady: Bool,
        transport: OandaTransport?,
        quote: LiveQuote?,
        lastFreshPollAt: Date?,
        now: Date = Date()
    ) -> FeedStatus {
        if !marketOpen {
            return .disconnected
        }
        if !sessionReady {
            return .error
        }
        switch transport {
        case nil:
            return .connecting
        case .missingToken, .unauthorized:
            return .error
        case .rateLimited, .timeout, .network:
            return lastFreshPollAt == nil ? .disconnected : .stale
        case .ok:
            if QuoteFreshness.isLiveQuote(quote, lastFreshPollAt: lastFreshPollAt, now: now) {
                return .live
            }
            // A completed successful response with no fresh usable quote is a
            // feed fault, not a connection still in progress. CONNECTING is
            // reserved for the interval before the first transport result.
            return lastFreshPollAt == nil ? .error : .stale
        }
    }
}
