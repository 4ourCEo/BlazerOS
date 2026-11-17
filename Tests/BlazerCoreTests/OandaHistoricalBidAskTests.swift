import Foundation
import Testing
@testable import BlazerCore

private final class OandaRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    func set(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        storedRequests.append(request)
    }

    func all() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return storedRequests
    }
}

private final class OandaStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = OandaRequestCapture()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capture.set(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSuccessfulLiveCapture(from: Date, to: Date,
                                       includeFirst: Bool = true) async -> OandaLiveHistoricalCapture {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OandaStubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    return await OandaClient.fetchLiveHistoricalCapture(
        asset: "GBP/JPY", from: from, to: to, granularity: "M1", includeFirst: includeFirst,
        session: OandaSession(token: "test-token", accountId: "test-account", environment: .live),
        requestSession: session)
}

@Test func historicalBidAskCandleRejectsCrossedOrMalformedPrices() {
    let candle = OandaBidAskCandle(instrument: "EUR_USD", granularity: "M1",
        sourceTime: Date(timeIntervalSince1970: 2_000_000_000), complete: true,
        bidOpen: 1.1, bidHigh: 1.101, bidLow: 1.099, bidClose: 1.1005,
        askOpen: 1.1009, askHigh: 1.1008, askLow: 1.0999, askClose: 1.1004)
    #expect(candle.validation.contains("ohlc_invalid"))
    #expect(candle.intrabarSequenceIsKnown == false)
}

@Test func liveHistoricalAcquisitionRejectsPracticeEnvironmentWithoutNetwork() async {
    let from = Date(timeIntervalSince1970: 2_000_000_000)
    let batch = await OandaClient.fetchLiveHistoricalBidAskCandles(
        asset: "GBP/JPY", from: from, to: from.addingTimeInterval(60),
        session: OandaSession(token: "token", accountId: "account", environment: .practice))
    #expect(batch.candles.isEmpty)
    #expect(batch.liveOnlyRejected == true)
    #expect(batch.transport == .network)
}

@Test func liveHistoricalRequestUsesBoundedLiveBidAskContract() async throws {
    let capture = OandaStubURLProtocol.capture
    capture.set(URLRequest(url: URL(string: "https://reset.invalid")!))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OandaStubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let from = Date(timeIntervalSince1970: 2_000_073_600)
    let to = from.addingTimeInterval(86_400)
    let captureResult = await OandaClient.fetchLiveHistoricalCapture(
        asset: "GBP/JPY", from: from, to: to, granularity: "M1", includeFirst: false,
        session: OandaSession(token: "test-token", accountId: "test-account", environment: .live),
        requestSession: session)
    let batch = captureResult.batch

    let request = try #require(capture.all().first { request in
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains {
            $0.name == "includeFirst" && $0.value == "false"
        } == true
    })
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
    #expect(url.host == "api-fxtrade.oanda.com")
    #expect(url.path == "/v3/instruments/GBP_JPY/candles")
    #expect(query["granularity"] == "M1")
    #expect(query["price"] == "BA")
    #expect(query["smooth"] == "false")
    #expect((components.queryItems ?? []).filter { $0.name == "includeFirst" }.map(\.value) == ["false"])
    #expect(query["from"] != nil && query["to"] != nil)
    #expect(query["count"] == nil)
    #expect(batch.transport == .ok && batch.httpStatus == 200)
    #expect(batch.liveOnlyRejected == false)
}

@Test func liveHistoricalWindowsAreUTCAlignedAndNonOverlapping() {
    let end = Date(timeIntervalSince1970: 2_000_073_600) // UTC midnight
    let windows = LiveHistoricalResearchArchive.utcDayWindows(dayCount: 3, endExclusive: end)
    #expect(windows?.count == 3)
    #expect(windows?.first?.includeFirst == true)
    #expect(windows?.allSatisfy(\.includeFirst) == true)
    #expect(windows?.dropFirst().first?.start == windows?.first?.end)
    #expect(LiveHistoricalResearchArchive.utcDayWindows(dayCount: 0, endExclusive: end) == nil)
    #expect(LiveHistoricalResearchArchive.utcDayWindows(
        dayCount: 1, endExclusive: end.addingTimeInterval(1)) == nil)
}

@Test func liveHistoricalArchiveRejectsPracticeBatchAndUnprovenLiveBatch() {
    let from = Date(timeIntervalSince1970: 2_000_073_600)
    let to = from.addingTimeInterval(86_400)
    let practice = OandaHistoricalBidAskBatch(instrument: "GBP_JPY", granularity: "M1",
        requestedFrom: from, requestedTo: to, candles: [], transport: .ok,
        practiceOnlyRejected: false, httpStatus: 200)
    #expect(LiveHistoricalResearchArchive.validationIssues(for: practice,
        expectedInstrument: "GBP_JPY", expectedGranularity: "M1",
        expectedFrom: from, expectedTo: to).contains("environment_rejected"))

    let unknownEnvironment = OandaHistoricalBidAskBatch(instrument: "GBP_JPY", granularity: "M1",
        requestedFrom: from, requestedTo: to, candles: [], transport: .ok, httpStatus: 200)
    #expect(LiveHistoricalResearchArchive.validationIssues(for: unknownEnvironment,
        expectedInstrument: "GBP_JPY", expectedGranularity: "M1",
        expectedFrom: from, expectedTo: to).contains("environment_rejected"))
}

@Test func liveHistoricalArchiveDigestCoversProvenanceMetadata() async throws {
    let from = Date(timeIntervalSince1970: 2_000_073_600)
    let to = from.addingTimeInterval(86_400)
    let capture = await makeSuccessfulLiveCapture(from: from, to: to)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: LiveHistoricalResearchArchive.ArchiveError.invalidBatch(["include_first_mismatch"])) {
        try LiveHistoricalResearchArchive.append(capture: capture, includeFirst: false,
            root: root)
    }
    let write = try LiveHistoricalResearchArchive.append(capture: capture, includeFirst: true,
        root: root)
    let original = try Data(contentsOf: write.url)
    var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
    object["includeFirst"] = false
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try tampered.write(to: write.url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: write.url.path)

    #expect(throws: LiveHistoricalResearchArchive.ArchiveError.existingArchiveInvalid) {
        try LiveHistoricalResearchArchive.append(capture: capture, includeFirst: true,
            root: root)
    }
}

@Test func liveHistoricalArchiveRejectsCaptureWithoutSuccessfulLiveReceipt() async {
    let from = Date(timeIntervalSince1970: 2_000_073_600)
    let capture = await OandaClient.fetchLiveHistoricalCapture(
        asset: "GBP/JPY", from: from, to: from.addingTimeInterval(86_400),
        session: OandaSession(token: "test-token", accountId: "test-account", environment: .practice))
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(throws: LiveHistoricalResearchArchive.ArchiveError.liveCaptureReceiptRequired) {
        try LiveHistoricalResearchArchive.append(capture: capture, includeFirst: true,
            root: root)
    }
}

@Test func historicalBidAskAcquisitionRejectsLiveEnvironmentWithoutNetwork() async {
    let from = Date(timeIntervalSince1970: 2_000_000_000)
    let batch = await OandaClient.fetchHistoricalBidAskCandles(
        asset: "EUR/USD", from: from, to: from.addingTimeInterval(60),
        session: OandaSession(token: "token", accountId: "account", environment: .live))
    #expect(batch.candles.isEmpty)
    #expect(batch.practiceOnlyRejected)
    #expect(batch.transport == .network)
}
