import BlazerCore
import SwiftUI

struct MarketsScreen: View {
    @ObservedObject var model: LightningDeskModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            radar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text("All markets")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(DeskInk.ink)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.pairs, id: \.self) { pair in
                    MarketTacticalTile(
                        pair: pair,
                        isSelected: pair == model.pair,
                        score: model.score(for: pair),
                        side: model.side(for: pair) ?? "WAIT",
                        strike: model.strike(for: pair),
                        candles: model.candles(for: pair),
                        orbDecision: model.orbDecision(for: pair),
                        orbPlan: currentORBPlan(for: pair),
                        feed: model.frame?.feed ?? model.feed,
                        scanState: scanState
                    ) {
                        DeskHaptics.tabSwitch()
                        model.selectAndNavigate(pair: pair)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            }
        }
    }

    private var radar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live market intelligence")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                    Text("Focus on what matters.")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DeskInk.ink)
                }
                Spacer()
                Text("\(model.pairs.count) PAIRS")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(DeskInk.slate)
            }

            RadarPlot(model: model, reduceMotion: reduceMotion)

            radarStatusStrip

            radarDetailCard
        }
    }

    private var radarStatusStrip: some View {
        let eligible = model.pairs.filter { ["HIGH", "LOW"].contains(model.side(for: $0)) }.count
        return HStack(spacing: 0) {
            radarStatusCell(title: "MONITORED", value: "\(model.pairs.count)")
            Divider().frame(height: 28).overlay(Color.white.opacity(0.08))
            radarStatusCell(title: "DESK SIGNALS", value: eligible == 0 ? "—" : "\(eligible)")
            Divider().frame(height: 28).overlay(Color.white.opacity(0.08))
            radarStatusCell(title: "FEED", value: feedWord)
        }
        .padding(.vertical, 10)
        .background(DeskInk.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Monitored \(model.pairs.count), desk signals \(eligible), feed \(feedWord), scan \(scanState)")
    }

    private func radarStatusCell(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(DeskInk.slate)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(DeskInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var radarDetailCard: some View {
        let pair = model.pair
        let side = model.side(for: pair) ?? "WAIT"
        let tint = radarTint(side)

        return Button {
            DeskHaptics.tabSwitch()
            model.selectAndNavigate(pair: pair)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .shadow(color: tint.opacity(0.75), radius: 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pair)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DeskInk.ink)
                        Text("M1")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DeskInk.slate)
                    }
                     Text("Research preview · tap for full scan")
                         .font(.system(size: 10, weight: .medium))
                         .foregroundStyle(DeskInk.slate)
                     if let orb = model.orbDecision(for: pair) {
                         Text("ORB · \(orb.stage.displayName)")
                             .font(.system(size: 9, weight: .bold, design: .monospaced))
                             .foregroundStyle(orb.stage == .setupConfirmed ? DeskInk.electric : DeskInk.slate)
                         Text(orb.reason.replacingOccurrences(of: "_", with: " "))
                             .font(.system(size: 9, weight: .medium))
                             .foregroundStyle(DeskInk.slate)
                             .lineLimit(1)
                     } else {
                         Text("ORB · NO_DATA · no engine decision")
                              .font(.system(size: 9, weight: .medium, design: .monospaced))
                              .foregroundStyle(DeskInk.slate)
                     }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(side == "HIGH" ? "CALL ↑" : side == "LOW" ? "PUT ↓" : "WAIT")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    if let score = model.score(for: pair) {
                        Text("Score \(score)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(DeskInk.slate)
                    }
                }
            }
            .padding(14)
            .background(DeskInk.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pair), \(side), ORB \(model.orbDecision(for: pair)?.stage.rawValue ?? "NO_DATA"), research preview. Tap for full scan.")
        .accessibilityIdentifier("markets.radar.detail.\(pair.replacingOccurrences(of: "/", with: "-"))")
    }

    private func radarTint(_ side: String) -> Color {
        switch side {
        case "HIGH": return DeskInk.emerald
        case "LOW": return DeskInk.coral
        default: return DeskInk.slate
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

    private var scanState: String {
        if model.scanning { return model.scanStep.map { "SCANNING \($0)" } ?? "SCANNING" }
        return model.lastScanAt == nil ? "NOT_SCANNED" : "SCAN_COMPLETE"
    }

    private func currentORBPlan(for pair: String) -> V3TradePlan? {
        guard let candidatePlan = model.orbDecision(for: pair)?.candidate?.plan,
              let cachedPlan = model.orbPlan(for: pair),
              candidatePlan.id == cachedPlan.id else { return nil }
        return cachedPlan
    }

    private var feedColor: Color {
        switch model.frame?.feed ?? model.feed {
        case .live:                     return DeskInk.emerald
        case .stale, .error:            return DeskInk.coral
        case .connecting, .disconnected: return DeskInk.slate
        }
    }

    private func radarLeaderBanner(_ leader: (asset: String, score: Int, conviction: Int, side: String)) -> some View {
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
                    Text("\(leader.side == "LOW" ? "PUT" : "CALL") \(leader.conviction)%")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(leader.conviction >= 70 ? (leader.side == "LOW" ? DeskInk.coral : DeskInk.emerald) : DeskInk.electric)
                    HStack(spacing: 3) {
                        Text("Review research")
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

private struct RadarPlot: View {
    @ObservedObject var model: LightningDeskModel
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.43

            ZStack {
                RadarGrid(center: center, radius: radius, reduceMotion: reduceMotion)

                ForEach(Array(model.pairs.enumerated()), id: \.element) { index, pair in
                    Button {
                        DeskHaptics.tabSwitch()
                        model.select(pair: pair)
                    } label: {
                        radarMarker(pair: pair, isSelected: pair == model.pair)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(radarAccessibilityLabel(for: pair))
                    .accessibilityAddTraits(pair == model.pair ? .isSelected : [])
                    .position(markerPoint(index: index, pair: pair, center: center, radius: radius))
                }

                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DeskInk.electric)
                    .frame(width: 46, height: 46)
                    .background(DeskInk.background, in: Circle())
                    .overlay(Circle().strokeBorder(DeskInk.electric.opacity(0.7), lineWidth: 1))
                    .shadow(color: DeskInk.electric.opacity(0.45), radius: 14)
                    .position(center)
            }
        }
        .frame(height: 285)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar plot for \(model.pairs.count) markets")
    }

    private func markerPoint(index: Int, pair: String, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard let score = model.score(for: pair) else { return center }
        let scoreValue = Double(score)
        let normalized = max(0.28, min(0.86, scoreValue / 100))
        let angle = (Double(index) / Double(max(model.pairs.count, 1))) * (.pi * 2) - (.pi / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius * normalized,
            y: center.y + CGFloat(sin(angle)) * radius * normalized
        )
    }

    private func radarMarker(pair: String, isSelected: Bool) -> some View {
        let side = model.side(for: pair) ?? "WAIT"
        let tint: Color
        if model.score(for: pair) == nil {
            tint = DeskInk.slate
        } else {
            tint = switch side {
            case "HIGH": DeskInk.emerald
            case "LOW": DeskInk.coral
            default: DeskInk.slate
            }
        }

        return VStack(spacing: 3) {
            Circle()
                .fill(tint)
                .frame(width: isSelected ? 15 : 9, height: isSelected ? 15 : 9)
                .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.8 : 0.35), lineWidth: 1))
                .shadow(color: tint.opacity(0.8), radius: isSelected ? 9 : 5)
            if isSelected {
                Text(model.score(for: pair) == nil ? "\(pair) · UNSCORED" : pair)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DeskInk.surface.opacity(0.95), in: Capsule())
            }
        }
    }

    private func radarAccessibilityLabel(for pair: String) -> String {
        let side = model.side(for: pair) ?? "WAIT"
        let direction = side == "HIGH" ? "CALL" : side == "LOW" ? "PUT" : side
        let score = model.score(for: pair).map { ", score \($0)" } ?? ""
        let orb = model.orbDecision(for: pair)
        let stage = orb?.stage.rawValue ?? "NO_DATA"
        let reason = orb?.reason.replacingOccurrences(of: "_", with: " ") ?? "no ORB engine decision"
        return "\(pair), \(direction)\(score), ORB \(stage), \(reason)\(pair == model.pair ? ", selected" : "")"
    }
}

private struct RadarGrid: View {
    let center: CGPoint
    let radius: CGFloat
    let reduceMotion: Bool

    var body: some View {
        Canvas { context, _ in
            for step in 1...4 {
                let diameter = radius * 2 * CGFloat(step) / 4
                let ring = Path(ellipseIn: CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                ))
                context.stroke(ring, with: .color(DeskInk.indigo.opacity(step == 4 ? 0.42 : 0.22)), lineWidth: 0.8)
            }

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: center.x - radius, y: center.y))
            horizontal.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            context.stroke(horizontal, with: .color(DeskInk.indigo.opacity(0.22)), lineWidth: 0.7)

            var vertical = Path()
            vertical.move(to: CGPoint(x: center.x, y: center.y - radius))
            vertical.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(vertical, with: .color(DeskInk.indigo.opacity(0.22)), lineWidth: 0.7)
        }
        .overlay {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let period = 7.0
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period * .pi * 2
                    Canvas { sweepContext, _ in
                        for offset in stride(from: 0.22, through: 0.02, by: -0.04) {
                            var path = Path()
                            let trailAngle = angle - offset * .pi
                            path.move(to: center)
                            path.addLine(to: CGPoint(x: center.x + cos(trailAngle) * radius, y: center.y + sin(trailAngle) * radius))
                            sweepContext.stroke(path, with: .color(DeskInk.electric.opacity(0.10 + (0.22 - offset) * 1.7)), lineWidth: offset < 0.06 ? 1.2 : 0.8)
                        }
                    }
                }
            }
        }
    }
}

private extension ORBStage {
    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
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
    let orbDecision: ORBDecision?
    let orbPlan: V3TradePlan?
    let feed: FeedStatus
    let scanState: String
    let action: () -> Void

    private var conviction: MarketEdgeWindow.PairConviction {
        MarketEdgeWindow.conviction(for: pair)
    }

    private var convictionRating: Int {
        let raw = score ?? 0
        return raw
    }

    private var isHighConviction: Bool {
        convictionRating >= 70 && (side == "HIGH" || side == "LOW")
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
                        Text("PRIOR")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(DeskInk.emerald)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(DeskInk.emerald.opacity(0.16), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else if case .chopRisk = conviction {
                        Text("EXCLUDED")
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

                orbResearchSummary
            }
            .padding(12)
            .frame(minHeight: 174)
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
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("markets.tile.\(pair.replacingOccurrences(of: "/", with: "-"))")
    }

    private var orbResearchSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("ORB \(orbDecision?.stage.displayName ?? "NO_DATA")")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(orbDecision == nil ? DeskInk.slate : tint)
                Spacer()
                Text(isSelected ? feed.rawValue : "NOT SELECTED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected && feed == .live ? DeskInk.emerald : DeskInk.slate)
            }
            Text(orbDecision?.reason.replacingOccurrences(of: "_", with: " ") ?? "No ORB engine decision for this instrument.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(1)
            if let orbPlan {
                Text("RESEARCH PLAN · INDICATIVE · NOT EXECUTABLE")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(DeskInk.electric)
                Text("\(orbPlan.state.rawValue) · \(PriceFormat.px(orbPlan.entryPrice)) → \(PriceFormat.px(orbPlan.targetPrice)) · stop \(PriceFormat.px(orbPlan.stopPrice))")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
                    .lineLimit(1)
            } else {
                Text("No research plan available · \(scanState)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(DeskInk.slate.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.top, 1)
    }

    private var accessibilitySummary: String {
        let stage = orbDecision?.stage.rawValue ?? "NO_DATA"
        let reason = orbDecision?.reason.replacingOccurrences(of: "_", with: " ") ?? "no ORB engine decision"
        let plan = orbPlan == nil ? "no research plan" : "indicative research plan, not executable"
        let feedState = isSelected ? feed.rawValue : "UNVERIFIED, not selected"
        return "\(pair), \(sideBadgeText), score \(score.map { String($0) } ?? "NO_DATA"), ORB \(stage), \(reason), \(plan), feed \(feedState), \(scanState)"
    }

    private var scoreGauge: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 3)
                .frame(width: 38, height: 38)

            let fraction = Double(min(100, max(0, convictionRating))) / 100.0
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

            Text(score.map { String($0) } ?? "—")
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
        case "HIGH": return "CALL"
        case "LOW":  return "PUT"
        default:     return "WAIT"
        }
    }
}
