import Foundation
import Testing
@testable import BlazerCore
@testable import LightningDesk

private struct FixedOTCClock: OTCResearchClock {
    let value: Date
    func now() -> Date { value }
}

private final class MockOTChartsTransport: OTChartsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [OTChartsHTTPResponse]
    private var streams: [AsyncThrowingStream<OTChartsServerEvent, any Error>]
    private(set) var requests: [URLRequest] = []

    init(responses: [OTChartsHTTPResponse] = [],
         streams: [AsyncThrowingStream<OTChartsServerEvent, any Error>] = []) {
        self.responses = responses
        self.streams = streams
    }

    func data(for request: URLRequest) async throws -> OTChartsHTTPResponse {
        lock.withLock {
            requests.append(request)
            return responses.removeFirst()
        }
    }

    func events(for request: URLRequest) -> AsyncThrowingStream<OTChartsServerEvent, any Error> {
        lock.withLock {
            requests.append(request)
            return streams.removeFirst()
        }
    }
}

private func eventStream(_ events: [OTChartsServerEvent], terminal: (any Error)? = nil)
    -> AsyncThrowingStream<OTChartsServerEvent, any Error> {
    AsyncThrowingStream { continuation in
        events.forEach { continuation.yield($0) }
        if let terminal { continuation.finish(throwing: terminal) }
        else { continuation.finish() }
    }
}

private func provider(_ transport: MockOTChartsTransport, enabled: Bool = true,
                      now: Double = 1_700_010_000) -> OTChartsProvider {
    OTChartsProvider(configuration: OTChartsConfiguration(apiKey: "private-test-key", enabled: enabled),
                     transport: transport,
                     clock: FixedOTCClock(value: Date(timeIntervalSince1970: now)))
}

@Test func otchartsIsDisabledBeforeTransportOrCredentialsAreUsed() async {
    let transport = MockOTChartsTransport()
    let subject = provider(transport, enabled: false)
    do {
        _ = try await subject.instruments()
        Issue.record("Disabled provider made a request")
    } catch let error as OTChartsError {
        #expect(error == .disabled)
    } catch { Issue.record("Unexpected error: \(error)") }
    #expect(transport.requests.isEmpty)
}

@Test func catalogPreservesIdentityAvailabilityAndPayout() async throws {
    let json = #"{"venue":"otc","symbols":[{"symbol":"EURUSD_otc","name":"EUR/USD OTC","payout":88,"open":true}]}"#
    let transport = MockOTChartsTransport(responses: [
        OTChartsHTTPResponse(data: Data(json.utf8), statusCode: 200)
    ])
    let result = try await provider(transport).instruments()
    #expect(result.count == 1)
    #expect(result[0].identity == ShadowMarketDataFixtures.pocketOptionEURUSDOTC)
    #expect(result[0].isOpen == true)
    #expect(result[0].payoutPercent == 88)
    #expect(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer private-test-key")
}

@Test func candlesPreserveRawClockNormalizeAndMarkIncomplete() async throws {
    // Vendor-reported 1,700,017,200 is normalized by -7,200 to the fixed local time.
    let json = #"{"symbol":"EURUSD_otc","candles":[{"open":1.1,"high":1.2,"low":1.0,"close":1.15,"time":1700017140},{"open":1.15,"high":1.3,"low":1.1,"close":1.25,"time":1700017200}]}"#
    let transport = MockOTChartsTransport(responses: [
        OTChartsHTTPResponse(data: Data(json.utf8), statusCode: 200)
    ])
    let result = try await provider(transport).candles(
        for: ShadowMarketDataFixtures.pocketOptionEURUSDOTC, intervalSeconds: 60, limit: 2)
    #expect(result.count == 2)
    #expect(result[0].providerTimestamp.rawUnixSeconds == 1_700_017_140)
    #expect(result[0].providerTimestamp.normalized == Date(timeIntervalSince1970: 1_700_009_940))
    #expect(result[0].complete)
    #expect(!result[1].complete)
}

@Test func streamRejectsOutOfOrderAndWrongInstrumentTicks() async throws {
    let connected = OTChartsServerEvent(name: "connected", data: #"{"symbols":["EURUSD_otc"]}"#)
    let first = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.1,"time":1700017200}"#)
    let older = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.2,"time":1700017199}"#)
    let transport = MockOTChartsTransport(streams: [eventStream([connected, first, older])])
    let updates = try await provider(transport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    do {
        for try await _ in updates {}
        Issue.record("Out-of-order stream completed as valid")
    } catch let error as OTChartsError {
        #expect(error == .staleOrOutOfOrder)
    }

    let wrong = OTChartsServerEvent(name: "tick", data: #"{"symbol":"GBPUSD_otc","price":1.2,"time":1700017200}"#)
    let secondTransport = MockOTChartsTransport(streams: [eventStream([wrong])])
    let second = try await provider(secondTransport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    do {
        for try await _ in second {}
        Issue.record("Wrong instrument stream completed as valid")
    } catch let error as OTChartsError {
        #expect(error == .wrongInstrument(expected: "EURUSD_otc", received: "GBPUSD_otc"))
    }
}

@Test func interruptionIsExplicitAndFreshnessExpires() async throws {
    let tick = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.1,"time":1700017200}"#)
    let replaced = OTChartsServerEvent(name: "replaced", data: #"{"reason":"newer"}"#)
    let transport = MockOTChartsTransport(streams: [eventStream([tick, replaced])])
    let updates = try await provider(transport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    var observation: ShadowMarketObservation?
    do {
        for try await update in updates {
            if case .observation(let value) = update { observation = value }
        }
        Issue.record("Replacement was not surfaced")
    } catch let error as OTChartsError {
        #expect(error == .providerClosed("Stream replaced by a newer connection"))
    }
    let captured = try #require(observation)
    #expect(captured.providerTimestamp.rawUnixSeconds == 1_700_017_200)
    #expect(captured.freshness(at: Date(timeIntervalSince1970: 1_700_010_000)) == .fresh)
    #expect(captured.freshness(at: Date(timeIntervalSince1970: 1_700_010_011)) == .expired)
    #expect(captured.researchOnly && !captured.mayAuthorizeEntry)
    #expect(captured.verification == .unverifiedVendorData)
}

@Test func providerThrottlingAndReconnectAreControlled() async throws {
    let throttled = MockOTChartsTransport(responses: [
        OTChartsHTTPResponse(data: Data(), statusCode: 429, headers: ["retry-after": "7"])
    ])
    do {
        _ = try await provider(throttled).instruments()
        Issue.record("429 was accepted")
    } catch let error as OTChartsError {
        #expect(error == .throttled(retryAfterSeconds: 7))
    }

    let tick = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.1,"time":1700017200}"#)
    let reconnecting = MockOTChartsTransport(streams: [eventStream([], terminal: URLError(.networkConnectionLost)), eventStream([tick])])
    let subject = provider(reconnecting)
    let first = try await subject.updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    do { for try await _ in first {} } catch { #expect(error is URLError) }
    let second = try await subject.updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    var count = 0
    for try await update in second { if case .observation = update { count += 1 } }
    #expect(count == 1)
    #expect(reconnecting.requests.count == 2)
}

@Test func tickPrintsThatShareASourceSecondAreRetained() async throws {
    let connected = OTChartsServerEvent(name: "connected", data: "{}")
    let first = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.1,"time":1700017200}"#)
    let sameSecond = OTChartsServerEvent(name: "tick", data: #"{"symbol":"EURUSD_otc","price":1.1001,"time":1700017200}"#)
    let transport = MockOTChartsTransport(streams: [eventStream([connected, first, sameSecond])])
    let updates = try await provider(transport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    var count = 0
    for try await update in updates { if case .observation = update { count += 1 } }
    #expect(count == 2)
}

@Test func observationRejectsACandleFromAnotherInstrument() {
    let candle = ShadowCandle(identity: ShadowMarketDataFixtures.standardEURUSD, intervalSeconds: 60,
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: 1_700_000_000),
        open: 1.1, high: 1.2, low: 1.0, close: 1.15, complete: true)
    let observation = ShadowMarketObservation(
        source: ShadowDataSourceIdentity(providerID: "otcharts", displayName: "OTCharts",
            venueID: "otc", directBrokerConnection: false),
        identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
        quote: ShadowQuote(price: 1.1), candle: candle,
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: 1_700_000_000),
        receivedAt: Date(timeIntervalSince1970: 1_700_000_000), connectionState: .live,
        verification: .unverifiedVendorData, provenance: "synthetic test fixture")
    #expect(!observation.isValid)
}

@Test func validationDoesNotClaimLiveEvidenceWithoutAnOTCPrint() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root)
    try await pipeline.record(OTCValidationSample(capturedAt: Date(), standard: nil, otc: nil,
        standardOrigin: nil, otcOrigin: nil))
    let report = try await pipeline.report()
    #expect(report.totalSamples == 1)
    #expect(!report.hasProviderOTCObservation)
    #expect(report.status == "UNVERIFIED")
}

@Test func flatTransitionsAreNotCountedAsDirectionalAgreement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root)
    let standard = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let t = 1_700_000_000.0
    for offset in [0.0, 60.0] {
        try await pipeline.record(OTCValidationSample(capturedAt: Date(timeIntervalSince1970: t + offset),
            standard: validationObservation(identity: standard, provider: "oanda",
                normalizedTime: t + offset, price: 1.10),
            otc: validationObservation(identity: otc, provider: "otcharts",
                normalizedTime: t + offset, price: 1.1005),
            standardOrigin: .independentAPI, otcOrigin: .independentAPI))
    }
    let report = try await pipeline.report()
    #expect(report.sixtySecondComparableTransitions == 0)
    #expect(report.sixtySecondDirectionAgreements == 0)
}

@Test func cancellationStopsAProviderThatKeepsProducing() async throws {
    let upstream = AsyncThrowingStream<OTChartsServerEvent, any Error> { continuation in
        let producer = Task {
            for index in 0..<100 {
                // This producer intentionally never checks cancellation.
                continuation.yield(OTChartsServerEvent(name: "tick",
                    data: #"{"symbol":"EURUSD_otc","price":1.1,"time":\#(1700017200 + index)}"#))
                try? await Task.sleep(for: .milliseconds(2))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in producer.cancel() }
    }
    let transport = MockOTChartsTransport(streams: [upstream])
    let updates = try await provider(transport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    let consumer = Task {
        var seen = 0
        do {
            for try await update in updates {
                if case .observation = update { seen += 1; if seen == 1 { break } }
            }
        } catch {}
        return seen
    }
    #expect(await consumer.value == 1)
}

@Test func manualBrokerObservationArchiveIsResearchOnlyAndCorruptionIsVisible() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ManualBrokerObservationStore(root: root)
    let observation = ManualBrokerChartObservation(
        identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
        observedAt: Date(timeIntervalSince1970: 1_700_000_000), brokerDisplayedPrice: 1.10203,
        providerPrice: 1.10201, candleTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
        payoutPercent: 88, screenshotReference: "IMG_0042.PNG",
        agreement: .agrees, confidence: .medium)
    try await store.record(observation)
    let loaded = try await store.observations()
    #expect(loaded == [observation])
    #expect(loaded[0].researchOnly && !loaded[0].mayAuthorizeEntry)

    let path = root.appendingPathComponent("manual-broker-chart/bad.json")
    try Data("not json".utf8).write(to: path)
    do {
        _ = try await store.observations()
        Issue.record("Corrupt evidence was hidden")
    } catch { #expect(error is DecodingError) }
}

@MainActor
@Test func intelWorkflowKeepsProviderSecretInVaultAndManualEvidenceSeparate() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = LightningDeskModel(storageRoot: root)
    let vault = InMemoryKeychainVault()
    model.otcCredentialVault = vault
    model.saveOTChartsAPIKey("  otc_test_secret  ")
    #expect(model.otcAPIKeyConfigured)
    #expect(model.otcConnectionState == .disabled)
    #expect(try vault.get(KeychainKey.otchartsAPIKey) == "otc_test_secret")

    await model.recordManualOTCObservation(
        brokerPrice: "1.10203", providerPrice: "1.10201", payoutPercent: "88",
        screenshotReference: "IMG_0042.PNG", agreement: .agrees, confidence: .medium)
    #expect(model.manualBrokerObservations.count == 1)
    #expect(model.manualBrokerObservations[0].identity.venueSymbol == "EURUSD_otc")
    #expect(model.manualBrokerObservations[0].researchOnly)
    #expect(!model.manualBrokerObservations[0].mayAuthorizeEntry)

    model.disconnectAndRemoveOTChartsAPIKey()
    #expect(!model.otcAPIKeyConfigured)
    #expect(model.otcConnectionState == .disabled)
    #expect(try vault.get(KeychainKey.otchartsAPIKey) == nil)
}

private func validationObservation(identity: ShadowMarketIdentity, provider: String,
                                   normalizedTime: Double, price: Double,
                                   verification: ShadowVerificationState = .syntheticTestFixture)
    -> ShadowMarketObservation {
    ShadowMarketObservation(source: ShadowDataSourceIdentity(providerID: provider,
        displayName: provider, venueID: identity.venue, directBrokerConnection: false),
        identity: identity, quote: ShadowQuote(price: price),
        providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: normalizedTime),
        receivedAt: Date(timeIntervalSince1970: normalizedTime), connectionState: .live,
        verification: verification, provenance: "synthetic test fixture")
}

@MainActor
private func otcModel(root: URL, transport: MockOTChartsTransport) -> LightningDeskModel {
    let otcRoot = root.appendingPathComponent("Research", isDirectory: true)
        .appendingPathComponent("otc-validation", isDirectory: true)
    let service = LiveOTCResearchService(
        root: otcRoot,
        provider: OTChartsProvider(
            configuration: OTChartsConfiguration(apiKey: "otc_test_secret", enabled: true),
            transport: transport,
            clock: FixedOTCClock(value: Date(timeIntervalSince1970: 1_700_010_000))))
    return LightningDeskModel(
        storageRoot: root,
        marketData: LiveDeskMarketDataService(),
        otcArchive: service,
        otcResearchServiceFactory: { _ in service })
}

@MainActor
@Test func boundedCapturePersistsProviderSamplesWithoutEntryAuthority() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let symbols = #"{"venue":"otc","symbols":[{"symbol":"EURUSD_otc","name":"EUR/USD OTC","payout":88,"open":true}]}"#
    let tick = OTChartsServerEvent(name: "tick",
        data: #"{"symbol":"EURUSD_otc","price":1.10203,"time":1700017200}"#)
    let transport = MockOTChartsTransport(
        responses: [OTChartsHTTPResponse(data: Data(symbols.utf8), statusCode: 200)],
        streams: [eventStream([OTChartsServerEvent(name: "connected", data: "{}"), tick])])
    let model = otcModel(root: root, transport: transport)
    model.otcCredentialVault = InMemoryKeychainVault()
    model.saveOTChartsAPIKey("otc_test_secret")

    model.startOTCResearchCapture(duration: 30)
    #expect(model.otcCaptureActive)
    var waited = 0
    while (model.otcCapturedObservations == 0 || model.otcCaptureActive) && waited < 400 {
        try await Task.sleep(for: .milliseconds(10))
        waited += 1
    }
    #expect(model.otcCapturedObservations == 1)
    #expect(!model.otcCaptureActive)
    #expect(model.otcConnectionState == .disabled)

    await model.refreshOTCValidationReport()
    let report = try #require(model.otcValidationReport)
    #expect(report.totalSamples == 1)
    #expect(report.containsSyntheticData == false)
    #expect(report.hasProviderOTCObservation)
    #expect(report.status == "PROVIDER DATA — NO PAIRED COMPARISON")

    // The persisted evidence itself must carry no execution authority.
    let archive = root.appendingPathComponent("Research/otc-validation/paired-observations")
    let file = try #require(try FileManager.default.contentsOfDirectory(
        at: archive, includingPropertiesForKeys: nil).first)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let sample = try decoder.decode(OTCValidationSample.self, from: Data(contentsOf: file))
    #expect(sample.otc?.researchOnly == true)
    #expect(sample.otc?.mayAuthorizeEntry == false)
}

@MainActor
@Test func backgroundingStopsTheResearchCaptureAndClearsConnectionState() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }

    let symbols = #"{"venue":"otc","symbols":[{"symbol":"EURUSD_otc","name":"EUR/USD OTC","payout":88,"open":true}]}"#
    let never = AsyncThrowingStream<OTChartsServerEvent, any Error> { _ in }
    let transport = MockOTChartsTransport(
        responses: [OTChartsHTTPResponse(data: Data(symbols.utf8), statusCode: 200)],
        streams: [never])
    let model = otcModel(root: root, transport: transport)
    model.otcCredentialVault = InMemoryKeychainVault()
    model.saveOTChartsAPIKey("otc_test_secret")

    model.startOTCResearchCapture(duration: 300)
    #expect(model.otcCaptureActive)
    model.handleAppBackgrounded()
    #expect(!model.otcCaptureActive)
    #expect(model.otcConnectionState == .disabled)
    #expect(model.otcCapturedObservations == 0)
}

@Test func futureDatedTicksAreRejected() async throws {
    let future = OTChartsServerEvent(name: "tick",
        data: #"{"symbol":"EURUSD_otc","price":1.1,"time":1700020000}"#)
    let transport = MockOTChartsTransport(streams: [eventStream([future])])
    let updates = try await provider(transport).updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
    do {
        for try await _ in updates {}
        Issue.record("Future-dated tick was accepted")
    } catch let error as OTChartsError {
        #expect(error == .staleOrOutOfOrder)
    }
}

@Test func denseTicksReduceToNonOverlappingSixtySecondBuckets() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root)
    let standard = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    // Aligned to a minute boundary so every 10-second sample falls in a known bucket.
    let base = 1_700_000_040.0
    for offset in stride(from: 0.0, through: 70.0, by: 10.0) {
        try await pipeline.record(OTCValidationSample(capturedAt: Date(timeIntervalSince1970: base + offset),
            standard: validationObservation(identity: standard, provider: "oanda",
                normalizedTime: base + offset, price: 1.10 + offset * 0.0001),
            otc: validationObservation(identity: otc, provider: "otcharts",
                normalizedTime: base + offset, price: 1.1005 + offset * 0.0001),
            standardOrigin: .independentAPI, otcOrigin: .independentAPI))
    }
    let report = try await pipeline.report()
    #expect(report.totalSamples == 8)
    #expect(report.sixtySecondComparableTransitions == 1)
    #expect(report.sixtySecondDirectionAgreements == 1)
}

@Test func researchArchiveRetainsOnlyTheNewestSamples() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root, maximumSamples: 5, pruneEvery: 1)
    let base = 1_700_000_000.0
    for index in 0..<10 {
        try await pipeline.record(OTCValidationSample(
            capturedAt: Date(timeIntervalSince1970: base + Double(index)),
            standard: nil, otc: nil, standardOrigin: nil, otcOrigin: nil))
    }
    let retained = try await pipeline.samples()
    #expect(retained.count == 5)
    #expect(retained.map(\.capturedAt) == retained.map(\.capturedAt).sorted())
    #expect(retained.first?.capturedAt == Date(timeIntervalSince1970: base + 5))
    let report = try await pipeline.report()
    #expect(report.totalSamples == 5)
    #expect(report.retentionLimit == 5)
    #expect(report.oldestCapturedAt == Date(timeIntervalSince1970: base + 5))
    #expect(report.newestCapturedAt == Date(timeIntervalSince1970: base + 9))
}

@Test func manualObservationCandleTimeMustNotPostDateTheObservation() async throws {
    let identity = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let valid = ManualBrokerChartObservation(identity: identity, observedAt: observedAt,
        brokerDisplayedPrice: 1.10203,
        candleTimestamp: observedAt.addingTimeInterval(-30),
        agreement: .agrees, confidence: .medium)
    #expect(valid.isValid)
    let future = ManualBrokerChartObservation(identity: identity, observedAt: observedAt,
        brokerDisplayedPrice: 1.10203,
        candleTimestamp: observedAt.addingTimeInterval(30),
        agreement: .agrees, confidence: .medium)
    #expect(!future.isValid)
}

@Test func validationPipelineMeasuresSixtySecondsAndExcludesStaleWeekendReference() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let pipeline = OTCValidationPipeline(root: root)
    let standard = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let t = 1_700_000_000.0
    try await pipeline.record(OTCValidationSample(capturedAt: Date(timeIntervalSince1970: t),
        standard: validationObservation(identity: standard, provider: "oanda", normalizedTime: t, price: 1.10),
        otc: validationObservation(identity: otc, provider: "otcharts", normalizedTime: t, price: 1.1005),
        standardOrigin: .syntheticTestFixture, otcOrigin: .syntheticTestFixture))
    try await pipeline.record(OTCValidationSample(capturedAt: Date(timeIntervalSince1970: t + 60),
        standard: validationObservation(identity: standard, provider: "oanda", normalizedTime: t + 60, price: 1.11),
        otc: validationObservation(identity: otc, provider: "otcharts", normalizedTime: t + 60, price: 1.1104),
        standardOrigin: .syntheticTestFixture, otcOrigin: .syntheticTestFixture))
    try await pipeline.record(OTCValidationSample(capturedAt: Date(timeIntervalSince1970: t + 120),
        standard: validationObservation(identity: standard, provider: "oanda", normalizedTime: t, price: 1.10),
        otc: validationObservation(identity: otc, provider: "otcharts", normalizedTime: t + 120, price: 1.12),
        standardOrigin: .syntheticTestFixture, otcOrigin: .syntheticTestFixture))
    let report = try await pipeline.report()
    #expect(report.totalSamples == 3)
    #expect(report.sixtySecondComparableTransitions == 1)
    #expect(report.sixtySecondDirectionAgreements == 1)
    #expect(report.staleWeekendReferencesExcluded == 1)
    #expect(report.containsSyntheticData)
    #expect(!report.hasProviderOTCObservation)
    #expect(report.status == "UNVERIFIED")
}
