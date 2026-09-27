import Foundation
import JavaScriptCore

public enum ScanError: LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

/// Hosts the bundled scan-engine.js in JavaScriptCore.
/// The script is the strategy. This bridge does not reimplement RSI/EMA in Swift.
/// One reusable JSContext. Evaluate off the main thread; never invents a tap side.
public enum StrategyEngine {
    private static let lock = NSLock()
    private static let jsQueue = DispatchQueue(label: "com.blazer.core.scan-bridge", qos: .userInitiated)
    nonisolated(unsafe) private static var context: JSContext?
    nonisolated(unsafe) private static var loadError: String?
    /// Exact JS exception for diagnostics only — desk why stays "SCAN ENGINE OFFLINE".
    nonisolated(unsafe) private static var lastJsException: String?

    public static var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return context != nil
    }

    public static var offlineReason: String? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return context == nil ? (loadError ?? "Scan bundle missing") : nil
    }

    public static var dtcException: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastJsException
    }

    /// Exact script the bridge evaluates. Both apps hash this for the parity seal.
    public static func bundleSource() -> String? {
        loadBundleSource()
    }

    public struct MarketInput: Encodable, Sendable {
        public var asset: String
        public var source: String
        public var candles1m: [CandlePayload]
        public var candles5m: [CandlePayload]
        public var lastPrice: Double
        public var bid: Double
        public var ask: Double
        public var spread: Double
        public var expirySeconds: Int

        public init(
            asset: String,
            source: String,
            candles1m: [CandlePayload],
            candles5m: [CandlePayload],
            lastPrice: Double,
            bid: Double,
            ask: Double,
            spread: Double,
            expirySeconds: Int
        ) {
            self.asset = asset
            self.source = source
            self.candles1m = candles1m
            self.candles5m = candles5m
            self.lastPrice = lastPrice
            self.bid = bid
            self.ask = ask
            self.spread = spread
            self.expirySeconds = expirySeconds
        }
    }

    public struct CandlePayload: Encodable, Sendable, Equatable {
        public var time: Double
        public var open: Double
        public var high: Double
        public var low: Double
        public var close: Double

        public init(time: Double, open: Double, high: Double, low: Double, close: Double) {
            self.time = time
            self.open = open
            self.high = high
            self.low = low
            self.close = close
        }
    }

    public struct EvaluateResult: Decodable, Sendable {
        public var signal: EngineSignal
        public var candles: [Candle]?
        public var source: String?
    }

    /// Tiny completed-bar fixture shared with launch preflight.
    public static func smokeFixtureInput() -> MarketInput {
        var candles: [CandlePayload] = []
        var price = 1.12
        let base = Date().timeIntervalSince1970 * 1000
        for i in 0..<52 {
            let open = price
            let close = price - 0.00035
            candles.append(
                CandlePayload(
                    time: base - Double(55 - i) * 60_000,
                    open: open,
                    high: max(open, close) + 0.00005,
                    low: min(open, close) - 0.0001,
                    close: close
                )
            )
            price = close
        }
        let last = candles.last!.close
        return MarketInput(
            asset: "EUR/USD",
            source: "preview",
            candles1m: candles,
            candles5m: candles,
            lastPrice: last,
            bid: last,
            ask: last + 0.00012,
            spread: 0.00012,
            expirySeconds: Timing.expirySec
        )
    }

    /// Mac launch name. Same fixture load as `preflight`.
    public static func preflightEcu() async -> (ok: Bool, detail: String?) {
        await preflight()
    }

    /// Load bundle + evaluate fixture off the main actor.
    public static func preflight() async -> (ok: Bool, detail: String?) {
        await withCheckedContinuation { cont in
            jsQueue.async {
                lock.lock()
                context = nil
                loadError = nil
                lastJsException = nil
                ensureLoadedLocked()
                guard context != nil else {
                    let detail = loadError ?? "SCAN ENGINE OFFLINE"
                    lastJsException = detail
                    lock.unlock()
                    cont.resume(returning: (false, detail))
                    return
                }
                lock.unlock()
                do {
                    let result = try evaluateSync(input: smokeFixtureInput())
                    let side = result.signal.cabinetSide
                    if side == "HIGH" || side == "LOW" || side == "WAIT" {
                        cont.resume(returning: (true, nil))
                    } else {
                        cont.resume(returning: (false, "Fixture returned non-verdict"))
                    }
                } catch {
                    let message = error.localizedDescription
                    lock.lock()
                    lastJsException = message
                    lock.unlock()
                    cont.resume(returning: (false, message))
                }
            }
        }
    }

    public static func evaluate(input: MarketInput) async throws -> EvaluateResult {
        try await withCheckedThrowingContinuation { cont in
            jsQueue.async {
                do {
                    cont.resume(returning: try evaluateSync(input: input))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public static func pickDesk(
        signals: [EngineSignal],
        trades: [DeskTap],
        payoutPercent: Double,
        preferAsset: String? = nil,
        nowMs: Double = Date().timeIntervalSince1970 * 1000
    ) async throws -> DeskPickEnvelope {
        try await withCheckedThrowingContinuation { cont in
            jsQueue.async {
                do {
                    cont.resume(
                        returning: try pickDeskSync(
                            signals: signals,
                            trades: trades,
                            payoutPercent: payoutPercent,
                            preferAsset: preferAsset,
                            nowMs: nowMs
                        )
                    )
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public struct SlippageGateResult: Decodable, Sendable, Equatable {
        public var veto: Bool
        public var adverseDriftPips: Double
        public var thresholdPips: Double
    }

    /// Calls the bundled JS gate. Nil when the engine is offline — no Swift copy of the formula.
    public static func slippageGate(
        asset: String,
        side: String,
        strike: Double,
        bid: Double,
        ask: Double
    ) -> SlippageGateResult? {
        struct Body: Encodable {
            var asset: String
            var side: String
            var strike: Double
            var bid: Double
            var ask: Double
        }
        let raw: String
        do {
            raw = try encode(Body(asset: asset, side: side, strike: strike, bid: bid, ask: ask))
        } catch {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard let context,
            let fn = context.objectForKeyedSubscript("BlazerScan")?
                .objectForKeyedSubscript("slippageGateJson"),
            fn.isObject
        else {
            return nil
        }
        context.exception = nil
        guard let value = fn.call(withArguments: [raw]),
            let json = value.toString(),
            !value.isUndefined,
            !value.isNull,
            context.exception == nil,
            let data = json.data(using: .utf8),
            let parsed = try? JSONDecoder().decode(SlippageGateResult.self, from: data)
        else {
            context.exception = nil
            return nil
        }
        return parsed
    }

    private static func evaluateSync(input: MarketInput) throws -> EvaluateResult {
        let raw = try encode(input)
        let json = try callJson(function: "evaluatePairJson", argument: raw)
        return try decode(EvaluateResult.self, from: json)
    }

    private static func pickDeskSync(
        signals: [EngineSignal],
        trades: [DeskTap],
        payoutPercent: Double,
        preferAsset: String?,
        nowMs: Double
    ) throws -> DeskPickEnvelope {
        struct PickBody: Encodable {
            var signals: [EngineSignalPayload]
            var trades: [DeskTap]
            var payoutPercent: Double
            var preferAsset: String?
            var nowMs: Double
        }
        struct EngineSignalPayload: Encodable {
            var asset: String
            var side: String
            var cabinetSide: String
            var call: String
            var confidence: Double
            var price: Double
            var asOfMs: Double?
            var printMs: Double?
            var source: String?
            var why: String
        }
        let body = PickBody(
            signals: signals.map {
                EngineSignalPayload(
                    asset: $0.asset,
                    side: sideFromCabinet($0.cabinetSide),
                    cabinetSide: $0.cabinetSide,
                    call: $0.call,
                    confidence: $0.confidence ?? 0,
                    price: $0.price,
                    asOfMs: $0.asOfMs,
                    printMs: $0.printMs,
                    source: $0.source,
                    why: $0.why
                )
            },
            trades: trades,
            payoutPercent: payoutPercent,
            preferAsset: preferAsset,
            nowMs: nowMs
        )
        let raw = try encode(body)
        let json = try callJson(function: "pickDeskJson", argument: raw)
        return try decode(DeskPickEnvelope.self, from: json)
    }

    private static func sideFromCabinet(_ cabinet: String) -> String {
        switch cabinet {
        case "HIGH":
            return "CALL"
        case "LOW":
            return "PUT"
        default:
            return "WAIT"
        }
    }

    private static func callJson(function: String, argument: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard let context else {
            let detail = loadError ?? "SCAN ENGINE OFFLINE"
            lastJsException = detail
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        guard let fn = context.objectForKeyedSubscript("BlazerScan")?
            .objectForKeyedSubscript(function),
            fn.isObject
        else {
            lastJsException = "Scan bridge missing \(function)"
            Self.context = nil
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        context.exception = nil
        guard let value = fn.call(withArguments: [argument]),
            let json = value.toString(),
            !value.isUndefined,
            !value.isNull
        else {
            let message = context.exception?.toString() ?? "Scan bridge returned empty"
            context.exception = nil
            lastJsException = message
            Self.context = nil
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        if let exception = context.exception {
            let message = exception.toString() ?? "Scan bridge exception"
            context.exception = nil
            lastJsException = message
            Self.context = nil
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        lastJsException = nil
        return json
    }

    private static func ensureLoadedLocked() {
        if context != nil { return }
        loadError = nil
        guard let source = loadBundleSource() else {
            loadError = "scan-engine.js not found in package resources"
            lastJsException = loadError
            return
        }
        guard let next = JSContext() else {
            loadError = "JavaScriptCore unavailable"
            lastJsException = loadError
            return
        }
        next.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "JavaScriptCore exception"
            loadError = message
            lastJsException = message
        }
        next.evaluateScript(source)
        if let exception = next.exception {
            loadError = exception.toString() ?? "Scan bundle failed to evaluate"
            lastJsException = loadError
            next.exception = nil
            return
        }
        guard let bridge = next.objectForKeyedSubscript("BlazerScan"),
            bridge.isObject,
            bridge.objectForKeyedSubscript("evaluatePairJson").isObject,
            bridge.objectForKeyedSubscript("pickDeskJson").isObject,
            bridge.objectForKeyedSubscript("slippageGateJson").isObject
        else {
            loadError = "BlazerScan bridge exports missing"
            lastJsException = loadError
            return
        }
        context = next
        loadError = nil
        lastJsException = nil
    }

    private static func loadBundleSource() -> String? {
        // The host app's Resources copy wins so a freshly bundled script is what SCAN runs.
        // The package bundle is the fallback for the parity tool and for iOS.
        if let source = readScript(in: Bundle.main) {
            return source
        }
        return readScript(in: Bundle.module)
    }

    private static func readScript(in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "scan-engine", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8),
            !source.isEmpty
        else {
            return nil
        }
        return source
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ScanError.failed("Could not encode scan payload")
        }
        return raw
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            lock.lock()
            lastJsException = "Could not decode scan result"
            context = nil
            lock.unlock()
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            lock.lock()
            lastJsException = error.localizedDescription
            context = nil
            lock.unlock()
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
    }
}
