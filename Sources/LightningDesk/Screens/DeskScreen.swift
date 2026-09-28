import BlazerCore
import SwiftUI

struct DeskScreen: View {
    @ObservedObject var model: LightningDeskModel
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .offset(y: reduceMotion ? 0 : model.heroLift)

            Spacer(minLength: 16)

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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            pairRow
            MiniCandleChart(candles: model.candles)
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
                Text(blocked)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DeskInk.surface.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
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
                    colors: [DeskInk.indigo.opacity(0.85), DeskInk.electric.opacity(0.12), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .frame(height: 180)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
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
            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Previous pair" : "Next pair")
    }

    private var feedMark: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(feedColor)
                .frame(width: 6, height: 6)
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
                .frame(minHeight: 58, alignment: .leading)
            Text(verbText)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(verbColor)
                .opacity(verbText == "WAIT" ? 0.62 : 1)
                .frame(minHeight: 24, alignment: .leading)
            Text(whyText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text(strikeText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.85))
                .monospacedDigit()

            if model.awaitingOutcome {
                HStack(spacing: 10) {
                    outcomeChoice("HIT", tint: DeskInk.emerald) {
                        Task { await model.settle(.hit) }
                    }
                    outcomeChoice("MISS", tint: DeskInk.coral) {
                        Task { await model.settle(.miss) }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func outcomeChoice(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
        guard let frame = model.frame else { return false }
        return frame.remainingMs > 0
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(DeskInk.violet)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * railFraction)))
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: railFraction)
            Text(railLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskInk.slate)
                .monospacedDigit()
                .frame(minHeight: 14, alignment: .leading)
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

    private var strikeText: String {
        guard let frame = model.frame else { return "Strike —" }
        return "Strike \(PriceFormat.px(frame.strike))"
    }

    private var railFraction: CGFloat {
        guard let frame = model.frame, Timing.liveMs > 0 else { return 0 }
        return CGFloat(min(1, max(0, frame.remainingMs / Timing.liveMs)))
    }

    private var railLabel: String {
        guard let frame = model.frame, frame.remainingMs > 0 else { return " " }
        return String(format: "%.1fs", frame.remainingMs / 1000)
    }

    private var verbColor: Color {
        switch verbText {
        case "TAP HIGH": return DeskInk.emerald
        case "TAP LOW":  return DeskInk.coral
        default:         return DeskInk.slate
        }
    }
}
