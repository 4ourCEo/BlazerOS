import Foundation

public enum DeskAction: String, Sendable {
    case tapHigh = "TAP HIGH"
    case tapLow = "TAP LOW"
    case wait = "WAIT"
    case skip = "SKIP"
    case expired = "EXPIRED"
}

public struct DeskRestraint: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var action: String

    public init(id: String, name: String, detail: String, action: String) {
        self.id = id
        self.name = name
        self.detail = detail
        self.action = action
    }
}

public struct EngineSignal: Decodable, Sendable {
    public var asset: String
    public var cabinetSide: String
    public var call: String
    public var why: String
    public var price: Double
    public var entryPrice: Double?
    public var invalidation: Double?
    public var confidence: Double?
    public var opportunity: Double?
    public var evidence: String?
    public var asOfMs: Double?
    public var printMs: Double?
    public var source: String?

    public init(
        asset: String,
        cabinetSide: String,
        call: String,
        why: String,
        price: Double,
        entryPrice: Double? = nil,
        invalidation: Double? = nil,
        confidence: Double? = nil,
        opportunity: Double? = nil,
        evidence: String? = nil,
        asOfMs: Double? = nil,
        printMs: Double? = nil,
        source: String? = nil
    ) {
        self.asset = asset
        self.cabinetSide = cabinetSide
        self.call = call
        self.why = why
        self.price = price
        self.entryPrice = entryPrice
        self.invalidation = invalidation
        self.confidence = confidence
        self.opportunity = opportunity
        self.evidence = evidence
        self.asOfMs = asOfMs
        self.printMs = printMs
        self.source = source
    }
}

public struct ScanEnvelope: Decodable, Sendable {
    public var signal: EngineSignal?
    public var error: String?
    public var candles: [Candle]?
    public var source: String?
    /// Completed bars actually passed to scan-engine.js. Chart refreshes must not replace these.
    public var snapshotBars: [Candle]?

    public init(
        signal: EngineSignal?,
        error: String?,
        candles: [Candle]?,
        source: String?,
        snapshotBars: [Candle]? = nil
    ) {
        self.signal = signal
        self.error = error
        self.candles = candles
        self.source = source
        self.snapshotBars = snapshotBars
    }
}

public struct Candle: Codable, Sendable, Equatable {
    public var time: Double?
    public var open: Double?
    public var high: Double?
    public var low: Double?
    public var close: Double

    public init(time: Double?, open: Double?, high: Double?, low: Double?, close: Double) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }

    public var bodyOpen: Double { open ?? close }
    public var bodyHigh: Double { high ?? max(bodyOpen, close) }
    public var bodyLow: Double { low ?? min(bodyOpen, close) }
    public var isUp: Bool { close >= bodyOpen }
}

public struct PairRow: Identifiable, Sendable {
    public var id: String { asset }
    public var asset: String
    public var side: String

    public init(asset: String, side: String) {
        self.asset = asset
        self.side = side
    }
}

public struct DeskTap: Codable, Sendable, Equatable {
    public var asset: String
    public var outcome: String

    public init(asset: String, outcome: String) {
        self.asset = asset
        self.outcome = outcome
    }
}

public struct PendingTap: Sendable, Equatable {
    public var asset: String
    public var side: String

    public init(asset: String, side: String) {
        self.asset = asset
        self.side = side
    }
}

public struct DeskPickSignal: Encodable, Sendable {
    public var asset: String
    public var cabinetSide: String
    public var confidence: Double
    public var asOfMs: Double?
    public var printMs: Double?

    public init(
        asset: String,
        cabinetSide: String,
        confidence: Double,
        asOfMs: Double? = nil,
        printMs: Double? = nil
    ) {
        self.asset = asset
        self.cabinetSide = cabinetSide
        self.confidence = confidence
        self.asOfMs = asOfMs
        self.printMs = printMs
    }
}

public struct QuoteEnvelope: Decodable, Sendable {
    public var lastPrice: Double?
    public var bid: Double?
    public var ask: Double?
    public var asOfMs: Double?
    public var source: String?
}

public struct PairHeatRow: Decodable, Sendable, Equatable {
    public var asset: String
    public var n: Int
    public var hits: Int
    public var misses: Int
    public var winRate: Double?
    public var breakEvenWinRate: Double
    public var verdict: String
}

public struct DeskPickEnvelope: Decodable, Sendable {
    public var asset: String?
    public var deskFact: String?
    public var heat: [PairHeatRow]?
}

public enum DeskURL {
    public static let demo = URL(string: "https://pocketoption.com/en/cabinet/demo-quick-high-low/")!

    /// LIVE pair name for search paste — exact `EUR/USD`.
    public static func handoffText(_ asset: String) -> String {
        asset
    }

    public static func feedLabel(_ source: String) -> String {
        switch source.lowercased() {
        case "ibkr":
            return "IBKR"
        case "oanda":
            return "OANDA"
        case "preview", "yahoo":
            return "Yahoo"
        default:
            return "LIVE FX"
        }
    }
}

public enum Assets {
    public static let watchlist = [
        "EUR/USD", "GBP/USD", "USD/JPY", "EUR/GBP", "AUD/USD", "USD/CAD",
    ]

    public static func symbolName(for asset: String) -> String {
        switch asset {
        case "EUR/USD", "EUR/GBP":
            return "eurosign"
        case "GBP/USD":
            return "sterlingsign"
        case "USD/JPY":
            return "yensign"
        case "AUD/USD":
            return "dollarsign"
        case "USD/CAD":
            return "dollarsign"
        default:
            return "coloncurrencysign"
        }
    }
}

public enum Timing {
    public static let pairHoldNs: UInt64 = 1_100_000_000
    /// 8s linear TAP HIGH/LOW beam → EXPIRED. Not quote freshness.
    public static let liveMs: Double = 8000
    /// Native quote pump cadence. Freshness is derived from this.
    public static let quotePollMs: Double = 750
    /// Wall-clock age since last successful quote poll.
    /// `quotePollMs × quoteStalePolls` ≈ 8000. Separate from `liveMs`.
    public static let quoteStalePolls: Int = 11
    public static var quoteStaleMs: Double { quotePollMs * Double(quoteStalePolls) }
    /// Absurd broker print age — drop the row.
    public static let printStaleMs: Double = 20 * 60 * 1000
    public static let expirySec = 60
}

/// Header feed word. Desk verbs stay on the result. Sole feed-health authority.
public enum FeedStatus: String, Equatable, Sendable, CaseIterable {
    case connecting = "CONNECTING"
    case live = "LIVE"
    case stale = "STALE"
    case disconnected = "DISCONNECTED"
    case error = "ERROR"
}

/// One authoritative freshness check for live bid/ask. Never invents a tap side.
///
/// LIVE is driven by wall-clock since the last successful poll.
/// OANDA `asOfMs` alone is not enough — a quiet market can leave the broker
/// timestamp unchanged for longer than `quoteStaleMs`.
public enum QuoteFreshness {
    public static func ageMs(asOfMs: Double, nowMs: Double) -> Double {
        max(0, nowMs - asOfMs)
    }

    /// Bid/ask finite, ask > bid, positive spread, and broker print not absurdly old.
    public static func isActionable(
        bid: Double,
        ask: Double,
        asOfMs: Double,
        nowMs: Double = Date().timeIntervalSince1970 * 1000
    ) -> Bool {
        guard bid.isFinite, ask.isFinite, ask > bid else { return false }
        let spread = ask - bid
        guard spread.isFinite, spread > 0 else { return false }
        return ageMs(asOfMs: asOfMs, nowMs: nowMs) <= Timing.printStaleMs
    }

    /// Wall-clock poll freshness — the authoritative LIVE / STALE gate.
    public static func isPollFresh(lastFreshPollAt: Date?, now: Date = Date()) -> Bool {
        guard let lastFreshPollAt else { return false }
        return now.timeIntervalSince(lastFreshPollAt) * 1000 <= Timing.quoteStaleMs
    }
}

public enum PriceFormat {
    public static func px(_ price: Double) -> String {
        price >= 20 ? String(format: "%.3f", price) : String(format: "%.5f", price)
    }
}

public struct LiveQuote: Sendable, Equatable {
    public var asset: String
    public var bid: Double
    public var ask: Double
    public var mid: Double
    public var asOfMs: Double
    public var source: String

    public init(asset: String, bid: Double, ask: Double, mid: Double, asOfMs: Double, source: String) {
        self.asset = asset
        self.bid = bid
        self.ask = ask
        self.mid = mid
        self.asOfMs = asOfMs
        self.source = source
    }
}

extension QuoteFreshness {
    /// Valid bid/ask and not an absurdly old broker print. Poll LIVE uses `isPollFresh`.
    public static func isFresh(_ quote: LiveQuote?, now: Date = Date()) -> Bool {
        guard let quote else { return false }
        return isActionable(
            bid: quote.bid,
            ask: quote.ask,
            asOfMs: quote.asOfMs,
            nowMs: now.timeIntervalSince1970 * 1000
        )
    }

    /// Fresh enough for slippage / SCAN when the last successful poll is recent.
    public static func isLiveQuote(_ quote: LiveQuote?, lastFreshPollAt: Date?, now: Date = Date()) -> Bool {
        guard isFresh(quote, now: now), isPollFresh(lastFreshPollAt: lastFreshPollAt, now: now) else {
            return false
        }
        return true
    }
}
