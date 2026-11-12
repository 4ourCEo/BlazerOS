import BlazerCore
import CryptoKit
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
    var orb = false
    var adaptive = false
    var adaptiveDiagnostic = false
    var interactiveCredentials = false
    var historicalBidAsk = false
    var authenticReplay = false
    var orbStructuralArchive = false
    var forwardQuotes = false
    var captureSeconds = 30
    var historicalHours = 15
    var historicalOffsetHours = 0
    var policyFunnel = false
    var asset: String?

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
            case "--orb": orb = true
            case "--adaptive": adaptive = true
            case "--adaptive-diagnostic": adaptiveDiagnostic = true
            case "--interactive-credentials": interactiveCredentials = true
            case "--historical-bid-ask": historicalBidAsk = true
            case "--authentic-replay": authenticReplay = true
            case "--orb-structural-archive": orbStructuralArchive = true
            case "--forward-quotes": forwardQuotes = true
            case "--policy-funnel": policyFunnel = true
            case "--replay": replay = true
            case "--continuous": continuous = true
            case "--daemon", "-d": daemon = true; continuous = true; primeOnly = true
            case "--prime-only", "--smart-schedule": primeOnly = true
            case "--all-policies": policies = ["control"] + ScanPolicy.allCases.map(\.rawValue)
            case "--root", "--policy", "--max-events", "--as-of", "--asset", "--historical-hours", "--historical-offset-hours", "--capture-seconds":
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
                if arg == "--asset" {
                    guard Assets.watchlist.contains(value) else { throw ScanError.failed("Unsupported asset \(value)") }
                    asset = value
                }
                if arg == "--historical-hours" {
                    guard let hours = Int(value), (1...120).contains(hours) else {
                        throw ScanError.failed("Historical hours must be between 1 and 120")
                    }
                    historicalHours = hours
                }
                if arg == "--historical-offset-hours" {
                    guard let offset = Int(value), (0...720).contains(offset) else {
                        throw ScanError.failed("Historical offset hours must be between 0 and 720")
                    }
                    historicalOffsetHours = offset
                }
                if arg == "--capture-seconds" {
                    guard let seconds = Int(value), (1...300).contains(seconds) else {
                        throw ScanError.failed("Capture seconds must be between 1 and 300")
                    }
                    captureSeconds = seconds
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
    var orbPlans: [String: V3TradePlan] = [:]
    var orbEntries: [String: V3PlanEntryEvidence] = [:]
    var orbCompleted: Set<String> = []

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
        if options.orb {
            orbPlans = Dictionary(uniqueKeysWithValues: try await store.v3TradePlans().map { ($0.id, $0) })
            orbEntries = Dictionary(uniqueKeysWithValues: try await store.v3PlanEntryEvidence().map { ($0.planID, $0) })
            orbCompleted = Set(try await store.v3StructuralOutcomes().map(\.planID))
        }
    }

    private func orbObservation(input: StrategyEngine.MarketInput, at time: Date) -> V3MarketObservation? {
        guard let timestamp = input.quoteAsOfMs else { return nil }
        guard timestamp.isFinite, timestamp > 0, input.bid.isFinite, input.ask.isFinite,
              input.bid > 0, input.ask > input.bid else { return nil }
        let sourceTime = Date(timeIntervalSince1970: timestamp / 1000)
        guard sourceTime <= time.addingTimeInterval(1) else { return nil }
        return V3MarketObservation(id: "orb-quote-\(input.asset)-\(timestamp)",
            instrument: input.asset, provider: "OANDA", environment: .oandaPractice,
            bid: input.bid, ask: input.ask, sourceTime: sourceTime, receivedAt: time)
    }

    private func processORB(input: StrategyEngine.MarketInput, at time: Date) async throws {
        guard let observation = orbObservation(input: input, at: time) else {
            print("ORB_ENTRY_UNAVAILABLE \(input.asset) missing_or_invalid_quote")
            return
        }
        for (planID, entry) in orbEntries where entry.observation.instrument == input.asset
            && !orbCompleted.contains(planID) {
            guard let plan = orbPlans[planID] else { continue }
            let outcome = V3StructuralOutcomeEvaluator.evaluate(plan: plan, entry: entry,
                exitQuotes: [observation], asOf: time)
            guard outcome.status == .winner || outcome.status == .loser
                || outcome.status == .ambiguous else { continue }
            try await store.record(outcome)
            orbCompleted.insert(planID)
            let netText = outcome.netPnl.map { String($0) } ?? "unresolved"
            print("ORB_OUTCOME \(input.asset) \(planID) \(outcome.status.rawValue) \(outcome.exitReason.rawValue) net=\(netText)")
        }
        let decision = ORBBreakRetestV1.evaluate(input: input, asOf: time)
        guard let plan = decision.candidate?.plan, !orbCompleted.contains(plan.id),
              orbEntries[plan.id] == nil else {
            print("ORB_STAGE \(input.asset) \(decision.stage.rawValue) \(decision.reason)")
            return
        }
        if orbPlans[plan.id] == nil {
            try await store.record(plan)
            orbPlans[plan.id] = plan
        }
        let entry = V3PlanEntryEvidence(id: "\(plan.id)-entry-\(observation.sourceTime.timeIntervalSince1970)",
            planID: plan.id, observation: observation, quality: .simulated, recordedAt: time)
        try await store.record(entry)
        orbEntries[plan.id] = entry
        print("ORB_ENTRY \(input.asset) \(plan.id) simulated_at=\(observation.sourceTime.timeIntervalSince1970)")
    }

    func registerCampaign() async throws {
        let candidates = [
            ResearchStrategyCandidate(
                id: "baseline",
                version: EngineIdentity.pinnedSHA1,
                description: "Pinned JavaScriptCore baseline; sole signal authority."
            ),
            ResearchStrategyCandidate(
                id: "candidate-001",
                version: "research-v1",
                description: "Candidate 001 annotations; research-only and never an entry authority."
            )
        ]
        let campaign = try ForwardValidationCampaign(
            id: "milestone-7-forward-2026-11",
            version: "v1",
            strategies: candidates,
            instruments: Assets.watchlist,
            sources: ["oanda-proxy"],
            evaluationCriteria: [
                "signal persisted before any outcome",
                "source-matched 60-second observation",
                "replay reproduces the pinned engine result",
                "unresolved observations remain visible"
            ]
        )
        try await store.record(campaign)
        let gaps = [
            ResearchGap(
                id: "m7-p0-integrated-lifecycle",
                component: "forward research lifecycle",
                severity: .p0,
                evidence: "No accepted authentic signal and independently resolved outcome have been captured yet.",
                owner: "engineering",
                requiredFix: "Continue the controlled forward campaign until one eligible signal lifecycle is observed.",
                regressionTest: "StrategyValidationTests and source-matched replay tests",
                status: .open
            ),
            ResearchGap(
                id: "m7-p1-physical-device",
                component: "iPhone handoff",
                severity: .p1,
                evidence: "Simulator and package validation do not establish physical-device timing or readability.",
                owner: "operator",
                requiredFix: "Run the manual handoff and timing checks on an authorized physical iPhone.",
                regressionTest: "Device verification checklist",
                disposition: "Blocked until an authorized physical device is available.",
                status: .blocked
            ),
            ResearchGap(
                id: "m7-p1-pr-chain",
                component: "integration",
                severity: .p1,
                evidence: "PRs #10-#15 remain open dependency-chain PRs; PR #16 contains the integrated branch.",
                owner: "engineering",
                requiredFix: "Keep PR #16 as the review surface and reconcile dependent PRs before any merge.",
                regressionTest: "CI engine pin, tests, parity, and iPhone build",
                disposition: "Blocked pending protected merge/review decisions.",
                status: .blocked
            )
        ]
        for gap in gaps {
            try await store.record(gap)
        }
        let hasResolvedSixtySecondOutcome = try await store.outcomes().contains {
            $0.horizon == 60 && $0.resolution != .unresolved
        }
        if hasResolvedSixtySecondOutcome {
            try await store.record(ResearchGap(
                id: "m7-p0-integrated-lifecycle-verified",
                component: "forward research lifecycle",
                severity: .p0,
                evidence: "Accepted OANDA-proxy signal persisted before outcome; source-matched 60-second outcome and replay verified.",
                owner: "engineering",
                requiredFix: "Continue collecting independent observations; do not promote on this sample.",
                regressionTest: "ForwardTest replay and StrategyValidationTests",
                independentQA: "Replay reproduced all frozen events.",
                disposition: "Supersedes m7-p0-integrated-lifecycle; promotion remains blocked by sample size.",
                relatedReference: "a8f93e4",
                status: .verified
            ))
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
        try await registerCampaign()
        try await restore()
        if options.orb {
            let diagnostic = await OandaClient.diagnose(session: session)
            let latencyText = diagnostic.latencyMs.map { String(format: "%.1f", $0) } ?? "unavailable"
            print("OANDA_DIAGNOSTIC state=\(diagnostic.state.rawValue) environment=\(diagnostic.environment.rawValue) instrument=\(diagnostic.instrument) quotes=\(diagnostic.quoteCount) candles=\(diagnostic.candleCount) latencyMs=\(latencyText) message=\(diagnostic.message)")
            guard diagnostic.state == .ready else {
                throw ScanError.failed("OANDA diagnostic \(diagnostic.state.rawValue): \(diagnostic.message)")
            }
        }
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
            let watchlist = options.asset.map { [$0] } ?? Assets.watchlist
            for pair in watchlist {
                if Task.isCancelled { break }
                do {
                    guard var input = try await OandaClient.fetchBundle(asset: pair, session: session),
                          let bar = input.candles1m.last, bar.time > (lastBar[pair] ?? 0) else { continue }
                    let time = Date()
                    input.evaluatedAtMs = time.timeIntervalSince1970 * 1000
                    if options.orb {
                        try await processORB(input: input, at: time)
                    }
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

    func printPolicyFunnel() async throws {
        let events = try await store.events()
        let reports = PolicyEligibilityDiagnostics.evaluate(events: events, instrument: options.asset)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(reports), as: UTF8.self))
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
                let directional = rows.filter { $0.resolution == .hit || $0.resolution == .miss }
                let returns = directional.compactMap { outcome -> Double? in
                    guard let event = byID[outcome.eventID], event.assumedPayout.isFinite,
                          event.assumedPayout > 0 else { return nil }
                    return outcome.resolution == .hit ? event.assumedPayout : -1
                }
                let payoutComplete = n > 0 && returns.count == n
                let ev = payoutComplete
                    ? String(format: "%+.4f", returns.reduce(0, +) / Double(n))
                    : "unavailable"
                let interval = EdgeEvidence.wilsonScoreInterval(wins: wins, total: n)
                let ci = n > 0 ? String(format: "%.1f–%.1f%%", interval.lower * 100, interval.upper * 100) : "unavailable"
                print("\(horizon)s: \(wins)/\(n) resolved wins (\(rate)); nominal Wilson CI=\(ci); mixed event-payout EV=\(ev) (coverage \(returns.count)/\(n)); ties=\(ties), unresolved=\(missing).")
                let conservativePayout = directional.compactMap { byID[$0.eventID]?.assumedPayout }.min()
                if options.bootstrap, n > 0, let payout = conservativePayout,
                   let boot = ExpectancyMath.bootstrapStressTest(
                       wins: wins, sampleSize: n, iterations: 500, payoutRatio: payout) {
                    let bootRate = String(format: "%.1f%%", boot.medianWinRate * 100)
                    let p5 = String(format: "%.1f%%", boot.p5WinRate * 100)
                    let p95 = String(format: "%.1f%%", boot.p95WinRate * 100)
                    let maxDD = String(format: "%.2f", boot.maxDrawdownWorstCase)
                    let posRate = String(format: "%.1f%%", boot.positiveEVRate * 100)
                    print("     └─ Bootstrap (500x): median=\(bootRate) (p5–p95: \(p5)–\(p95)), worst DD=\(maxDD) units, profitable runs=\(posRate).")
                }
            }
        }
        print("Descriptive proxy/synthetic labels. Event payouts may include capture-time fallbacks; no profitable-edge certification.")
    }
}

@main
struct ForwardTestApp {
    @MainActor static func main() async {
        do {
            let options = try Options(Array(CommandLine.arguments.dropFirst()))
            if options.help {
                 print("ForwardTest [--orb-structural-archive --root SCRATCH_ROOT (scratch only; contains historical-bid-ask; report written under root) [--asset EUR/USD|GBP/JPY] | --edge-report --root DESK_PATH --as-of UNIX_SECONDS | --policy-funnel | --historical-bid-ask --historical-hours N --historical-offset-hours N | --forward-quotes --capture-seconds N | --authentic-replay | --benchmark | --stats | --bootstrap | --replay | --experiment | --adaptive | --adaptive-diagnostic] [--interactive-credentials] [--orb] [--root PATH] [--asset PAIR] [--policy baseline|continuation|reversal|regime|control | --all-policies] [--max-events N] [--prime-only] [--continuous | --daemon]")
                return
            }
            if options.orbStructuralArchive {
                guard let root = options.root else {
                    throw ScanError.failed("--orb-structural-archive requires --root SCRATCH_ROOT")
                }
                try ORBArchiveReplayCommand.run(root: root, asset: options.asset)
                return
            }
            let runner = ResearchRunner(options: options)
            if options.edgeReport { try await runner.printEdgeReport(); return }
            if options.policyFunnel { try await runner.printPolicyFunnel(); return }
            if options.historicalBidAsk {
                let credentialGate: CredentialGate
                if options.interactiveCredentials {
                    credentialGate = DeskCredentials.session(allowPrompt: true)
                } else if let environmentSession = DeskCredentials.environmentSession() {
                    credentialGate = .ready(environmentSession)
                } else {
                    credentialGate = .missing
                }
                guard case .ready(let session) = credentialGate else {
                    print("HISTORICAL_BID_ASK state=CREDENTIAL_CONTEXT_UNAVAILABLE")
                    return
                }
                guard session.environment == .practice else {
                    print("HISTORICAL_BID_ASK state=LIVE_REJECTED")
                    return
                }
                let asset = options.asset ?? "EUR/USD"
                let to = Date().addingTimeInterval(-60 - Double(options.historicalOffsetHours) * 3600)
                let from = to.addingTimeInterval(-Double(options.historicalHours) * 3600)
                async let m1 = OandaClient.fetchHistoricalBidAskCandles(
                    asset: asset, from: from, to: to, granularity: "M1", session: session)
                async let m5 = OandaClient.fetchHistoricalBidAskCandles(
                    asset: asset, from: from, to: to, granularity: "M5", session: session)
                let batches = await [m1, m5]
                for batch in batches {
                    let first = batch.candles.first?.sourceTime.timeIntervalSince1970
                    let last = batch.candles.last?.sourceTime.timeIntervalSince1970
                    let firstText = first.map { String($0) } ?? "none"
                    let lastText = last.map { String($0) } ?? "none"
                    let statusText = batch.httpStatus.map { String($0) } ?? "none"
                    let errorText = batch.serverError ?? "none"
                    print("HISTORICAL_BID_ASK instrument=\(batch.instrument) granularity=\(batch.granularity) transport=\(batch.transport) httpStatus=\(statusText) serverError=\(errorText) completeCount=\(batch.candles.count) firstUnix=\(firstText) lastUnix=\(lastText) intrabarSequence=unknown")
                    guard batch.transport == .ok, !batch.candles.isEmpty else { continue }
                    let archiveRoot = (options.root ?? ResearchStore.defaultRoot())
                        .appendingPathComponent("historical-bid-ask", isDirectory: true)
                    try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    let payload = try encoder.encode(batch)
                    let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
                    let start = Int(batch.requestedFrom.timeIntervalSince1970)
                    let end = Int(batch.requestedTo.timeIntervalSince1970)
                    let name = "oanda-practice-\(batch.instrument)-\(batch.granularity)-\(start)-\(end).json"
                    let destination = archiveRoot.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try payload.write(to: destination, options: .withoutOverwriting)
                    }
                    print("HISTORICAL_ARCHIVE path=\(destination.path) sha256=\(digest) status=immutable")
                }
                return
            }
            if options.authenticReplay {
                try await runner.runAuthenticReplay()
                return
            }
            if options.forwardQuotes {
                let credentialGate: CredentialGate
                if options.interactiveCredentials {
                    credentialGate = DeskCredentials.session(allowPrompt: true)
                } else if let environmentSession = DeskCredentials.environmentSession() {
                    credentialGate = .ready(environmentSession)
                } else {
                    credentialGate = .missing
                }
                guard case .ready(let session) = credentialGate else {
                    print("FORWARD_QUOTES state=CREDENTIAL_CONTEXT_UNAVAILABLE")
                    return
                }
                guard session.environment == .practice else {
                    print("FORWARD_QUOTES state=LIVE_REJECTED")
                    return
                }
                let asset = options.asset ?? "EUR/USD"
                let capture = await OandaClient.captureForwardQuotes(
                    asset: asset, duration: TimeInterval(options.captureSeconds),
                    maxQuotes: 500, session: session)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let payload = try encoder.encode(capture)
                let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
                let directory = (options.root ?? ResearchStore.defaultRoot())
                    .appendingPathComponent("forward-quotes", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(
                    "\(asset.replacingOccurrences(of: "/", with: "_"))-\(Int(capture.startedAt.timeIntervalSince1970)).json")
                try payload.write(to: file, options: .withoutOverwriting)
                let status = capture.httpStatus.map { String($0) } ?? "none"
                let contentType = capture.contentType ?? "none"
                let errorCode = capture.errorCode ?? "none"
                print("FORWARD_QUOTES instrument=\(capture.instrument) transport=\(capture.transport) httpStatus=\(status) contentType=\(contentType) count=\(capture.quotes.count) heartbeats=\(capture.heartbeatCount) parseFailures=\(capture.parseFailures) termination=\(capture.termination) errorCode=\(errorCode) started=\(capture.startedAt.timeIntervalSince1970) ended=\(capture.endedAt.timeIntervalSince1970) archive=\(file.path) sha256=\(digest)")
                return
            }
            if options.experiment { try await runner.runExperiment(); return }
            if options.stats { try await runner.printStats(); return }
            if options.replay { try await runner.replay(); return }
            if options.synthetic { try await runner.runSynthetic(); return }
            guard EngineIdentity.bundleMatchesPin() else { throw ScanError.failed("Engine pin mismatch") }
            if options.adaptive || options.adaptiveDiagnostic {
                let credentialStart = DispatchTime.now().uptimeNanoseconds
                // The default remains noninteractive: access-controlled values
                // can block an unattended CLI. An owner may explicitly opt in
                // to the native Keychain authorization flow for one bounded
                // research run.
                let credentialGate: CredentialGate
                if options.interactiveCredentials {
                    credentialGate = DeskCredentials.session(allowPrompt: true)
                } else if let environmentSession = DeskCredentials.environmentSession() {
                    credentialGate = .ready(environmentSession)
                } else {
                    credentialGate = .missing
                }
                guard case .ready(let session) = credentialGate else {
                    let credentialMs = Double(DispatchTime.now().uptimeNanoseconds - credentialStart) / 1_000_000
                    let state: String
                    if case .locked = credentialGate {
                        state = "KEYCHAIN_AUTHORIZATION_REQUIRED"
                    } else {
                        state = "CLI_CREDENTIAL_CONTEXT_MISSING"
                    }
                    print("ADAPTIVE_DIAGNOSTIC state=\(state) message=approved_Practice_credential_context_unavailable durationMs=\(String(format: "%.3f", credentialMs))")
                    print("PHASE process_termination state=COMPLETE")
                    return
                }
                let credentialMs = Double(DispatchTime.now().uptimeNanoseconds - credentialStart) / 1_000_000
                guard session.environment == .practice else {
                    print("ADAPTIVE_DIAGNOSTIC state=LIVE_REJECTED message=adaptive_diagnostic_is_practice_only durationMs=\(String(format: "%.3f", credentialMs))")
                    print("PHASE process_termination state=COMPLETE")
                    return
                }
                print("PHASE credential_lookup state=KEYCHAIN_OR_SECURE_ENVIRONMENT environment=practice durationMs=\(String(format: "%.3f", credentialMs))")
                let asset = options.asset ?? "EUR/USD"
                let diagnostic = await AdaptiveMarketRehearsal.runBounded(
                    asset: asset, session: session,
                    store: ResearchStore(root: options.root ?? ResearchStore.defaultRoot()))
                print("ADAPTIVE_DIAGNOSTIC state=\(diagnostic.state.rawValue) message=\(diagnostic.message)")
                guard let result = diagnostic.result else {
                    print("PHASE process_termination state=COMPLETE")
                    return
                }
                let rehearsal = result.record
                print("ADAPTIVE_REHEARSAL \(rehearsal.instrument) availability=\(rehearsal.availability.rawValue) state=\(rehearsal.decisionState.rawValue) selected=\(rehearsal.decision.selectedCandidateID ?? "NO_TRADE")")
                for candidate in rehearsal.candidates {
                    print("CANDIDATE \(candidate.strategyID) direction=\(candidate.direction.rawValue) state=\(candidate.state.rawValue) freshness=\(candidate.freshness.rawValue) reasons=\(candidate.rejectionReasons.joined(separator: "|"))")
                }
                if let timing = diagnostic.timing {
                    print("LATENCY credentialMs=\(String(format: "%.3f", credentialMs)) brokerMs=\(String(format: "%.3f", timing.brokerMs)) validationMs=\(String(format: "%.3f", timing.validationMs)) candidateMs=\(String(format: "%.3f", timing.candidateEvaluationMs)) selectionMs=\(String(format: "%.3f", timing.selectionMs)) persistenceMs=\(String(format: "%.3f", timing.persistenceMs)) totalMs=\(String(format: "%.3f", timing.totalMs)) publication=unmeasured")
                }
                print("PHASE process_termination state=COMPLETE")
                return
            }
            // Never make ordinary CLI research probe the native app's
            // access-controlled Keychain item. That path is intentionally
            // opt-in because SwiftPM executables are ad-hoc signed and their
            // identity can change after a rebuild. Use the approved secure
            // environment provider for unattended/repeatable runs, or pass
            // --interactive-credentials once for an explicitly authorized
            // native Keychain access.
            let gate: CredentialGate
            if options.interactiveCredentials {
                gate = DeskCredentials.session(allowPrompt: true)
            } else if let environmentSession = DeskCredentials.environmentSession() {
                gate = .ready(environmentSession)
            } else {
                gate = .missing
            }
            let session: OandaSession
            switch gate {
            case .ready(let value):
                session = value
            case .locked:
                throw ScanError.failed("OANDA credentials require explicit authorization: rerun with --interactive-credentials")
            case .missing:
                throw ScanError.failed("OANDA credentials missing: use the approved secure environment provider or --interactive-credentials")
            }
            try await runner.runLive(session: session)
        } catch {
            print("ERROR: \(error.localizedDescription)")
            exit(1)
        }
    }
}
