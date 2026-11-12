import XCTest
@testable import BlazerCore

final class OandaForwardQuoteCaptureTests: XCTestCase {
    func testEarlyEOFIsNotSuccessful() {
        let started = Date(timeIntervalSince1970: 100)
        let result = OandaClient.finalizeForwardStream(
            endedAt: started.addingTimeInterval(2), startedAt: started,
            duration: 30, quoteCount: 1, maxQuotes: 100,
            termination: "stream_ended")

        XCTAssertEqual(result.transport, .network)
        XCTAssertEqual(result.termination, "early_eof")
    }

    func testHTTP429IsRateLimited() {
        XCTAssertEqual(OandaClient.forwardHTTPTransport(statusCode: 429), .rateLimited)
        XCTAssertEqual(OandaClient.forwardHTTPTransport(statusCode: 401), .unauthorized)
        XCTAssertEqual(OandaClient.forwardHTTPTransport(statusCode: 503), .network)
    }

    func testCancellationIsDistinctFromNetwork() {
        let cancellation = OandaClient.classifyForwardError(CancellationError())
        let urlCancellation = OandaClient.classifyForwardError(URLError(.cancelled))
        let network = OandaClient.classifyForwardError(NSError(domain: "test.network", code: 7))

        XCTAssertEqual(cancellation.termination, "cancelled")
        XCTAssertEqual(urlCancellation.termination, "cancelled")
        XCTAssertEqual(network.termination, "network_failure")
        XCTAssertEqual(cancellation.transport, .network)
        XCTAssertEqual(urlCancellation.transport, .network)
        XCTAssertEqual(network.transport, .network)
    }

    func testNonPositiveAndCrossedQuotesAreRejected() {
        XCTAssertFalse(OandaClient.isValidForwardBidAsk(bid: 0, ask: 1))
        XCTAssertFalse(OandaClient.isValidForwardBidAsk(bid: -1, ask: 1))
        XCTAssertFalse(OandaClient.isValidForwardBidAsk(bid: 2, ask: 1))
        XCTAssertFalse(OandaClient.isValidForwardBidAsk(bid: .nan, ask: 2))
        XCTAssertTrue(OandaClient.isValidForwardBidAsk(bid: 1, ask: 2))
    }
}
