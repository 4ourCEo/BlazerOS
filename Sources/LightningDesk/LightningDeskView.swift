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
            .modifier(ReferencePhoneInset())

            if model.showingLaunch {
                LaunchCover(
                    status: launchWord,
                    markLit: reduceMotion || model.launchMarkLit,
                    wordLit: reduceMotion || model.launchWordLit
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            if model.showingJournal {
                JournalCover(model: model)
                    .modifier(ReferencePhoneInset())
                    .transition(.opacity)
            }

            if !model.showingLaunch && model.keychainState == .missing {
                CredentialCover(model: model)
                    .modifier(ReferencePhoneInset())
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
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
                .equatable()
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
            if model.awaitingOutcome {
                HStack(spacing: 10) {
                    outcomeChoice("HIT", tint: DeskInk.emerald) {
                        Task { await model.settle(.hit) }
                    }
                    outcomeChoice("MISS", tint: DeskInk.coral) {
                        Task { await model.settle(.miss) }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func outcomeChoice(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var bookStrip: some View {
        BookStripView(
            book: model.book,
            selectedPair: model.pair,
            onSelect: { asset in
                model.select(pair: asset)
            }
        )
        .equatable()
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journal")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(DeskInk.ink)
                        if model.outcomeStats.hits + model.outcomeStats.misses > 0 {
                            Text("\(model.outcomeStats.hits) HIT · \(model.outcomeStats.misses) MISS")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DeskInk.slate)
                                .monospacedDigit()
                        }
                    }
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
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(model.journal) { entry in
                                Button {
                                    model.openReplay(entry.id)
                                } label: {
                                    journalFace(
                                        pair: entry.pair,
                                        score: "\(entry.score)",
                                        verb: entry.outcome ?? entry.verb,
                                        why: entry.veto ?? entry.why,
                                        when: entry.scannedAt.formatted(date: .omitted, time: .shortened)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(entry.pair) \(entry.outcome ?? entry.verb) \(entry.score)")
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                    }
                }
            }

            if let entry = model.journal.first(where: { $0.id == model.openReplayID }) {
                ReplayCover(entry: entry, coach: model.coachExplanation) { model.closeReplay() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
    var coach: CoachExplanation?
    var close: () -> Void

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            ScrollView {
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
                    .equatable()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                Text("\(entry.score)")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .monospacedDigit()
                Text(entry.outcome ?? entry.verb)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(verbInk(entry.verb))
                    .opacity((entry.outcome ?? entry.verb) == "WAIT" ? 0.62 : 1)
                Text(entry.why.isEmpty ? " " : entry.why)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let coach {
                    CoachCard(explanation: coach)
                }
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
    case "HIT":
        return DeskInk.emerald
    case "MISS":
        return DeskInk.coral
    case "EXPIRED", "WAIT", "SCAN":
        return DeskInk.slate
    default:
        return DeskInk.slate
    }
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

private struct CandleCanvas: View {
    let bars: [Candle]
    let minP: Double
    let span: Double

    var body: some View {
        Canvas { context, size in
            let count = bars.count
            guard count > 0, span > 0 else { return }
            let spacing: CGFloat = 3.5
            let totalSpacing = spacing * CGFloat(count - 1)
            let candleWidth = max(2.5, min(8.0, (size.width - totalSpacing) / CGFloat(count)))
            let effectiveWidth = (candleWidth + spacing) * CGFloat(count) - spacing
            let xOffset = max(0, size.width - effectiveWidth)
            let height = size.height

            for (i, bar) in bars.enumerated() {
                let cx = xOffset + CGFloat(i) * (candleWidth + spacing) + candleWidth / 2
                let highFrac = CGFloat((bar.bodyHigh - minP) / span)
                let lowFrac = CGFloat((bar.bodyLow - minP) / span)
                let openFrac = CGFloat((bar.bodyOpen - minP) / span)
                let closeFrac = CGFloat((bar.close - minP) / span)

                let highY = height - (highFrac * height)
                let lowY = height - (lowFrac * height)
                let openY = height - (openFrac * height)
                let closeY = height - (closeFrac * height)

                let topBody = min(openY, closeY)
                let bottomBody = max(openY, closeY)
                let bodyHeight = max(2.5, bottomBody - topBody)
                let tint = bar.isUp ? DeskInk.emerald : DeskInk.coral

                // Wick: 1pt line from high to low
                var wickPath = Path()
                wickPath.move(to: CGPoint(x: cx, y: highY))
                wickPath.addLine(to: CGPoint(x: cx, y: lowY))
                context.stroke(wickPath, with: .color(tint.opacity(0.85)), lineWidth: 1.0)

                // Body: rounded rect
                let bodyRect = CGRect(
                    x: cx - candleWidth / 2,
                    y: topBody,
                    width: candleWidth,
                    height: bodyHeight
                )
                let roundedBody = Path(roundedRect: bodyRect, cornerRadius: 1.0)
                context.fill(roundedBody, with: .color(tint))
            }

            // Reference line on last close
            if let lastBar = bars.last {
                let closeFrac = CGFloat((lastBar.close - minP) / span)
                let lastY = height - (closeFrac * height)
                var refLine = Path()
                refLine.move(to: CGPoint(x: 0, y: lastY))
                refLine.addLine(to: CGPoint(x: size.width, y: lastY))
                context.stroke(
                    refLine,
                    with: .color(Color.white.opacity(0.12)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
                )
            }
        }
    }
}

private struct BookStripView: View, Equatable {
    let book: [BookRow]
    let selectedPair: String
    let onSelect: (String) -> Void

    static nonisolated func == (lhs: BookStripView, rhs: BookStripView) -> Bool {
        lhs.book == rhs.book && lhs.selectedPair == rhs.selectedPair
    }

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(book) { row in
                Button {
                    onSelect(row.asset)
                } label: {
                    BookCell(row: row, isSelected: row.asset == selectedPair)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(book.map { "\($0.asset) \($0.side)" }.joined(separator: ", "))
    }
}

private struct BookCell: View {
    let row: BookRow
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.asset)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(row.side)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bookInk(row.side))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.white.opacity(0.08)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct MiniCandleChart: View, Equatable {
    var candles: [Candle]

    static nonisolated func == (lhs: MiniCandleChart, rhs: MiniCandleChart) -> Bool {
        lhs.candles == rhs.candles
    }

    private var bars: [Candle] {
        Array(candles.suffix(32))
    }

    var body: some View {
        if bars.isEmpty {
            loadingState
        } else {
            chartPlot(bars: bars)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(DeskInk.slate)
            Text("Loading candles…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskInk.slate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading candles")
    }

    private func chartPlot(bars: [Candle]) -> some View {
        let rawMax = bars.map(\.bodyHigh).max() ?? 1.0
        let rawMin = bars.map(\.bodyLow).min() ?? 0.0
        let rawSpan = max(rawMax - rawMin, 0.00002)
        let pad = rawSpan * 0.08
        let maxP = rawMax + pad
        let minP = rawMin - pad
        let span = maxP - minP

        return ZStack(alignment: .topTrailing) {
            gridLines
            CandleCanvas(bars: bars, minP: minP, span: span)
            priceLabels(high: rawMax, low: rawMin)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Completed candles")
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.04))
            Spacer()
            Divider().background(Color.white.opacity(0.03))
            Spacer()
            Divider().background(Color.white.opacity(0.04))
        }
    }

    private func priceLabels(high: Double, low: Double) -> some View {
        VStack {
            Text(PriceFormat.px(high))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.55))
                .padding(.trailing, 4)
            Spacer()
            Text(PriceFormat.px(low))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.55))
                .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
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

/// Mac reference window uses the iPhone 16 safe areas. iOS applies the real insets.
private struct ReferencePhoneInset: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .padding(.top, PhoneTarget.topInset)
            .padding(.bottom, PhoneTarget.bottomInset)
        #else
        content
        #endif
    }
}

/// Shown only when the phone Keychain has no OANDA session. Not a second desk.
private struct CredentialCover: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Quote source")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Text("Saved in the Keychain on this device only.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                SecureField("Token", text: $model.draftToken)
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(DeskInk.ink)
                TextField("Account", text: $model.draftAccount)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(DeskInk.ink)
                HStack(spacing: 10) {
                    environmentChoice(.practice, title: "Practice")
                    environmentChoice(.live, title: "Live")
                }
                if model.credentialSaveFailed {
                    Text("Could not save to the Keychain.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DeskInk.coral)
                }
                Button {
                    model.credentialSaveFailed = !model.storeCredentials(
                        token: model.draftToken,
                        accountId: model.draftAccount,
                        environment: model.draftEnvironment
                    )
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(colors: [DeskInk.indigo, DeskInk.electric], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.draftAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 8)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
    }

    private func environmentChoice(_ choice: OandaEnvironment, title: String) -> some View {
        Button {
            model.draftEnvironment = choice
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.draftEnvironment == choice ? DeskInk.ink : DeskInk.slate)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    (model.draftEnvironment == choice ? DeskInk.indigo.opacity(0.45) : DeskInk.surface),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
