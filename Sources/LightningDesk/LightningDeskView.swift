import SwiftUI
import BlazerCore
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// One-handed execution desk. The hero card is the product. Scan lives in the lower third.
public struct LightningDeskView: View {
    public init(model: LightningDeskModel) {
        self.model = model
    }
    @ObservedObject var model: LightningDeskModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(spacing: 0) {
                hero
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .offset(y: reduceMotion ? 0 : model.heroLift)
                Spacer(minLength: 20)
                ScanControl(
                    scanning: model.scanning,
                    pair: model.pair,
                    title: model.scanStep ?? "Scan"
                ) {
                    Task { await model.scan() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                glassNav
                    .padding(.bottom, 22)
            }

            if model.showingLaunch {
                LaunchCover(
                    status: launchWord,
                    markLit: reduceMotion || model.launchMarkLit,
                    wordLit: reduceMotion || model.launchWordLit
                )
                .transition(.opacity)
            }

            if model.showingJournal {
                JournalCover(model: model)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.showingLaunch)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: model.heroLift)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: verbText)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: model.frame?.veto)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.showingJournal)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: model.openReplayID)
        .onChange(of: model.frame?.fingerprint) { previous, next in
            guard let next, next != previous else { return }
            DeskHaptics.commit()
        }
        .onChange(of: model.frame?.veto) { previous, next in
            guard let next, !next.isEmpty, next != previous else { return }
            DeskHaptics.veto()
        }
        .task { await model.run() }
        .task { await model.settleLaunch() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            pairRow
            MiniCandleChart(candles: model.candles)
                .frame(height: 148)
                .frame(maxWidth: .infinity)
            verdict
            if !model.book.isEmpty {
                bookStrip
            }
            rail
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroSurface)
        .overlay(alignment: .bottom) {
            if let blocked {
                Text(blocked)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(DeskInk.surface.opacity(0.94))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var heroSurface: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(DeskInk.surface)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [DeskInk.indigo.opacity(0.95), DeskInk.electric.opacity(0.15), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .mask(
                    LinearGradient(
                        colors: [.black, .black.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var pairRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                pairStep(systemName: "chevron.left", delta: -1)
                Text(model.pair)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                pairStep(systemName: "chevron.right", delta: 1)
            }
            HStack {
                Spacer(minLength: 0)
                feedMark
            }
            .padding(.trailing, 8)
        }
    }

    private func pairStep(systemName: String, delta: Int) -> some View {
        Button {
            stepPair(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DeskInk.slate)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Previous pair" : "Next pair")
    }

    private var feedMark: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(feedColor)
                .frame(width: 6, height: 6)
            Text(feedWord)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
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
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(DeskInk.ink)
                .monospacedDigit()
                .frame(minHeight: 68, alignment: .leading)
            Text(verbText)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(verbColor)
                .opacity(verbText == "WAIT" ? 0.62 : 1)
                .frame(minHeight: 28, alignment: .leading)
            Text(whyText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            Text(strikeText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.85))
                .monospacedDigit()
        }
    }

    private var bookStrip: some View {
        let columns = [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(model.book) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.asset)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(row.side)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(bookInk(row.side))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.book.map { "\($0.asset) \($0.side)" }.joined(separator: ", "))
    }

    private func bookInk(_ side: String) -> Color {
        switch side {
        case "HIGH":
            return DeskInk.emerald
        case "LOW":
            return DeskInk.coral
        case "WAIT", "—":
            return DeskInk.slate
        default:
            return DeskInk.slate
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(DeskInk.violet)
                        .frame(width: max(0, geo.size.width * railFraction))
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? nil : .linear(duration: 0.1), value: railFraction)
            Text(railLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskInk.slate)
                .monospacedDigit()
                .frame(minHeight: 16, alignment: .leading)
        }
    }

    private var glassNav: some View {
        Button {
            model.showJournal()
        } label: {
            HStack(spacing: 8) {
                markImage
                    .frame(width: 18, height: 18)
                Text("Blazer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeskInk.ink.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Journal")
    }

    @ViewBuilder
    private var markImage: some View {
        if let url = Bundle.module.url(forResource: "BlazerMark", withExtension: "png") {
            #if os(macOS)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #elseif os(iOS)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #endif
        }
    }

    private var launchWord: String {
        switch model.feed {
        case .live:
            return "LIVE"
        case .connecting:
            return "CONNECTING"
        case .stale, .disconnected, .error:
            return "OFFLINE"
        }
    }

    private var feedWord: String {
        model.frame?.feed.rawValue ?? model.feed.rawValue
    }

    private var feedColor: Color {
        switch model.frame?.feed ?? model.feed {
        case .live:
            return DeskInk.emerald
        case .stale, .error:
            return DeskInk.coral
        case .connecting, .disconnected:
            return DeskInk.slate
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

    private var verbText: String {
        model.frame?.verb ?? "SCAN"
    }

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
        case "TAP HIGH":
            return DeskInk.emerald
        case "TAP LOW":
            return DeskInk.coral
        case "EXPIRED":
            return DeskInk.slate
        case "WAIT", "SCAN":
            return DeskInk.slate
        default:
            return DeskInk.slate
        }
    }
}

/// One control. Scanning changes the fill and the word inside the same bounds.
private struct ScanControl: View {
    var scanning: Bool
    var pair: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: scanning
                                ? [DeskInk.violet.opacity(0.85), DeskInk.indigo.opacity(0.9)]
                                : [DeskInk.indigo, DeskInk.electric],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                if scanning {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.35) / 1.35
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: geo.size.width * 0.34, height: geo.size.height)
                                .offset(x: -geo.size.width * 0.45 + phase * geo.size.width * 1.35)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .allowsHitTesting(false)
                }
                Text(scanning ? title : "Scan")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .disabled(scanning)
        .animation(.easeInOut(duration: 0.35), value: scanning)
        .accessibilityLabel(scanning ? "Scanning \(title)" : "Scan \(pair)")
    }
}

private struct JournalCover: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Journal")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Spacer()
                    Button("Close") { model.hideJournal() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                if model.journal.isEmpty {
                    Text("A scan you commit lands here.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 24)
                    Spacer()
                } else {
                    cardStack
                        .padding(.horizontal, 24)
                    Spacer()
                }
            }

            if let entry = model.journal.first(where: { $0.id == model.openReplayID }) {
                ReplayCover(entry: entry) { model.closeReplay() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var cardStack: some View {
        let cards = Array(model.journal.prefix(4))
        return ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated().reversed()), id: \.element.id) { index, entry in
                Button {
                    model.openReplay(entry.id)
                } label: {
                    journalFace(
                        pair: entry.pair,
                        score: "\(entry.score)",
                        verb: entry.verb,
                        why: entry.veto ?? entry.why,
                        when: entry.scannedAt.formatted(date: .omitted, time: .shortened)
                    )
                }
                .buttonStyle(.plain)
                .offset(y: CGFloat(index) * 22)
                .scaleEffect(1 - CGFloat(index) * 0.035, anchor: .top)
                .accessibilityLabel("\(entry.pair) \(entry.verb) \(entry.score)")
            }
        }
        .padding(.bottom, CGFloat(max(0, cards.count - 1)) * 22)
    }

    private func journalFace(pair: String, score: String, verb: String, why: String, when: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pair)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Text(when)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(score)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .monospacedDigit()
                Text(verb)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(verbInk(verb))
                    .opacity(verb == "WAIT" ? 0.62 : 1)
            }
            Text(why.isEmpty ? " " : why)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct ReplayCover: View {
    var entry: ReplayEntry
    var close: () -> Void

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(entry.pair)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Spacer()
                    Button("Close") { close() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                }
                Text(entry.scannedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                MiniCandleChart(candles: entry.candles)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                Text("\(entry.score)")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .monospacedDigit()
                Text(entry.verb)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(verbInk(entry.verb))
                    .opacity(entry.verb == "WAIT" ? 0.62 : 1)
                Text(entry.why.isEmpty ? " " : entry.why)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Strike \(PriceFormat.px(entry.strike))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
                if let veto = entry.veto, !veto.isEmpty {
                    Text(veto)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DeskInk.coral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Spacer()
                Text(entry.fingerprint)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate.opacity(0.7))
            }
            .padding(24)
            .padding(.top, 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.pair) \(entry.verb) \(entry.score)")
    }
}

private func verbInk(_ verb: String) -> Color {
    switch verb {
    case "TAP HIGH":
        return DeskInk.emerald
    case "TAP LOW":
        return DeskInk.coral
    case "EXPIRED", "WAIT", "SCAN":
        return DeskInk.slate
    default:
        return DeskInk.slate
    }
}

private struct MiniCandleChart: View {
    var candles: [Candle]

    var body: some View {
        GeometryReader { geo in
            let bars = Array(candles.suffix(32))
            if bars.isEmpty {
                Text("Waiting for candles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxP = bars.map(\.bodyHigh).max() ?? 1
                let minP = bars.map(\.bodyLow).min() ?? 0
                let span = max(maxP - minP, 0.00001)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                            let height = max(4, (bar.bodyHigh - bar.bodyLow) / span * (geo.size.height - 4))
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(bar.isUp ? DeskInk.emerald : DeskInk.coral)
                                .frame(maxWidth: .infinity)
                                .frame(height: height)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Completed candles")
    }
}

/// Same mark as BlazerMac. Status is passed in. This view does not decide LIVE.
private struct LaunchCover: View {
    var status: String
    var markLit: Bool
    var wordLit: Bool

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(spacing: 22) {
                markImage
                    .frame(width: 112, height: 112)
                    .scaleEffect(markLit ? 1 : 0.94)
                    .opacity(markLit ? 1 : 0)
                    .animation(.easeOut(duration: 0.45), value: markLit)
                Text("BLAZER")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(DeskInk.ink)
                    .opacity(wordLit ? 1 : 0)
                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(DeskInk.slate)
                    .opacity(wordLit ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.35), value: wordLit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blazer \(status)")
    }

    @ViewBuilder
    private var markImage: some View {
        if let url = Bundle.module.url(forResource: "BlazerMark", withExtension: "png") {
            #if os(macOS)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #elseif os(iOS)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #endif
        }
    }
}

private enum DeskHaptics {
    static func commit() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        #endif
    }

    static func veto() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
        #endif
    }
}

enum DeskInk {
    static let background = Color(red: 11.0 / 255, green: 15.0 / 255, blue: 23.0 / 255)
    static let surface = Color(red: 21.0 / 255, green: 29.0 / 255, blue: 42.0 / 255)
    static let indigo = Color(red: 79.0 / 255, green: 70.0 / 255, blue: 229.0 / 255)
    static let electric = Color(red: 47.0 / 255, green: 128.0 / 255, blue: 255.0 / 255)
    static let emerald = Color(red: 16.0 / 255, green: 185.0 / 255, blue: 129.0 / 255)
    static let coral = Color(red: 240.0 / 255, green: 113.0 / 255, blue: 103.0 / 255)
    static let violet = Color(red: 139.0 / 255, green: 124.0 / 255, blue: 255.0 / 255)
    static let ink = Color.white
    static let slate = Color(red: 148.0 / 255, green: 163.0 / 255, blue: 184.0 / 255)
}
