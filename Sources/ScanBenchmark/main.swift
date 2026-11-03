import BlazerCore
import Foundation

@main
enum ScanBenchmark {
    static func main() async throws {
        let iterations = max(10, Int(CommandLine.arguments.dropFirst().first ?? "250") ?? 250)
        let boot = await StrategyEngine.boot()
        guard boot.ok else { throw ScanError.failed(boot.detail ?? "Engine unavailable") }

        let input = GoldenFixture.market()
        for _ in 0..<10 { _ = try await StrategyEngine.evaluate(input: input) }

        var durationsMs: [Double] = []
        durationsMs.reserveCapacity(iterations)
        var decisionSeal: String?
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            let result = try await StrategyEngine.evaluate(input: input)
            let elapsed = start.duration(to: .now)
            let components = elapsed.components
            let milliseconds = Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1e15
            durationsMs.append(milliseconds)
            let seal = "\(result.signal.cabinetSide):\(result.signal.confidence ?? 0):\(result.signal.why)"
            if let decisionSeal, decisionSeal != seal {
                throw ScanError.failed("Frozen benchmark decision changed across iterations")
            }
            decisionSeal = seal
        }

        durationsMs.sort()
        let p50 = percentile(0.50, in: durationsMs)
        let p95 = percentile(0.95, in: durationsMs)
        let mean = durationsMs.reduce(0, +) / Double(durationsMs.count)
        let inputAgeMs: Double? = input.quoteAsOfMs.flatMap { quoteTime in
            input.evaluatedAtMs.map { max(0, $0 - quoteTime) }
        }
        print("workload=GoldenFixture.market() engine=\(EngineIdentity.loadedSHA1() ?? "unverified") bars_m1=\(input.candles1m.count) bars_m5=\(input.candles5m.count) iterations=\(iterations)")
        print("scan_compute_ms p50=\(format(p50)) p95=\(format(p95)) mean=\(format(mean)) source_age_ms=\(inputAgeMs.map(format) ?? "unavailable") fetch_ms=unavailable publication_ms=unavailable eligible_pairs=unavailable decision=\(decisionSeal ?? "unavailable")")
    }

    private static func percentile(_ fraction: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return .nan }
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded(.up)))]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
