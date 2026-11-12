import BlazerCore
import CryptoKit
import Foundation

struct AuthenticReplaySummary: Codable {
    let instrument: String
    let sourceFiles: [String]
    let m1Candles: Int
    let m5Candles: Int
    let cases: Int
    let rejections: Int
    let strategyResults: [StrategyReplaySummary]
    let adaptive: StrategyReplaySummary
    let orb: ORBReplaySummary
    let delaySensitivity: [DelayReplaySummary]
    let costSensitivity: [CostReplaySummary]
    let chronologicalHoldout: HoldoutReplaySummary
}

struct ORBReplaySummary: Codable {
    let rawSetupSignals: Int
    let uniquePlans: Int
    let executableNonOverlappingPlans: Int
    let winners: Int
    let losers: Int
    let ambiguous: Int
    let untriggered: Int
    let unresolved: Int
    let netPnlPriceUnits: Double
    let netR: Double?
    let ambiguityExclusionNetR: Double?
    let ambiguityStopFirstNetR: Double?
    let ambiguityTargetFirstNetR: Double?
    let caveat: String
}

struct StrategyReplaySummary: Codable {
    let strategy: String
    let observations: Int
    let rawDirectionalSignals: Int
    let validTrades: Int
    let executableNonOverlappingTrades: Int
    let profitable: Int
    let unprofitable: Int
    let unresolved: Int
    let netPnlPriceUnits: Double
    let nonOverlappingNetPnlPriceUnits: Double
    let averageNetPnlPriceUnits: Double?
    let caveat: String
}

struct DelayReplaySummary: Codable {
    let entryDelaySeconds: Double
    let validTrades: Int
    let unresolved: Int
    let note: String
}

struct CostReplaySummary: Codable {
    let additionalCostPerUnit: Double
    let validTrades: Int
    let netPnlPriceUnits: Double
    let note: String
}

struct HoldoutReplaySummary: Codable {
    let developmentCases: Int
    let validationCases: Int
    let heldOutCases: Int
    let heldOutValidTrades: Int
    let heldOutNetPnlPriceUnits: Double
    let note: String
}

extension ResearchRunner {
    func runAuthenticReplay() async throws {
        let assets = options.asset.map { [$0] } ?? ["EUR/USD", "GBP/JPY"]
        for asset in assets {
            let result = try await authenticReplay(asset: asset)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = try encoder.encode(result)
            print(String(decoding: payload, as: UTF8.self))
            let directory = root.appendingPathComponent("authentic-replay", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            let destination = directory.appendingPathComponent("\(asset.replacingOccurrences(of: "/", with: "_"))-summary.json")
            try payload.write(to: destination, options: .atomic)
            print("AUTHENTIC_REPLAY_ARCHIVE path=\(destination.path) sha256=\(digest)")
        }
    }

    private func authenticReplay(asset: String) async throws -> AuthenticReplaySummary {
        let directory = root.appendingPathComponent("historical-bid-ask", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.contains("oanda-practice-\(asset.replacingOccurrences(of: "/", with: "_"))-") }
        let decoder = JSONDecoder()
        let batches = try urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decoder.decode(OandaHistoricalBidAskBatch.self, from: Data(contentsOf: $0)) }
        let m1 = deduplicate(batches.filter { $0.granularity == "M1" }.flatMap(\.candles))
        let m5 = deduplicate(batches.filter { $0.granularity == "M5" }.flatMap(\.candles))
        guard !m1.isEmpty, !m5.isEmpty else {
            throw ScanError.failed("No authentic bid/ask archive for \(asset)")
        }

        func midpoint(_ bid: Double, _ ask: Double) -> Double { (bid + ask) / 2 }
        let m1Payload = m1.map {
            StrategyEngine.CandlePayload(time: $0.sourceTime.timeIntervalSince1970 * 1_000,
                open: midpoint($0.bidOpen, $0.askOpen),
                high: midpoint($0.bidHigh, $0.askHigh),
                low: midpoint($0.bidLow, $0.askLow),
                close: midpoint($0.bidClose, $0.askClose))
        }
        let m5Payload = m5.map {
            StrategyEngine.CandlePayload(time: $0.sourceTime.timeIntervalSince1970 * 1_000,
                open: midpoint($0.bidOpen, $0.askOpen),
                high: midpoint($0.bidHigh, $0.askHigh),
                low: midpoint($0.bidLow, $0.askLow),
                close: midpoint($0.bidClose, $0.askClose))
        }
        let prices = m1.map {
            ValidationPriceObservation(instrumentID: asset, venueID: "OANDA",
                observedAt: $0.sourceTime.addingTimeInterval(60),
                price: midpoint($0.bidClose, $0.askClose), bid: $0.bidClose,
                ask: $0.askClose, source: "oanda-practice-bid-ask-close",
                authority: .directBroker)
        }
        let times = prices.map(\.observedAt)
        let series = HistoricalValidationSeries(instrumentID: asset, engineAsset: asset,
            venueID: "OANDA", marketKind: .standard, source: "oanda",
            authority: .directBroker, candles1m: m1Payload, candles5m: m5Payload,
            prices: prices, evaluationTimes: times, provenance: urls.map(\.path).joined(separator: "|"))
        let built = HistoricalValidationCaseBuilder.build(series: series, minimumM1: 52,
            minimumM5: 20, maximumBars: 200)
        let policies = ["baseline", "continuation", "reversal", "regime"]
        let configurations = [0.0, 3.0, 10.0].map {
            SpotFXReplayConfiguration(entryDelaySeconds: $0, horizonSeconds: 60,
                observationToleranceSeconds: $0 == 0 ? 0.5 : 2,
                maximumExitDelaySeconds: 1, units: 1, additionalCostPerUnit: 0)
        }
        var recordsByDelay: [(Double, [SpotFXReplayRecord])] = []
        for configuration in configurations {
            recordsByDelay.append((configuration.entryDelaySeconds,
                try await SpotFXHistoricalReplay.replay(cases: built.cases,
                    strategyID: "baseline", configuration: configuration)))
        }
        var strategyRecords: [(String, [SpotFXReplayRecord])] = []
        for policy in policies {
            strategyRecords.append((policy, try await SpotFXHistoricalReplay.replay(
                cases: built.cases, strategyID: policy, configuration: configurations[0])))
        }
        var adaptivePolicies: [String: String] = [:]
        for item in built.cases {
            var candidates: [AdaptiveOpportunityCandidate] = []
            for policy in policies {
                var input = item.input
                input.policy = ScanPolicy(rawValue: policy)
                let evaluation: StrategyEngine.EvaluateResult
                do {
                    evaluation = try await StrategyEngine.evaluate(input: input)
                } catch {
                    throw ScanError.failed("\(StrategyEngine.dtcException ?? error.localizedDescription) policy=\(policy) case=\(item.id) m1=\(input.candles1m.count) m5=\(input.candles5m.count) evaluated=\(input.evaluatedAtMs ?? -1)")
                }
                candidates.append(AdaptiveOpportunityAdapters.engine(input, policy: ScanPolicy(rawValue: policy)!,
                    startedAt: item.signalTimestamp, completedAt: item.signalTimestamp, result: evaluation))
            }
            let decision = AdaptiveOpportunitySelector.select(candidates, now: item.signalTimestamp,
                decisionAt: item.signalTimestamp)
            if let selected = decision.selectedCandidateID,
               let policy = policies.first(where: { selected.hasPrefix("\($0)-") }) {
                adaptivePolicies[item.id] = policy
            }
        }
        let records = Dictionary(uniqueKeysWithValues: strategyRecords.map { ($0.0, $0.1) })
        let adaptiveRecords = built.cases.compactMap { item -> SpotFXReplayRecord? in
            guard let policy = adaptivePolicies[item.id], let record = records[policy]?.first(where: { $0.caseID == item.id }) else { return nil }
            return record
        }
        let slippageCosts = [0, 0.25, 0.5].map { Assets.pipScale(for: asset) * $0 }
        var costSensitivity: [CostReplaySummary] = []
        for cost in slippageCosts {
            let costRecords = try await SpotFXHistoricalReplay.replay(cases: built.cases,
                strategyID: "baseline", configuration: SpotFXReplayConfiguration(
                    entryDelaySeconds: 0, horizonSeconds: 60,
                    observationToleranceSeconds: 0.5, maximumExitDelaySeconds: 1,
                    units: 1, additionalCostPerUnit: cost))
            costSensitivity.append(CostReplaySummary(additionalCostPerUnit: cost,
                validTrades: costRecords.filter { $0.status == .valid }.count,
                netPnlPriceUnits: costRecords.compactMap(\.netPnl).reduce(0, +),
                note: "Modeled additional slippage only; bid/ask spread is already in executable sides."))
        }
        let orderedCases = built.cases.sorted { $0.signalTimestamp < $1.signalTimestamp }
        let developmentCount = orderedCases.count / 2
        let validationCount = (orderedCases.count - developmentCount) / 2
        let holdoutIDs = Set(orderedCases.dropFirst(developmentCount + validationCount).map(\.id))
        let holdoutRecords = (records["baseline"] ?? []).filter { holdoutIDs.contains($0.caseID) }
        let holdoutNet = holdoutRecords.compactMap(\.netPnl).reduce(0, +)
        return AuthenticReplaySummary(instrument: asset, sourceFiles: urls.map(\.path),
            m1Candles: m1.count, m5Candles: m5.count, cases: built.cases.count,
            rejections: built.rejections.count,
            strategyResults: strategyRecords.map { summarize(policy: $0.0, records: $0.1, cases: built.cases.count) },
            adaptive: summarize(policy: "adaptive", records: adaptiveRecords, cases: built.cases.count),
            orb: orbReplay(asset: asset, candles: m1, prices: prices),
            delaySensitivity: recordsByDelay.map { delay, records in
                DelayReplaySummary(entryDelaySeconds: delay,
                    validTrades: records.filter { $0.status == .valid }.count,
                    unresolved: records.filter { $0.status == .unresolved }.count,
                    note: delay == 0 ? "Candle-close bid/ask observation; no post-close fill delay." : "No tick-level observation within the configured delay; unresolved is conservative. ")
            }, costSensitivity: costSensitivity,
            chronologicalHoldout: HoldoutReplaySummary(
                developmentCases: developmentCount, validationCases: validationCount,
                heldOutCases: orderedCases.count - developmentCount - validationCount,
                heldOutValidTrades: holdoutRecords.filter { $0.status == .valid }.count,
                heldOutNetPnlPriceUnits: holdoutNet,
                note: "Chronological descriptive split only; no threshold tuning or statistical certification."))
    }

    private func orbReplay(asset: String, candles: [OandaBidAskCandle],
                           prices: [ValidationPriceObservation]) -> ORBReplaySummary {
        let bars = candles.map {
            ORBBar(id: "\(asset)-\($0.sourceTime.timeIntervalSince1970)", instrument: asset,
                sourceTime: $0.sourceTime, endTime: $0.sourceTime.addingTimeInterval(60),
                open: ($0.bidOpen + $0.askOpen) / 2,
                high: ($0.bidHigh + $0.askHigh) / 2,
                low: ($0.bidLow + $0.askLow) / 2,
                close: ($0.bidClose + $0.askClose) / 2)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let sessions = Dictionary(grouping: bars) { bar in
            let components = calendar.dateComponents([.year, .month, .day], from: bar.sourceTime)
            return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        }
        var candidates: [String: ORBTradePlanCandidate] = [:]
        var rawSignals = 0
        for sessionBars in sessions.values {
            let orderedBars = sessionBars.sorted { $0.sourceTime < $1.sourceTime }
            for bar in orderedBars {
                let decision = ORBBreakRetestV1.evaluate(instrument: asset,
                    bars: orderedBars, asOf: bar.endTime)
                if let candidate = decision.candidate {
                    rawSignals += 1
                    candidates[candidate.plan.id] = candidate
                }
            }
        }
        var evaluated: [(Date, V3StructuralOutcome)] = []
        var ambiguousPlans: [(date: Date, stopR: Double, targetR: Double)] = []
        for candidate in candidates.values {
            guard let entryQuote = prices.first(where: { $0.observedAt == candidate.plan.createdAt }),
                  let bid = entryQuote.bid, let ask = entryQuote.ask else { continue }
            let entryObservation = V3MarketObservation(id: "orb-entry-\(candidate.plan.id)",
                instrument: asset, provider: "OANDA", environment: .oandaPractice,
                bid: bid, ask: ask, sourceTime: entryQuote.observedAt,
                receivedAt: entryQuote.observedAt)
            let evidence = V3PlanEntryEvidence(id: "orb-evidence-\(candidate.plan.id)",
                planID: candidate.plan.id, observation: entryObservation,
                quality: .simulated, recordedAt: entryQuote.observedAt)
            let ambiguous = candles.contains { candle in
                guard candle.sourceTime >= entryQuote.observedAt else { return false }
                if candidate.plan.side == .long {
                    let stopReachable = candle.bidLow <= candidate.plan.stopPrice
                    let targetReachable = candle.bidHigh >= candidate.plan.targetPrice
                    return stopReachable && targetReachable
                } else {
                    let stopReachable = candle.askHigh >= candidate.plan.stopPrice
                    let targetReachable = candle.askLow <= candidate.plan.targetPrice
                    return stopReachable && targetReachable
                }
            }
            if ambiguous {
                let risk = abs(candidate.plan.entryPrice - candidate.plan.stopPrice)
                let targetR = risk > 0
                    ? abs(candidate.plan.targetPrice - candidate.plan.entryPrice) / risk : 0
                ambiguousPlans.append((candidate.plan.createdAt, -1, targetR))
                continue
            }
            let exits = prices.compactMap { quote -> V3MarketObservation? in
                guard quote.observedAt >= entryQuote.observedAt,
                      quote.observedAt <= entryQuote.observedAt.addingTimeInterval(120 * 60),
                      let bid = quote.bid, let ask = quote.ask else { return nil }
                return V3MarketObservation(id: "orb-exit-\(candidate.plan.id)-\(quote.observedAt.timeIntervalSince1970)",
                    instrument: asset, provider: "OANDA", environment: .oandaPractice,
                    bid: bid, ask: ask, sourceTime: quote.observedAt, receivedAt: quote.observedAt)
            }
            guard let asOf = exits.last?.sourceTime else { continue }
            let outcome = V3StructuralOutcomeEvaluator.evaluate(plan: candidate.plan,
                entry: evidence, exitQuotes: exits, asOf: asOf, quality: .simulated,
                maximumEvidenceAge: 2 * 60 * 60)
            evaluated.append((candidate.plan.createdAt, outcome))
        }
        var nextAvailable = Date.distantPast
        var executable: [V3StructuralOutcome] = []
        var executableAmbiguous = 0
        var ambiguousStopFirstR = 0.0
        var ambiguousTargetFirstR = 0.0
        let lifecycle = evaluated.map {
            (date: $0.0, outcome: Optional($0.1), stopR: 0.0, targetR: 0.0)
        } + ambiguousPlans.map {
            (date: $0.date, outcome: Optional<V3StructuralOutcome>.none,
             stopR: $0.stopR, targetR: $0.targetR)
        }
        for item in lifecycle.sorted(by: { $0.date < $1.date }) {
            if item.date < nextAvailable { continue }
            if let outcome = item.outcome {
                guard let entry = outcome.entryObservation else { continue }
                executable.append(outcome)
                nextAvailable = outcome.exitObservation?.sourceTime ?? entry.sourceTime.addingTimeInterval(120 * 60)
            } else {
                executableAmbiguous += 1
                ambiguousStopFirstR += item.stopR
                ambiguousTargetFirstR += item.targetR
                nextAvailable = item.date.addingTimeInterval(120 * 60)
            }
        }
        let resolved = executable.filter { $0.status == .winner || $0.status == .loser }
        let net = resolved.compactMap(\.netPnl).reduce(0, +)
        let rValues = resolved.compactMap { outcome -> Double? in
            guard outcome.entryPrice != nil,
                  let plan = candidates[outcome.planID]?.plan else { return nil }
            let risk = abs(plan.entryPrice - plan.stopPrice)
            return risk > 0 ? (outcome.netPnl ?? 0) / risk : nil
        }
        return ORBReplaySummary(rawSetupSignals: rawSignals, uniquePlans: candidates.count,
            executableNonOverlappingPlans: executable.count,
            winners: executable.filter { $0.status == .winner }.count,
            losers: executable.filter { $0.status == .loser }.count,
            ambiguous: executableAmbiguous + executable.filter { $0.status == .ambiguous }.count,
            untriggered: executable.filter { $0.status == .untriggered }.count,
            unresolved: executable.filter { $0.status == .unresolved }.count,
            netPnlPriceUnits: net, netR: rValues.isEmpty ? nil : rValues.reduce(0, +),
            ambiguityExclusionNetR: rValues.isEmpty ? nil : rValues.reduce(0, +),
            ambiguityStopFirstNetR: rValues.isEmpty ? nil : rValues.reduce(0, +) + ambiguousStopFirstR,
            ambiguityTargetFirstNetR: rValues.isEmpty ? nil : rValues.reduce(0, +) + ambiguousTargetFirstR,
            caveat: "ORB uses existing structural plans and close-time bid/ask observations; candle intrabar stop/target order is not inferred.")
    }

    private func deduplicate(_ candles: [OandaBidAskCandle]) -> [OandaBidAskCandle] {
        Dictionary(candles.map { ($0.sourceTime, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.sourceTime < $1.sourceTime }
    }

    private func summarize(policy: String, records: [SpotFXReplayRecord], cases: Int) -> StrategyReplaySummary {
        let valid = records.filter { $0.status == .valid }
        let pnl = valid.compactMap(\.netPnl)
        var nextAvailable = Date.distantPast
        var nonOverlapping: [SpotFXReplayRecord] = []
        for record in valid.sorted(by: { $0.signalTimestamp < $1.signalTimestamp }) {
            guard record.signalTimestamp >= nextAvailable else { continue }
            nonOverlapping.append(record)
            nextAvailable = record.exitTimestamp ?? record.signalTimestamp.addingTimeInterval(60)
        }
        return StrategyReplaySummary(strategy: policy, observations: cases,
            rawDirectionalSignals: records.filter { $0.side != nil }.count,
            validTrades: valid.count,
            executableNonOverlappingTrades: nonOverlapping.count,
            profitable: pnl.filter { $0 > 0 }.count,
            unprofitable: pnl.filter { $0 < 0 }.count,
            unresolved: records.filter { $0.status == .unresolved }.count,
            netPnlPriceUnits: pnl.reduce(0, +),
            nonOverlappingNetPnlPriceUnits: nonOverlapping.compactMap(\.netPnl).reduce(0, +),
            averageNetPnlPriceUnits: pnl.isEmpty ? nil : pnl.reduce(0, +) / Double(pnl.count),
            caveat: "Bid/ask OHLC close observations; no tick sequencing, slippage, or R normalization claimed.")
    }
}
