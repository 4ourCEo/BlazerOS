import Foundation

/// The scan path both desks call. Quotes stay on the device. The verdict comes from scan-engine.js.
public enum ScanKernel {
    /// In-process strategy SCAN. Incomplete bar or missing spread returns WAIT and does not invent a side.
    public static func fetch(
        asset: String,
        session: OandaSession,
        expiry: Int = Timing.expirySec,
        ring: CompletedBarRing = CompletedBarRing()
    ) async throws -> ScanEnvelope {
        guard StrategyEngine.isReady else {
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        let loaded: StrategyEngine.MarketInput?
        do {
            loaded = try await OandaClient.fetchBundle(asset: asset, session: session)
        } catch let error as ScanError {
            throw error
        } catch {
            throw ScanError.failed(error.localizedDescription)
        }
        guard var input = loaded else {
            throw ScanError.failed("Scan missed \(asset)")
        }
        return try await evaluate(input: &input, asset: asset, expiry: expiry, ring: ring)
    }

    /// Evaluate an already-frozen market input. Used by parity tests and replay.
    public static func evaluate(
        input: inout StrategyEngine.MarketInput,
        asset: String,
        expiry: Int = Timing.expirySec,
        ring: CompletedBarRing = CompletedBarRing()
    ) async throws -> ScanEnvelope {
        guard StrategyEngine.isReady else {
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        let completed = input.candles1m.map {
            CompletedBar(
                time: $0.time,
                open: $0.open,
                high: $0.high,
                low: $0.low,
                close: $0.close,
                complete: true
            )
        }
        await ring.loadCompleted(completed)
        let ringBars = await ring.fetchLatestBars(count: completed.count)
        input.candles1m = ringBars.map {
            StrategyEngine.CandlePayload(
                time: $0.time,
                open: $0.open,
                high: $0.high,
                low: $0.low,
                close: $0.close
            )
        }
        input.expirySeconds = expiry
        let barComplete = !ringBars.isEmpty && ringBars.allSatisfy(\.complete)
        let realSpread: Double? = input.spread.isFinite && input.spread > 0 ? input.spread : nil
        if !MechanicalLifters.verifyLift(barComplete: barComplete, spread: realSpread) {
            let frozen = ringBars.map {
                Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
            }
            return ScanEnvelope(
                signal: EngineSignal(
                    asset: asset,
                    cabinetSide: "WAIT",
                    call: "WAIT",
                    why: "Feed incomplete.",
                    price: input.lastPrice,
                    entryPrice: input.lastPrice,
                    invalidation: nil,
                    confidence: 0,
                    asOfMs: Date().timeIntervalSince1970 * 1000,
                    printMs: nil,
                    source: input.source
                ),
                error: nil,
                candles: frozen,
                source: input.source,
                snapshotBars: frozen
            )
        }
        let result: StrategyEngine.EvaluateResult
        do {
            result = try await StrategyEngine.evaluate(input: input)
        } catch {
            throw ScanError.failed("SCAN ENGINE OFFLINE")
        }
        let frozen = input.candles1m.map {
            Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close)
        }
        return ScanEnvelope(
            signal: result.signal,
            error: nil,
            candles: result.candles,
            source: result.source ?? input.source,
            snapshotBars: frozen
        )
    }

    /// Freeze the JS result. Later brakes may set veto and drift. They must not change the call.
    public static func commit(
        from found: EngineSignal,
        bars snapshot: [Candle],
        scannedAt: Date = Date()
    ) -> ScanCommit {
        let fingerprint = ScanFingerprint.hex(candles: snapshot)
        return ScanCommit(
            asset: found.asset,
            engineCall: found.call,
            score: Int((found.opportunity ?? found.confidence ?? 0).rounded()),
            evidence: found.evidence ?? found.why,
            strike: found.entryPrice ?? found.price,
            fingerprint: fingerprint,
            candleCount: snapshot.count,
            candles: snapshot,
            scannedAt: scannedAt,
            veto: nil,
            driftPips: nil
        )
    }
}
