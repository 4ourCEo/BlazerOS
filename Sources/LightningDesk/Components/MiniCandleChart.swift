import BlazerCore
import SwiftUI

struct MiniCandleChart: View, Equatable {
    var candles: [Candle]
    var strike: Double? = nil
    var currentPrice: Double? = nil
    var side: String? = nil
    var pair: String? = nil
    var candidateAnnotations: [Candidate001Candidate] = []
    var visibleBars: Int = 32
    var allowsZoom: Bool = false
    var lightAppearance: Bool = false
    var isLoading = false
    var emptyMessage: String? = nil

    @State private var scrubbedIndex: Int? = nil
    @State private var zoomScale: CGFloat = 1
    @State private var viewportShift: Int = 0

    static nonisolated func == (lhs: MiniCandleChart, rhs: MiniCandleChart) -> Bool {
        lhs.candles == rhs.candles
            && lhs.strike == rhs.strike
            && lhs.currentPrice == rhs.currentPrice
            && lhs.side == rhs.side
            && lhs.pair == rhs.pair
            && lhs.candidateAnnotations == rhs.candidateAnnotations
            && lhs.visibleBars == rhs.visibleBars
            && lhs.allowsZoom == rhs.allowsZoom
            && lhs.lightAppearance == rhs.lightAppearance
            && lhs.isLoading == rhs.isLoading
            && lhs.emptyMessage == rhs.emptyMessage
    }

    private var bars: [Candle] {
        let count = max(6, min(visibleBars, Int(CGFloat(visibleBars) / zoomScale)))
        let end = max(count, candles.count - viewportShift)
        let start = max(0, end - count)
        return Array(candles[start..<min(end, candles.count)])
    }

    var body: some View {
        Group {
            if bars.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                chartPlot(bars: bars)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bars.count)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(DeskInk.slate)
            }
            Text(isLoading ? "Loading candles\u{2026}" : (emptyMessage ?? "No candles available"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskInk.slate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(isLoading ? "Loading candles" : (emptyMessage ?? "No candles available"))
    }

    private func chartPlot(bars: [Candle]) -> some View {
        var values = bars.map(\.bodyHigh) + bars.map(\.bodyLow)
        if let s = strike { values.append(s) }
        if let cp = currentPrice { values.append(cp) }

        let rawMax = values.max() ?? 1.0
        let rawMin = values.min() ?? 0.0
        let rawSpan = max(rawMax - rawMin, 0.00002)
        let pad = rawSpan * 0.12
        let maxP = rawMax + pad
        let minP = rawMin - pad
        let span = maxP - minP

        return GeometryReader { geo in
            let showsAxis = geo.size.height >= 80
            let axisWidth: CGFloat = showsAxis ? 64 : 0
            let plotWidth = max(1, geo.size.width - axisWidth)
            let count = bars.count
            let spacing = candleSpacing(width: plotWidth, count: count)
            let totalSpacing = spacing * CGFloat(count - 1)
            let candleWidth = max(1.0, min(24.0, (plotWidth - totalSpacing) / CGFloat(count)))
            let effectiveWidth = (candleWidth + spacing) * CGFloat(count) - spacing
            let xOffset = max(0, plotWidth - effectiveWidth)
            let plotHeight = max(1, geo.size.height - (showsAxis ? 22 : 0))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        gridLines
                        CandleCanvas(
                            bars: bars,
                            minP: minP,
                            span: span,
                            strike: strike,
                            currentPrice: currentPrice,
                            side: side,
                            pair: pair,
                            candidateAnnotations: candidateAnnotations,
                            scrubbedIndex: scrubbedIndex,
                            lightAppearance: lightAppearance
                        )
                        if let idx = scrubbedIndex, idx >= 0, idx < bars.count {
                            scrubPill(for: bars[idx])
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .frame(width: plotWidth, height: plotHeight)
                    .background(lightAppearance ? Color.white : DeskInk.background)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let relativeX = value.location.x - xOffset
                                let rawIndex = Int(round((relativeX - candleWidth / 2) / (candleWidth + spacing)))
                                let clamped = max(0, min(count - 1, rawIndex))
                                if clamped != scrubbedIndex {
                                    scrubbedIndex = clamped
                                    DeskHaptics.scrubTick()
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    scrubbedIndex = nil
                                }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard allowsZoom else { return }
                                zoomScale = min(3, max(1, value))
                            }
                            .onEnded { _ in
                                guard allowsZoom else { return }
                                zoomScale = min(3, max(1, zoomScale))
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 14)
                            .onEnded { value in
                                guard allowsZoom, zoomScale > 1, candles.count > bars.count else { return }
                                let shift = Int((-value.translation.width / 18).rounded())
                                let maxShift = max(0, candles.count - bars.count)
                                viewportShift = min(maxShift, max(0, viewportShift + shift))
                            }
                    )
                    if showsAxis {
                        priceLabels(maxP: maxP, minP: minP)
                            .frame(width: axisWidth, height: plotHeight)
                            .opacity(scrubbedIndex == nil ? 1.0 : 0.25)
                            .animation(.easeInOut(duration: 0.15), value: scrubbedIndex)
                    }
                }
                .frame(height: plotHeight)
                if showsAxis {
                    timeAxis(bars)
                        .frame(width: plotWidth)
                        .frame(height: 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Interactive candle chart")
        .accessibilityHint(allowsZoom
            ? "Drag to scrub. Pinch to zoom and drag horizontally to browse candles"
            : "Drag horizontally to inspect earlier candles")
    }

    private func scrubPill(for bar: Candle) -> some View {
        HStack(spacing: 7) {
            ohlcField("TIME", candleTime(bar), tint: DeskInk.slate, weight: .medium)
            ohlcField("O", PriceFormat.px(bar.bodyOpen), tint: DeskInk.ink, weight: .medium)
            ohlcField("H", PriceFormat.px(bar.bodyHigh), tint: DeskInk.ink, weight: .medium)
            ohlcField("L", PriceFormat.px(bar.bodyLow), tint: DeskInk.ink, weight: .medium)
            ohlcField(
                "C", PriceFormat.px(bar.close),
                tint: bar.isUp ? DeskInk.emerald : DeskInk.coral, weight: .bold
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Capsule()
                .fill(DeskInk.surface.opacity(0.94))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
        .padding(.top, 4)
    }

    /// One label/value pair in the scrub pill.
    ///
    /// Kept as its own view so `scrubPill` stays cheap for the type checker; inlining four
    /// concatenated `Text` pairs in one `HStack` timed out on the Swift 6.1 toolchain.
    private func ohlcField(
        _ label: String, _ value: String, tint: Color, weight: Font.Weight
    ) -> some View {
        HStack(spacing: 0) {
            Text(label).foregroundStyle(DeskInk.slate.opacity(0.8))
            Text(" \(value)").foregroundStyle(tint)
        }
        .font(.system(size: 9.5, weight: weight, design: .monospaced))
        .accessibilityElement(children: .combine)
    }

    private var gridLines: some View {
        Canvas { context, size in
            for index in 0...4 {
                let y = size.height * CGFloat(index) / 4
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    line,
                    with: .color((lightAppearance ? Color(red: 0.16, green: 0.22, blue: 0.31) : Color.white).opacity(lightAppearance ? (index == 0 || index == 4 ? 0.14 : 0.07) : (index == 0 || index == 4 ? 0.11 : 0.065))),
                    style: StrokeStyle(lineWidth: index == 2 ? 0.9 : 0.6, dash: index == 2 ? [] : [3, 5])
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func priceLabels(maxP: Double, minP: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                ForEach(0..<5, id: \.self) { index in
                    let fraction = Double(index) / 4
                    let value = maxP - (maxP - minP) * fraction
                    Text(PriceFormat.px(value))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle((lightAppearance ? Color(red: 0.39, green: 0.48, blue: 0.59) : DeskInk.slate).opacity(0.92))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background((lightAppearance ? Color.white : DeskInk.background).opacity(0.88), in: RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: geometry.size.width - 30,
                            y: min(geometry.size.height - 8, max(8, geometry.size.height * CGFloat(fraction)))
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func timeAxis(_ bars: [Candle]) -> some View {
        let middle = bars.count / 2
        return HStack {
            Text(candleTime(bars.first))
            Spacer()
            Text(candleTime(bars.indices.contains(middle) ? bars[middle] : nil))
            Spacer()
            Text(candleTime(bars.last))
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle((lightAppearance ? Color(red: 0.39, green: 0.48, blue: 0.59) : DeskInk.slate).opacity(0.85))
        .padding(.horizontal, 4)
    }

    private func candleTime(_ candle: Candle?) -> String {
        guard let milliseconds = candle?.time, milliseconds.isFinite, milliseconds > 0 else { return "—" }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
            .formatted(date: .omitted, time: .shortened)
    }

    private func candleSpacing(width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return min(4.5, max(0.5, (width / CGFloat(count)) * 0.22))
    }
}

struct CandleCanvas: View {
    let bars: [Candle]
    let minP: Double
    let span: Double
    var strike: Double? = nil
    var currentPrice: Double? = nil
    var side: String? = nil
    var pair: String? = nil
    var candidateAnnotations: [Candidate001Candidate] = []
    var scrubbedIndex: Int? = nil
    var lightAppearance: Bool = false

    var body: some View {
        Canvas { context, size in
            let count = bars.count
            guard count > 0, span > 0 else { return }
            let spacing = min(4.5, max(0.5, (size.width / CGFloat(count)) * 0.22))
            let totalSpacing = spacing * CGFloat(count - 1)
            let candleWidth = max(1.0, min(24.0, (size.width - totalSpacing) / CGFloat(count)))
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
                let tint = bar.isUp
                    ? (lightAppearance ? Color(red: 0.06, green: 0.82, blue: 0.65) : DeskInk.emerald)
                    : (lightAppearance ? Color(red: 0.98, green: 0.36, blue: 0.48) : DeskInk.coral)

                var wickPath = Path()
                wickPath.move(to: CGPoint(x: cx, y: highY))
                wickPath.addLine(to: CGPoint(x: cx, y: lowY))
                context.stroke(wickPath, with: .color(tint.opacity(0.85)), lineWidth: 1.0)

                let bodyRect = CGRect(x: cx - candleWidth / 2, y: topBody, width: candleWidth, height: bodyHeight)
                let roundedBody = Path(roundedRect: bodyRect, cornerRadius: 1.0)
                context.fill(roundedBody, with: .color(tint))

                // Highlight latest candle with glowing edge
                if i == count - 1 {
                    context.stroke(
                        roundedBody,
                        with: .color(Color.white.opacity(0.4)),
                        lineWidth: 0.75
                    )
                }

            }

            drawCandidateAnnotations(
                context: &context,
                bars: bars,
                size: size,
                minP: minP,
                span: span,
                annotations: candidateAnnotations
            )

            // Reference close dashed line on last bar
            if let lastBar = bars.last {
                let closeFrac = CGFloat((lastBar.close - minP) / span)
                let lastY = height - (closeFrac * height)
                let lastTint = lastBar.isUp ? DeskInk.emerald : DeskInk.coral
                var refLine = Path()
                refLine.move(to: CGPoint(x: 0, y: lastY))
                refLine.addLine(to: CGPoint(x: size.width, y: lastY))
                context.stroke(refLine, with: .color(lastTint.opacity(0.25)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }

            // Laser Strike Horizon
            if let strikePrice = strike {
                let strikeFrac = CGFloat((strikePrice - minP) / span)
                let strikeY = max(2, min(height - 2, height - (strikeFrac * height)))

                var strikeLine = Path()
                strikeLine.move(to: CGPoint(x: 0, y: strikeY))
                strikeLine.addLine(to: CGPoint(x: size.width, y: strikeY))

                // Glowing strike laser
                context.stroke(
                    strikeLine,
                    with: .color(DeskInk.electric.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 2.0)
                )
                context.stroke(
                    strikeLine,
                    with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [6, 3])
                )
            }

            // Live Quote Diamond Beacon & Pip Drift Tag
            if let current = currentPrice {
                let currentFrac = CGFloat((current - minP) / span)
                let currentY = max(4, min(height - 4, height - (currentFrac * height)))
                let beaconX = size.width - 8

                var currentLine = Path()
                currentLine.move(to: CGPoint(x: 0, y: currentY))
                currentLine.addLine(to: CGPoint(x: size.width, y: currentY))
                context.stroke(currentLine, with: .color(DeskInk.electric.opacity(0.38)),
                               style: StrokeStyle(lineWidth: 0.8, dash: [2, 4]))

                let pipScale = Assets.pipScale(for: pair ?? "")
                let pipDiff = strike != nil ? (current - strike!) / pipScale : 0.0

                let isITM: Bool
                if let s = side {
                    isITM = s == "HIGH" ? pipDiff > 0 : (s == "LOW" ? pipDiff < 0 : false)
                } else {
                    isITM = pipDiff >= 0
                }
                let beaconTint = isITM ? DeskInk.emerald : DeskInk.coral

                // Diamond Path
                var diamond = Path()
                diamond.move(to: CGPoint(x: beaconX, y: currentY - 4))
                diamond.addLine(to: CGPoint(x: beaconX + 4, y: currentY))
                diamond.addLine(to: CGPoint(x: beaconX, y: currentY + 4))
                diamond.addLine(to: CGPoint(x: beaconX - 4, y: currentY))
                diamond.closeSubpath()

                // Glow halo
                context.fill(diamond, with: .color(beaconTint))
                context.stroke(diamond, with: .color(Color.white.opacity(0.9)), lineWidth: 0.75)
            }

            // Scrub Crosshair Cursor & Highlighted Close Beacon
            if let idx = scrubbedIndex, idx >= 0, idx < count {
                let sBar = bars[idx]
                let scx = xOffset + CGFloat(idx) * (candleWidth + spacing) + candleWidth / 2

                // Vertical laser cursor
                var crosshair = Path()
                crosshair.move(to: CGPoint(x: scx, y: 0))
                crosshair.addLine(to: CGPoint(x: scx, y: height))
                context.stroke(
                    crosshair,
                    with: .color(Color.white.opacity(0.38)),
                    style: StrokeStyle(lineWidth: 1.0, dash: [4, 3])
                )

                // Glowing beacon on bar close
                let cFrac = CGFloat((sBar.close - minP) / span)
                let cY = max(4, min(height - 4, height - (cFrac * height)))
                let dotRect = CGRect(x: scx - 3.5, y: cY - 3.5, width: 7, height: 7)
                let haloRect = CGRect(x: scx - 6.5, y: cY - 6.5, width: 13, height: 13)

                let tint = sBar.isUp ? DeskInk.emerald : DeskInk.coral
                context.fill(Path(ellipseIn: haloRect), with: .color(tint.opacity(0.3)))
                context.fill(Path(ellipseIn: dotRect), with: .color(tint))
                context.stroke(Path(ellipseIn: dotRect), with: .color(Color.white), lineWidth: 1.0)
            }
        }

    }

    private func drawCandidateAnnotations(
            context: inout GraphicsContext,
            bars: [Candle],
            size: CGSize,
            minP: Double,
            span: Double,
            annotations: [Candidate001Candidate]
        ) {
            guard !annotations.isEmpty else { return }
            let count = bars.count
        let spacing = min(4.5, max(0.5, (size.width / CGFloat(count)) * 0.22))
            let totalSpacing = spacing * CGFloat(count - 1)
        let candleWidth = max(1.0, min(24.0, (size.width - totalSpacing) / CGFloat(count)))
            let effectiveWidth = (candleWidth + spacing) * CGFloat(count) - spacing
            let xOffset = max(0, size.width - effectiveWidth)

            func y(for price: Double) -> CGFloat {
                size.height - CGFloat((price - minP) / span) * size.height
            }
            func x(for date: Date) -> CGFloat? {
                guard let index = bars.firstIndex(where: {
                    guard let time = $0.time else { return false }
                    return abs(time / 1000 - date.timeIntervalSince1970) < 0.5
                }) else { return nil }
                return xOffset + CGFloat(index) * (candleWidth + spacing) + candleWidth / 2
            }

            for candidate in annotations {
                let tint = candidate.direction == .bullish ? DeskInk.emerald : DeskInk.coral
                let fvgY = y(for: candidate.fvg.midpoint)
                var fvgLine = Path()
                fvgLine.move(to: CGPoint(x: 0, y: fvgY))
                fvgLine.addLine(to: CGPoint(x: size.width, y: fvgY))
                context.stroke(fvgLine, with: .color(tint.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                for level in [candidate.fibonacci.level50, candidate.fibonacci.level618] {
                    var fibLine = Path()
                    let levelY = y(for: level)
                    fibLine.move(to: CGPoint(x: 0, y: levelY))
                    fibLine.addLine(to: CGPoint(x: size.width, y: levelY))
                    context.stroke(fibLine, with: .color(DeskInk.violet.opacity(0.28)),
                                   style: StrokeStyle(lineWidth: 0.75, dash: [2, 4]))
                }

                guard let triggeredAt = candidate.triggeredAt,
                      let markerX = x(for: triggeredAt) else { continue }
                let markerY = y(for: candidate.fvg.midpoint)
                var marker = Path()
                marker.move(to: CGPoint(x: markerX, y: markerY - 5))
                marker.addLine(to: CGPoint(x: markerX + 5, y: markerY))
                marker.addLine(to: CGPoint(x: markerX, y: markerY + 5))
                marker.addLine(to: CGPoint(x: markerX - 5, y: markerY))
                marker.closeSubpath()
                context.fill(marker, with: .color(tint))
                context.stroke(marker, with: .color(Color.white.opacity(0.9)), lineWidth: 0.75)
        }
    }
}
