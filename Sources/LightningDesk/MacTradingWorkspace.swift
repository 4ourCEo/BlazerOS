#if os(macOS)
import BlazerCore
import SwiftUI

/// Native Mac FX presentation. The scanner, ORB engine and persistence remain shared with iOS.
struct MacTradingWorkspace: View {
    @ObservedObject var model: LightningDeskModel
    @State private var destination = "Trade"
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
                if destination == "Trade" { tradeView }
                else { secondaryView }
            }
        }
        .frame(minWidth: 1040, minHeight: 708)
        .background(canvas.ignoresSafeArea())
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $model.showingCredentials) {
            CredentialCover(model: model, practiceOnly: true)
                .frame(width: 520, height: 590)
                .preferredColorScheme(.light)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(blue).font(.system(size: 19, weight: .semibold))
                Text("BlazerOS").font(.system(size: 17, weight: .bold))
            }.padding(.bottom, 8)
            ForEach(["Trade", "Plans", "My Trades", "Learn", "Analytics", "Settings"], id: \.self) { item in
                Button { destination = item } label: {
                    Label(item, systemImage: icon(for: item))
                        .font(.system(size: 13, weight: destination == item ? .semibold : .medium))
                        .foregroundStyle(destination == item ? blue : muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).padding(.horizontal, 10)
                        .background(destination == item ? blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Divider().overlay(line)
            Text("PRACTICE WATCHLIST").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(muted)
            ForEach(["EUR/USD", "GBP/JPY"], id: \.self) { pair in
                Button { model.select(pair: pair) } label: {
                    HStack { Text(pair); Spacer(); if model.pair == pair { Image(systemName: "checkmark").foregroundStyle(blue) } }
                        .font(.system(size: 12, weight: model.pair == pair ? .semibold : .regular))
                        .foregroundStyle(ink).padding(8)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("mac.pair.\(pair.replacingOccurrences(of: "/", with: "-"))")
            }
            Spacer()
            Label("Practice only", systemImage: "checkmark.shield.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
        }
        .padding(16).background(.white)
        .overlay(alignment: .trailing) { Rectangle().fill(line).frame(width: 1) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(destination).font(.system(size: 20, weight: .semibold))
                Text("FX research workspace · no broker orders").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            Label(model.keychainState == .ready ? "Practice connected" : "Practice not connected",
                  systemImage: model.keychainState == .ready ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(model.keychainState == .ready ? blue : muted)
            Button(model.keychainState == .ready ? "Credentials" : "Connect Practice") { model.showingCredentials = true }
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
            HStack(spacing: 12) {
                contextPanel
                checklistPanel
                nextPanel
            }.frame(height: 126)
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var marketPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.pair).font(.system(size: 25, weight: .semibold))
                Text("ORB · source candles").font(.system(size: 11)).foregroundStyle(muted)
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
            MiniCandleChart(candles: model.candles, currentPrice: model.currentPrice, pair: model.pair, visibleBars: 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(8)
                .background(Color(red: 0.985, green: 0.99, blue: 0.998), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Source candle window · timeframe shown only when supplied by feed")
                Spacer()
                Text("Quote is indicative, not an execution")
            }.font(.system(size: 10)).foregroundStyle(muted)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("TRADE SETUP").font(.system(size: 11, weight: .bold)).tracking(0.7)
                Spacer()
                Text("PRACTICE").font(.system(size: 9, weight: .bold)).foregroundStyle(blue)
                    .padding(.horizontal, 7).padding(.vertical, 4).background(blue.opacity(0.08), in: Capsule())
            }
            Button { Task { await model.scan() } } label: {
                Label(model.scanning ? (model.scanStep ?? "Scanning…") : "SCAN", systemImage: model.scanning ? "arrow.triangle.2.circlepath" : "scope")
                    .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).tint(blue).disabled(model.scanning).accessibilityIdentifier("mac.scan")
            let decision = model.orbDecision(for: model.pair)
            let plan = model.orbPlan(for: model.pair)
            let lifecycle = model.spotFXPracticeState(for: model.pair)
            value("Status", lifecycle?.state.rawValue ?? decision?.stage.rawValue ?? "Waiting for scan")
            value("Direction", decision?.direction?.rawValue.uppercased() ?? "WAIT / NO TRADE")
            value("Entry", plan.map { PriceFormat.px($0.entryPrice) } ?? "—")
            value("Stop", plan.map { PriceFormat.px($0.stopPrice) } ?? "—")
            value("Target", plan.map { PriceFormat.px($0.targetPrice) } ?? "—")
            value("Risk", "risk_missing · units withheld")
            if let lifecycle { Text(lifecycle.reason).font(.system(size: 10)).foregroundStyle(muted).lineLimit(3) }
            else if let decision { Text(decision.reason).font(.system(size: 10)).foregroundStyle(muted).lineLimit(3) }
            if let issue = model.spotFXPracticeRestoreIssue { Text(issue).font(.system(size: 10)).foregroundStyle(.orange) }
            if let notice = model.notice { Text(notice).font(.system(size: 10)).foregroundStyle(muted).lineLimit(2) }
            Spacer(minLength: 0)
            Text("No broker orders · manual reports are not fills").font(.system(size: 9)).foregroundStyle(muted)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(line))
    }

    private var contextPanel: some View {
        infoPanel("MARKET CONTEXT", model.orbDecision(for: model.pair)?.reason ?? "No current ORB evaluation. Press SCAN to request fresh Practice market data.")
    }
    private var checklistPanel: some View {
        infoPanel("SETUP CHECKLIST", "Market data: \(model.currentFXQuote == nil ? "unknown" : "available")  ·  ORB decision: \(model.orbDecision(for: model.pair) == nil ? "pending" : "evaluated")  ·  Risk: unresolved")
    }
    private var nextPanel: some View {
        infoPanel("NEXT STEP", model.currentFXQuote == nil ? "Connect Practice or scan for current source data." : "Review the engine decision; do not treat a forming setup as actionable.")
    }

    private var secondaryView: some View {
        Group {
            switch destination {
            case "Plans": ScrollView { VStack(alignment: .leading, spacing: 12) {
                Text("Practice plans").font(.system(size: 20, weight: .semibold))
                ForEach(["EUR/USD", "GBP/JPY"], id: \.self) { pair in
                    let plan = model.orbPlan(for: pair)
                    let state = model.spotFXPracticeState(for: pair)
                    HStack { VStack(alignment: .leading, spacing: 5) { Text(pair).font(.system(size: 14, weight: .semibold)); Text(state?.state.rawValue ?? "No saved lifecycle").font(.system(size: 11)).foregroundStyle(muted); if let plan { Text("Entry \(PriceFormat.px(plan.entryPrice)) · Stop \(PriceFormat.px(plan.stopPrice)) · Target \(PriceFormat.px(plan.targetPrice))").font(.system(size: 11, design: .monospaced)) } }; Spacer(); Text("risk_missing").font(.system(size: 10)).foregroundStyle(muted) }
                        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
                }
            }.padding(22) }
            case "My Trades": JournalScreen(model: model).padding(14)
            case "Settings": VStack(alignment: .leading, spacing: 12) { Text("Settings").font(.system(size: 20, weight: .semibold)); Text("Practice-only device credentials. This Mac app does not read iPhone Keychain items or collector environment variables.").font(.system(size: 12)).foregroundStyle(muted); Button("Manage OANDA Practice credentials") { model.showingCredentials = true }.buttonStyle(.borderedProminent).tint(blue) }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case "Learn": infoPanel("LEARN · ORB", "Opening Range Breakout: the engine evaluates a defined opening range and subsequent market structure. A forming condition is not an entry confirmation.").padding(22)
            default: infoPanel("ANALYTICS", "Performance analytics are not available for this Practice-only plan workflow yet.").padding(22)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
