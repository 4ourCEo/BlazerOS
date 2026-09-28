import BlazerCore
import SwiftUI

struct MiniCandleChart: View, Equatable {
    var candles: [Candle]
    var strike: Double? = nil
    var currentPrice: Double? = nil
    var side: String? = nil
    var pair: String? = nil

    static nonisolated func == (lhs: MiniCandleChart, rhs: MiniCandleChart) -> Bool {
        lhs.candles == rhs.candles
            && lhs.strike == rhs.strike
            && lhs.currentPrice == rhs.currentPrice
            && lhs.side == rhs.side
            && lhs.pair == rhs.pair
    }

    private var bars: [Candle] {
        Array(candles.suffix(32))
    }

    var body: some View {
        Group {
            if bars.isEmpty {
                loadingState
                    .transition(.opacity)
            } else {
                chartPlot(bars: bars)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bars.count)
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(DeskInk.slate)
            Text("Loading candles\u{2026}")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeskInk.slate.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading candles")
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

        return ZStack(alignment: .topTrailing) {
            gridLines
            CandleCanvas(
                bars: bars,
                minP: minP,
                span: span,
                strike: strike,
                currentPrice: currentPrice,
                side: side,
                pair: pair
            )
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

struct CandleCanvas: View {
    let bars: [Candle]
    let minP: Double
    let span: Double
    var strike: Double? = nil
    var currentPrice: Double? = nil
    var side: String? = nil
    var pair: String? = nil

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

                let pipScale = (pair?.contains("JPY") == true || current > 50) ? 0.01 : 0.0001
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
        }
    }
}
