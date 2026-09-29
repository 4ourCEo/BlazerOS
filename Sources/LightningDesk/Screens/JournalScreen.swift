import BlazerCore
import SwiftUI

struct JournalScreen: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    } else {
                        Text("Performance & History")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DeskInk.slate)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if model.outcomeStats.hits + model.outcomeStats.misses > 0 {
                        let total = model.outcomeStats.hits + model.outcomeStats.misses
                        let rate = Int(round(Double(model.outcomeStats.hits) / Double(total) * 100))
                        Text("\(rate)% WIN")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(rate >= 50 ? DeskInk.emerald : DeskInk.coral)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((rate >= 50 ? DeskInk.emerald : DeskInk.coral).opacity(0.12), in: Capsule())
                    }

                    if !model.journal.isEmpty {
                        ShareLink(
                            item: csvLedgerData,
                            subject: Text("BlazerOS Trade Ledger"),
                            message: Text("Exported \(model.journal.count) entries from BlazerOS Ledger"),
                            preview: SharePreview("BlazerOS_Ledger.csv", icon: Image(systemName: "tablecells"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DeskInk.electric)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(DeskInk.electric.opacity(0.14), in: Capsule())
                                .overlay(Capsule().strokeBorder(DeskInk.electric.opacity(0.35), lineWidth: 0.8))
                        }
                        .accessibilityLabel("Export Ledger CSV")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if model.journal.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "book.closed")
                        .font(.system(size: 38))
                        .foregroundStyle(DeskInk.slate.opacity(0.6))
                    Text("No Journal Entries")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text("Committed and settled scans are permanently appended to the local ledger and appear here.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if model.outcomeStats.hits + model.outcomeStats.misses > 0 {
                            PerformanceAnalyticsCard(
                                hits: model.outcomeStats.hits,
                                misses: model.outcomeStats.misses,
                                journal: model.journal
                            )
                        }

                        VStack(spacing: 10) {
                            ForEach(model.journal) { entry in
                                Button {
                                    DeskHaptics.tabSwitch()
                                    model.openReplay(entry.id)
                                } label: {
                                    JournalRowCard(entry: entry)
                                }
                                .buttonStyle(SpringPressButtonStyle())
                                .accessibilityLabel("\(entry.pair) \(entry.outcome ?? entry.verb) \(entry.score)")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var csvLedgerData: String {
        var rows = ["Timestamp,Pair,Score,Outcome,Strike,EdgeVerdict,Evidence"]
        for entry in model.journal {
            let outcome = entry.outcome ?? entry.verb
            let sanitizedWhy = entry.why.replacingOccurrences(of: "\"", with: "\"\"")
            let row = "\"\(entry.scannedAt)\",\"\(entry.pair)\",\(entry.score),\"\(outcome)\",\(entry.strike),\"\(entry.verb)\",\"\(sanitizedWhy)\""
            rows.append(row)
        }
        return rows.joined(separator: "\n")
    }
}

struct JournalRowCard: View {
    let entry: ReplayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.pair)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Text(entry.scannedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(entry.score)")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                    .monospacedDigit()
                Text(entry.outcome ?? entry.verb)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verbInk(entry.outcome ?? entry.verb))
                    .opacity((entry.outcome ?? entry.verb) == "WAIT" ? 0.62 : 1)
                Spacer()
                Text("Strike \(PriceFormat.px(entry.strike))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate.opacity(0.85))
            }

            Text(entry.why.isEmpty ? " " : entry.why)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let veto = entry.veto, !veto.isEmpty {
                Text(veto)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DeskInk.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if let voiceNote = entry.voiceNote, !voiceNote.transcript.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.violet)
                    Text(voiceNote.transcript)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeskInk.violet.opacity(0.95))
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DeskInk.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct PerformanceAnalyticsCard: View {
    let hits: Int
    let misses: Int
    let journal: [ReplayEntry]

    @State private var stakeAmount: Double = 25.0

    private var totalSettled: Int { hits + misses }
    private var winRate: Double {
        totalSettled > 0 ? (Double(hits) / Double(totalSettled)) * 100.0 : 0
    }
    private var edgeVsBreakeven: Double {
        winRate - 54.05
    }

    private var netDollarPnL: Double {
        let winProfit = Double(hits) * (stakeAmount * 0.85)
        let lossAmount = Double(misses) * stakeAmount
        return winProfit - lossAmount
    }

    private var currentStreak: (count: Int, isHit: Bool)? {
        guard !recentOutcomes.isEmpty else { return nil }
        let firstIsHit = recentOutcomes[0] == "HIT"
        var streak = 0
        for item in recentOutcomes {
            if (item == "HIT") == firstIsHit {
                streak += 1
            } else {
                break
            }
        }
        return (streak, firstIsHit)
    }

    private var pairStats: [(pair: String, hits: Int, total: Int, rate: Int)] {
        var dict: [String: (hits: Int, total: Int)] = [:]
        for entry in journal {
            guard let outcome = entry.outcome, outcome == "HIT" || outcome == "MISS" else { continue }
            var current = dict[entry.pair] ?? (0, 0)
            current.total += 1
            if outcome == "HIT" { current.hits += 1 }
            dict[entry.pair] = current
        }
        return dict.map { (pair, stat) in
            let rate = stat.total > 0 ? Int(round(Double(stat.hits) / Double(stat.total) * 100)) : 0
            return (pair: pair, hits: stat.hits, total: stat.total, rate: rate)
        }.sorted { $0.total > $1.total }
    }

    private var recentOutcomes: [String] {
        journal.compactMap(\.outcome)
            .filter { $0 == "HIT" || $0 == "MISS" }
            .suffix(10)
            .reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Win Rate & Edge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EDGE ANALYTICS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(DeskInk.slate.opacity(0.8))
                    Text(String(format: "%.1f%% Win Rate", winRate))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DeskInk.ink)
                        .monospacedDigit()
                }

                Spacer()

                HStack(spacing: 6) {
                    if let streak = currentStreak, streak.count >= 2 {
                        HStack(spacing: 3) {
                            Text(streak.isHit ? "🔥" : "⚠️")
                                .font(.system(size: 10))
                            Text("\(streak.count) \(streak.isHit ? "HIT" : "MISS")")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(streak.isHit ? DeskInk.emerald : DeskInk.coral)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((streak.isHit ? DeskInk.emerald : DeskInk.coral).opacity(0.16), in: Capsule())
                    }

                    HStack(spacing: 4) {
                        Image(systemName: edgeVsBreakeven >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%+.1f%% Edge", edgeVsBreakeven))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(edgeVsBreakeven >= 0 ? DeskInk.emerald : DeskInk.coral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((edgeVsBreakeven >= 0 ? DeskInk.emerald : DeskInk.coral).opacity(0.14), in: Capsule())
                }
            }

            // Stake & Net PnL Bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EST. NET P&L (85% PO)")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(DeskInk.slate.opacity(0.7))

                    Text(String(format: "%@$%.2f", netDollarPnL >= 0 ? "+" : "", netDollarPnL))
                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                        .foregroundStyle(netDollarPnL >= 0 ? DeskInk.emerald : DeskInk.coral)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach([10.0, 25.0, 50.0, 100.0], id: \.self) { amount in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                stakeAmount = amount
                            }
                            DeskHaptics.tabSwitch()
                        } label: {
                            Text("$\(Int(amount))")
                                .font(.system(size: 10, weight: stakeAmount == amount ? .bold : .medium))
                                .foregroundStyle(stakeAmount == amount ? DeskInk.ink : DeskInk.slate)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    stakeAmount == amount ? DeskInk.indigo.opacity(0.3) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            stakeAmount == amount ? DeskInk.electric.opacity(0.5) : Color.clear,
                                            lineWidth: 0.75
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Dual-tone Win/Loss Progress Meter
            VStack(spacing: 6) {
                GeometryReader { geo in
                    let hitFraction = totalSettled > 0 ? CGFloat(hits) / CGFloat(totalSettled) : 0.5
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DeskInk.coral.opacity(0.85))

                        Capsule()
                            .fill(DeskInk.emerald)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * hitFraction)))

                        // 54.1% Breakeven Threshold Line
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 1.5, height: 10)
                            .offset(x: geo.size.width * 0.5405 - 0.75, y: -2)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(hits) HIT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.emerald)
                    Spacer()
                    Text("54% B/E")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeskInk.slate.opacity(0.6))
                    Spacer()
                    Text("\(misses) MISS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.coral)
                }
            }

            // Cumulative Bankroll Equity Curve
            EquityCurveView(
                journal: journal,
                stakeAmount: stakeAmount,
                hits: hits,
                misses: misses
            )

            // Recent Sequence
            if !recentOutcomes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT SEQUENCE (NEWEST FIRST)")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(DeskInk.slate.opacity(0.7))

                    HStack(spacing: 5) {
                        ForEach(recentOutcomes.indices, id: \.self) { idx in
                            let outcome = recentOutcomes[idx]
                            let isHit = outcome == "HIT"
                            Circle()
                                .fill(isHit ? DeskInk.emerald : DeskInk.coral)
                                .frame(width: 8, height: 8)
                                .shadow(color: (isHit ? DeskInk.emerald : DeskInk.coral).opacity(0.6), radius: 3)
                        }
                    }
                }
            }

            // Pair Breakdown Chips
            if !pairStats.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WATCHLIST ACCURACY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(DeskInk.slate.opacity(0.7))

                    HStack(spacing: 8) {
                        ForEach(pairStats, id: \.pair) { item in
                            HStack(spacing: 4) {
                                Text(item.pair)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(DeskInk.slate)
                                Text("\(item.rate)%")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(item.rate >= 54 ? DeskInk.emerald : DeskInk.coral)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DeskInk.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [DeskInk.indigo.opacity(0.5), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
    }
}

struct EquityCurveView: View {
    let journal: [ReplayEntry]
    let stakeAmount: Double
    let hits: Int
    let misses: Int

    private var settledTrades: [ReplayEntry] {
        journal.filter { $0.outcome == "HIT" || $0.outcome == "MISS" }
            .sorted { $0.scannedAt < $1.scannedAt }
    }

    private var cumulativeData: [Double] {
        var running: Double = 0.0
        var list: [Double] = [0.0]
        for trade in settledTrades {
            if trade.outcome == "HIT" {
                running += (stakeAmount * 0.85)
            } else {
                running -= stakeAmount
            }
            list.append(running)
        }
        return list
    }

    private var maxDrawdown: Double {
        var peak: Double = 0.0
        var maxDd: Double = 0.0
        for val in cumulativeData {
            if val > peak { peak = val }
            let dd = peak - val
            if dd > maxDd { maxDd = dd }
        }
        return maxDd
    }

    private var expectancy: Double {
        let total = hits + misses
        guard total > 0 else { return 0.0 }
        let winRate = Double(hits) / Double(total)
        let lossRate = Double(misses) / Double(total)
        return (winRate * (stakeAmount * 0.85)) - (lossRate * stakeAmount)
    }

    private var profitFactor: Double {
        let grossGains = Double(hits) * (stakeAmount * 0.85)
        let grossLosses = Double(misses) * stakeAmount
        guard grossLosses > 0 else { return grossGains > 0 ? 9.9 : 1.0 }
        return min(9.9, grossGains / grossLosses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EQUITY TRAJECTORY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DeskInk.slate.opacity(0.7))

                Spacer()

                if let current = cumulativeData.last {
                    Text(String(format: "%@$%.2f", current >= 0 ? "+" : "", current))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(current >= 0 ? DeskInk.emerald : DeskInk.coral)
                }
            }

            // Curve Canvas
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let data = cumulativeData

                if data.count < 2 {
                    // Preview Baseline
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h / 2))
                            path.addLine(to: CGPoint(x: w, y: h / 2))
                        }
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        Text("Curve maps live as setups settle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DeskInk.slate.opacity(0.5))
                    }
                } else {
                    let minVal = data.min() ?? 0.0
                    let maxVal = data.max() ?? 0.0
                    let span = max(maxVal - minVal, 10.0)
                    let pad = span * 0.15
                    let plotMin = minVal - pad
                    let plotMax = maxVal + pad
                    let plotSpan = plotMax - plotMin

                    let points: [CGPoint] = data.enumerated().map { idx, val in
                        let x = (CGFloat(idx) / CGFloat(data.count - 1)) * w
                        let yFrac = CGFloat((val - plotMin) / plotSpan)
                        let y = h - (yFrac * h)
                        return CGPoint(x: x, y: y)
                    }

                    let isPositive = (data.last ?? 0) >= 0
                    let tint = isPositive ? DeskInk.emerald : DeskInk.coral

                    ZStack {
                        // Zero Baseline
                        if plotMin <= 0 && plotMax >= 0 {
                            let zeroFrac = CGFloat((0.0 - plotMin) / plotSpan)
                            let zeroY = h - (zeroFrac * h)
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: zeroY))
                                p.addLine(to: CGPoint(x: w, y: zeroY))
                            }
                            .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                        }

                        // Gradient Area Fill
                        Path { p in
                            guard let first = points.first else { return }
                            p.move(to: CGPoint(x: first.x, y: h))
                            p.addLine(to: first)
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                            if let last = points.last {
                                p.addLine(to: CGPoint(x: last.x, y: h))
                            }
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Stroke Line
                        Path { p in
                            guard let first = points.first else { return }
                            p.move(to: first)
                            for pt in points.dropFirst() {
                                p.addLine(to: pt)
                            }
                        }
                        .stroke(
                            tint,
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                        )

                        // Settlement Nodes
                        ForEach(Array(points.dropFirst().enumerated()), id: \.offset) { i, pt in
                            let isWin = settledTrades[i].outcome == "HIT"
                            Circle()
                                .fill(isWin ? DeskInk.emerald : DeskInk.coral)
                                .frame(width: 5, height: 5)
                                .position(pt)
                                .shadow(color: (isWin ? DeskInk.emerald : DeskInk.coral).opacity(0.6), radius: 2)
                        }

                        // Last point beacon
                        if let last = points.last {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .position(last)
                                .shadow(color: tint.opacity(0.8), radius: 4)
                        }
                    }
                }
            }
            .frame(height: 58)

            // Quant Metrics Footer Bar
            HStack(spacing: 8) {
                // Expectancy
                HStack(spacing: 3) {
                    Text("EXP:")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(DeskInk.slate.opacity(0.7))
                    Text(String(format: "%@$%.2f/T", expectancy >= 0 ? "+" : "", expectancy))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(expectancy >= 0 ? DeskInk.emerald : DeskInk.coral)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                // Max Drawdown
                HStack(spacing: 3) {
                    Text("MAX DD:")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(DeskInk.slate.opacity(0.7))
                    Text(String(format: "-$%.2f", maxDrawdown))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(maxDrawdown > 0 ? DeskInk.coral : DeskInk.slate)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                Spacer()

                // Profit Factor
                HStack(spacing: 3) {
                    Text("PROFIT FACTOR:")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(DeskInk.slate.opacity(0.7))
                    Text(String(format: "%.2fx", profitFactor))
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(profitFactor >= 1.5 ? DeskInk.emerald : (profitFactor >= 1.0 ? DeskInk.slate : DeskInk.coral))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
