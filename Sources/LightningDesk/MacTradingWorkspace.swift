#if os(macOS)
import BlazerCore
import SwiftUI

/// Desktop command-center presentation. The trading model and lifecycle remain shared with iOS.
struct MacTradingWorkspace: View {
    @ObservedObject var model: LightningDeskModel
    @State private var showingEvidence = true

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            HSplitView {
                radar.frame(minWidth: 190, idealWidth: 245, maxWidth: 330)
                chartPanel.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                decisionPanel.frame(minWidth: 250, idealWidth: 310, maxWidth: 390)
            }
            .padding(12)
            DisclosureGroup("Lifecycle evidence · Research · Journal", isExpanded: $showingEvidence) {
                evidencePanel.frame(height: 170)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(DeskInk.background.ignoresSafeArea())
        .foregroundStyle(DeskInk.ink)
        .sheet(isPresented: $model.showingCredentials) {
            CredentialCover(model: model)
                .frame(width: 560, height: 640)
                .preferredColorScheme(.dark)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            Label("LIGHTNING DESK", systemImage: "waveform.path.ecg")
                .font(.system(size: 13, weight: .bold))
            statusPill("OANDA · \(model.keychainState == .ready ? "credentials saved" : model.keychainState == .missing ? "credentials missing" : "credentials \(String(describing: model.keychainState))")")
            statusPill("Feed · \(model.feed.rawValue.uppercased())")
            statusPill("Observed · \(model.lastMarketObservationAt.map(Self.time.string(from:)) ?? "not yet")")
            Button(model.keychainState == .ready ? "Credentials" : "Connect OANDA") {
                model.showingCredentials = true
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("mac.connect-oanda")
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Focus-window policy · weekdays 09:30–16:00 New York")
                Text("30m warmup configured · monitoring/background scanning not enabled")
                    .foregroundStyle(DeskInk.slate)
            }
            .font(.system(size: 10, weight: .medium))
            .accessibilityIdentifier("mac.monitor-policy")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(DeskInk.surface)
    }

    private var radar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FOREX RADAR").font(.system(size: 12, weight: .bold))
                    Text("Scan status · \(model.scanning ? (model.scanStep ?? "scanning") : (model.lastScanAt.map(Self.time.string(from:)) ?? "idle"))")
                        .font(.system(size: 10)).foregroundStyle(DeskInk.slate)
                }
                Spacer(minLength: 4)
                Button {
                    Task { await model.scan() }
                } label: {
                    Label(model.scanning ? "Scanning" : "Scan", systemImage: "arrow.clockwise")
                }
                .disabled(model.scanning)
                .accessibilityIdentifier("mac.scan")
                .accessibilityLabel("Scan forex watchlist")
            }
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(model.pairs, id: \.self) { pair in
                        Button {
                            model.select(pair: pair)
                        } label: {
                            HStack {
                                Text(pair).font(.system(size: 12, weight: pair == model.pair ? .bold : .medium))
                                Spacer()
                                Text(model.book.first(where: { $0.asset == pair })?.side ?? "—")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DeskInk.slate)
                            }
                            .padding(9)
                            .background(pair == model.pair ? DeskInk.indigo.opacity(0.28) : Color.white.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mac.pair.\(pair.replacingOccurrences(of: "/", with: "-"))")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(DeskInk.surface.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.pair).font(.system(size: 25, weight: .bold, design: .rounded))
                Text("ORB BREAK · RETEST").font(.system(size: 11, weight: .semibold)).foregroundStyle(DeskInk.slate)
                Spacer()
                Text(model.currentPrice.map(PriceFormat.px) ?? "—")
                    .font(.system(size: 21, weight: .medium, design: .monospaced))
            }
            HStack {
                Text("Candles · available observation window")
                Spacer()
                Text("Reference quote only · not a fill")
            }.font(.system(size: 10)).foregroundStyle(DeskInk.slate)
            MiniCandleChart(candles: model.candles, currentPrice: model.currentPrice, pair: model.pair, visibleBars: 90)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10).background(Color.black.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 9))
            Text("Timeframe/context · source candles as provided; no timeframe conversion or session inference")
                .font(.system(size: 10)).foregroundStyle(DeskInk.slate)
        }
        .padding(14).background(DeskInk.surface.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var decisionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DECISION / ORB PRACTICE").font(.system(size: 12, weight: .bold))
            if let decision = model.orbDecision(for: model.pair) {
                Text(decision.stage.rawValue.uppercased())
                    .font(.system(size: 17, weight: .bold))
                if let direction = decision.direction {
                    Text("Direction · \(direction.rawValue.uppercased())")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(decision.reason).font(.system(size: 11)).foregroundStyle(DeskInk.slate)
            } else {
                Text("No ORB decision available").font(.system(size: 12)).foregroundStyle(DeskInk.slate)
            }
            Divider().overlay(Color.white.opacity(0.1))
            let plan = model.orbPlan(for: model.pair)
            level("Entry", plan.map { PriceFormat.px($0.entryPrice) } ?? "—")
            level("Stop", plan.map { PriceFormat.px($0.stopPrice) } ?? "—")
            level("Target", plan.map { PriceFormat.px($0.targetPrice) } ?? "—")
            level("Max spread (price units)", plan.map { PriceFormat.px($0.maxSpread) } ?? "—")
            level("Risk", "Unresolved · risk_missing")
            Text("Units omitted — placeholder plan sizing is not trade sizing.")
                .font(.system(size: 10)).foregroundStyle(DeskInk.slate)
            Text("Manual workflow only · BlazerOS does not place broker orders.")
                .font(.system(size: 10)).foregroundStyle(DeskInk.slate)
            if let lifecycle = model.spotFXPracticeState(for: model.pair) {
                Text("Lifecycle · \(lifecycle.state.rawValue)").font(.system(size: 11, weight: .semibold))
                Text(lifecycle.reason).font(.system(size: 10)).foregroundStyle(DeskInk.slate)
                if let spread = lifecycle.spreadPips { level("Observed spread", "\(spread.formatted(.number.precision(.fractionLength(1)))) pips") }
                if lifecycle.state == .actionable {
                    Button("Acknowledge practice plan (not a fill)") {
                        Task { await model.acknowledgeSpotFXPracticePlan(for: model.pair) }
                    }
                    .font(.system(size: 10))
                }
                Text("Acknowledgement is not a fill.").font(.system(size: 10)).foregroundStyle(DeskInk.slate)
            } else {
                Text("Practice lifecycle unresolved").font(.system(size: 11)).foregroundStyle(DeskInk.slate)
            }
            Spacer(minLength: 0)
        }
        .padding(14).background(DeskInk.surface.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var evidencePanel: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT LIFECYCLE EVIDENCE").font(.system(size: 10, weight: .bold))
                let lifecycle = model.spotFXPracticeState(for: model.pair)
                Text(lifecycle?.reason ?? model.orbDecision(for: model.pair)?.reason ?? "No evidence available")
                Text("Plan risk unresolved (risk_missing) is shown as unresolved; units are withheld.")
                    .foregroundStyle(DeskInk.slate)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("ADAPTIVE RESEARCH PROJECTION").font(.system(size: 10, weight: .bold))
                Text(model.adaptiveResearchProjection.map(Self.adaptiveSummary) ?? "No projection available")
                    .lineLimit(3).foregroundStyle(DeskInk.slate)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT JOURNAL / REPLAY").font(.system(size: 10, weight: .bold))
                if model.journal.isEmpty { Text("No journal entries").foregroundStyle(DeskInk.slate) }
                ForEach(model.journal.prefix(4)) { entry in
                    HStack {
                        Text("\(entry.pair) · \(entry.verb)")
                        Spacer(minLength: 8)
                        Text(Self.time.string(from: entry.scannedAt)).foregroundStyle(DeskInk.slate)
                    }.font(.system(size: 10)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
    }

    private func statusPill(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(DeskInk.slate)
            .lineLimit(1)
    }

    private func level(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(DeskInk.slate); Spacer(); Text(value).font(.system(size: 11, design: .monospaced)) }
            .font(.system(size: 11))
    }

    private static func adaptiveSummary(_ projection: AdaptiveResearchProjection) -> String {
        var summary = "\(projection.instrument) · \(projection.decisionState.rawValue) · research only"
        if let strategy = projection.strategyID { summary += " · \(strategy)" }
        if let direction = projection.direction { summary += " · \(direction.rawValue.uppercased())" }
        if let reason = projection.invalidationReason { summary += " · \(reason)" }
        return summary
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
#endif
