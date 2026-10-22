import Foundation

// MARK: - CTFeedError
// Unified error type for BinanceClient and KrakenClient.
// Never surfaces from the daemon loop — all callers catch and emit a
// [FEED_ERROR] log line, then continue to the next scan cycle.

public enum CTFeedError: Error, CustomStringConvertible {
    case unsupportedPair(String)
    case httpError(Int)
    case networkError(String)
    case insufficientBars(Int, required: Int)
    case decodingError(String)

    public var description: String {
        switch self {
        case .unsupportedPair(let p):
            return "Unsupported pair: \(p)"
        case .httpError(let code):
            return "HTTP \(code)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .insufficientBars(let got, let req):
            return "Insufficient bars: got \(got), need \(req)"
        case .decodingError(let ctx):
            return "Decoding error: \(ctx)"
        }
    }
}
