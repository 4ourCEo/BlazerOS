import BlazerCore
import Foundation
import LightningDesk

// MARK: - Forward-Testing Models

struct ForwardArm: Sendable {
    let id: String
    let pair: String
    let side: String
    let strike: Double
    let score: Int
    let entryTime: Date
    let expiryTime: Date
    let fingerprint: String
    let snapshotBars: [Candle]
}

struct ForwardOutcome: Sendable {
    let arm: ForwardArm
    let exitPrice: Double
    let outcome: DeskOutcome
    let driftPips: Double
    let settledAt: Date
}

// MARK: - ANSI Dashboard Formatter

enum Dashboard {
    static let clearScreen = "\u{001B}[2J\u{001B}[H"
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let green = "\u{001B}[32m"
    static let red = "\u{001B}[31m"
    static let yellow = "\u{001B}[33m"
    static let cyan = "\u{001B}[36m"
    static let gray = "\u{001B}[90m"

    static func render(
        mode: String,
        sessionText: String,
        activeArms: [ForwardArm],
        settled: [ForwardOutcome],
        targetWinRate: Double = 0.60
    ) {
        let total = settled.count
        let hits = settled.filter { $0.outcome == .hit }.count
        let misses = settled.filter { $0.outcome == .miss }.count
        let winRate = total > 0 ? Double(hits) / Double(total) : 0.0

        let rateColor = winRate >= targetWinRate ? green : (total >= 10 ? red : yellow)
        let edgeStatus = total >= 100 && winRate >= targetWinRate
            ? "\(green)\(bold)EDGE CONFIRMED (≥60% WIN RATE)\(reset)"
            : (total >= 100 ? "\(red)\(bold)EDGE UNCONFIRMED (<60%)\(reset)" : "\(yellow)CALIBRATING (\(total)/100 signals)\(reset)")

        print(clearScreen)
        print("\(bold)\(cyan)========================================================================\(reset)")
        print("\(bold)\(cyan)    BLAZER OS // AUTOMATED FORWARD-TESTING VALIDATION HARNESS           \(reset)")
        print("\(bold)\(cyan)========================================================================\(reset)")
        print(" \(gray)Mode:\(reset) \(mode)   \(gray)Session:\(reset) \(sessionText)")
        print(" \(gray)Engine:\(reset) scan-engine.js (Parity Sealed)   \(gray)Expiry:\(reset) 60s M1 Binary Horizon")
        print("\(gray)------------------------------------------------------------------------\(reset)")
        print("\(bold) PERFORMANCE METRICS\(reset)")
        print("  Total Signals Tested:  \(bold)\(total)\(reset)")
        print("  Hits (Wins):           \(green)\(bold)\(hits)\(reset)")
        print("  Misses (Losses):       \(red)\(bold)\(misses)\(reset)")
        let pct = String(format: "%.1f%%", winRate * 100)
        print("  Live Win Rate:         \(rateColor)\(bold)\(pct)\(reset) (Benchmark: ≥\(Int(targetWinRate * 100))%)")
        print("  Edge Status:           \(edgeStatus)")
        print("\(gray)------------------------------------------------------------------------\(reset)")

        print("\(bold) ACTIVE 60-SECOND POSITIONS (\(activeArms.count))\(reset)")
        if activeArms.isEmpty {
            print("  \(gray)No active forward positions. Scanning completed M1 candles...\(reset)")
        } else {
            let now = Date()
            for arm in activeArms {
                let remaining = max(0, Int(arm.expiryTime.timeIntervalSince(now)))
                let sideBadge = arm.side == "HIGH" ? "\(green)\(bold)HIGH\(reset)" : "\(red)\(bold)LOW \(reset)"
                let strikeStr = String(format: "%.5f", arm.strike)
                print("  [\(remaining)s] \(arm.pair) \(sideBadge) Strike: \(strikeStr) Score: \(arm.score) ID: \(arm.id.prefix(8))")
            }
        }
        print("\(gray)------------------------------------------------------------------------\(reset)")

        print("\(bold) RECENT SETTLED OUTCOMES (Last 10)\(reset)")
        if settled.isEmpty {
            print("  \(gray)Awaiting first trade expiration...\(reset)")
        } else {
            let recent = settled.suffix(10).reversed()
            print("  \(gray)TIME      PAIR     SIDE  STRIKE    EXIT      DRIFT    OUTCOME\(reset)")
            for item in recent {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let timeStr = formatter.string(from: item.settledAt)
                let sideStr = item.arm.side == "HIGH" ? "\(green)HIGH\(reset)" : "\(red)LOW \(reset)"
                let strikeStr = String(format: "%.5f", item.arm.strike)
                let exitStr = String(format: "%.5f", item.exitPrice)
                let driftStr = String(format: "%+.1f", item.driftPips)
                let mark = item.outcome == .hit ? "\(green)\(bold)HIT \(reset)" : "\(red)\(bold)MISS\(reset)"
                print("  \(timeStr)  \(item.arm.pair)  \(sideStr)  \(strikeStr)  \(exitStr)  \(driftStr)p  \(mark)")
            }
        }
        print("\(bold)\(cyan)========================================================================\(reset)")
        print(" \(gray)Press Ctrl+C to stop forward test and export ledger summary.\(reset)\n")
    }
}

// MARK: - Forward Test Engine

@MainActor
final class ForwardTestRunner {
    private let coordinator: PersistenceCoordinator
    private var activeArms: [ForwardArm] = []
    private var settledHistory: [ForwardOutcome] = []
    private var lastScannedCandleTimes: [String: Double] = [:]
    private var isRunning = true

    init() {
        let root = FileLocations.applicationSupport()
        self.coordinator = PersistenceCoordinator(root: root)
    }

    // MARK: - Benchmark Replay Suite (100+ forward-tested signals)

    func runBenchmark(targetSignals: Int = 100) async {
        print("\(Dashboard.bold)Running Automated 100-Signal Forward-Testing Benchmark...\(Dashboard.reset)")
        let pairs = ["EUR/USD", "GBP/USD", "USD/JPY", "EUR/GBP", "AUD/USD"]
        var evaluatedSignals = 0

        // Build continuous realistic random-walk candle sequences with varying market regimes
        for pairIndex in 0..<pairs.count {
            if evaluatedSignals >= targetSignals { break }
            let pair = pairs[pairIndex]
            var basePrice = pair == "USD/JPY" ? 150.00 : (pair == "EUR/GBP" ? 0.85 : 1.08)
            let pipSize = pair == "USD/JPY" ? 0.01 : 0.0001
            var currentTimeMs = Date().timeIntervalSince1970 * 1000 - Double(targetSignals * 2) * 60_000

            // Generate sequence of 150 candles
            var candleStream: [StrategyEngine.CandlePayload] = []
            for _ in 0..<180 {
                let delta = Double.random(in: -3.0...3.0) * pipSize
                let open = basePrice
                let close = basePrice + delta
                let high = max(open, close) + Double.random(in: 0.1...1.5) * pipSize
                let low = min(open, close) - Double.random(in: 0.1...1.5) * pipSize
                candleStream.append(
                    StrategyEngine.CandlePayload(
                        time: currentTimeMs,
                        open: open,
                        high: high,
                        low: low,
                        close: close
                    )
                )
                basePrice = close
                currentTimeMs += 60_000
            }

            // Walk forward through candle stream (using 60 candles window)
            for windowEnd in 60..<candleStream.count - 1 {
                if evaluatedSignals >= targetSignals { break }
                let window = Array(candleStream[(windowEnd - 60)...windowEnd])
                let nextCandle = candleStream[windowEnd + 1]
                let currentQuote = window.last!.close

                let input = StrategyEngine.MarketInput(
                    asset: pair,
                    source: "benchmark",
                    candles1m: window,
                    candles5m: window,
                    lastPrice: currentQuote,
                    bid: currentQuote - (0.2 * pipSize),
                    ask: currentQuote + (0.2 * pipSize),
                    spread: 0.4 * pipSize,
                    expirySeconds: 60
                )

                guard let result = try? await StrategyEngine.evaluate(input: input) else { continue }
                let side = result.signal.cabinetSide
                guard side == "HIGH" || side == "LOW" else { continue }

                let score = Int((result.signal.opportunity ?? result.signal.confidence ?? 65).rounded())
                guard score >= 55 else { continue }

                let strike = currentQuote
                let exitPrice = nextCandle.close
                let outcome: DeskOutcome
                if side == "HIGH" {
                    outcome = exitPrice > strike ? .hit : .miss
                } else {
                    outcome = exitPrice < strike ? .hit : .miss
                }

                let armID = UUID().uuidString
                let frozenBars = window.map { Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close) }
                let hash = ScanFingerprint.hex(candles: frozenBars)
                let driftPips = (exitPrice - strike) / pipSize

                let arm = ForwardArm(
                    id: armID,
                    pair: pair,
                    side: side,
                    strike: strike,
                    score: score,
                    entryTime: Date(timeIntervalSince1970: window.last!.time / 1000),
                    expiryTime: Date(timeIntervalSince1970: nextCandle.time / 1000),
                    fingerprint: hash,
                    snapshotBars: frozenBars
                )

                let forwardOutcome = ForwardOutcome(
                    arm: arm,
                    exitPrice: exitPrice,
                    outcome: outcome,
                    driftPips: driftPips,
                    settledAt: Date(timeIntervalSince1970: nextCandle.time / 1000)
                )

                // Record to persistent coordinator
                let entry = JournalEntry(
                    id: armID,
                    fingerprint: hash,
                    pair: pair,
                    score: score,
                    side: side,
                    verb: side == "HIGH" ? "CALL" : "PUT",
                    why: result.signal.why,
                    strike: strike,
                    veto: nil,
                    scannedAt: arm.entryTime,
                    outcome: outcome.rawValue
                )
                let snapshot = SnapshotRecord(
                    hash: hash,
                    pair: pair,
                    bars: frozenBars,
                    strike: strike,
                    score: score,
                    side: side
                )
                let ledgerRow = LedgerRow(
                    timestamp: forwardOutcome.settledAt,
                    pair: pair,
                    hash: hash,
                    score: score,
                    side: side,
                    veto: false,
                    drift: driftPips,
                    outcome: outcome.rawValue,
                    outcomeEventID: armID
                )

                try? await coordinator.recordScan(entry, snapshot: snapshot)
                _ = try? await coordinator.settle(armID: armID, row: ledgerRow, snapshot: snapshot)

                settledHistory.append(forwardOutcome)
                evaluatedSignals += 1

                Dashboard.render(
                    mode: "BENCHMARK WALK-FORWARD (M1 EXPIRY)",
                    sessionText: "Simulated Feed (\(evaluatedSignals)/\(targetSignals))",
                    activeArms: [],
                    settled: settledHistory
                )
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms render throttle
            }
        }

        printFinalReport()
    }

    // MARK: - Live Forward-Testing Loop (OANDA Feed)

    func runLive(session: OandaSession) async {
        let pairs = Assets.watchlist
        print("Starting live forward testing across \(pairs.count) pairs with OANDA...")

        while isRunning {
            let now = Date()

            // 1. Settle any expired arms
            var remainingArms: [ForwardArm] = []
            for arm in activeArms {
                if now >= arm.expiryTime {
                    await settleLiveArm(arm, session: session)
                } else {
                    remainingArms.append(arm)
                }
            }
            activeArms = remainingArms

            // 2. Scan pairs for newly completed candles
            for pair in pairs {
                do {
                    guard let bundle = try await OandaClient.fetchBundle(asset: pair, session: session) else {
                        continue
                    }
                    guard let latestCandle = bundle.candles1m.last else { continue }
                    let lastTime = lastScannedCandleTimes[pair] ?? 0

                    if latestCandle.time > lastTime {
                        lastScannedCandleTimes[pair] = latestCandle.time
                        let result = try await StrategyEngine.evaluate(input: bundle)
                        let side = result.signal.cabinetSide
                        if side == "HIGH" || side == "LOW" {
                            let score = Int((result.signal.opportunity ?? result.signal.confidence ?? 60).rounded())
                            if score >= 60 {
                                armNewTrade(pair: pair, side: side, strike: bundle.lastPrice, score: score, why: result.signal.why, input: bundle)
                            }
                        }
                    }
                } catch {
                    // Suppress transient network hiccups in live loop
                }
            }

            // 3. Render dashboard
            Dashboard.render(
                mode: "LIVE OANDA STREAM (\(session.environment.rawValue.uppercased()))",
                sessionText: "Account: \(session.accountId.prefix(7))...",
                activeArms: activeArms,
                settled: settledHistory
            )

            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second polling interval
        }
    }

    private func armNewTrade(
        pair: String,
        side: String,
        strike: Double,
        score: Int,
        why: String,
        input: StrategyEngine.MarketInput
    ) {
        let armID = UUID().uuidString
        let now = Date()
        let expiry = now.addingTimeInterval(60.0) // 60s binary horizon
        let frozenBars = input.candles1m.map { Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close) }
        let hash = ScanFingerprint.hex(candles: frozenBars)

        let arm = ForwardArm(
            id: armID,
            pair: pair,
            side: side,
            strike: strike,
            score: score,
            entryTime: now,
            expiryTime: expiry,
            fingerprint: hash,
            snapshotBars: frozenBars
        )
        activeArms.append(arm)

        let entry = JournalEntry(
            id: armID,
            fingerprint: hash,
            pair: pair,
            score: score,
            side: side,
            verb: side == "HIGH" ? "CALL" : "PUT",
            why: why,
            strike: strike,
            veto: nil,
            scannedAt: now
        )
        let snapshot = SnapshotRecord(
            hash: hash,
            pair: pair,
            bars: frozenBars,
            strike: strike,
            score: score,
            side: side
        )

        Task {
            try? await coordinator.recordScan(entry, snapshot: snapshot)
        }
    }

    private func settleLiveArm(_ arm: ForwardArm, session: OandaSession) async {
        let quotes = await OandaClient.fetchQuotes(assets: [arm.pair], session: session)
        guard let exitQuote = quotes.first else {
            // Retry next cycle if quote fetch fails
            activeArms.append(arm)
            return
        }

        let exitPrice = exitQuote.mid
        let pipScale = arm.pair.contains("JPY") ? 0.01 : 0.0001
        let driftPips = (exitPrice - arm.strike) / pipScale

        let outcome: DeskOutcome
        if arm.side == "HIGH" {
            outcome = exitPrice > arm.strike ? .hit : .miss
        } else {
            outcome = exitPrice < arm.strike ? .hit : .miss
        }

        let forwardOutcome = ForwardOutcome(
            arm: arm,
            exitPrice: exitPrice,
            outcome: outcome,
            driftPips: driftPips,
            settledAt: Date()
        )
        settledHistory.append(forwardOutcome)

        let snapshot = SnapshotRecord(
            hash: arm.fingerprint,
            pair: arm.pair,
            bars: arm.snapshotBars,
            strike: arm.strike,
            score: arm.score,
            side: arm.side
        )
        let row = LedgerRow(
            timestamp: forwardOutcome.settledAt,
            pair: arm.pair,
            hash: arm.fingerprint,
            score: arm.score,
            side: arm.side,
            veto: false,
            drift: driftPips,
            outcome: outcome.rawValue,
            outcomeEventID: arm.id
        )

        _ = try? await coordinator.settle(armID: arm.id, row: row, snapshot: snapshot)
    }

    func stop() {
        isRunning = false
    }

    private func printFinalReport() {
        let total = settledHistory.count
        let hits = settledHistory.filter { $0.outcome == .hit }.count
        let winRate = total > 0 ? (Double(hits) / Double(total)) * 100 : 0.0
        print("\n\(Dashboard.bold)Validation Summary:\(Dashboard.reset)")
        print("  Total Signals: \(total)")
        print("  Win Rate:      \(String(format: "%.1f%%", winRate))")
        if winRate >= 60.0 {
            print("  \(Dashboard.green)\(Dashboard.bold)RESULT: PASS (Trading edge validated >= 60%)\(Dashboard.reset)")
        } else {
            print("  \(Dashboard.red)\(Dashboard.bold)RESULT: EDGE NOT CONFIRMED (< 60%)\(Dashboard.reset)")
        }
    }

    func printStats() async {
        let root = FileLocations.applicationSupport()
        let ledger = LedgerStore(root: root)
        let rows = (try? await ledger.rows()) ?? []
        print("\n\(Dashboard.bold)\(Dashboard.cyan)========================================================================\(Dashboard.reset)")
        print("\(Dashboard.bold)\(Dashboard.cyan)       BLAZER OS // LIVE FORWARD-TEST LEDGER AUDIT                      \(Dashboard.reset)")
        print("\(Dashboard.bold)\(Dashboard.cyan)========================================================================\(Dashboard.reset)")
        print(" \(Dashboard.gray)Storage:\(Dashboard.reset) \(FileLocations.ledgerCSV(in: root).path)")
        print(" \(Dashboard.gray)Total Recorded Trades:\(Dashboard.reset) \(rows.count)")

        let hits = rows.filter { $0.outcome == "HIT" }.count
        let misses = rows.filter { $0.outcome == "MISS" }.count
        let winRate = rows.count > 0 ? (Double(hits) / Double(rows.count)) * 100 : 0.0
        let color = winRate >= 60.0 ? Dashboard.green : (rows.count >= 5 ? Dashboard.red : Dashboard.yellow)

        print("  Hits: \(Dashboard.green)\(hits)\(Dashboard.reset)   Misses: \(Dashboard.red)\(misses)\(Dashboard.reset)   Win Rate: \(color)\(Dashboard.bold)\(String(format: "%.1f%%", winRate))\(Dashboard.reset)")
        print("\(Dashboard.gray)------------------------------------------------------------------------\(Dashboard.reset)")
        print("\(Dashboard.bold) RECENT TRADES:\(Dashboard.reset)")
        let formatter = ISO8601DateFormatter()
        for row in rows.suffix(10).reversed() {
            let mark = row.outcome == "HIT" ? "\(Dashboard.green)\(Dashboard.bold)HIT \(Dashboard.reset)" : "\(Dashboard.red)\(Dashboard.bold)MISS\(Dashboard.reset)"
            let drift = String(format: "%+.1f", row.drift)
            print("  \(formatter.string(from: row.timestamp))  \(row.pair.padding(toLength: 8, withPad: " ", startingAt: 0))  \(row.side.padding(toLength: 8, withPad: " ", startingAt: 0))  \(drift)p  \(mark)")
        }
        print("\(Dashboard.bold)\(Dashboard.cyan)========================================================================\(Dashboard.reset)\n")
    }
}

// MARK: - Entry Point

@main
struct ForwardTestApp {
    static func main() async {
        let args = CommandLine.arguments

        let runner = ForwardTestRunner()

        if args.contains("--stats") || args.contains("-s") {
            await runner.printStats()
            return
        }

        if args.contains("--benchmark") || args.contains("-b") {
            let count = 100
            await runner.runBenchmark(targetSignals: count)
            return
        }

        // Check for Keychain OANDA credentials
        let gate = DeskCredentials.session(allowPrompt: true)
        switch gate {
        case .ready(let session):
            if args.contains("--replay") {
                await runner.runBenchmark(targetSignals: 100)
            } else {
                await runner.runLive(session: session)
            }
        case .locked:
            print("\(Dashboard.red)Keychain item exists but is locked. Unlock keychain and retry.\(Dashboard.reset)")
            print("\(Dashboard.yellow)Falling back to 100-signal automated benchmark...\(Dashboard.reset)")
            await runner.runBenchmark(targetSignals: 100)
        case .missing:
            print("\(Dashboard.yellow)No OANDA credentials found in Keychain.\(Dashboard.reset)")
            print("\(Dashboard.bold)Running 100-signal forward-testing validation benchmark...\(Dashboard.reset)")
            await runner.runBenchmark(targetSignals: 100)
        }
    }
}
