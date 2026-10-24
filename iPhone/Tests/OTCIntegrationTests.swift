import BlazerCore
import Foundation
import XCTest
@testable import LightningDesk

/// iOS-only integration coverage: the scan coordinator must consume a queued Siri request only
/// after it relinquishes scan ownership, while an independent OTC research capture keeps running.
@MainActor
final class OTCIntegrationTests: XCTestCase {
    private struct StubMarketData: DeskMarketDataServing {
        let counter: ScanCounter

        func scan(market: DeskMarket, asset: String,
                  session: OandaSession?) async throws -> MarketScanSnapshot {
            await counter.increment()
            let candle = Candle(time: 1_000, open: 100, high: 101, low: 99, close: 100)
            return MarketScanSnapshot(
                signal: EngineSignal(asset: asset, cabinetSide: "WAIT", call: "WAIT",
                    why: "test", price: 100),
                candles: [candle], m5Candles: [], bid: 99, ask: 101, spread: 2,
                expirySeconds: 60, engineSHA: "test", policy: "test",
                source: "test", veto: nil)
        }

        func quotes(market: DeskMarket, assets: [String],
                    session: OandaSession?) async -> MarketQuoteResult {
            MarketQuoteResult(quotes: [], status: .network)
        }

        func candles(market: DeskMarket, asset: String, session: OandaSession?,
                     count: Int) async -> [Candle] { [] }
    }

    private actor ScanCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private struct ScriptedOTCProvider: ShadowMarketObservationProvider {
        let sourceIdentity = ShadowDataSourceIdentity(
            providerID: "test.otc.research", displayName: "Test OTC", venueID: "otc",
            directBrokerConnection: false)

        func instruments() async throws -> [ShadowInstrumentAvailability] {
            [ShadowInstrumentAvailability(
                identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
                isOpen: true, payoutPercent: 88)]
        }

        func candles(for identity: ShadowMarketIdentity, intervalSeconds: Int,
                     limit: Int) async throws -> [ShadowCandle] { [] }

        func updates(for identities: [ShadowMarketIdentity]) async throws
            -> AsyncThrowingStream<ShadowProviderUpdate, any Error> {
            let now = Date()
            let observation = ShadowMarketObservation(
                source: sourceIdentity,
                identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
                quote: ShadowQuote(price: 1.10203),
                providerTimestamp: ShadowProviderTimestamp(
                    rawUnixSeconds: now.timeIntervalSince1970),
                receivedAt: now, connectionState: .live,
                verification: .unverifiedVendorData,
                provenance: "hermetic integration fixture; not live evidence")
            return AsyncThrowingStream { continuation in
                continuation.yield(.connection(.live, reason: nil))
                continuation.yield(.observation(observation))
                // Keep the capture open until the test stops it.
            }
        }
    }

    func testSiriRequestIsConsumedAfterScanIdlesWhileOTCCaptureContinues() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-ios-otc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        defaults?.set(false, forKey: PhoneTarget.pendingScanKey)
        defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
        defer { defaults?.set(false, forKey: PhoneTarget.pendingScanKey) }

        let counter = ScanCounter()
        let otcRoot = root.appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent("otc-validation", isDirectory: true)
        let service = LiveOTCResearchService(root: otcRoot,
                                             provider: ScriptedOTCProvider())
        let model = LightningDeskModel(
            storageRoot: root,
            marketData: StubMarketData(counter: counter),
            otcArchive: service,
            otcResearchServiceFactory: { _ in service })
        model.marketMode = .crypto
        model.otcCredentialVault = InMemoryKeychainVault()
        model.saveOTChartsAPIKey("otc_ios_test_key")

        model.startOTCResearchCapture(duration: 300)
        XCTAssertTrue(model.otcCaptureActive)
        let captured = await poll { model.otcCapturedObservations > 0 }
        XCTAssertTrue(captured, "research capture did not persist a sample")

        await model.scanCrypto(asset: "BTC/USDT")

        // The coordinator's idle hook consumes the queued Siri scan once. It is intentionally
        // detached from the worker that just exited, so wait for the observable handoff.
        let consumed = await poll {
            defaults?.bool(forKey: PhoneTarget.pendingScanKey) == false
        }
        XCTAssertTrue(consumed, "queued Siri request was not consumed")
        let reran = await poll { await counter.value >= 2 }
        XCTAssertTrue(reran, "Siri-triggered scan did not run")
        // OTC research remains independent of scan scheduling and Siri ingress.
        XCTAssertTrue(model.otcCaptureActive)
        XCTAssertGreaterThanOrEqual(model.otcCapturedObservations, 1)
        model.stopOTCResearchCapture()
    }

    private func poll(timeoutMs: Int = 10_000,
                      _ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    func testBackgroundStopsCaptureAndPreventsQueuedSiriScanFromRunning() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-ios-otc-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        defaults?.set(false, forKey: PhoneTarget.pendingScanKey)
        defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
        defer { defaults?.set(false, forKey: PhoneTarget.pendingScanKey) }

        let service = LiveOTCResearchService(
            root: root.appendingPathComponent("Research/otc-validation", isDirectory: true),
            provider: ScriptedOTCProvider())
        let model = LightningDeskModel(
            storageRoot: root,
            marketData: StubMarketData(counter: ScanCounter()),
            otcArchive: service,
            otcResearchServiceFactory: { _ in service })
        model.otcCredentialVault = InMemoryKeychainVault()
        model.saveOTChartsAPIKey("otc_ios_test_key")
        model.startOTCResearchCapture(duration: 300)
        XCTAssertTrue(model.otcCaptureActive)
        model.handleAppBackgrounded()
        XCTAssertFalse(model.otcCaptureActive)
        XCTAssertEqual(model.otcConnectionState, .disabled)
        // A queued Siri request is not consumed while the desk is backgrounded.
        XCTAssertTrue(defaults?.bool(forKey: PhoneTarget.pendingScanKey) ?? false)
    }
}
