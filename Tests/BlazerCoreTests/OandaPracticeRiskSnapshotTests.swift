import Foundation
import Testing
@testable import BlazerCore

private final class PracticeRiskRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        stored.append(request)
    }

    func requests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private final class PracticeRiskStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = PracticeRiskRequestCapture()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.capture.append(request)
        let body: String
        switch request.url?.path {
        case "/v3/accounts/test-account/summary":
            body = #"{"account":{"currency":"USD","balance":"10000","NAV":"9950","marginAvailable":"8000"}}"#
        case "/v3/accounts/test-account/instruments":
            body = #"{"instruments":[{"name":"GBP_JPY","marginRate":"0.05","minimumTradeSize":"1","maximumOrderUnits":"1000000","commission":{"commission":"2","unitsTraded":"100000","minimumCommission":"0"}}]}"#
        case "/v3/accounts/test-account/pricing":
            body = #"{"time":"2033-05-18T03:33:20Z","prices":[{"instrument":"GBP_JPY","status":"tradeable","time":"2033-05-18T03:33:20Z","bids":[{"price":"200.000"}],"asks":[{"price":"200.010"}]}],"homeConversions":[{"currency":"JPY","accountLoss":"0.0067"},{"currency":"GBP","positionValue":"1.27"}]}"#
        default:
            body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func practiceSizingFactorsUseOANDAConversionValues() async {
    let snapshot = OandaPracticeRiskSnapshot(
        accountId: "practice-account", accountCurrency: "USD", balance: 10_000,
        nav: 9_900, marginAvailable: 8_000, instrument: "GBP_JPY",
        instrumentMarginRate: 0.05, minimumTradeSize: 1, maximumOrderUnits: 1_000_000,
        commissionPerUnitsTraded: 2, commissionUnitsTraded: 100_000, minimumCommission: 0,
        quoteLossToHomeFactor: 0.0067, basePositionToHomeFactor: 1.27,
        bid: 200, ask: 200.01, quoteAsOf: Date(), conversionsAsOf: Date(), observedAt: Date())

    let factors = snapshot.sizingFactors(entryPrice: 200)
    #expect(factors?.accountRiskPerPriceUnit == 0.0067)
    #expect(abs((factors?.marginPerUnit ?? 0) - 12.7) < 1e-9)
}

@Test func practiceSizingFactorsFailClosedForInvalidValues() async {
    let snapshot = OandaPracticeRiskSnapshot(
        accountId: "practice-account", accountCurrency: "USD", balance: 10_000,
        nav: 9_900, marginAvailable: 8_000, instrument: "GBP_JPY",
        instrumentMarginRate: .nan, minimumTradeSize: 1, maximumOrderUnits: 1_000_000,
        commissionPerUnitsTraded: 0, commissionUnitsTraded: 1, minimumCommission: 0,
        quoteLossToHomeFactor: 0, basePositionToHomeFactor: 1.27,
        bid: 200, ask: 200.01, quoteAsOf: Date(), conversionsAsOf: Date(), observedAt: Date())

    #expect(snapshot.sizingFactors(entryPrice: 200) == nil)
    #expect(snapshot.sizingFactors(entryPrice: .infinity) == nil)
}

@Test func practiceSnapshotRejectsLiveEnvironmentBeforeNetworkAccess() async {
    let result = await OandaClient.fetchPracticeGBPYJSizingSnapshot(
        session: OandaSession(token: "not-used", accountId: "account", environment: .live))

    #expect(result.snapshot == nil)
    #expect(result.reason == "practice_environment_required")
}

@Test func practiceSnapshotRejectsMissingCredentialsBeforeNetworkAccess() async {
    let result = await OandaClient.fetchPracticeGBPYJSizingSnapshot(
        session: OandaSession(token: "", accountId: "", environment: .practice))

    #expect(result.snapshot == nil)
    #expect(result.transport == .missingToken)
    #expect(result.reason == "credentials_missing")
}

@Test func practiceSnapshotReadsOnlyPracticeAccountInputsAndAppliesConversions() async throws {
    let capture = PracticeRiskStubURLProtocol.capture
    capture.append(URLRequest(url: URL(string: "https://reset.invalid")!))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PracticeRiskStubURLProtocol.self]
    let requestSession = URLSession(configuration: configuration)
    defer { requestSession.invalidateAndCancel() }

    let result = await OandaClient.fetchPracticeGBPYJSizingSnapshot(
        session: OandaSession(token: "test-token", accountId: "test-account", environment: .practice),
        requestSession: requestSession)

    let snapshot = try #require(result.snapshot)
    #expect(result.transport == .ok)
    #expect(snapshot.accountCurrency == "USD")
    #expect(snapshot.balance == 10_000)
    #expect(snapshot.nav == 9_950)
    #expect(snapshot.marginAvailable == 8_000)
    #expect(snapshot.minimumTradeSize == 1)
    #expect(snapshot.maximumOrderUnits == 1_000_000)
    #expect(abs((snapshot.estimatedRoundTripCommissionPerUnit ?? 0) - 0.00004) < 1e-9)
    #expect(snapshot.bid == 200)
    #expect(snapshot.ask == 200.01)
    #expect(snapshot.sizingFactors(entryPrice: 200)?.accountRiskPerPriceUnit == 0.0067)
    #expect(abs((snapshot.sizingFactors(entryPrice: 200)?.marginPerUnit ?? 0) - 12.7) < 1e-9)

    let requests = capture.requests().filter { $0.url?.host == "api-fxpractice.oanda.com" }
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.httpMethod == "GET" })
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-token" })
    #expect(requests.map { $0.url?.path } == [
        "/v3/accounts/test-account/summary",
        "/v3/accounts/test-account/instruments",
        "/v3/accounts/test-account/pricing",
    ])
    let pricingURL = try #require(requests.last?.url)
    let query = URLComponents(url: pricingURL, resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.contains(URLQueryItem(name: "includeHomeConversions", value: "true")) == true)
}

@Test func accountRiskRequestUsesOnePercentNAVAndInstrumentUnitLimit() {
    let snapshot = OandaPracticeRiskSnapshot(
        accountId: "practice-account", accountCurrency: "USD", balance: 10_000,
        nav: 9_900, marginAvailable: 1_000_000, instrument: "GBP_JPY",
        instrumentMarginRate: 0.05, minimumTradeSize: 1, maximumOrderUnits: 5_000,
        commissionPerUnitsTraded: 2, commissionUnitsTraded: 100_000, minimumCommission: 0,
        quoteLossToHomeFactor: 0.0067, basePositionToHomeFactor: 1.27,
        bid: 200, ask: 200.01, quoteAsOf: Date(), conversionsAsOf: Date(), observedAt: Date())
    let request = snapshot.riskSizingRequest(
        entryPrice: snapshot.ask, stopPrice: 199.5, spreadCostPerUnit: 0.000067)

    #expect(request?.accountBalanceUSD == 9_900)
    #expect(request?.riskFraction == 0.01)
    #expect(request?.maximumUnits == 5_000)
    if let request {
        let result = V3RiskSizer.size(request)
        #expect(result.accepted)
        #expect(result.units <= 5_000)
        #expect(result.estimatedWorstCaseLossUSD! <= result.riskBudgetUSD)
        #expect(result.estimatedMarginUSD! <= snapshot.marginAvailable)
    } else {
        Issue.record("Expected valid risk sizing inputs")
    }
}
