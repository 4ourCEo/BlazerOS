import BlazerCore
import Foundation
import LightningDesk

struct Options {
    var synthetic = false
    var edgeReport = false
    var asOf: Date?
    var stats = false
    var replay = false
    var continuous = false
    var primeOnly = false
    var daemon = false
    var help = false
    var root: URL?
    var policies = ["baseline"]
    var maxEvents = 100
    var bootstrap = false
    var experiment = false

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--help", "-h": help = true
            case "--benchmark", "-b": synthetic = true
            case "--edge-report": edgeReport = true
            case "--stats", "-s": stats = true
            case "--bootstrap": stats = true; bootstrap = true
            case "--experiment": experiment = true
            case "--replay": replay = true
            case "--continuous": continuous = true
            case "--daemon", "-d": daemon = true; continuous = true; primeOnly = true
            case "--prime-only", "--smart-schedule": primeOnly = true
            case "--all-policies": policies = ["control"] + ScanPolicy.allCases.map(\.rawValue)
            case "--root", "--policy", "--max-events", "--as-of":
                index += 1
                guard index < arguments.count else { throw ScanError.failed("Missing value for \(arg)") }
                let value = arguments[index]
                if arg == "--as-of" {
                    guard let seconds = Double(value), seconds.isFinite, seconds >= 0, seconds < 253_402_300_800 else {
                        throw ScanError.failed("Invalid report cutoff (Unix seconds)")
                    }
                    asOf = Date(timeIntervalSince1970: seconds)
                }
                if arg == "--root" { root = URL(fileURLWithPath: value, isDirectory: true) }
                if arg == "--policy" {
                    guard value == "control" || ScanPolicy(rawValue: value) != nil else { throw ScanError.failed("Unknown policy \(value)") }
                    policies = [value]
                }
                if arg == "--max-events" {
                    guard let count = Int(value), count > 0 else { throw ScanError.failed("Invalid event limit") }
                    maxEvents = count
                }
            default: throw ScanError.failed("Unknown argument \(arg)")
            }
            index += 1
        }
    }
}

@MainActor
final class ResearchRunner {
    let store: ResearchStore
    let options: Options
    let root: URL
    let horizons = [60, 180, 300]
    var pending: [String: ResearchEvent] = [:]
    var completed: Set<String> = []
    var lastBar: [String: Double] = [:]
    var captured = 0
    var observationFault: String?

    init(options: Options) {
        self.options = options
        root = options.root ?? ResearchStore.defaultRoot(synthetic: options.synthetic)
        store = ResearchStore(root: root)
    }

    func evaluate(_ input: StrategyEngine.MarketInput, policy: String) async throws -> EngineSignal {
        if policy == "control" { return try await StrategyEngine.evaluateControl(input: input).signal }
        var candidate = input
        candidate.policy = ScanPolicy(rawValue: policy)
        return try await StrategyEngine.evaluate(input: candidate).signal
    }

    func capture(_ input: StrategyEngine.MarketInput, quote: LiveQuote, at time: Date, synthetic: Bool) async throws -> [ResearchEvent] {
        var events: [ResearchEvent] = []
        for policy in options.policies {
            var candidate = input
            candidate.policy = policy == "control" ? nil : ScanPolicy(rawValue: policy)
            let signal = try await evaluate(candidate, policy: policy)
            let event = try ResearchEvent(input: candidate, signal: signal,
                sourceKind: synthetic ? "synthetic" : "oanda-proxy", capturedAt: time, entryQuote: quote,
                engineSHA: policy == "control" ? StrategyEngine.controlSHA1 : (EngineIdentity.loadedSHA1() ?? "unverified"))
            try await store.record(event) // Persist before exposing an accepted research entry.
            if event.entryTime != nil { pending[event.id] = event }
            events.append(event)
            print("CAPTURE \(policy) \(input.asset) \(signal.cabinetSide) \(event.entryVeto ?? "accepted proxy entry")")
        }
        captured += 1
        return events
    }

    func restore() async throws {
        completed = Set(try await store.outcomes().map { "\($0.eventID)-\($0.horizon)" })
        let events = try await store.events()
        for event in events where event.sourceKind == "oanda-proxy" && event.entryTime != nil {
            if horizons.contains(where: { !completed.contains("\(event.id)-\($0)") }) { pending[event.id] = event }
        }
        // Avoid recapturing a completed candle after restart.
        for event in events where event.sourceKind == "oanda-proxy" {
            if let time = event.input.candles1m.last?.time { lastBar[event.input.asset] = max(lastBar[event.input.asset] ?? 0, time) }
        }
    }

    func observe(session: OandaSession) async throws {
        while !Task.isCancelled {
            let assets = Set(pending.values.map { $0.input.asset }).sorted()
            if !assets.isEmpty {
                let batch = await OandaClient.fetchQuoteBatch(assets: assets, session: session)
                let observed = Date()
                let quotes = Dictionary(batch.quotes.map { ($0.asset, $0) }, uniquingKeysWith: { first, _ in first })
                for event in Array(pending.values) {
                    guard let entryTime = event.entryTime, let strike = event.entryPrice else { continue }
                    for horizon in horizons {
                        let key = "\(event.id)-\(horizon)"
                        let expiry = entryTime.addingTimeInterval(Double(horizon))
                        guard !completed.contains(key), observed >= expiry else { continue }
                        let outcome = ResearchOutcome.resolve(eventID: event.id, horizon: horizon,
                            entryTime: entryTime, strike: strike, side: event.signal.cabinetSide,
                            quote: batch.transport == .ok ? quotes[event.input.asset] : nil, observedAt: observed)
                        // Allow an observation until the window closes. Old or later prints never become wins/losses.
                        if outcome.resolution == .unresolved && observed.timeIntervalSince(expiry) <= 5 { continue }
                        try await store.record(outcome)
                        completed.insert(key)
                        print("OUTCOME \(event.signal.policy ?? "baseline") \(event.input.asset) \(horizon)s \(outcome.resolution.rawValue)")
                    }
                    if horizons.allSatisfy({ completed.contains("\(event.id)-\($0)") }) { pending[event.id] = nil }
                }
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    func runLive(session: OandaSession) async throws {
        try await restore()
        let observer = Task {
            do { try await self.observe(session: session) }
            catch is CancellationError {}
            catch { self.observationFault = error.localizedDescription }
        }
        defer { observer.cancel() }
        print("Local OANDA proxy research. Root: \(root.path). Policies: \(options.policies.joined(separator: ", ")). No venue trades are placed.")
        while !Task.isCancelled && (options.continuous || captured < options.maxEvents) {
            // Surface archive/observer errors instead of continuing with a broken outcome sampler.
            if let observationFault { throw ScanError.failed("Outcome sampler failed: \(observationFault)") }
            if !FxSession.isOpen() || (options.primeOnly && !MarketEdgeWindow.current().isPrime) {
                try await Task.sleep(for: .seconds(5))
                continue
            }
            for pair in Assets.watchlist {
                if Task.isCancelled { break }
                do {
                    guard var input = try await OandaClient.fetchBundle(asset: pair, session: session),
                          let bar = input.candles1m.last, bar.time > (lastBar[pair] ?? 0) else { continue }
                    let time = Date()
                    input.evaluatedAtMs = time.timeIntervalSince1970 * 1000
                    let quote = LiveQuote(asset: pair, bid: input.bid, ask: input.ask, mid: input.lastPrice,
                        asOfMs: input.quoteAsOfMs ?? 0, source: input.source)
                    _ = try await capture(input, quote: quote, at: time, synthetic: false)
                    lastBar[pair] = bar.time
                } catch {
                    print("SCAN_ERROR \(pair): \(error.localizedDescription)")
                    // Storage errors must terminate; transport/scan errors are retried on the next pass.
                    if !(error is ScanError) { throw error }
                }
                if !options.continuous && captured >= options.maxEvents { break }
            }
            try await Task.sleep(for: .seconds(1))
        }
        while !pending.isEmpty && !Task.isCancelled {
            if let observationFault { throw ScanError.failed("Outcome sampler failed: \(observationFault)") }
            try await Task.sleep(for: .seconds(1))
        }
        observer.cancel()
        await observer.value
        if let observationFault { throw ScanError.failed("Outcome sampler failed: \(observationFault)") }
        try await printStats()
    }

    func runSynthetic() async throws {
        print("Deterministic synthetic software exercise; results do not measure a market edge. Root: \(root.path)")
        var seed: UInt64 = 42
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed >> 11) / Double(UInt64.max >> 11) * 2 - 1
        }
        let count = max(650, 605 + options.maxEvents)
        let base = 1_700_000_000_000.0
        var price = 1.1
        var bars: [StrategyEngine.CandlePayload] = []
        for i in 0..<count {
            let open = price
            price += (noise() * 2 + 0.15) * 0.0001
            bars.append(.init(time: base + Double(i) * 60_000, open: open,
                high: max(open, price) + 0.0001, low: min(open, price) - 0.0001, close: price))
        }
        for end in 599..<(599 + options.maxEvents) {
            let prefix = Array(bars[0...end])
            var m5: [StrategyEngine.CandlePayload] = []
            for start in stride(from: 0, through: prefix.count - 5, by: 5) {
                let group = Array(prefix[start..<(start + 5)])
                m5.append(.init(time: group[0].time, open: group[0].open,
                    high: group.map(\.high).max()!, low: group.map(\.low).min()!, close: group[4].close))
            }
            let timeMs = bars[end].time + 60_000
            let time = Date(timeIntervalSince1970: timeMs / 1000)
            let mid = bars[end].close
            let input = StrategyEngine.MarketInput(asset: "EUR/USD", source: "synthetic",
                candles1m: Array(prefix.suffix(120)), candles5m: Array(m5.suffix(120)), lastPrice: mid,
                bid: mid - 0.00002, ask: mid + 0.00002, spread: 0.00004,
                expirySeconds: 60, quoteAsOfMs: timeMs, evaluatedAtMs: timeMs)
            let quote = LiveQuote(asset: input.asset, bid: input.bid, ask: input.ask, mid: mid, asOfMs: timeMs, source: "synthetic")
            let events = try await capture(input, quote: quote, at: time, synthetic: true)
            for event in events {
                guard let entry = event.entryTime, let strike = event.entryPrice else { continue }
                for horizon in horizons {
                    let target = entry.addingTimeInterval(Double(horizon))
                    let exit = bars[end + horizon / 60].close
                    let quote = LiveQuote(asset: input.asset, bid: exit - 0.00002, ask: exit + 0.00002,
                        mid: exit, asOfMs: target.timeIntervalSince1970 * 1000, source: "synthetic")
                    let outcome = ResearchOutcome.resolve(eventID: event.id, horizon: horizon,
                        entryTime: entry, strike: strike, side: event.signal.cabinetSide,
                        quote: quote, observedAt: target, labelSource: "synthetic")
                    try await store.record(outcome)
                }
                pending[event.id] = nil
            }
        }
        try await printStats()
    }

    func replay() async throws {
        let events = try await store.events()
        var matches = 0
        for event in events {
            let policy = event.signal.policy ?? "baseline"
            let expectedSHA = policy == "control" ? StrategyEngine.controlSHA1 : EngineIdentity.pinnedSHA1
            guard event.engineSHA == expectedSHA else { throw ScanError.failed("Replay requires archived engine \(event.engineSHA)") }
            let signal = try await evaluate(event.input, policy: policy)
            guard signal.cabinetSide == event.signal.cabinetSide, signal.confidence == event.signal.confidence,
                  signal.evidence == event.signal.evidence, signal.why == event.signal.why else {
                throw ScanError.failed("Replay mismatch for \(event.id)")
            }
            matches += 1
        }
        print("Replayed \(matches) frozen events with matching side, conviction, evidence and veto narrative.")
    }

    func printEdgeReport() async throws {
        guard let archiveRoot = options.root, let cutoff = options.asOf else {
            throw ScanError.failed("--edge-report requires --root (desk storage) and --as-of (Unix seconds) for reproducibility")
        }
        let report = try await ExecutionIntelligence.loadReport(root: archiveRoot, asOf: cutoff)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }

    func runExperiment() async throws {
        let events = try await store.events()
        let outcomes = try await store.outcomes()

        for policy in options.policies {
            let engine = policy == "control" ? StrategyEngine.controlSHA1 : (EngineIdentity.loadedSHA1() ?? "unverified")

            // Quote the payout the archive actually recorded, not a hard-coded 88%. When the
            // archive is mixed, the lowest rate is the one promotion must clear.
            let policyEvents = events.filter {
                ($0.signal.policy ?? ScanPolicy.baseline.rawValue) == policy && $0.engineSHA == engine
            }
            let payouts = policyEvents.map(\.assumedPayout).filter { $0.isFinite && $0 > 0 }
            let meanPayout = payouts.isEmpty
                ? EntryQuality.assumedPayout
                : payouts.reduce(0, +) / Double(payouts.count)
            let minimumPayout = payouts.min() ?? EntryQuality.assumedPayout
            let breakEven = 1.0 / (1.0 + minimumPayout)
            let breakEvenText = String(format: "%.2f", breakEven * 100)
            let payoutText = String(format: "%.1f", minimumPayout * 100)

            // Reuse the first experiment for this policy/engine so its held-out boundary
            // stays frozen. Creating a new record every run silently re-uses the holdout.
            let stored = try await store.experiments()
            let experiment: ResearchExperiment
            if let existing = stored.first(where: {
                $0.policy == policy && $0.engineSHA == engine && $0.hasFrozenHoldout
            }) {
                experiment = existing
            } else {
                let splitAt = ResearchEvaluator.splitDate(
                    events: events, policy: policy, engineSHA: engine, splitFraction: 0.7
                )
                experiment = ResearchExperiment(
                    name: "chronological \(policy) evaluation",
                    policy: policy,
                    engineSHA: engine,
                    splitAt: splitAt,
                    payoutRatio: meanPayout,
                    acceptanceCriteria: "Held-out cohort has positive expectancy and a cluster-adjusted lower Wilson bound above the \(breakEvenText)% break-even implied by the lowest recorded payout (\(payoutText)%), after at least 250 independent clustered events, prospective registration and venue confirmation.",
                    rejectionCriteria: "Held-out cohort has non-positive expectancy, fewer than 250 independent clustered events, or a cluster-adjusted lower Wilson bound at or below the \(breakEvenText)% break-even.",
                    notes: "Generated locally. No live activation. Retrospective split is exploratory. Proxy/synthetic outcomes never establish venue edge. Independent validation and authorization required."
                )
                try await store.record(experiment)
            }

            let report = ResearchEvaluator.evaluate(experiment: experiment, events: events, outcomes: outcomes)
            try await store.record(report)

            print("EXPERIMENT \(policy): splitFrozen=\(report.isHoldoutFrozen) breakEven=\(String(format: "%.2f%%", (report.breakEvenWinRate ?? breakEven) * 100)) acceptance=\(report.acceptanceSatisfied ? "MET" : "NOT MET")")
            for cohort in [report.train, report.test] {
                let rate = cohort.winRate.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable"
                let ev = cohort.expectancy.map { String(format: "%+.4f", $0) } ?? "unavailable"
                let blocks = cohort.blocks.map(String.init) ?? "·"
                let nEff = cohort.effectiveSampleSize.map { String(format: "%.1f", $0) } ?? "·"
                print("EXPERIMENT \(policy) \(cohort.label): n=\(cohort.resolved) blocks=\(blocks) nEff=\(nEff) H=\(cohort.highSignals) L=\(cohort.lowSignals) WAIT=\(cohort.waitSignals) accepted=\(cohort.acceptedEntries)/\(cohort.candidates) WR=\(rate) EV=\(ev) balanced=\(report.highLowBalanced)")
                print("  \(cohort.caveat)")
            }
        }
    }

    func printStats() async throws {
        let events = try await store.events()
        let outcomes = try await store.outcomes()
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        print("Research archive: \(root.path). \(events.count) captured candidates; \(events.filter { $0.entryTime != nil }.count) accepted entries.")
        let cohorts = Dictionary(grouping: events) {
            "\($0.sourceKind)/\($0.engineSHA)/\($0.policyVersion)/\($0.signal.policy ?? "baseline")"
        }
        for cohort in cohorts.keys.sorted() {
            let candidateIDs = Set(cohorts[cohort]!.map(\.id))
            let candidates = cohorts[cohort]!
            let accepted = candidates.filter { $0.entryTime != nil }.count
            print("COHORT \(cohort): \(accepted)/\(candidates.count) candidates accepted.")
            for horizon in horizons {
                let rows = outcomes.filter { candidateIDs.contains($0.eventID) && $0.horizon == horizon && byID[$0.eventID] != nil }
                let wins = rows.filter { $0.resolution == .hit }.count
                let losses = rows.filter { $0.resolution == .miss }.count
                let ties = rows.filter { $0.resolution == .tie }.count
                let missing = rows.filter { $0.resolution == .unresolved }.count
                let n = wins + losses
                let rate = n > 0 ? String(format: "%.1f%%", Double(wins) / Double(n) * 100) : "unavailable"
                let ev = n > 0 ? String(format: "%+.4f", (Double(wins) * EntryQuality.assumedPayout - Double(losses)) / Double(n)) : "unavailable"
                let interval = EdgeEvidence.wilsonScoreInterval(wins: wins, total: n)
                let ci = n > 0 ? String(format: "%.1f–%.1f%%", interval.lower * 100, interval.upper * 100) : "unavailable"
                print("\(horizon)s: \(wins)/\(n) resolved wins (\(rate)); nominal Wilson CI=\(ci); assumed EV88=\(ev); ties=\(ties), unresolved=\(missing).")
                if options.bootstrap, n > 0, let boot = ExpectancyMath.bootstrapStressTest(wins: wins, sampleSize: n, iterations: 500) {
                    let bootRate = String(format: "%.1f%%", boot.medianWinRate * 100)
                    let p5 = String(format: "%.1f%%", boot.p5WinRate * 100)
                    let p95 = String(format: "%.1f%%", boot.p95WinRate * 100)
                    let maxDD = String(format: "%.2f", boot.maxDrawdownWorstCase)
                    let posRate = String(format: "%.1f%%", boot.positiveEVRate * 100)
                    print("     └─ Bootstrap (500x): median=\(bootRate) (p5–p95: \(p5)–\(p95)), worst DD=\(maxDD) units, profitable runs=\(posRate).")
                }
            }
        }
        print("Descriptive proxy/synthetic labels. No profitable-edge certification; payout is assumed, not verified.")
    }
}

@main
struct ForwardTestApp {
    @MainActor static func main() async {
        do {
            let options = try Options(Array(CommandLine.arguments.dropFirst()))
            if options.help {
                print("ForwardTest [--edge-report --root DESK_PATH --as-of UNIX_SECONDS | --benchmark | --stats | --bootstrap | --replay | --experiment] [--root PATH] [--policy baseline|continuation|reversal|regime|control | --all-policies] [--max-events N] [--prime-only] [--continuous | --daemon]")
                return
            }
            let runner = ResearchRunner(options: options)
            if options.edgeReport { try await runner.printEdgeReport(); return }
            if options.experiment { try await runner.runExperiment(); return }
            if options.stats { try await runner.printStats(); return }
            if options.replay { try await runner.replay(); return }
            if options.synthetic { try await runner.runSynthetic(); return }
            guard EngineIdentity.bundleMatchesPin() else { throw ScanError.failed("Engine pin mismatch") }
            let gate = DeskCredentials.session(allowPrompt: !options.daemon)
            guard case .ready(let session) = gate else {
                throw ScanError.failed("OANDA Keychain session unavailable. Use --benchmark explicitly for isolated synthetic testing.")
            }
            try await runner.runLive(session: session)
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }
}
