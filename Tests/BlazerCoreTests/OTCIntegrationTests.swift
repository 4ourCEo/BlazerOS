import BlazerCore
import BlazerCrypto
import Foundation
import Testing
@testable import LightningDesk

// MARK: - Integration fixtures

/// Emits deterministic, already-normalized research observations. It never opens a socket and it
/// has no order method, so the integration tests stay hermetic.
private struct ScriptedOTCProvider: ShadowMarketObservationProvider {
    let sourceIdentity = ShadowDataSourceIdentity(
        providerID: "test.otc.research", displayName: "Test OTC", venueID: "otc",
        directBrokerConnection: false)
    let observations: [ShadowMarketObservation]
    let keepsStreamOpen: Bool

    func instruments() async throws -> [ShadowInstrumentAvailability] {
        [ShadowInstrumentAvailability(
            identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
            isOpen: true, payoutPercent: 88)]
    }

    func candles(for identity: ShadowMarketIdentity, intervalSeconds: Int,
                 limit: Int) async throws -> [ShadowCandle] { [] }

    func updates(for identities: [ShadowMarketIdentity]) async throws
        -> AsyncThrowingStream<ShadowProviderUpdate, any Error> {
        let observations = self.observations
        let keepsStreamOpen = self.keepsStreamOpen
        return AsyncThrowingStream { continuation in
            continuation.yield(.connection(.live, reason: nil))
            for observation in observations {
                continuation.yield(.observation(observation))
            }
            if !keepsStreamOpen { continuation.finish() }
        }
    }
}

private func researchObservation(price: Double = 1.10203,
                                 at date: Date = Date()) -> ShadowMarketObservation {
    ShadowMarketObservation(
        source: ShadowDataSourceIdentity(providerID: "test.otc.research",
            displayName: "Test OTC", venueID: "otc", directBrokerConnection: false),
        identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
        quote: ShadowQuote(price: price),
        providerTimestamp: ShadowProviderTimestamp(
            rawUnixSeconds: date.timeIntervalSince1970),
        receivedAt: date, connectionState: .live,
        verification: .unverifiedVendorData,
        provenance: "hermetic integration fixture; not live evidence")
}

@MainActor
private func researchModel(
    root: URL,
    marketData: any DeskMarketDataServing,
    observations: [ShadowMarketObservation],
    keepsStreamOpen: Bool,
    candleCache: CandleCache = CandleCache()
) -> LightningDeskModel {
    let otcRoot = root.appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("otc-validation", isDirectory: true)
    let service = LiveOTCResearchService(
        root: otcRoot,
        provider: ScriptedOTCProvider(observations: observations,
                                      keepsStreamOpen: keepsStreamOpen))
    let model = LightningDeskModel(
        storageRoot: root,
        marketData: marketData,
        candleCache: candleCache,
        otcArchive: service,
        otcResearchServiceFactory: { _ in service })
    model.otcCredentialVault = InMemoryKeychainVault()
    model.saveOTChartsAPIKey("otc_integration_test_key")
    return model
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-otc-integration-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool,
                       iterations: Int = 400) async throws {
    var count = 0
    while !condition() && count < iterations {
        try await Task.sleep(for: .milliseconds(5))
        count += 1
    }
}

// MARK: - Scan scheduling + research capture

private actor SuspendedMarketDataService: DeskMarketDataServing {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false

    func waitForRelease() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func scan(market: DeskMarket, asset: String, session: OandaSession?) async throws -> MarketScanSnapshot {
        await waitForRelease()
        let candle = Candle(time: 1_000, open: 100, high: 101, low: 99, close: 100)
        return MarketScanSnapshot(
            signal: EngineSignal(asset: asset, cabinetSide: "WAIT", call: "WAIT",
                why: "test", price: 100),
            candles: [candle], m5Candles: [], bid: 99, ask: 101, spread: 2,
            expirySeconds: 60, engineSHA: "test", policy: "test", source: "test", veto: nil)
    }

    func quotes(market: DeskMarket, assets: [String],
                session: OandaSession?) async -> MarketQuoteResult {
        MarketQuoteResult(quotes: [], status: .network)
    }

    func candles(market: DeskMarket, asset: String, session: OandaSession?,
                 count: Int) async -> [Candle] { [] }
}

@MainActor
@Test func suspendedScanAndOTCCaptureProgressIndependently() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let market = SuspendedMarketDataService()
    let model = researchModel(root: root, marketData: market,
        observations: [researchObservation()], keepsStreamOpen: true)
    model.marketMode = .crypto

    let scan = Task { @MainActor in await model.scanCrypto(asset: "BTC/USDT") }
    while await !market.waiting { await Task.yield() }
    #expect(model.scanning)

    model.startOTCResearchCapture(duration: 60)
    try await waitUntil { model.otcCapturedObservations == 1 }
    #expect(model.otcCapturedObservations == 1)
    #expect(model.otcCaptureActive)
    #expect(model.scanning)

    await market.release()
    await scan.value
    #expect(model.frame != nil)
    #expect(model.candles(for: "BTC/USDT").isEmpty == false)
    // Research capture is independent of the scan lifecycle.
    #expect(model.otcCaptureActive)
    model.stopOTCResearchCapture()
}

@MainActor
@Test func backgroundCancelsResearchCaptureAndInvalidatesSuspendedScan() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let market = SuspendedMarketDataService()
    let model = researchModel(root: root, marketData: market,
        observations: [researchObservation()], keepsStreamOpen: true)
    model.marketMode = .crypto

    let scan = Task { @MainActor in await model.scanCrypto(asset: "BTC/USDT") }
    while await !market.waiting { await Task.yield() }
    model.startOTCResearchCapture(duration: 300)
    try await waitUntil { model.otcCaptureActive }

    model.handleAppBackgrounded()
    #expect(!model.otcCaptureActive)
    #expect(!model.scanning)

    await market.release()
    await scan.value
    #expect(model.frame == nil)
    #expect(model.candles.isEmpty)
}

// MARK: - Cache + persistence isolation

private struct ImmediateMarketDataService: DeskMarketDataServing {
    let bars: [Candle]

    func scan(market: DeskMarket, asset: String, session: OandaSession?) async throws -> MarketScanSnapshot {
        throw DeskMarketDataError.unavailable(asset)
    }

    func quotes(market: DeskMarket, assets: [String],
                session: OandaSession?) async -> MarketQuoteResult {
        MarketQuoteResult(quotes: [], status: .network)
    }

    func candles(market: DeskMarket, asset: String, session: OandaSession?,
                 count: Int) async -> [Candle] { bars }
}

@MainActor
@Test func candleCacheAndOTCSamplesRemainSeparate() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let bars = [Candle(time: 1_000, open: 100, high: 101, low: 99, close: 100)]
    let model = researchModel(root: root,
        marketData: ImmediateMarketDataService(bars: bars),
        observations: [researchObservation()], keepsStreamOpen: true)
    model.marketMode = .crypto
    model.pair = "BTC/USDT"

    await model.loadCandles(for: "BTC/USDT")
    #expect(model.candles(for: "BTC/USDT") == bars)

    model.startOTCResearchCapture(duration: 60)
    try await waitUntil { model.otcCapturedObservations == 1 }
    // OTC observations never replace or invalidate the desk candle cache.
    #expect(model.candles(for: "BTC/USDT") == bars)
    model.stopOTCResearchCapture()
}

@MainActor
@Test func researchEvidenceSurvivesRelaunchWithoutMutatingTheLedger() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = researchModel(root: root,
        marketData: ImmediateMarketDataService(bars: []),
        observations: [researchObservation(price: 1.10203)],
        keepsStreamOpen: false)
    first.startOTCResearchCapture(duration: 60)
    try await waitUntil { first.otcCapturedObservations == 1 && !first.otcCaptureActive }
    await first.recordManualOTCObservation(
        brokerPrice: "1.10203", providerPrice: "1.10201", payoutPercent: "88",
        screenshotReference: "IMG_0100.PNG", agreement: .agrees, confidence: .medium)
    #expect(first.manualBrokerObservations.count == 1)

    let second = researchModel(root: root,
        marketData: ImmediateMarketDataService(bars: []),
        observations: [], keepsStreamOpen: false)
    await second.restoreForTesting()
    await second.refreshOTCValidationReport()

    #expect(second.manualBrokerObservations.count == 1)
    #expect(second.manualBrokerObservations[0].researchOnly)
    #expect(!second.manualBrokerObservations[0].mayAuthorizeEntry)
    #expect(second.otcValidationReport?.totalSamples == 1)
    #expect(second.otcValidationReport?.hasProviderOTCObservation == true)
    // Research evidence never enters execution accounting.
    #expect(second.ledgerRows.isEmpty)
    #expect(second.outcomeStats == .empty)
    #expect(second.executionObservations.isEmpty)
    #expect(second.frame == nil)
}

// MARK: - Siri handoff

@MainActor
@Test func pendingSiriFlagIsConsumedExactlyOnceWhileResearchCaptureIsActive() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
    defaults?.set(false, forKey: PhoneTarget.pendingScanKey)
    defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
    defer { defaults?.set(false, forKey: PhoneTarget.pendingScanKey) }

    let model = researchModel(root: root,
        marketData: ImmediateMarketDataService(bars: []),
        observations: [researchObservation()], keepsStreamOpen: true)
    model.startOTCResearchCapture(duration: 60)
    try await waitUntil { model.otcCapturedObservations == 1 }

    #expect(model.takePendingScanRequest())
    #expect(!model.takePendingScanRequest())
    #expect(model.otcCaptureActive)
    model.stopOTCResearchCapture()
}

@MainActor
@Test func scanCoordinatorFiresIdleOnlyAfterOwnershipIsRelinquished() async throws {
    let coordinator = ScanOperationCoordinator()
    var idleCount = 0
    coordinator.onIdle = { idleCount += 1 }
    var published: [String] = []

    await coordinator.submit(market: .crypto, asset: "BTC/USDT",
                             assets: ["BTC/USDT"]) { request in
        if coordinator.isCurrent(request), let asset = request.asset {
            published.append(asset)
        }
    }
    #expect(published == ["BTC/USDT"])
    #expect(idleCount == 1)
    #expect(coordinator.isIdle)
}

// MARK: - Cancellation and evidence labeling

@MainActor
@Test func demoBarsAreNeverCachedAsFreshTransportData() {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = CandleCache()
    let model = researchModel(root: root,
        marketData: ImmediateMarketDataService(bars: []),
        observations: [], keepsStreamOpen: false, candleCache: cache)

    model.loadDemoDesk()
    let key = CandleCache.Key(market: model.marketMode, asset: model.pair)
    #expect(!cache.cached(key).isEmpty)
    #expect(!cache.isFresh(key))
}

@Test func cancellingAResearchStreamEndsAConsumerWithoutAnotherYield() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let service = LiveOTCResearchService(
        root: root,
        provider: ScriptedOTCProvider(observations: [], keepsStreamOpen: true))
    let stream = try await service.updates(for: service.researchIdentity)
    let consumer = Task {
        var count = 0
        do {
            for try await _ in stream.events { count += 1 }
        } catch {}
        return count
    }
    try await Task.sleep(for: .milliseconds(20))
    stream.cancel()
    let count = await consumer.value
    // The initial connection event is the only element; cancellation ends the consumer.
    #expect(count == 1)
}

@Test func syntheticVerificationCannotClaimProviderEvidence() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root)
    let now = Date()
    let identity = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let observation = ShadowMarketObservation(
        source: ShadowDataSourceIdentity(providerID: "fixture.otc",
            displayName: "Fixture", venueID: "otc", directBrokerConnection: false),
        identity: identity, quote: ShadowQuote(price: 1.1),
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: now.timeIntervalSince1970),
        receivedAt: now, connectionState: .live,
        verification: .syntheticTestFixture, provenance: "synthetic fixture")
    try await pipeline.record(OTCValidationSample(capturedAt: now, standard: nil,
        otc: observation, standardOrigin: nil, otcOrigin: .independentAPI))
    let report = try await pipeline.report()
    #expect(report.syntheticSampleCount == 1)
    #expect(report.containsSyntheticData)
    #expect(!report.hasProviderOTCObservation)
    #expect(report.status == "UNVERIFIED")
}
