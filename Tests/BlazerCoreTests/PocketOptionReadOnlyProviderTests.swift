import Foundation
import Testing
@testable import BlazerCore
@testable import LightningDesk

private actor MockPocketOptionTransport: PocketOptionReadOnlyTransport {
    private let scriptedFrames: [PocketOptionSocketFrame]
    private let keepsOpen: Bool
    private(set) var sent: [String] = []
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0

    init(_ scriptedFrames: [PocketOptionSocketFrame], keepsOpen: Bool = false) {
        self.scriptedFrames = scriptedFrames
        self.keepsOpen = keepsOpen
    }

    func connect(_ request: URLRequest) async throws
        -> AsyncThrowingStream<PocketOptionSocketFrame, any Error> {
        connectCount += 1
        return AsyncThrowingStream { continuation in
            for frame in scriptedFrames { continuation.yield(frame) }
            if !keepsOpen { continuation.finish() }
        }
    }

    func send(_ text: String) async throws {
        sent.append(text)
    }

    func disconnect() async {
        disconnectCount += 1
    }

    func snapshot() -> (sent: [String], connects: Int, disconnects: Int) {
        (sent, connectCount, disconnectCount)
    }
}

private final class FailingRemovalVault: KeychainVault, @unchecked Sendable {
    private let base = InMemoryKeychainVault()
    func set(_ value: String, for key: String) throws { try base.set(value, for: key) }
    func get(_ key: String) throws -> String? { try base.get(key) }
    func remove(_ key: String) throws { throw KeychainError.failure(-1) }
}

private struct FixedPocketOptionClock: OTCResearchClock {
    let date: Date
    func now() -> Date { date }
}

private let validDemoAuthFrame = #"42["auth",{"session":"test-session","isDemo":1,"uid":42,"platform":0,"isFastHistory":true,"isOptimized":true}]"#

private let eurusdAssetPayload = #"[[66,"EURUSD_otc","EUR/USD OTC","currency",2,92,60,30,3,1,170,0,[],1792910000,1,[{"time":60}],0,0,0]]"#

private func directProvider(
    _ transport: MockPocketOptionTransport,
    enabled: Bool = true,
    now: Double = 1_700_010_000
) -> PocketOptionReadOnlyProvider {
    PocketOptionReadOnlyProvider(
        configuration: PocketOptionReadOnlyConfiguration(
            authFrame: validDemoAuthFrame,
            enabled: enabled
        ),
        transport: transport,
        clock: FixedPocketOptionClock(date: Date(timeIntervalSince1970: now))
    )
}

@Test func directPocketOptionProviderIsDisabledBeforeUsingTheSession() async {
    let transport = MockPocketOptionTransport([])
    do {
        _ = try await directProvider(transport, enabled: false).instruments()
        Issue.record("Disabled provider unexpectedly connected")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .disabled)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
    #expect(await transport.snapshot().connects == 0)
}

@Test func directPocketOptionCatalogDeclaresOnlyTheConfiguredResearchIdentity() async throws {
    let transport = MockPocketOptionTransport([])
    let instruments = try await directProvider(transport).instruments()
    let eurusd = try #require(instruments.first)

    #expect(eurusd.identity == ShadowMarketDataFixtures.pocketOptionEURUSDOTC)
    #expect(eurusd.isOpen == nil)
    #expect(eurusd.payoutPercent == nil)
    let snapshot = await transport.snapshot()
    #expect(snapshot.connects == 0)
    #expect(snapshot.sent.isEmpty)
}

@Test func directPocketOptionTickNormalizesBrokerClockAndCannotAuthorizeEntry() async throws {
    let rawBrokerTime = 1_700_017_200.0
    let transport = MockPocketOptionTransport([
        .text(#"0{"sid":"engine"}"#),
        .text(#"40{"sid":"socket"}"#),
        .text(#"451-["updateAssets",{"_placeholder":true,"num":0}]"#),
        .data(Data(eurusdAssetPayload.utf8)),
        .text(#"451-["successauth",{"_placeholder":true,"num":0}]"#),
        .data(Data(#"{"serverName":"demo"}"#.utf8)),
        .text(#"451-["updateOpenedDeals",{"_placeholder":true,"num":0}]"#),
        .data(Data(#"[["account-data-is-not-a-tick"]]"#.utf8)),
        .text(#"451-["updateStream",{"_placeholder":true,"num":0}]"#),
        .data(Data(#"[["EURUSD_otc",1700017200,1.11433]]"#.utf8)),
    ])
    let updates = try await directProvider(transport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    var observation: ShadowMarketObservation?
    for try await update in updates {
        if case .observation(let value) = update { observation = value }
    }
    let value = try #require(observation)

    #expect(value.providerTimestamp.rawUnixSeconds == rawBrokerTime)
    #expect(value.providerTimestamp.normalizationSeconds == -7_200)
    #expect(value.providerTimestamp.normalized == Date(timeIntervalSince1970: 1_700_010_000))
    #expect(value.quote.price == 1.11433)
    #expect(value.payoutPercent == 92)
    #expect(value.marketOpen == true)
    #expect(value.source.directBrokerConnection)
    #expect(value.verification == .unverifiedVendorData)
    #expect(value.researchOnly)
    #expect(!value.mayAuthorizeEntry)
    #expect(value.freshness(at: Date(timeIntervalSince1970: 1_700_010_000)) == .fresh)
    let sent = await transport.snapshot().sent
    #expect(sent.contains(#"42["changeSymbol",{"asset":"EURUSD_otc","period":60}]"#))
    #expect(sent.contains(#"42["subfor","EURUSD_otc"]"#))
}

@Test func directPocketOptionProviderRejectsWrongInstrumentAndFutureTicks() async throws {
    let wrongTransport = MockPocketOptionTransport([
        .text(#"42["updateStream",[["GBPUSD_otc",1700017200,1.25]]]"#),
    ])
    let wrongUpdates = try await directProvider(wrongTransport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    do {
        for try await _ in wrongUpdates {}
        Issue.record("Wrong instrument unexpectedly entered the stream")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .wrongInstrument(expected: "EURUSD_otc", received: "GBPUSD_otc"))
    }

    let futureTransport = MockPocketOptionTransport([
        .text(#"42["updateStream",[["EURUSD_otc",1700017300,1.11433]]]"#),
    ])
    let futureUpdates = try await directProvider(futureTransport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    do {
        for try await _ in futureUpdates {}
        Issue.record("Future tick unexpectedly entered the stream")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .staleOrOutOfOrder)
    }
}

@Test func directPocketOptionProviderRequiresCurrentBrokerMetadataForEveryTick() async throws {
    let missingTransport = MockPocketOptionTransport([
        .text(#"42["updateStream",[["EURUSD_otc",1700017200,1.11433]]]"#),
    ])
    let missingUpdates = try await directProvider(missingTransport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    do {
        for try await _ in missingUpdates {}
        Issue.record("Tick without broker metadata unexpectedly entered the stream")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .invalidResponse)
    }

    let unrelatedAssets = #"[[67,"GBPUSD_otc","GBP/USD OTC","currency",2,92,60,30,3,1,170,0,[],1792910000,1,[{"time":60}],0,0,0]]"#
    let staleTransport = MockPocketOptionTransport([
        .text(#"451-["updateAssets",{"_placeholder":true,"num":0}]"#),
        .data(Data(eurusdAssetPayload.utf8)),
        .text(#"451-["updateAssets",{"_placeholder":true,"num":0}]"#),
        .data(Data(unrelatedAssets.utf8)),
        .text(#"42["updateStream",[["EURUSD_otc",1700017200,1.11433]]]"#),
    ])
    let staleUpdates = try await directProvider(staleTransport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    do {
        for try await _ in staleUpdates {}
        Issue.record("Tick reused stale payout metadata")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .invalidResponse)
    }
}

@Test func directPocketOptionAuthenticationAloneNeverReportsLive() async throws {
    let transport = MockPocketOptionTransport([
        .text(#"42["successauth",{}]"#),
    ])
    let updates = try await directProvider(transport).updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    var states: [ShadowConnectionState] = []
    for try await update in updates {
        if case .connection(let state, _) = update { states.append(state) }
    }
    #expect(states == [.connecting, .disconnected])
}

@Test func directPocketOptionProviderRejectsOverlappingStreams() async throws {
    let transport = MockPocketOptionTransport([], keepsOpen: true)
    let provider = directProvider(transport)
    let first = try await provider.updates(
        for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC]
    )
    do {
        _ = try await provider.updates(for: [ShadowMarketDataFixtures.pocketOptionEURUSDOTC])
        Issue.record("Overlapping stream unexpectedly replaced the active socket")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .connectionAlreadyOpen)
    }
    let consumer = Task { for try await _ in first {} }
    consumer.cancel()
    _ = await consumer.result
}

@Test func directPocketOptionProviderHasNoHistoricalOrTradingSurface() async {
    let provider = directProvider(MockPocketOptionTransport([]))
    do {
        _ = try await provider.candles(
            for: ShadowMarketDataFixtures.pocketOptionEURUSDOTC,
            intervalSeconds: 60,
            limit: 10
        )
        Issue.record("Unsupported history unexpectedly succeeded")
    } catch let error as PocketOptionReadOnlyError {
        #expect(error == .historicalCandlesUnavailable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@MainActor
@Test func directPocketOptionSessionStaysInTheVaultAndCanBeRemovedImmediately() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-direct-session-\(UUID().uuidString)", isDirectory: true)
    let model = LightningDeskModel(storageRoot: root)
    let vault = InMemoryKeychainVault()
    model.otcCredentialVault = vault

    model.savePocketOptionReadOnlySession(validDemoAuthFrame)
    #expect(model.pocketOptionSessionConfigured)
    #expect(try vault.get(KeychainKey.pocketOptionReadOnlySession) == validDemoAuthFrame)
    #expect(model.otcConnectionState == .disabled)

    model.disconnectAndRemovePocketOptionSession()
    #expect(!model.pocketOptionSessionConfigured)
    #expect(try vault.get(KeychainKey.pocketOptionReadOnlySession) == nil)
    #expect(model.otcConnectionState == .disabled)
}

@MainActor
@Test func malformedPocketOptionSessionIsNeverPersisted() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-invalid-session-\(UUID().uuidString)", isDirectory: true)
    let model = LightningDeskModel(storageRoot: root)
    let vault = InMemoryKeychainVault()
    model.otcCredentialVault = vault

    model.savePocketOptionReadOnlySession("not-a-session")
    #expect(!model.pocketOptionSessionConfigured)
    #expect(try vault.get(KeychainKey.pocketOptionReadOnlySession) == nil)
    #expect(model.otcResearchIssue == "Enter a complete Pocket Option demo auth frame")

    let realFrame = #"42["auth",{"session":"real-session","isDemo":0,"uid":42,"platform":0}]"#
    model.savePocketOptionReadOnlySession(realFrame)
    #expect(!model.pocketOptionSessionConfigured)
    #expect(try vault.get(KeychainKey.pocketOptionReadOnlySession) == nil)
}

@MainActor
@Test func failedPocketOptionSessionRemovalRemainsVisible() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-failed-session-removal-\(UUID().uuidString)", isDirectory: true)
    let model = LightningDeskModel(storageRoot: root)
    let vault = FailingRemovalVault()
    model.otcCredentialVault = vault
    model.savePocketOptionReadOnlySession(validDemoAuthFrame)

    model.disconnectAndRemovePocketOptionSession()

    #expect(model.pocketOptionSessionConfigured)
    #expect(try vault.get(KeychainKey.pocketOptionReadOnlySession) == validDemoAuthFrame)
    #expect(model.otcResearchIssue == "Pocket Option session removal could not be confirmed")
}
