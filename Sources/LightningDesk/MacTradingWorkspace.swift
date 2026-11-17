#if os(macOS)
import BlazerCore
import SwiftUI

/// Independent native Mac workspace; the iPhone retains its own mobile navigation and layout.
struct MacTradingWorkspace: View {
    @ObservedObject var model: LightningDeskModel
    @State private var destination = "Trade"
    @State private var selectedPracticeSignalID: String?
    @ScaledMetric(relativeTo: .caption) private var diagnosticFontSize = 9.0

    private let ink = Color(red: 0.12, green: 0.19, blue: 0.29)
    private let muted = Color(red: 0.39, green: 0.48, blue: 0.59)
    private let blue = Color(red: 0.16, green: 0.42, blue: 0.78)
    private let line = Color(red: 0.87, green: 0.91, blue: 0.95)
    private let canvas = Color(red: 0.96, green: 0.975, blue: 0.99)

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            VStack(spacing: 0) {
                header
                notificationBanner
                if destination == "Trade" { tradeView } else { secondaryView }
            }
        }
        .frame(minWidth: 1040, minHeight: 708)
        .background(canvas.ignoresSafeArea())
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.showingCredentials) {
            CredentialCover(model: model)
                .frame(width: 520, height: 590)
                .preferredColorScheme(.dark)
        }
        .onChange(of: model.keychainState) { _, state in
            if state == .missing || state == .locked { model.showingCredentials = true }
        }
        .onChange(of: model.activeTab) { _, tab in
            destination = switch tab {
            case .desk: "Trade"
            case .radar: "Analytics"
            case .review: "My Trades"
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(blue).font(.system(size: 19, weight: .semibold))
                Text("BlazerOS").font(.system(size: 17, weight: .bold))
            }.padding(.bottom, 10)
            ForEach(["Trade", "Plans", "My Trades", "Learn", "Analytics", "Settings"], id: \.self) { item in
                Button {
                    destination = item
                    if item == "Trade" { model.activeTab = .desk }
                    if item == "My Trades" { model.activeTab = .review }
                    if item == "Analytics" { model.activeTab = .radar }
                    if item == "Settings" { model.showingCredentials = true }
                } label: {
                    Label(item, systemImage: icon(for: item))
                        .font(.system(size: 13, weight: destination == item ? .semibold : .medium))
                        .foregroundStyle(destination == item ? blue : muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).padding(.horizontal, 10)
                        .background(destination == item ? blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Divider().overlay(line).padding(.vertical, 5)
            Text("LIVE WATCHLIST").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(muted)
            ForEach(model.pairs, id: \.self) { pair in
                Button { model.select(pair: pair) } label: {
                    HStack { Text(pair); Spacer(); if model.pair == pair { Image(systemName: "checkmark").foregroundStyle(blue) } }
                        .font(.system(size: 12, weight: model.pair == pair ? .semibold : .regular))
                        .foregroundStyle(ink).padding(8)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("mac.pair.\(pair.replacingOccurrences(of: "/", with: "-"))")
            }
            Spacer()
            Label("\(model.connectedOandaEnvironment?.rawValue.uppercased() ?? "OANDA") · SIGNALS · MANUAL EXECUTION", systemImage: "waveform.path.ecg")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
        }
        .padding(16).background(.white)
        .overlay(alignment: .trailing) { Rectangle().fill(line).frame(width: 1) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(destination).font(.system(size: 20, weight: .semibold))
                Text("OANDA FX workstation · structural plans and market evidence").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            Label(oandaEnvironmentLabel, systemImage: model.feed == .live ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(model.feed == .live ? blue : muted)
            Button("Credentials") { model.showingCredentials = true }
                .buttonStyle(.bordered).tint(blue).accessibilityIdentifier("mac.connect-oanda")
        }
        .padding(.horizontal, 22).padding(.vertical, 14).background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private var tradeView: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                marketPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                setupPanel.frame(width: 276).frame(maxHeight: .infinity)
            }
            researchSignalsPanel.frame(height: 160)
            strategySignalSummaryPanel.frame(height: 126)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var oandaEnvironmentLabel: String {
        guard let environment = model.connectedOandaEnvironment else { return "OANDA DISCONNECTED" }
        return "OANDA \(environment.rawValue.uppercased()) · \(model.feed.rawValue)"
    }

    private var researchSignalsPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("STRATEGY SIGNALS").font(.system(size: 10, weight: .bold)).tracking(0.7)
                Text("SETUP STAGE · PLAN DETAILS · MANUAL BROKER ACTION")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
                Text("GBP/JPY · EVALUATOR COVERAGE")
                    .font(.system(size: 8, weight: .medium)).foregroundStyle(muted)
            }
            ScrollView(.vertical) { researchSignalDetails }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityIdentifier("mac.research-signal-details")
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.96, blue: 0.98), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityIdentifier("mac.research-signals")
    }

    @ViewBuilder private var researchSignalDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(researchSignalStatusText).font(.system(size: diagnosticFontSize, weight: .medium))
                .foregroundStyle(muted)
            if model.macResearchSignals.isEmpty && model.macResearchEvaluationDiagnostics.isEmpty {
                Text("Signal details appear after a fresh scan with supported market data.")
                    .font(.system(size: diagnosticFontSize)).foregroundStyle(muted)
            }
            if !model.macResearchSignals.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: 8) {
                    ForEach(model.macResearchSignals) { signal in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(signal.stage.rawValue) · \(signal.direction == .long ? "LONG" : "SHORT") · \(signal.instrument) · \(signal.environment.rawValue)")
                                .font(.system(size: diagnosticFontSize, weight: .bold, design: .monospaced))
                            Text("\(signal.strategyID) · \(signal.strategyVersion)")
                                .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium))
                            Text("TIMEFRAME · \(signal.timeframe ?? "UNSPECIFIED")")
                                .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium))
                                .foregroundStyle(muted)
                            Text("ENTRY \(signal.entryReference.map(PriceFormat.px) ?? "—") · STOP \(signal.stopPrice.map(PriceFormat.px) ?? "—") · TARGET \(signal.targetPrice.map(PriceFormat.px) ?? "—")")
                                .font(.system(size: max(8, diagnosticFontSize - 1), weight: .semibold, design: .monospaced))
                            if let plan = signal.planPreview {
                                Text("R:R \(plan.rewardRisk, specifier: "%.2f") · MAX SPREAD \(PriceFormat.px(plan.maxSpread))")
                                    .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium, design: .monospaced))
                                    .foregroundStyle(muted)
                                Text("Plan preview only · account risk and margin are not checked here.")
                                    .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium))
                                    .foregroundStyle(muted)
                            } else {
                                let missing = [
                                    signal.entryReference == nil ? "entry" : nil,
                                    signal.stopPrice == nil ? "stop" : nil,
                                    signal.targetPrice == nil ? "target" : nil
                                ].compactMap { $0 }
                                let blocker = missing.isEmpty ? "plan validation" : missing.joined(separator: ", ")
                                Text("PLAN PREVIEW BLOCKED · \(blocker)")
                                    .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                            Text(LiveDecisionAgeLabel.text(observedAt: signal.observedAt))
                                .font(.system(size: max(8, diagnosticFontSize - 1), weight: .medium))
                                .foregroundStyle(muted)
                            Text(signal.reasons.joined(separator: " · "))
                                .font(.system(size: max(8, diagnosticFontSize - 1)))
                                    .foregroundStyle(muted).lineLimit(2)
                            Button(selectedPracticeSignalID == signal.id ? "Selected for setup" : "Use in setup") {
                                selectedPracticeSignalID = signal.id
                            }
                            .font(.system(size: max(8, diagnosticFontSize - 1), weight: .semibold))
                            .buttonStyle(.bordered).tint(blue)
                            .disabled(signal.environment != .practice)
                            .accessibilityIdentifier("mac.use-practice-signal.\(signal.id)")
                        }
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(line))
                        .accessibilityIdentifier("mac.research-signal.\(signal.id)")
                    }
                }
            }
            if !model.macResearchEvaluationDiagnostics.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: 8) {
                    ForEach(model.macResearchEvaluationDiagnostics) { diagnostic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.family.rawValue.uppercased())
                                .font(.system(size: max(8, diagnosticFontSize - 1), weight: .bold))
                                .foregroundStyle(muted)
                            Text(diagnostic.statusLabel)
                                .font(.system(size: diagnosticFontSize, weight: .semibold)).lineLimit(2)
                            if let detail = diagnostic.detail {
                                Text(detail).font(.system(size: max(8, diagnosticFontSize - 1)))
                                    .foregroundStyle(muted).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(diagnostic.family.rawValue) evaluator")
                        .accessibilityValue(([diagnostic.statusLabel] + (diagnostic.detail.map { [$0] } ?? []))
                            .joined(separator: ". "))
                        .accessibilityIdentifier("mac.research-evaluator.\(diagnostic.family.rawValue)")
                    }
                }
                .accessibilityIdentifier("mac.research-evaluator-diagnostics")
            }
        }
    }

    private var researchSignalStatusText: String {
        switch model.macResearchSignalStatus {
        case .awaitingFreshScan: "Awaiting fresh scan"
        case .completedNoCandidate: "Scan complete · no candidates"
        case .completedWithCandidates: "Fresh scan complete"
        case .conditionsNotMet: "Setup detected · waiting on conditions"
        case .partialResults: "Some evaluators lack required data"
        case .failed: "Evaluation issue"
        case .sourceAttestationUnavailable: "Verified source manifest unavailable"
        }
    }

    @ViewBuilder private var notificationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let receipt = model.settleReceipt {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(receipt.outcome.rawValue) · \(receipt.pair)").font(.system(size: 12, weight: .bold))
                        Text("Result recorded in the local journal.").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    Spacer()
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14).padding(.top, 8)
            }
            if let decision = model.strategyDecision(for: model.pair) {
                let action = decision.action.rawValue
                let strategyNames = decision.supportingStrategies.map { strategyName($0) }
                    .joined(separator: " + ")
                HStack(spacing: 10) {
                    Image(systemName: decision.action == .wait ? "hand.raised.fill" : "bell.badge.fill")
                        .foregroundStyle(decision.action == .wait ? Color.orange : blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decision.action == .wait
                             ? "STRATEGY DECISION · WAIT · \(model.pair)"
                             : "STRATEGY SIGNAL · \(action) \(model.pair)")
                            .font(.system(size: 12, weight: .bold))
                        Text(decision.action == .wait
                             ? "\(strategyWaitReason(decision.reasons.first)) · \(LiveDecisionAgeLabel.text(observedAt: decision.observedAt))"
                             : "Rules aligned: \(strategyNames). Review the levels below; no order is open. \(LiveDecisionAgeLabel.text(observedAt: decision.observedAt)).")
                            .font(.system(size: 10)).foregroundStyle(muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let plan = decision.plan {
                        let pip = Assets.pipScale(for: plan.instrument)
                        let stopPips = abs(plan.entryPrice - plan.stopPrice) / pip
                        let targetPips = abs(plan.targetPrice - plan.entryPrice) / pip
                        Text("Entry \(PriceFormat.px(plan.entryPrice))  ·  Stop \(PriceFormat.px(plan.stopPrice)) (\(stopPips, specifier: "%.1f") pips)  ·  Target \(PriceFormat.px(plan.targetPrice)) (\(targetPips, specifier: "%.1f") pips)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background((decision.action == .wait ? Color.orange : blue).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14).padding(.top, 8)
                .accessibilityIdentifier("mac.trade-notification.strategy-decision")
                .help("Rules evaluated: \(strategyNames). Rule sources: \(decision.sourceReferences.joined(separator: " · ")). Book methodology: \(StrategyResearchRegistry.researchMethodReferences.joined(separator: " · ")). Book chapters guide validation methods; they do not define these entry rules.")
            }
            if let notice = model.notice, !notice.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: model.feed == .error ? "exclamationmark.triangle.fill" : "bell.fill")
                        .foregroundStyle(model.feed == .error ? Color.orange : blue)
                    Text(notice).font(.system(size: 11, weight: .medium)).lineLimit(2)
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted) }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss notification")
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(line))
                .padding(.horizontal, 14).padding(.top, 8)
            }
        }
    }

    private func strategyName(_ raw: String) -> String {
        switch raw {
        case "ORB_BREAK_RETEST": return "ORB Breakout + Retest"
        case "CHOCH_FVG_FIB": return "CHoCH + FVG + Fibonacci"
        case "AUCTION_FAILURE": return "Auction Failure"
        case "LEGACY_V1": return "Legacy V1"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func strategyWaitReason(_ reason: String?) -> String {
        switch reason {
        case "eligible_strategy_direction_conflict":
            return "Strategies disagree on direction. No trade plan is issued."
        case "strategy_agreement_missing":
            return "No second strategy family agrees with the setup. No trade plan is issued."
        case "confirmed_structural_plan_unavailable":
            return "No eligible structural plan with an entry, stop and target. Waiting for a valid setup."
        case "structural_plan_ranking_ambiguous":
            return "Multiple structural plans rank equally. Waiting instead of selecting arbitrarily."
        case "fresh_live_quote_unavailable":
            return "Fresh Live quote unavailable. Waiting for current market data."
        case "insufficient_completed_candles":
            return "Not enough completed candles to evaluate the strategies."
        case "restored_plan_requires_live_revalidation":
            return "Previous plan restored from this Mac. It is not current; waiting for Live revalidation."
        case "strategy_decision_persistence_failed":
            return "Strategy result was not saved. Waiting for the next Live scan."
        case "live_m1_candles_unavailable":
            return "Live M1 candles unavailable. Previous signal withdrawn; waiting for fresh data."
        case "live_m5_candles_unavailable":
            return "Live M5 candles unavailable. Previous signal withdrawn; waiting for fresh data."
        case "live_candles_malformed_or_insufficient":
            return "Completed candle data is invalid or insufficient. Previous signal withdrawn."
        case "live_strategy_snapshot_invalid":
            return "Live strategy input is incomplete or malformed. Previous signal withdrawn."
        case "live_scan_failed":
            return "Live market scan failed. Previous signal withdrawn; retry when data is available."
        case "live_credentials_unavailable", "live_session_unavailable":
            return "OANDA Live session unavailable. Previous signal withdrawn until a fresh scan."
        case "fx_market_closed":
            return "FX market is closed. Previous signal withdrawn; setup was not marked expired."
        case "live_instrument_not_currently_monitored":
            return "This pair is no longer being monitored. Re-select it to request fresh Live analysis."
        default:
            return "No complete, agreeing strategy setup. No trade is open."
        }
    }

    private var marketPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.pair).font(.system(size: 25, weight: .semibold))
                Text("Multi-strategy · source candles").font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                if let quote = model.currentFXQuote {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("BID  \(PriceFormat.px(quote.bid))     ASK  \(PriceFormat.px(quote.ask))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text("Spread \(spreadPips(quote).map { $0.formatted(.number.precision(.fractionLength(1))) + " pips" } ?? "—") · \(quoteFreshness(quote))")
                            .font(.system(size: 10)).foregroundStyle(muted)
                    }
                } else { Text("Quote unavailable").font(.system(size: 11)).foregroundStyle(muted) }
            }
            Group {
                if model.candles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 25)).foregroundStyle(blue.opacity(0.65))
                        Text("No candle data loaded").font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
                        Text(model.feed == .error ? "Check the OANDA Live token and account in Credentials, then SCAN again." : "Press SCAN to request current OANDA Live candles.")
                            .font(.system(size: 11)).foregroundStyle(muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MiniCandleChart(candles: model.candles, currentPrice: model.currentPrice,
                                    pair: model.pair, visibleBars: 64, allowsZoom: true,
                                    lightAppearance: true, isLoading: model.candlesLoading,
                                    emptyMessage: model.candleIssue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
            .background(Color(red: 0.985, green: 0.99, blue: 0.998), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text(CandleStatusLabel.make(feed: model.feed,
                                            isStale: model.candlesAreStale,
                                            count: model.candles.count))
                Spacer()
                Text("Quote is indicative, not an execution")
            }
                .font(.system(size: 10)).foregroundStyle(muted)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("TRADE SETUP").font(.system(size: 11, weight: .bold)).tracking(0.7)
                Spacer()
                Text(model.connectedOandaEnvironment?.rawValue.uppercased() ?? "DISCONNECTED")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(blue)
                    .padding(.horizontal, 7).padding(.vertical, 4).background(blue.opacity(0.08), in: Capsule())
            }
            HStack(spacing: 8) {
                Button { Task { await model.scan() } } label: {
                    Label(model.scanning ? (model.scanStep ?? "Scanning…") : "SCAN ALL 6",
                          systemImage: model.scanning ? "arrow.triangle.2.circlepath" : "scope")
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(blue).disabled(model.scanning)
                    .accessibilityIdentifier("mac.scan")
                Button {
                    let selectedPair = model.pair
                    Task { await model.scanSelectedFXPair(selectedPair) }
                } label: {
                    Label("SCAN \(model.pair)", systemImage: "scope")
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.bordered).tint(blue).disabled(model.scanning)
                    .accessibilityIdentifier("mac.scan-selected-pair")
                    .help("Run the normal OANDA FX scan for \(model.pair) only")
            }
            let practiceSignal = practiceSignalForSetup
            let decision = practiceSignal == nil ? model.strategyDecision(for: model.pair) : nil
            let plan = decision?.plan
            let entry = practiceSignal?.entryReference ?? practiceSignal?.planPreview?.entryPrice ?? plan?.entryPrice
            let stop = practiceSignal?.stopPrice ?? practiceSignal?.planPreview?.stopPrice ?? plan?.stopPrice
            let target = practiceSignal?.targetPrice ?? practiceSignal?.planPreview?.targetPrice ?? plan?.targetPrice
            value("Status", practiceSignal.map { "\($0.stage.rawValue) · PRACTICE PLAN" }
                  ?? decision?.action.rawValue ?? (model.scanning ? "Scanning" : "Waiting for scan"))
            value("Direction", practiceSignal.map { $0.direction == .long ? "LONG" : "SHORT" }
                  ?? (decision?.action == .buy ? "BUY" : decision?.action == .sell ? "SELL" : "WAIT / NO TRADE"))
            if let practiceSignal {
                value("Strategy", practiceSignal.strategyID)
                value("Timeframe", practiceSignal.timeframe ?? "unspecified")
            }
            value("Entry", entry.map(PriceFormat.px) ?? "—")
            value("Stop", stop.map(PriceFormat.px) ?? "—")
            value("Target", target.map(PriceFormat.px) ?? "—")
            if let entry, let stop, let target {
                let pipSize = Assets.pipScale(for: model.pair)
                let stopPips = abs(entry - stop) / pipSize
                let targetPips = abs(target - entry) / pipSize
                if pipSize.isFinite && pipSize > 0 && stopPips.isFinite && targetPips.isFinite {
                    value("Stop distance", String(format: "%.1f pips", stopPips))
                    value("Target distance", String(format: "%.1f pips", targetPips))
                } else {
                    value("Stop distance", "—")
                    value("Target distance", "—")
                }
            } else {
                value("Stop distance", "—")
                value("Target distance", "—")
            }
            value("Risk", "risk_missing · units withheld")
            if practiceSignal != nil {
                Text("Practice plan preview · verify account risk and margin in OANDA before manual entry.")
                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(3)
            }
            if let decision {
                let reasons = decision.reasons.joined(separator: ", ")
                let strategies = decision.supportingStrategies.map(strategyName).joined(separator: " · ")
                Text(decision.action == .wait ? strategyWaitReason(decision.reasons.first) : "Rules aligned: \(strategies). Review the structural levels before acting.")
                    .font(.system(size: 10)).foregroundStyle(muted).lineLimit(4)
                if decision.action == .wait && !reasons.isEmpty {
                    Text("Reason: \(reasons)").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted).lineLimit(2)
                }
            }
            if let notice = model.notice { Text(notice).font(.system(size: 10)).foregroundStyle(muted).lineLimit(3) }
            Spacer(minLength: 0)
            Text("No broker orders · review before acting").font(.system(size: 9)).foregroundStyle(muted)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
    }

    private var practiceSignalForSetup: MacResearchSignal? {
        guard model.connectedOandaEnvironment == .practice else { return nil }
        let currentSignals = model.macResearchSignals.filter {
            $0.instrument == model.pair && $0.environment == .practice
        }
        if let selectedPracticeSignalID,
           let selected = currentSignals.first(where: { $0.id == selectedPracticeSignalID }) {
            return selected
        }
        return currentSignals.first
    }

    private var strategySignalSummaryPanel: some View {
        let unconfigured = model.macResearchEvaluationDiagnostics
            .filter { $0.state == .notConfigured }
            .map { $0.family.rawValue }
        return VStack(alignment: .leading, spacing: 5) {
            Text("SIGNAL ENGINE")
                .font(.system(size: 9, weight: .bold)).tracking(0.45)
            Text("\(model.pair) · \(researchSignalStatusText)")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
            HStack(spacing: 12) {
                value("VISIBLE SETUPS", String(model.macResearchSignals.count))
                value("EVALUATORS", String(model.macResearchEvaluationDiagnostics.count))
            }
            if !unconfigured.isEmpty {
                Text("PROFILE REQUIRED · \(unconfigured.joined(separator: " · "))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted).lineLimit(2)
            }
            Text("Use qualifying signals to prepare a manual OANDA Practice trade. Live orders still require their own authorization.")
                .font(.system(size: 9)).foregroundStyle(muted).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
        .accessibilityIdentifier("mac.strategy-signal-summary")
    }
    @ViewBuilder private var secondaryView: some View {
        switch destination {
        case "Plans":
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                Text("Live structural plans").font(.system(size: 20, weight: .semibold))
                ForEach(model.pairs, id: \.self) { pair in
                    let plan = model.orbPlan(for: pair)
                    let decision = model.orbDecision(for: pair)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pair).font(.system(size: 14, weight: .semibold))
                            Text(decision?.stage.rawValue ?? "No saved plan").font(.system(size: 11)).foregroundStyle(muted)
                            if let plan { Text("Entry \(PriceFormat.px(plan.entryPrice)) · Stop \(PriceFormat.px(plan.stopPrice)) · Target \(PriceFormat.px(plan.targetPrice))").font(.system(size: 11, design: .monospaced)) }
                        }
                        Spacer(); Text("risk_missing").font(.system(size: 10)).foregroundStyle(muted)
                    }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
                }
            }.padding(22) }
        case "My Trades": JournalScreen(model: model).padding(14)
        case "Settings":
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.system(size: 20, weight: .semibold))
                Text("OANDA Live credentials are stored in this Mac’s Keychain.").font(.system(size: 12)).foregroundStyle(muted)
                Button("Manage OANDA Live credentials") { model.showingCredentials = true }.buttonStyle(.borderedProminent).tint(blue)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case "Learn": infoPanel("LEARN · ORB", "Opening Range Breakout: the engine evaluates a defined opening range and subsequent market structure. A forming condition is not an entry confirmation.").padding(22)
        default: ReviewScreen(model: model).padding(14)
        }
    }

    private func value(_ title: String, _ text: String) -> some View {
        HStack { Text(title).foregroundStyle(muted); Spacer(minLength: 5); Text(text).font(.system(size: 11, weight: .medium, design: .monospaced)).multilineTextAlignment(.trailing) }.font(.system(size: 11))
    }
    private func infoPanel(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 10, weight: .bold)).tracking(0.6); Text(text).font(.system(size: 11)).foregroundStyle(muted).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading) }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
    }
    private func icon(for item: String) -> String {
        switch item { case "Trade": "chart.xyaxis.line"; case "Plans": "list.clipboard"; case "My Trades": "book.closed"; case "Learn": "book"; case "Analytics": "chart.bar"; default: "gearshape" }
    }
    private func spreadPips(_ quote: LiveQuote) -> Double? {
        let scale = Assets.pipScale(for: model.pair)
        guard quote.ask >= quote.bid, scale > 0 else { return nil }
        return (quote.ask - quote.bid) / scale
    }
    private func quoteFreshness(_ quote: LiveQuote) -> String {
        let age = max(0, Date().timeIntervalSince1970 - quote.asOfMs / 1_000)
        return age < 30 ? "fresh \(Int(age))s" : "stale \(Int(age))s"
    }
}
#endif
