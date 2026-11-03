import Foundation

/// Serializes desk scan ingress into one running request and one latest pending request.
/// The desk remains the owner of execution state; this type only manages request identity.
@MainActor
final class ScanRequestScheduler {
    struct Request: Equatable, Sendable {
        let generation: UInt64
        let market: DeskMarket
        let asset: String?
        let assets: [String]
    }

    private(set) var generation: UInt64 = 0
    private(set) var pending: Request?

    @discardableResult
    func submit(market: DeskMarket, asset: String? = nil, assets: [String]) -> Request {
        generation &+= 1
        let request = Request(generation: generation, market: market, asset: asset, assets: assets)
        pending = request
        return request
    }

    func takePending() -> Request? {
        defer { pending = nil }
        return pending
    }

    func isCurrent(_ request: Request) -> Bool {
        request.generation == generation
    }

    func invalidate() {
        generation &+= 1
        pending = nil
    }
}
