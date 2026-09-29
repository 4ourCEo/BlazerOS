import BlazerCore
import SwiftUI

struct MarketsScreen: View {
    @ObservedObject var model: LightningDeskModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let leader = model.radarLeader {
                        radarLeaderBanner(leader)
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(model.pairs, id: \.self) { pair in
                            MarketTacticalTile(
                                pair: pair,
                                isSelected: pair == model.pair,
                                score: model.score(for: pair),
                                side: model.side(for: pair) ?? "WAIT",
                                strike: model.strike(for: pair),
                                candles: model.candles(for: pair)
                            ) {
                                DeskHaptics.tabSwitch()
                                model.selectAndNavigate(pair: pair)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Radar")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Text("Opportunity Matrix · 6 Core Pairs")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(feedColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: feedColor.opacity(0.8), radius: 3)
                Text(feedWord)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(feedColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DeskInk.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    private var feedWord: String { model.frame?.feed.rawValue ?? model.feed.rawValue }

    private var feedColor: Color {
        switch model.frame?.feed ?? model.feed {
        case .live:                     return DeskInk.emerald
        case .stale, .error:            return DeskInk.coral
        case .connecting, .disconnected: return DeskInk.slate
        }
    }

    private func radarLeaderBanner(_ leader: (asset: String, score: Int, side: String)) -> some View {
        Button {
            DeskHaptics.tabSwitch()
            model.selectAndNavigate(pair: leader.asset)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(DeskInk.electric.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DeskInk.electric)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("RADAR LEADER")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(DeskInk.electric)
                        if leader.side == "HIGH" || leader.side == "LOW" {
                            Text(leader.side == "HIGH" ? "CALL" : "PUT")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(leader.side == "HIGH" ? DeskInk.emerald : DeskInk.coral)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background((leader.side == "HIGH" ? DeskInk.emerald : DeskInk.coral).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(leader.asset)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(DeskInk.ink)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("SCORE \(leader.score)")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(leader.score >= 70 ? DeskInk.emerald : DeskInk.electric)
                    HStack(spacing: 3) {
                        Text("Trade on Desk")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DeskInk.slate)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DeskInk.electric)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DeskInk.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(DeskInk.electric.opacity(0.4), lineWidth: 1.0)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tactical Matrix Tile

struct MarketTacticalTile: View {
    let pair: String
    let isSelected: Bool
    let score: Int?
    let side: String
    let strike: Double?
    let candles: [Candle]
    let action: () -> Void

    private var conviction: MarketEdgeWindow.PairConviction {
        MarketEdgeWindow.conviction(for: pair)
    }

    private var isHighConviction: Bool {
        (score ?? 0) >= 70 && (side == "HIGH" || side == "LOW")
    }

    private var tint: Color {
        switch side {
        case "HIGH": return DeskInk.emerald
        case "LOW":  return DeskInk.coral
        default:     return isSelected ? DeskInk.electric : DeskInk.slate
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Top Row: Pair & Desk status
                HStack(alignment: .center, spacing: 6) {
                    Text(pair)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(DeskInk.ink)

                    if case .edgeConfirmed = conviction {
                        Text("EDGE")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(DeskInk.emerald)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(DeskInk.emerald.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else if case .chopRisk = conviction {
                        Text("CHOP")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(DeskInk.coral)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(DeskInk.coral.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    Spacer()

                    if isSelected {
                        Text("DESK")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(DeskInk.electric)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DeskInk.electric.opacity(0.18), in: Capsule())
                    } else if isHighConviction {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .shadow(color: tint.opacity(0.9), radius: 3)
                    }
                }

                // Middle Row: Radial Score Arc + Micro Sparkline
                HStack(spacing: 8) {
                    scoreGauge
                    sparklineView
                        .frame(height: 38)
                        .frame(maxWidth: .infinity)
                }

                // Bottom Row: Directional Badge & Strike
                HStack(alignment: .center) {
                    HStack(spacing: 3) {
                        if side == "HIGH" {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        } else if side == "LOW" {
                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text(sideBadgeText)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer()

                    if let s = strike {
                        Text(PriceFormat.px(s))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DeskInk.slate.opacity(0.8))
                            .monospacedDigit()
                    }
                }
            }
            .padding(12)
            .frame(height: 126)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DeskInk.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? DeskInk.electric.opacity(0.5) : (isHighConviction ? tint.opacity(0.4) : Color.white.opacity(0.06)),
                        lineWidth: isSelected || isHighConviction ? 1.0 : 0.5
                    )
            )
            .shadow(
                color: isHighConviction ? tint.opacity(0.12) : Color.black.opacity(0.2),
                radius: isHighConviction ? 8 : 4,
                y: 2
            )
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel("\(pair) score \(score ?? 0) \(side)")
    }

    private var scoreGauge: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
                .frame(width: 38, height: 38)

            let fraction = Double(min(100, max(0, score ?? 0))) / 100.0
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.6), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 38, height: 38)

            Text("\(score ?? 0)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(DeskInk.ink)
                .monospacedDigit()
        }
    }

    private var sparklineView: some View {
        GeometryReader { geo in
            let bars = Array(candles.suffix(14))
            if bars.count >= 2 {
                let closes = bars.map(\.close)
                let minC = closes.min() ?? 0
                let maxC = closes.max() ?? 1
                let span = max(maxC - minC, 0.00001)
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Subtle Area Gradient Fill
                    Path { path in
                        for (index, val) in closes.enumerated() {
                            let x = CGFloat(index) / CGFloat(closes.count - 1) * w
                            let y = h - (CGFloat((val - minC) / span) * (h - 8) + 4)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: h))
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Trend Line
                    Path { path in
                        for (index, val) in closes.enumerated() {
                            let x = CGFloat(index) / CGFloat(closes.count - 1) * w
                            let y = h - (CGFloat((val - minC) / span) * (h - 8) + 4)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    // Live Beacon Node on Last Bar
                    if let lastVal = closes.last {
                        let lastY = h - (CGFloat((lastVal - minC) / span) * (h - 8) + 4)
                        Circle()
                            .fill(tint)
                            .frame(width: 4.5, height: 4.5)
                            .position(x: w, y: lastY)
                            .shadow(color: tint.opacity(0.8), radius: 3)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text("—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DeskInk.slate.opacity(0.4))
                    Spacer()
                }
            }
        }
    }

    private var sideBadgeText: String {
        switch side {
        case "HIGH": return "HIGH"
        case "LOW":  return "LOW"
        default:     return "WAIT"
        }
    }
}
