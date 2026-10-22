import Foundation

// MARK: - BinanceRateLimit
// Keeps blazerCT well under Binance's 1200 req/min ceiling.
// Steady-state: 10 req/s. Burst: 12 req/s max.

public actor BinanceRateLimit {
    public static let shared = BinanceRateLimit()

    private var tokens: Double = 12
    private let capacity: Double = 12
    private let steadyRate: Double = 10   // 10 req/s
    private var lastRefill = Date()

    public init() {}

    public func acquire() async {
        refill()
        while tokens < 1 {
            let deficit = 1 - tokens
            let waitSec = deficit / steadyRate
            let nanos = UInt64(max(0.05, waitSec) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            refill()
        }
        tokens -= 1
    }

    private func refill() {
        let elapsed = Date().timeIntervalSince(lastRefill)
        guard elapsed > 0 else { return }
        tokens = min(capacity, tokens + elapsed * steadyRate)
        lastRefill = Date()
    }
}
