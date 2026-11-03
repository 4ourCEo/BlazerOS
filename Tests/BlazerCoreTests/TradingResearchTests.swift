import CryptoKit
import Foundation
import Testing
@testable import BlazerCore

private func signed(_ alert: PineScriptWebhookAlert, secret: String) throws -> (Data, String) {
    let data = try JSONEncoder().encode(alert)
    let code = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: Data(secret.utf8)))
    return (data, code.map { String(format: "%02x", $0) }.joined())
}

@Test func webhookRejectsUnauthorizedStaleAndDuplicateAlerts() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let alert = PineScriptWebhookAlert(id: "a1", symbol: "EUR/USD", direction: "HIGH",
        timestamp: now, price: 1.1, timeframeSeconds: 60, strategyVersion: "pine-v1")
    let (data, signature) = try signed(alert, secret: "secret")
    let replayURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("pine-replay-\(UUID().uuidString).json")
    let store = PineScriptWebhookStore(secret: "secret", replayURL: replayURL)
    await #expect(throws: TradingResearchError.unauthorized) {
        try await store.ingest(data, authorization: "bad", now: now)
    }

    let accepted = try await store.ingest(data, authorization: signature, now: now)
    #expect(accepted == alert)
    await #expect(throws: TradingResearchError.duplicateAlert) {
        try await store.ingest(data, authorization: signature, now: now)
    }

}

@Test func webhookReplayStateSurvivesStoreRestart() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_100)
    let alert = PineScriptWebhookAlert(id: "restart-1", symbol: "EUR/USD", direction: "HIGH",
        timestamp: now, price: 1.1, timeframeSeconds: 60, strategyVersion: "pine-v1")
    let (data, signature) = try signed(alert, secret: "secret")
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pine-replay-\(UUID().uuidString).json")
    let first = PineScriptWebhookStore(secret: "secret", replayURL: url)
    _ = try await first.ingest(data, authorization: signature, now: now)
    let restarted = PineScriptWebhookStore(secret: "secret", replayURL: url)
    await #expect(throws: TradingResearchError.duplicateAlert) {
        try await restarted.ingest(data, authorization: signature, now: now)
    }
}

@Test func replayUsesOnlySourceMatchedObservationsAndExactlySixtySeconds() {
    let entry = Date(timeIntervalSince1970: 1_700_000_000)
    let alert = PineScriptWebhookAlert(id: "a2", symbol: "EUR/USD", direction: "HIGH",
        timestamp: entry, price: 1.1, timeframeSeconds: 60, strategyVersion: "pine-v1")
    let observations = [
        ValidationPriceObservation(instrumentID: "EUR/USD", venueID: "tradingview-pine",
            observedAt: entry, price: 1.1, source: "pine", authority: .independentProvider),
        ValidationPriceObservation(instrumentID: "EUR/USD", venueID: "other",
            observedAt: entry.addingTimeInterval(60), price: 1.2, source: "other",
            authority: .independentProvider),
        ValidationPriceObservation(instrumentID: "EUR/USD", venueID: "tradingview-pine",
            observedAt: entry.addingTimeInterval(60), price: 1.2, source: "pine",
            authority: .independentProvider),
    ]
    let result = SixtySecondReplayResult(alert: alert, observations: observations)
    #expect(result.expiryAt == entry.addingTimeInterval(60))
    #expect(result.resolution == .win)
    #expect(result.researchOnly)
}

@Test func signalComparisonCannotAuthorizeExternalDirection() throws {
    let signal = EngineSignal(asset: "EUR/USD", cabinetSide: "HIGH", call: "TAP HIGH",
        why: "engine", price: 1.1, asOfMs: 1_700_000_000_000)
    let alert = PineScriptWebhookAlert(id: "a3", symbol: "EUR/USD", direction: "LOW",
        timestamp: Date(timeIntervalSince1970: 1_700_000_000), price: 1.1,
        timeframeSeconds: 60, strategyVersion: "pine-v1")
    let comparison = try ResearchSignalComparison(authoritative: signal, external: alert)
    #expect(!comparison.agrees)
    #expect(comparison.researchOnly)
}
