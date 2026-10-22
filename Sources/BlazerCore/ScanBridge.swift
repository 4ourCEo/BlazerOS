import Foundation
import JavaScriptCore

public enum ScanError: LocalizedError, Equatable {
    case failed(String)
    /// The engine produced output that violates the wire contract. Distinct from `.failed`:
    /// the engine is reachable, but its answer cannot be trusted as-is.
    case contract(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        case .contract(let message):
            return "SCAN CONTRACT: \(message)"
        }
    }
}

/// Hosts the bundled scan-engine.js in JavaScriptCore.
/// The script is the strategy. This bridge does not reimplement RSI/EMA in Swift.
/// One reusable JSContext. Evaluate off the main thread; never invents a tap side.
public enum StrategyEngine {
    /// Lifecycle of the bundled engine. Only `ready` has executed a verdict.
    public enum Health: Sendable, Equatable {
        case unloaded
        /// Source hash matches the pin and the bridge exports are present.
        case loaded(sha: String)
        /// `loaded` plus a successful smoke-fixture verdict.
        case ready(sha: String)
        /// Refused: missing source, hash mismatch, compile failure, or missing exports.
        case failed(reason: String)

        public var sha: String? {
            switch self {
            case .loaded(let sha), .ready(let sha): return sha
            case .unloaded, .failed: return nil
            }
        }

        public var isUsable: Bool {
            switch self {
            case .loaded, .ready: return true
            case .unloaded, .failed: return false
            }
        }

        public var isVerifiedAndProven: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    private static let lock = NSRecursiveLock()
    private static let jsQueue = DispatchQueue(label: "com.blazer.core.scan-bridge", qos: .userInitiated)
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    nonisolated(unsafe) private static var context: JSContext?
    nonisolated(unsafe) private static var loadError: String?
    /// Exact JS exception for diagnostics only — desk why stays "SCAN ENGINE OFFLINE".
    nonisolated(unsafe) private static var lastJsException: String?
    nonisolated(unsafe) private static var health: Health = .unloaded

    public static var engineHealth: Health {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return health
    }

    /// Hash of the loaded engine without forcing a load. Nil when nothing is loaded.
    public static var knownSHA: String? {
        lock.lock()
        defer { lock.unlock() }
        return health.sha
    }

    public static var isReady: Bool {
        engineHealth.isUsable
    }

    /// True only after `boot()` has executed the smoke fixture successfully.
    public static var isPreflighted: Bool {
        engineHealth.isVerifiedAndProven
    }

    public static var offlineReason: String? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return health.isUsable ? nil : (loadError ?? "Scan bundle missing")
    }

    public static var dtcException: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastJsException
    }

    /// Which bundle supplied the script that is actually loaded ("main-bundle" / "package-bundle").
    public static var loadedOrigin: String? {
        lock.lock()
        defer { lock.unlock() }
        return loadedOriginLocked
    }
    nonisolated(unsafe) private static var loadedOriginLocked: String?

    /// Exact script the bridge evaluates. Both apps hash this for the parity seal.
    public static func bundleSource() -> String? {
        loadBundleSource()
    }

    /// True when the bundled research control artifact still matches `controlSHA1`.
    public static var controlArtifactMatchesPin: Bool {
        guard let url = Bundle.module.url(forResource: "scan-engine-control", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return EngineIdentity.sha1Hex(of: source) == controlSHA1
    }

    public struct MarketInput: Codable, Sendable {
        public var asset: String
        public var source: String
        public var candles1m: [CandlePayload]
        public var candles5m: [CandlePayload]
        public var lastPrice: Double
        public var bid: Double
        public var ask: Double
        public var spread: Double
        public var expirySeconds: Int
        public var quoteAsOfMs: Double?
        public var evaluatedAtMs: Double?
        public var policy: ScanPolicy?

        public init(
            asset: String,
            source: String,
            candles1m: [CandlePayload],
            candles5m: [CandlePayload],
            lastPrice: Double,
            bid: Double,
            ask: Double,
            spread: Double,
            expirySeconds: Int,
            quoteAsOfMs: Double? = nil,
            evaluatedAtMs: Double? = nil,
            policy: ScanPolicy? = nil
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
            self.quoteAsOfMs = quoteAsOfMs
            self.evaluatedAtMs = evaluatedAtMs
            self.policy = policy
        }
    }

    public struct CandlePayload: Codable, Sendable, Equatable {
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

    /// Mac launch name. Same boot sequence as `boot()`.
    public static func preflightEcu() async -> (ok: Bool, detail: String?) {
        await boot()
    }

    /// Load, verify the pin, and prove the engine can produce a verdict.
    /// Safe to call repeatedly; each call reloads so a failed engine can recover after a fix.
    @discardableResult
    public static func boot() async -> (ok: Bool, detail: String?) {
        await withCheckedContinuation { cont in
            jsQueue.async {
                lock.lock()
                // Never tear down a healthy context: boot can race with an in-flight scan,
                // and reloading would turn a working engine into a transient offline state.
                if context == nil || !health.isUsable {
                    reloadLocked()
                    ensureLoadedLocked()
                }
                guard context != nil else {
                    let detail = loadError ?? "SCAN ENGINE OFFLINE"
                    lastJsException = detail
                    lock.unlock()
                    cont.resume(returning: (false, detail))
                    return
                }
                do {
                    let result = try evaluateSync(input: smokeFixtureInput())
                    let side = result.signal.cabinetSide
                    guard side == "HIGH" || side == "LOW" || side == "WAIT" else {
                        let detail = "Fixture returned non-verdict: \(side)"
                        lastJsException = detail
                        health = .failed(reason: detail)
                        lock.unlock()
                        cont.resume(returning: (false, detail))
                        return
                    }
                    if case .loaded(let sha) = health {
                        health = .ready(sha: sha)
                    }
                    lock.unlock()
                    cont.resume(returning: (true, nil))
                } catch {
                    let message = error.localizedDescription
                    lastJsException = message
                    health = .failed(reason: message)
                    lock.unlock()
                    cont.resume(returning: (false, message))
                }
            }
        }
    }

    /// Kept for existing call sites; boot is the preflight.
    public static func preflight() async -> (ok: Bool, detail: String?) {
        await boot()
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

    /// Immutable pre-research control artifact. Only the research runner calls this path.
    public static let controlSHA1 = "1a1d264d44eec606ded991cb4814df953bc07b34"
    public static func evaluateControl(input: MarketInput) async throws -> EvaluateResult {
        try validateInput(input)
        return try await withCheckedThrowingContinuation { continuation in
            jsQueue.async {
                do {
                    guard let url = Bundle.module.url(forResource: "scan-engine-control", withExtension: "js"),
                          let source = try? String(contentsOf: url, encoding: .utf8),
                          EngineIdentity.sha1Hex(of: source) == controlSHA1,
                          let context = JSContext() else { throw ScanError.failed("Control artifact missing or changed") }
                    context.evaluateScript(source)
                    guard context.exception == nil,
                          let fn = context.objectForKeyedSubscript("BlazerScan")?.objectForKeyedSubscript("evaluatePairJson"),
                          let value = fn.call(withArguments: [try encode(input)]),
                          context.exception == nil, let json = value.toString(), let data = json.data(using: .utf8) else {
                        throw ScanError.failed("Control evaluation failed")
                    }
                    var result = try JSONDecoder().decode(EvaluateResult.self, from: data)
                    try validate(result: result, for: input)
                    result.signal.asOfMs = input.evaluatedAtMs
                    result.signal.policy = "control"
                    // The control artifact predates volatility features. Both research arms must be
                    // gated identically, so the shared feature block comes from the baseline engine
                    // for this input. It is an input descriptor, not a control-engine decision; if the
                    // baseline engine is unavailable the control arm records nil rather than failing.
                    result.signal.features = try? evaluateSync(input: input).signal.features
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
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
        /// Why the gate blocked, when it could not evaluate. `nil` on a real verdict.
        public var reason: String?

        public init(veto: Bool, adverseDriftPips: Double, thresholdPips: Double, reason: String? = nil) {
            self.veto = veto
            self.adverseDriftPips = adverseDriftPips
            self.thresholdPips = thresholdPips
            self.reason = reason
        }

        /// Fail closed. A gate that cannot evaluate must veto, never silently allow.
        public static func blocked(_ reason: String) -> SlippageGateResult {
            SlippageGateResult(veto: true, adverseDriftPips: 0, thresholdPips: 0, reason: reason)
        }
    }

    private struct SlippageGateInput: Encodable {
        let asset: String
        let side: String
        let strike: Double
        let bid: Double
        let ask: Double
    }

    /// Calls the bundled JS gate. Always returns a verdict: invalid input, a missing bridge,
    /// or a malformed answer all produce `veto: true` with a `reason`.
    public static func slippageGate(
        asset: String,
        side: String,
        strike: Double,
        bid: Double,
        ask: Double
    ) -> SlippageGateResult {
        guard strike.isFinite, bid.isFinite, ask.isFinite, bid > 0, ask >= bid else {
            return .blocked("Invalid quote")
        }
        let input = SlippageGateInput(asset: asset, side: side, strike: strike, bid: bid, ask: ask)
        guard let rawData = try? JSONEncoder().encode(input),
              let raw = String(data: rawData, encoding: .utf8) else {
            return .blocked("Gate input could not be encoded")
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard let context,
            let fn = context.objectForKeyedSubscript("BlazerScan")?
                .objectForKeyedSubscript("slippageGateJson"),
            fn.isObject
        else {
            let reason = loadError ?? "Gate offline"
            lastJsException = reason
            return .blocked(reason)
        }
        context.exception = nil
        guard let value = fn.call(withArguments: [raw]),
            let json = value.toString(),
            !value.isUndefined,
            !value.isNull,
            context.exception == nil,
            let data = json.data(using: .utf8),
            let parsed = try? decoder.decode(SlippageGateResult.self, from: data)
        else {
            let message = context.exception?.toString() ?? "Gate returned malformed result"
            context.exception = nil
            lastJsException = message
            return .blocked(message)
        }
        return parsed
    }

    private static func validateInput(_ input: MarketInput) throws {
        guard !input.asset.isEmpty else { throw ScanError.contract("empty asset") }
        guard input.bid.isFinite, input.ask.isFinite, input.bid > 0, input.ask >= input.bid else {
            throw ScanError.contract("invalid quote bid=\(input.bid) ask=\(input.ask)")
        }
        guard input.spread.isFinite, input.spread >= 0 else {
            throw ScanError.contract("invalid spread \(input.spread)")
        }
        guard input.lastPrice.isFinite, input.lastPrice > 0 else {
            throw ScanError.contract("invalid lastPrice \(input.lastPrice)")
        }
        try validateCandles(input.candles1m, label: "1m")
        try validateCandles(input.candles5m, label: "5m")
    }

    private static func validateCandles(_ candles: [CandlePayload], label: String) throws {
        guard !candles.isEmpty else { throw ScanError.contract("no \(label) candles") }
        var previous: Double?
        for bar in candles {
            guard bar.time.isFinite, bar.open.isFinite, bar.high.isFinite,
                  bar.low.isFinite, bar.close.isFinite else {
                throw ScanError.contract("non-finite \(label) candle at \(bar.time)")
            }
            guard bar.high >= bar.low,
                  bar.high >= Swift.max(bar.open, bar.close),
                  bar.low <= Swift.min(bar.open, bar.close) else {
                throw ScanError.contract("inconsistent \(label) OHLC at \(bar.time)")
            }
            if let previous, bar.time <= previous {
                throw ScanError.contract("\(label) candles are not strictly increasing at \(bar.time)")
            }
            previous = bar.time
        }
    }

    private static func evaluateSync(input: MarketInput) throws -> EvaluateResult {
        try validateInput(input)
        let raw = try encode(input)
        let json = try callJson(function: "evaluatePairJson", argument: raw)
        let result = try decode(EvaluateResult.self, from: json)
        try validate(result: result, for: input)
        return result
    }

    /// Reject engine output that cannot be trusted. Contract violations are reported as
    /// `.contract`, never as "engine offline", and never tear down a healthy context.
    internal static func validate(result: EvaluateResult, for input: MarketInput) throws {
        let signal = result.signal

        guard ["HIGH", "LOW", "WAIT"].contains(signal.cabinetSide) else {
            throw ScanError.contract("unknown cabinetSide '\(signal.cabinetSide)'")
        }
        guard ["TAP HIGH", "TAP LOW", "WAIT"].contains(signal.call) else {
            throw ScanError.contract("unknown call '\(signal.call)'")
        }
        switch signal.cabinetSide {
        case "HIGH" where signal.call != "TAP HIGH":
            throw ScanError.contract("side HIGH paired with call '\(signal.call)'")
        case "LOW" where signal.call != "TAP LOW":
            throw ScanError.contract("side LOW paired with call '\(signal.call)'")
        case "WAIT" where signal.call != "WAIT":
            throw ScanError.contract("side WAIT paired with call '\(signal.call)'")
        default:
            break
        }

        guard signal.price.isFinite, signal.price > 0 else {
            throw ScanError.contract("non-finite or non-positive price \(signal.price)")
        }
        if let confidence = signal.confidence {
            guard confidence.isFinite, (0.0...100.0).contains(confidence) else {
                throw ScanError.contract("confidence \(confidence) outside 0...100")
            }
        }
        if let direction = signal.directionScore {
            guard direction.isFinite, (-0.001...100.001).contains(direction) else {
                throw ScanError.contract("directionScore \(direction) outside 0...100")
            }
        }
        if let strength = signal.strength {
            guard strength.isFinite, (-0.001...100.001).contains(strength) else {
                throw ScanError.contract("strength \(strength) outside 0...100")
            }
        }
        if let asOf = signal.asOfMs, !asOf.isFinite {
            throw ScanError.contract("non-finite asOfMs")
        }
        guard !signal.asset.isEmpty, signal.asset == input.asset else {
            throw ScanError.contract("engine returned asset '\(signal.asset)' for '\(input.asset)'")
        }
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
        guard let loaded = loadEngineSource() else {
            let reason = "scan-engine.js not found in any bundle"
            loadError = reason
            lastJsException = reason
            health = .failed(reason: reason)
            return
        }
        loadedOriginLocked = loaded.origin

        // Fail closed before the context is installed. The pin is compared here — the moment
        // the engine is about to be used — not only in a test that may never run.
        let outcome = loadOutcome(source: loaded.source, origin: loaded.origin)
        guard let next = outcome.context else {
            let reason = outcome.error ?? "engine rejected"
            loadError = reason
            lastJsException = reason
            health = outcome.health
            return
        }
        next.exceptionHandler = { _, exception in
            let message = exception?.toString() ?? "JavaScriptCore exception"
            lock.lock()
            loadError = message
            lastJsException = message
            lock.unlock()
        }
        context = next
        loadError = nil
        lastJsException = nil
        health = outcome.health
    }

    internal struct LoadOutcome {
        let health: Health
        let context: JSContext?
        let error: String?
    }

    /// Pure gate: verify the pin, compile, and confirm the bridge surface.
    /// Never mutates shared state, so tests can prove a tampered script is refused.
    internal static func loadOutcome(source: String, origin: String) -> LoadOutcome {
        switch EngineIdentity.verify(source: source) {
        case .mismatch(let got, let pinned):
            let reason = "engine hash mismatch: loaded \(got), pinned \(pinned) (from \(origin))"
            return LoadOutcome(health: .failed(reason: reason), context: nil, error: reason)
        case .unavailable:
            let reason = "engine source unavailable"
            return LoadOutcome(health: .failed(reason: reason), context: nil, error: reason)
        case .verified(let sha):
            guard let next = JSContext() else {
                let reason = "JavaScriptCore unavailable"
                return LoadOutcome(health: .failed(reason: reason), context: nil, error: reason)
            }
            next.evaluateScript(source)
            if let exception = next.exception {
                let reason = exception.toString() ?? "Scan bundle failed to evaluate"
                next.exception = nil
                return LoadOutcome(health: .failed(reason: reason), context: nil, error: reason)
            }
            guard let bridge = next.objectForKeyedSubscript("BlazerScan"),
                bridge.isObject,
                bridge.objectForKeyedSubscript("evaluatePairJson").isObject,
                bridge.objectForKeyedSubscript("pickDeskJson").isObject,
                bridge.objectForKeyedSubscript("slippageGateJson").isObject
            else {
                let reason = "BlazerScan bridge exports missing"
                return LoadOutcome(health: .failed(reason: reason), context: nil, error: reason)
            }
            return LoadOutcome(health: .loaded(sha: sha), context: next, error: nil)
        }
    }

    private static func reloadLocked() {
        context = nil
        loadError = nil
        health = .unloaded
    }

    private struct LoadedEngine {
        let source: String
        let origin: String
    }

    private static func loadEngineSource() -> LoadedEngine? {
        // The host app's Resources copy wins so a freshly bundled script is what SCAN runs.
        // The package bundle is the fallback for the parity tool and for iOS.
        if let source = readScript(in: Bundle.main) {
            return LoadedEngine(source: source, origin: "main-bundle")
        }
        if let source = readScript(in: Bundle.module) {
            return LoadedEngine(source: source, origin: "package-bundle")
        }
        return nil
    }

    private static func loadBundleSource() -> String? {
        loadEngineSource()?.source
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
        let data = try encoder.encode(value)
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ScanError.failed("Could not encode scan payload")
        }
        return raw
    }

    private static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw ScanError.contract("engine response was not UTF-8")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // A schema mismatch is a contract problem, not a dead engine. Keep the context:
            // tearing it down turns a diagnosable drift into a permanent "offline" state.
            let reason = "response did not match \(type): \(error.localizedDescription)"
            lock.lock()
            lastJsException = reason
            lock.unlock()
            throw ScanError.contract(reason)
        }
    }
}
