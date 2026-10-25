import BlazerCore
import SwiftUI

/// Dedicated OTC research surface. It is intentionally separate from the trading hero: there is
/// no entry action, no armed rail, and no production frame. Every value is research context.
struct OTCResearchCard: View {
    @ObservedObject var model: LightningDeskModel
    /// Re-rendered every second so a frozen signal cannot keep a stale FRESH badge.
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MiniCandleChart(
                candles: model.candles,
                strike: nil,
                currentPrice: model.currentPrice,
                side: model.side(for: model.pair),
                pair: model.pair
            )
            .equatable()
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            if let signal = model.otcSignal {
                signalBlock(signal)
            } else {
                emptyState
            }
            controls
            if let report = model.otcReplayReport {
                Text(String(
                    format: "REPLAY %d/%d accepted · coverage %.0f%% · stale refusals %.0f%% · %@",
                    report.accepted, report.evaluated, report.coverage * 100,
                    report.staleRefusalRate * 100, report.status))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.pair)
                    .font(.system(size: 19, weight: .heavy, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
                Text("POCKET OPTION OTC · 60s RESEARCH")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(DeskInk.violet)
            }
            Spacer(minLength: 4)
            Text("RESEARCH ONLY")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(DeskInk.violet)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DeskInk.violet.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(DeskInk.violet.opacity(0.45), lineWidth: 0.8))
        }
    }

    private func signalBlock(_ signal: OTCResearchSignal) -> some View {
        let age = max(0, now.timeIntervalSince(signal.evaluatedAt))
        let freshness = ShadowFreshness.classify(
            sourceTime: signal.quoteTimestamp, receivedAt: signal.quoteTimestamp,
            now: now, freshFor: 3, expiresAfter: 10)
        let feed = OTCFeedQuality.classify(model.otcSignalConnectionState)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(signal.decision.rawValue)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(decisionColor(signal.decision))
                VStack(alignment: .leading, spacing: 1) {
                    Text("SCORE \(signal.score)")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(DeskInk.ink)
                    Text("deterministic · not a win probability")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                }
                Spacer()
                Text("\(signal.horizonSeconds)s")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.electric)
            }

            HStack(spacing: 6) {
                badge(freshness.rawValue.uppercased(), tint: freshnessColor(freshness))
                badge(feed.rawValue.uppercased(), tint: connectionColor(feed))
                badge("AGE \(Int(age))s", tint: freshness == .expired ? DeskInk.coral : DeskInk.slate)
                if let payout = signal.payoutPercent ?? model.otcLastPayoutPercent {
                    badge(String(format: "PAYOUT %.1f%%", payout), tint: DeskInk.emerald)
                }
            }
            if freshness == .expired {
                Text("SIGNAL AGED OUT — refresh OTC research before using this read.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DeskInk.coral)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    detail("SOURCE", signal.source.displayName)
                    detail("VENUE", signal.source.venueID)
                }
                GridRow {
                    detail("ENGINE", signal.engineVersion)
                    detail("STRATEGY", signal.strategyVersion)
                }
                GridRow {
                    detail("QUOTE", String(format: "%.5f", signal.quotePrice))
                    detail("CANDLE", signal.candleCloseTime.map(Self.time) ?? "—")
                }
                GridRow {
                    detail("EVALUATED", Self.time(signal.evaluatedAt))
                    detail("SNAPSHOT", String(signal.sourceSnapshotID.prefix(18)))
                }
            }

            if !signal.vetoes.isEmpty {
                Text("VETO · " + signal.vetoes.map(\.rawValue).joined(separator: " · "))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(signal.decision == .wait ? DeskInk.coral : DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(signal.explanation)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO OTC SIGNAL YET")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(DeskInk.ink)
            Text(model.otcSignalIssue ?? "Add an OTCharts API key, then refresh. OTC research is read-only and never arms a trade.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if model.otcAvailableInstruments.count > 1 {
                Menu {
                    ForEach(model.otcAvailableInstruments) { instrument in
                        Button(instrument.displaySymbol) {
                            Task { await model.selectOTCInstrument(instrument.instrumentID) }
                        }
                    }
                } label: {
                    Label("Instrument", systemImage: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.slate)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                Task { await model.refreshOTCReplayReport() }
            } label: {
                Label("Replay", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskInk.slate)
            }
            .buttonStyle(.plain)
            if let issue = model.otcSignalIssue, model.otcSignal != nil {
                Text(issue)
                    .font(.system(size: 9))
                    .foregroundStyle(DeskInk.coral)
                    .lineLimit(1)
            }
            Button {
                Task { await model.refreshOTCSignal() }
            } label: {
                HStack(spacing: 5) {
                    if model.otcSignalRefreshing {
                        ProgressView().controlSize(.mini).tint(DeskInk.ink)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh research")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DeskInk.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DeskInk.indigo, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.otcSignalRefreshing)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.6))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DeskInk.slate.opacity(0.8))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeskInk.slate)
                .lineLimit(1)
        }
    }

    private func decisionColor(_ decision: OTCSignalDecision) -> Color {
        switch decision {
        case .high: return DeskInk.emerald
        case .low: return DeskInk.coral
        case .wait: return DeskInk.slate
        }
    }

    private func freshnessColor(_ freshness: ShadowFreshness) -> Color {
        switch freshness {
        case .fresh: return DeskInk.emerald
        case .aging: return DeskInk.electric
        case .expired: return DeskInk.coral
        }
    }

    private func connectionColor(_ quality: OTCFeedQuality) -> Color {
        switch quality {
        case .live: return DeskInk.emerald
        case .degraded: return DeskInk.electric
        case .stale: return DeskInk.coral
        case .unavailable: return DeskInk.slate
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
