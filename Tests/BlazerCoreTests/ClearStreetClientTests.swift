import Foundation
import Testing
@testable import BlazerCore

@Suite("ClearStreetClientTests")
struct ClearStreetClientTests {

    @Test func sessionConfiguredValidation() {
        let empty = ClearStreetSession(apiKey: "")
        #expect(!empty.isConfigured)

        let spaces = ClearStreetSession(apiKey: "   ")
        #expect(!spaces.isConfigured)

        let valid = ClearStreetSession(apiKey: "cs_demo_token_12345", accountId: "acc_99")
        #expect(valid.isConfigured)
        #expect(valid.environment == .demo)
        #expect(valid.environment.host == "https://api.clearstreet.com")
        #expect(valid.environment.studioHost == "https://api.clearstreet.io/studio/v2")
    }

    @Test func parseQuotesFromListResponse() throws {
        let json = """
        {
            "data": [
                {
                    "symbol": "SPY",
                    "bid": 580.25,
                    "ask": 580.30,
                    "mid": 580.275,
                    "timestamp": 1790000000000
                },
                {
                    "symbol": "QQQ",
                    "bid": 490.10,
                    "ask": 490.15,
                    "mid": 490.125,
                    "timestamp": 1790000000000
                }
            ]
        }
        """
        let data = Data(json.utf8)
        let quotes = ClearStreetClient.parseQuotes(from: data, requestedSymbols: ["SPY", "QQQ"])

        #expect(quotes.count == 2)
        let spy = try #require(quotes.first(where: { $0.asset == "SPY" }))
        #expect(spy.bid == 580.25)
        #expect(spy.ask == 580.30)
        #expect(spy.mid == 580.275)
        #expect(spy.source == "clearstreet")
        #expect(spy.asOfMs == 1790000000000)

        let qqq = try #require(quotes.first(where: { $0.asset == "QQQ" }))
        #expect(qqq.bid == 490.10)
        #expect(qqq.ask == 490.15)
        #expect(qqq.source == "clearstreet")
    }

    @Test func parseQuotesFromDictionaryResponse() throws {
        let json = """
        {
            "AAPL": {
                "bid_price": 230.50,
                "ask_price": 230.55,
                "timestamp": 1790000000123
            }
        }
        """
        let data = Data(json.utf8)
        let quotes = ClearStreetClient.parseQuotes(from: data, requestedSymbols: ["AAPL"])

        #expect(quotes.count == 1)
        let aapl = try #require(quotes.first)
        #expect(aapl.asset == "AAPL")
        #expect(aapl.bid == 230.50)
        #expect(aapl.ask == 230.55)
        #expect(aapl.mid == 230.525)
        #expect(aapl.source == "clearstreet")
    }

    @Test func orderModelInitializationAndDefaults() {
        let order = ClearStreetOrder(
            symbol: "NVDA",
            side: .buy,
            orderType: .limit,
            quantity: 100,
            limitPrice: 125.50,
            timeInForce: .day
        )

        #expect(order.symbol == "NVDA")
        #expect(order.side == .buy)
        #expect(order.orderType == .limit)
        #expect(order.quantity == 100)
        #expect(order.limitPrice == 125.50)
        #expect(order.timeInForce == .day)
        #expect(!order.clientOrderId.isEmpty)
    }

    @Test func unconfiguredClientFailsFast() async {
        let unconfigured = ClearStreetSession(apiKey: "")
        let ping = await ClearStreetClient.pingLatency(session: unconfigured)
        #expect(!ping.ok)
        #expect(ping.fault == "Clear Street API key missing")

        let batch = await ClearStreetClient.fetchQuoteBatch(symbols: ["SPY"], session: unconfigured)
        #expect(batch.transport == .missingKey)
        #expect(batch.quotes.isEmpty)
    }
}
