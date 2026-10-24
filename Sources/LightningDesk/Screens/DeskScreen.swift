import BlazerCore
import SwiftUI

struct DeskScreen: View {
    @ObservedObject var model: LightningDeskModel
    var reduceMotion: Bool
    @State private var showingPrimeSchedule = false
    @State private var showingStrikeSheet = false
    @State private var showingEntryDetails = false
    @State private var pressingOutcome: DeskOutcome?

    var body: some View {
        VStack(spacing: 0) {
            topIntelligenceBar
                .padding(.horizontal, 20)
                .padding(.top, 4)

            hero
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .offset(y: reduceMotion ? 0 : model.heroLift)

            if let receipt = model.settleReceipt {
                settleReceiptCard(receipt)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer(minLength: 10)

            ScanControl(
                scanning: model.scanning || model.otcSignalRefreshing,
                pair: model.pair,
                title: model.marketMode == .otc
                    ? (model.otcSignalRefreshing ? "Evaluating OTC research" : "Refresh OTC research")
                    : (model.scanStep ?? "Scan")
            ) {
                Task { await model.scan() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            Picker("Market", selection: $model.marketMode) {
                Text("Crypto").tag(DeskMarket.crypto)
                Text("FX").tag(DeskMarket.fx)
                Text("OTC").tag(DeskMarket.otc)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            .disabled(model.activeTrade != nil || model.awaitingOutcome
                || model.isSettlementInFlight || model.isEntryInFlight)
            .padding(.bottom, 8)

            if model.marketMode != .otc {
                Button {
                    DeskHaptics.tabSwitch()
                    showingStrikeSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "target")
                        Text("Track Strike Contract")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeskInk.electric)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.settleReceipt)
        .sheet(isPresented: $showingPrimeSchedule) {
            PrimeScheduleSheet()
        }
        .sheet(isPresented: $showingStrikeSheet) {
            StrikeTradeSheet(model: model)
        }
        .sheet(isPresented: $showingEntryDetails) {
            ManualEntryDetailsSheet(model: model)
        }
        .onChange(of: model.marketMode) { _, _ in
            Task { await model.scan() }
        }
    }

    private var topIntelligenceBar: some View {
        let edgeWindow = MarketEdgeWindow.current()
        let isOpen = FxSession.isOpen()
        let leader = model.radarLeader

        return HStack(spacing: 8) {
            // Left: Session / Prime Intel (Tappable to jump to Intel tab)
            Button {
                DeskHaptics.tabSwitch()
                model.activeTab = .intel
            } label: {
                let otcMode = model.marketMode == .otc
                let cryptoMode = model.marketMode == .crypto
                let sessionColor: Color = otcMode
                    ? (model.otcSignalConnectionState == .live ? DeskInk.emerald : DeskInk.violet)
                    : (cryptoMode
                        ? cryptoFeedTint(model.feed)
                        : (edgeWindow.isSupremePrime ? DeskInk.emerald : (edgeWindow.isTactical ? DeskInk.electric : (isOpen ? DeskInk.violet : DeskInk.coral))))
                let sessionLabel: String = otcMode
                    ? "🔬 OTC RESEARCH · \(model.otcSignalConnectionState.rawValue.uppercased())"
                    : (cryptoMode
                        ? "₿ \(model.feed.rawValue)"
                        : (edgeWindow.isSupremePrime ? "⚡ SUPREME PRIME" : (edgeWindow.isTactical ? "🌙 TACTICAL (BURSTS)" : "⚡ OFF-PEAK · \(FxSession.activeSessionName())")))

                HStack(spacing: 5) {
                    Circle()
                        .fill(sessionColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: sessionColor.opacity(0.8), radius: 3)

                    Text(sessionLabel)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(sessionColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(sessionColor.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            sessionColor.opacity(0.35),
                            lineWidth: 0.8
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(edgeWindow.isPrime ? "Prime window active" : "Off-peak session")
            .accessibilityHint("Tap to view Pacific Time prime window schedule and alert settings")

            Spacer(minLength: 4)

            // Right: Either Hot Radar Switch OR Next Prime Countdown
            if let leader, model.marketMode != .otc, leader.asset != model.pair, leader.conviction >= 65 {
                Button {
                    DeskHaptics.tabSwitch()
                    model.select(pair: leader.asset)
                } label: {
                    let badgeTint = leader.conviction >= 70 ? (leader.side == "LOW" ? DeskInk.coral : DeskInk.emerald) : DeskInk.electric
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(badgeTint)
                        Text(leader.asset)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(DeskInk.ink)
                        Text(leader.side == "LOW" ? "PUT \(leader.conviction)" : "CALL \(leader.conviction)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(badgeTint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(badgeTint.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(badgeTint.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(badgeTint.opacity(0.4), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Radar Leader \(leader.asset), \(leader.side == "LOW" ? "PUT" : "CALL") conviction \(leader.conviction)")
                .accessibilityHint("Tap to switch desk to \(leader.asset)")
            } else {
                Button {
                    DeskHaptics.tabSwitch()
                    model.activeTab = .intel
                } label: {
                    HStack(spacing: 4) {
                        Text(model.marketMode == .otc ? "RESEARCH ONLY" : edgeWindow.detailText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.marketMode == .otc
                                ? DeskInk.violet
                                : (edgeWindow.isPrime ? DeskInk.emerald : DeskInk.slate.opacity(0.85)))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(edgeWindow.isPrime ? DeskInk.emerald.opacity(0.7) : DeskInk.slate.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cryptoFeedTint(_ status: FeedStatus) -> Color {
        switch status {
        case .live: return DeskInk.emerald
        case .stale: return DeskInk.electric
        case .connecting: return DeskInk.violet
        case .disconnected, .error: return DeskInk.coral
        }
    }

    @ViewBuilder
    private var hero: some View {
        if model.marketMode == .otc {
            OTCResearchCard(model: model)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(heroSurface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityElement(children: .contain)
        } else {
            tradingHero
        }
    }

    private var tradingHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            pairRow
            MiniCandleChart(
                candles: model.candles,
                strike: model.activeTrade?.strike ?? (isArmed ? model.frame?.strike : nil),
                currentPrice: model.currentPrice,
                side: model.activeTrade?.side ?? model.side(for: model.pair),
                pair: model.pair
            )
            .equatable()
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            verdict
            if isArmed {
                rail
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroSurface)
        .overlay(alignment: .bottom) {
            if let blocked {
                Button {
                    Task { await model.scan() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DeskInk.coral)

                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("CAPITAL PRESERVED")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(DeskInk.coral)
                            Text(vetoExplanation(blocked))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DeskInk.slate)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 4)

                        Text("Rescan")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DeskInk.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DeskInk.coral.opacity(0.25), in: Capsule())
                            .overlay(Capsule().strokeBorder(DeskInk.coral.opacity(0.5), lineWidth: 0.8))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DeskInk.surface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DeskInk.coral.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
                    .padding(8)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .onTapGesture {
            if model.activeTrade == nil && isArmed {
                Task { await model.lockInTrade() }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -40 {
                        stepPair(1)
                    } else if value.translation.width > 40 {
                        stepPair(-1)
                    }
                }
        )
    }

    private var heroSurface: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(DeskInk.surface)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: ambientColors,
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .frame(height: 200)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.5), value: verbText)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        isArmed ? verbColor.opacity(0.4) : Color.white.opacity(0.08),
                        lineWidth: isArmed ? 1.0 : 0.5
                    )
                    .animation(.easeInOut(duration: 0.35), value: isArmed)
            )
            .shadow(
                color: isArmed ? verbColor.opacity(0.2) : Color.black.opacity(0.25),
                radius: isArmed ? 16 : 8,
                x: 0,
                y: isArmed ? 6 : 2
            )
            .animation(.easeInOut(duration: 0.35), value: isArmed)
    }

    private var ambientColors: [Color] {
        if model.scanning {
            return [DeskInk.violet.opacity(0.8), DeskInk.electric.opacity(0.25), .clear]
        }
        if let trade = model.activeTrade {
            if let isITM = trade.isInTheMoney {
                return isITM
                    ? [DeskInk.emerald.opacity(0.42), DeskInk.indigo.opacity(0.7), .clear]
                    : [DeskInk.coral.opacity(0.40), DeskInk.indigo.opacity(0.7), .clear]
            }
            return trade.side == "HIGH"
                ? [DeskInk.emerald.opacity(0.38), DeskInk.indigo.opacity(0.7), .clear]
                : [DeskInk.coral.opacity(0.35), DeskInk.indigo.opacity(0.7), .clear]
        }
        switch verbText {
        case "TAP HIGH", "HIGH ACTIVE":
            return [DeskInk.emerald.opacity(0.38), DeskInk.indigo.opacity(0.7), .clear]
        case "TAP LOW", "LOW ACTIVE":
            return [DeskInk.coral.opacity(0.35), DeskInk.indigo.opacity(0.7), .clear]
        default:
            return [DeskInk.indigo.opacity(0.85), DeskInk.electric.opacity(0.12), .clear]
        }
    }

    private var pairRow: some View {
        HStack(alignment: .center, spacing: 0) {
            pairStep(systemName: "chevron.left", delta: -1)

            Menu {
                ForEach(model.pairs, id: \.self) { p in
                    Button {
                        DeskHaptics.tabSwitch()
                        model.select(pair: p)
                    } label: {
                        HStack {
                            Text(p)
                            if let s = model.score(for: p) {
                                Text("· \(s)")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.pair)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(DeskInk.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DeskInk.slate.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            pairStep(systemName: "chevron.right", delta: 1)

            feedMark
                .padding(.leading, 4)

            Button {
                DeskHaptics.tabSwitch()
                model.showingCredentials = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskInk.slate.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SpringPressButtonStyle())
            .accessibilityLabel("Quote source settings")
        }
    }

    private func pairStep(systemName: String, delta: Int) -> some View {
        Button {
            stepPair(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DeskInk.slate)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel(delta < 0 ? "Previous pair" : "Next pair")
    }

    private var feedMark: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(feedColor)
                .frame(width: 6, height: 6)
                .shadow(color: feedColor.opacity(0.8), radius: 3)
            Text(feedWord)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(feedColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed \(feedWord)")
    }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Score + Live Strike
            HStack(alignment: .firstTextBaseline) {
                Text(scoreText)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minHeight: 56, alignment: .leading)
                    .animation(.spring(response: 0.45, dampingFraction: 0.72), value: scoreText)

                Spacer()

                Text(strikeText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate.opacity(0.85))
                    .monospacedDigit()
            }

            if let trade = model.activeTrade {
                HStack(spacing: 8) {
                    Circle()
                        .fill(verbColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: verbColor.opacity(0.9), radius: 4)

                    Text(trade.side == "HIGH" ? "CALL · HIGH" : "PUT · LOW")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(verbColor)

                    if let pip = trade.pipDiff {
                        let isITM = pip > 0
                        HStack(spacing: 3) {
                            Image(systemName: isITM ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%@%.1f pips", pip >= 0 ? "+" : "", pip))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(isITM ? DeskInk.emerald : DeskInk.coral)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((isITM ? DeskInk.emerald : DeskInk.coral).opacity(0.18), in: Capsule())
                    }
                }
                .frame(minHeight: 24, alignment: .leading)

                Text(whyText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            } else {
                let telemetry = model.stalkingTelemetry
                HStack(spacing: 8) {
                    if isArmed {
                        Circle()
                            .fill(verbColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: verbColor.opacity(0.9), radius: 4)
                        Text(verbText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(verbColor)

                        Text(telemetry.badgeLabel)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(telemetryBadgeColor(telemetry.tier))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(telemetryBadgeColor(telemetry.tier).opacity(0.16), in: Capsule())
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: telemetryIcon(telemetry.tier))
                                .font(.system(size: 9, weight: .bold))
                            Text(telemetry.badgeLabel)
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(telemetryBadgeColor(telemetry.tier))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(telemetryBadgeColor(telemetry.tier).opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(telemetryBadgeColor(telemetry.tier).opacity(0.35), lineWidth: 0.8))
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 8, weight: .bold))
                        Text(telemetry.stakeGuidance)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(telemetryBadgeColor(telemetry.tier).opacity(0.85))
                }
                .frame(minHeight: 24, alignment: .leading)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: verbText)

                Text(telemetry.telemetryDetail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            }

            if model.activeTrade == nil && isArmed {
                // Multi-Horizon Expiry Selector (60s | 3m | 5m)
                HStack(spacing: 8) {
                    horizonPill(seconds: 60, title: "60s")
                    horizonPill(seconds: 180, title: "3m")
                    horizonPill(seconds: 300, title: "5m")
                }
                .padding(.top, 2)

                Button {
                    Task { await model.lockInTrade() }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(verbColor.opacity(0.25))
                                .frame(width: 28, height: 28)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(verbColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RECORD \(horizonLabel(model.selectedHorizonSec)) MANUAL ENTRY")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(DeskInk.ink)
                            Text("Place it in Pocket Option first · Anchors live strike")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DeskInk.slate)
                        }
                        Spacer()
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(verbColor)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(verbColor.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [verbColor.opacity(0.8), verbColor.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: verbColor.opacity(0.15), radius: 8, y: 2)
                }
                .buttonStyle(SpringPressButtonStyle())
                .padding(.top, 4)
            } else if model.canLogLateEntry {
                Button {
                    Task { await model.lockInTrade(late: true) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DeskInk.electric)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LOG LATE ENTRY")
                                .font(.system(size: 12, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(DeskInk.ink)
                            Text("Beam closed · records the trade for data only")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DeskInk.slate)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DeskInk.electric)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DeskInk.electric.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DeskInk.electric.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(SpringPressButtonStyle())
                .padding(.top, 4)
            }

            if let issue = model.entryIssue {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(issue)
                        .font(.system(size: 10, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if model.canLogLateEntry {
                        Button("Log anyway") {
                            Task { await model.lockInTrade(late: true) }
                        }
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(DeskInk.electric)
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(DeskInk.coral)
                .padding(.top, 2)
                .transition(.opacity)
            }

            if model.awaitingOutcome {
                settlePanel
            }

            if model.pendingSaveCount > 0 {
                Button {
                    Task { await model.retryPendingSettlement() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("RETRY SAVING OUTCOME (\(model.pendingSaveCount))")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.4)
                    }
                    .foregroundStyle(DeskInk.coral)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DeskInk.coral.opacity(0.14), in: Capsule())
                }
                .buttonStyle(SpringPressButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Settle panel

    /// Post-expiry confirmation. The reference label is a suggestion only; the venue result
    /// is still recorded by the operator.
    private var settlePanel: some View {
        let reference = model.referenceSuggestion
        let side = model.settleSide ?? "WAIT"
        let isHigh = side.contains("HIGH")

        return VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(DeskInk.slate.opacity(0.18))

            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DeskInk.electric)
                Text("SETTLE ENTRY")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(DeskInk.ink)
                Spacer(minLength: 0)
                if let reference {
                    Text("REFERENCE \(reference.rawValue)")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(reference == .hit ? DeskInk.emerald : DeskInk.coral)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (reference == .hit ? DeskInk.emerald : DeskInk.coral).opacity(0.14),
                            in: Capsule()
                        )
                }
            }

            HStack(spacing: 6) {
                Text("Strike \(priceLabel(model.settleStrike))")
                Text("·").foregroundStyle(DeskInk.slate.opacity(0.5))
                Text("Ref \(priceLabel(model.expiryReferencePrice))")
                Text("·").foregroundStyle(DeskInk.slate.opacity(0.5))
                Text(pipsLabel(model.expiryReferenceDeltaPips))
                    .foregroundStyle(pipsTint(model.expiryReferenceDeltaPips))
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(DeskInk.slate)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            HStack(spacing: 10) {
                settleButton(
                    outcome: .hit,
                    title: "HIT",
                    subtitle: isHigh ? "Closed above strike" : "Closed below strike",
                    icon: "arrow.up.right",
                    tint: DeskInk.emerald,
                    isSuggested: reference == .hit
                ) {
                    Task { await model.confirmVenueOutcome(.hit) }
                }

                settleButton(
                    outcome: .miss,
                    title: "MISS",
                    subtitle: isHigh ? "Closed below strike" : "Closed above strike",
                    icon: "arrow.down.right",
                    tint: DeskInk.coral,
                    isSuggested: reference == .miss
                ) {
                    Task { await model.confirmVenueOutcome(.miss) }
                }
            }

            Button {
                Task { await model.confirmVenueOutcome(.unresolved) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("NOT SURE · RECORD AS UNVERIFIED")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                }
                .foregroundStyle(DeskInk.slate)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not sure. Record as unverified and exclude from statistics.")

            if let note = model.referenceSuggestionNote {
                Text(note)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 2)
    }

    private func settleButton(
        outcome: DeskOutcome,
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isSuggested: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let pressing = pressingOutcome == outcome

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(0.8)
                Spacer(minLength: 0)
                if isSuggested {
                    Text("SUGGESTED")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.2), in: Capsule())
                }
            }
            .foregroundStyle(tint)

            HStack(spacing: 4) {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "hand.tap")
                    Text("HOLD")
                }
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(DeskInk.slate.opacity(0.65))
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(pressing ? 0.34 : (isSuggested ? 0.28 : 0.11)),
                    tint.opacity(isSuggested ? 0.10 : 0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(pressing ? 1 : (isSuggested ? 0.85 : 0.3)), lineWidth: isSuggested || pressing ? 1.5 : 0.75)
        )
        .shadow(color: tint.opacity(isSuggested ? 0.18 : 0.04), radius: 10, y: 3)
        .scaleEffect(pressing ? 0.97 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.55, maximumDistance: 24) {
            pressingOutcome = nil
            DeskHaptics.tradeLocked()
            action()
        } onPressingChanged: { isPressing in
            withAnimation(.easeOut(duration: 0.15)) {
                if isPressing {
                    pressingOutcome = outcome
                } else if pressingOutcome == outcome {
                    pressingOutcome = nil
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(title). \(subtitle). Hold to confirm.")
        .accessibilityAction { action() }
    }

    private func settleReceiptCard(_ receipt: SettleReceipt) -> some View {
        let tint: Color = switch receipt.outcome {
        case .hit: DeskInk.emerald
        case .miss: DeskInk.coral
        case .unresolved: DeskInk.slate
        }
        let symbol: String = switch receipt.outcome {
        case .hit: "checkmark"
        case .miss: "xmark"
        case .unresolved: "questionmark"
        }
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(receipt.outcome.rawValue)
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                    Text(receipt.pair)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                }
                Text(receiptLine(receipt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("RECORDED")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(DeskInk.slate.opacity(0.7))
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { model.dismissSettleReceipt() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recorded \(receipt.outcome.rawValue) on \(receipt.pair).")
    }

    private func receiptLine(_ receipt: SettleReceipt) -> String {
        if receipt.outcome == .unresolved {
            return "unverified · excluded from confirmed stats"
        }
        var parts: [String] = []
        if let pips = receipt.pips, pips.isFinite {
            parts.append(String(format: "%+.1fp", pips))
        }
        parts.append("\(Int((receipt.payout * 100).rounded()))% payout")
        parts.append(receipt.labelSource == "venue-confirmed" ? "venue confirmed" : receipt.labelSource)
        return parts.joined(separator: " · ")
    }

    private func priceLabel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let pip = model.settleAsset.map { Assets.pipScale(for: $0) } ?? 0.0001
        let decimals = max(0, Int(round(-log10(max(pip, 0.00001)))) + 1)
        return String(format: "%.\(decimals)f", value)
    }

    private func pipsLabel(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%+.1fp", value)
    }

    private func pipsTint(_ value: Double?) -> Color {
        guard let value else { return DeskInk.slate }
        if value > 0 { return DeskInk.emerald }
        if value < 0 { return DeskInk.coral }
        return DeskInk.slate
    }

    private var bookStrip: some View {
        BookStripView(
            book: model.book,
            selectedPair: model.pair,
            onSelect: { asset in model.select(pair: asset) }
        )
        .equatable()
    }

    private var isArmed: Bool {
        if model.activeTrade != nil { return true }
        guard let frame = model.frame else { return false }
        return frame.isActionable
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trade = model.activeTrade {
                let isITM = trade.isInTheMoney ?? false
                let pip = trade.pipDiff ?? 0.0
                let statusTint = isITM ? DeskInk.emerald : DeskInk.coral

                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 7, height: 7)
                            .shadow(color: statusTint.opacity(0.9), radius: 4)

                        Text(railLabel)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(DeskInk.ink)
                            .monospacedDigit()
                    }

                    Spacer()

                    Button {
                        showingEntryDetails = true
                    } label: {
                        Text(trade.brokerEntryPrice == nil ? "Add broker details" : "Edit broker details")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DeskInk.electric)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add optional broker entry price, stake, and payout")

                    // Dynamic Live Pip Cushion Pill
                    HStack(spacing: 4) {
                        Text(String(format: "%@%.1f pips", pip >= 0 ? "+" : "", pip))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        Text(isITM ? "ITM" : "OTM")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(statusTint.opacity(0.16), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(statusTint.opacity(0.4), lineWidth: 0.8)
                    )
                }

                if let age = trade.evaluationAgeMs, let remaining = trade.remainingBeamMs {
                    Text(String(format: "Recorded %.1fs after scan · %.1fs beam left", age / 1000, remaining / 1000))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                        .accessibilityLabel(String(format: "Recorded %.1f seconds after the scan. %.1f seconds of the action window remained.", age / 1000, remaining / 1000))
                }

                GeometryReader { geo in
                    let fillWidth = max(0, min(geo.size.width, geo.size.width * railFraction))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [statusTint.opacity(0.7), statusTint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                            .shadow(color: statusTint.opacity(0.8), radius: 6, y: 0)

                        if fillWidth > 8 {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 7, height: 7)
                                .shadow(color: .white, radius: 4)
                                .shadow(color: statusTint, radius: 6)
                                .offset(x: fillWidth - 7)
                        }
                    }
                }
                .frame(height: 7)
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: railFraction)
            } else {
                // 8s Action Window (Pre-trade)
                GeometryReader { geo in
                    let fillWidth = max(0, min(geo.size.width, geo.size.width * railFraction))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [DeskInk.violet, DeskInk.electric, verbColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth)
                            .shadow(color: verbColor.opacity(0.6), radius: 6, y: 0)

                        if fillWidth > 8 {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .shadow(color: .white, radius: 4)
                                .shadow(color: verbColor, radius: 6)
                                .offset(x: fillWidth - 6)
                        }
                    }
                }
                .frame(height: 6)
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: railFraction)

                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(railFraction < 0.25 ? DeskInk.coral : verbColor)
                            .frame(width: 5, height: 5)
                        Text(railLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(railFraction < 0.25 ? DeskInk.coral : DeskInk.ink)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(minHeight: 14, alignment: .leading)

                    Spacer()

                    Text("ACTION WINDOW")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(verbColor)
                }
            }
        }
    }

    // MARK: - Computed helpers

    private var feedWord: String { model.frame?.feed.rawValue ?? model.feed.rawValue }

    private var feedColor: Color {
        switch model.frame?.feed ?? model.feed {
        case .live:                     return DeskInk.emerald
        case .stale, .error:            return DeskInk.coral
        case .connecting, .disconnected: return DeskInk.slate
        }
    }

    private func stepPair(_ delta: Int) {
        let pairs = model.pairs
        guard let index = pairs.firstIndex(of: model.pair) else { return }
        let next = pairs[(index + delta + pairs.count) % pairs.count]
        model.select(pair: next)
    }

    private var scoreText: String {
        guard let frame = model.frame else { return "—" }
        return "\(frame.score)"
    }

    private var verbText: String { model.frame?.verb ?? "SCAN" }

    private var whyText: String {
        if model.scanning, let why = model.frame?.why, !why.isEmpty { return why }
        if let notice = model.notice, !notice.isEmpty { return spoken(notice) }
        if let why = model.frame?.why, !why.isEmpty { return why }
        return "Press Scan"
    }

    private func spoken(_ notice: String) -> String {
        if notice == "OANDA token missing" { return "Quote source unavailable" }
        if notice.hasPrefix("Scanning ") { return "Press Scan" }
        return notice
    }

    private var blocked: String? {
        guard let veto = model.frame?.veto, !veto.isEmpty else { return nil }
        return veto
    }

    private func vetoExplanation(_ veto: String) -> String {
        switch veto {
        case "Slippage":
            return "Slippage Brake · Price drifted adversely. Rescan for fresh entry."
        default:
            return veto
        }
    }

    private var strikeText: String {
        if let trade = model.activeTrade {
            let pxMid = trade.currentPrice.map { " · Live \(PriceFormat.px($0))" } ?? ""
            return "Strike \(PriceFormat.px(trade.strike))\(pxMid)"
        }
        guard let frame = model.frame else { return "Strike —" }
        return "Strike \(PriceFormat.px(frame.strike))"
    }

    private var railFraction: CGFloat {
        if let trade = model.activeTrade {
            guard trade.durationSec > 0 else { return 0 }
            return CGFloat(min(1, max(0, (trade.remainingMs / 1000.0) / trade.durationSec)))
        }
        guard let frame = model.frame, Timing.liveMs > 0 else { return 0 }
        return CGFloat(min(1, max(0, frame.remainingMs / Timing.liveMs)))
    }

    private func horizonPill(seconds: Double, title: String) -> some View {
        let isSelected = model.selectedHorizonSec == seconds
        return Button {
            DeskHaptics.tabSwitch()
            model.selectedHorizonSec = seconds
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? DeskInk.electric.opacity(0.28) : Color.white.opacity(0.04), in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? DeskInk.electric.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func horizonLabel(_ seconds: Double) -> String {
        if seconds >= 60 {
            let m = Int(seconds) / 60
            return "\(m)m"
        }
        return "\(Int(seconds))s"
    }

    private var railLabel: String {
        if let trade = model.activeTrade {
            let remSec = trade.remainingMs / 1000
            if remSec >= 60 {
                let m = Int(remSec) / 60
                let s = Int(remSec) % 60
                return String(format: "%dm %02ds REMAINING", m, s)
            }
            return String(format: "%.1fs REMAINING", remSec)
        }
        guard let frame = model.frame, frame.remainingMs > 0 else { return " " }
        return String(format: "%.1fs TO ENTER", frame.remainingMs / 1000)
    }

    private var verbColor: Color {
        if let trade = model.activeTrade {
            return trade.side == "HIGH" ? DeskInk.emerald : DeskInk.coral
        }
        switch verbText {
        case "TAP HIGH", "HIGH ACTIVE": return DeskInk.emerald
        case "TAP LOW", "LOW ACTIVE":  return DeskInk.coral
        default:                        return DeskInk.slate
        }
    }

    // MARK: - Telemetry Helpers

    private func telemetryBadgeColor(_ tier: StalkingTelemetry.Tier) -> Color {
        switch tier {
        case .apexPrime: return DeskInk.emerald
        case .tacticalProbe: return DeskInk.electric
        case .stalkingSetup: return DeskInk.violet
        case .capitalShield: return DeskInk.slate
        case .safetyBrake, .pairWarning: return DeskInk.coral
        }
    }

    private func telemetryIcon(_ tier: StalkingTelemetry.Tier) -> String {
        switch tier {
        case .apexPrime: return "bolt.fill"
        case .tacticalProbe: return "scope"
        case .stalkingSetup: return "binoculars.fill"
        case .capitalShield: return "shield.fill"
        case .safetyBrake, .pairWarning: return "exclamationmark.shield.fill"
        }
    }
}
