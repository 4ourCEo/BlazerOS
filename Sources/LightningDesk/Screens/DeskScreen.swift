import BlazerCore
import SwiftUI

struct DeskScreen: View {
    @ObservedObject var model: LightningDeskModel
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            sessionPill
                .padding(.horizontal, 20)
                .padding(.top, 4)

            hero
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .offset(y: reduceMotion ? 0 : model.heroLift)

            Spacer(minLength: 12)

            ScanControl(
                scanning: model.scanning,
                pair: model.pair,
                title: model.scanStep ?? "Scan"
            ) {
                Task { await model.scan() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var sessionPill: some View {
        let edgeWindow = MarketEdgeWindow.current()
        let isOpen = FxSession.isOpen()

        return HStack(spacing: 6) {
            Circle()
                .fill(edgeWindow.isPrime ? DeskInk.emerald : (isOpen ? DeskInk.slate : DeskInk.coral))
                .frame(width: 6, height: 6)
                .shadow(color: (edgeWindow.isPrime ? DeskInk.emerald : DeskInk.slate).opacity(0.8), radius: 3)

            Text(edgeWindow.isPrime ? "⚡ \(edgeWindow.badgeTitle)" : FxSession.activeSessionName())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(edgeWindow.isPrime ? DeskInk.emerald : DeskInk.slate)

            Spacer()

            Text(edgeWindow.detailText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(edgeWindow.isPrime ? DeskInk.emerald : DeskInk.slate.opacity(0.75))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var hero: some View {
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
            .frame(height: 136)
            .frame(maxWidth: .infinity)
            verdict
            if !model.book.isEmpty {
                bookStrip
            }
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
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(vetoExplanation(blocked))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("Rescan")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DeskInk.coral.opacity(0.18), in: Capsule())
                    }
                    .foregroundStyle(DeskInk.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DeskInk.surface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                model.lockInTrade()
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

            Text(model.pair)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DeskInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.pair)

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
        VStack(alignment: .leading, spacing: 4) {
            Text(scoreText)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(DeskInk.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minHeight: 58, alignment: .leading)
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: scoreText)

            if let trade = model.activeTrade {
                HStack(spacing: 8) {
                    Circle()
                        .fill(verbColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: verbColor.opacity(0.9), radius: 4)

                    Text(trade.side == "HIGH" ? "CALL · HIGH" : "PUT · LOW")
                        .font(.system(size: 22, weight: .bold))
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
                .frame(minHeight: 26, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    if isArmed {
                        Circle()
                            .fill(verbColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: verbColor.opacity(0.9), radius: 4)
                    }
                    Text(verbText)
                        .font(.system(size: isArmed ? 22 : 20, weight: isArmed ? .bold : .semibold))
                        .foregroundStyle(verbColor)
                        .opacity(verbText == "WAIT" ? 0.62 : 1)
                }
                .frame(minHeight: 26, alignment: .leading)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: verbText)
            }

            Text(whyText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                .animation(.easeInOut(duration: 0.25), value: whyText)

            Text(strikeText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.85))
                .monospacedDigit()

            if model.activeTrade == nil && isArmed {
                Button {
                    model.lockInTrade()
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
                            Text("LOCK IN 60s POSITION")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(DeskInk.ink)
                            Text("Anchors live strike · Tap before beam expires")
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
            }

            if model.awaitingOutcome {
                HStack(spacing: 10) {
                    outcomeChoice(
                        model.predictedOutcome == .hit ? "HIT (WIN)" : "HIT",
                        tint: DeskInk.emerald,
                        isHighlighted: model.predictedOutcome == .hit
                    ) {
                        Task { await model.settle(.hit) }
                    }
                    outcomeChoice(
                        model.predictedOutcome == .miss ? "MISS (LOSS)" : "MISS",
                        tint: DeskInk.coral,
                        isHighlighted: model.predictedOutcome == .miss
                    ) {
                        Task { await model.settle(.miss) }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func outcomeChoice(_ title: String, tint: Color, isHighlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(tint.opacity(isHighlighted ? 0.25 : 0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(isHighlighted ? 0.9 : 0.35), lineWidth: isHighlighted ? 1.5 : 0.75)
                )
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel(title)
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
        return frame.remainingMs > 0
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
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

                if isArmed {
                    Text(model.activeTrade != nil ? "60s BINARY HORIZON" : "ACTION WINDOW")
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

    private var railLabel: String {
        if let trade = model.activeTrade {
            return String(format: "%.1fs REMAINING", trade.remainingMs / 1000)
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
}
