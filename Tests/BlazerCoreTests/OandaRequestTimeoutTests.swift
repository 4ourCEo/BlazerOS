import Foundation
import Testing
@testable import BlazerCore

@Test func finiteOandaRequestsHaveIdleAndTotalTimeouts() {
    let configuration = OandaClient.finiteRequestSession.configuration
    #expect(configuration.timeoutIntervalForRequest == 20)
    #expect(configuration.timeoutIntervalForResource == 30)
}
