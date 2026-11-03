import BlazerCore
import SwiftUI

struct ReplayCover: View {
    var entry: ReplayEntry
    var coach: CoachExplanation?
    @ObservedObject var voiceSession: VoiceSession
    var onAsk: () -> Void
    var onStopVoice: () -> Void
    var close: () -> Void

    @State private var candleStep: Int? = nil

    private var visibleBars: [Candle] {
        let count = candleStep ?? entry.candles.count
        return Array(entry.candles.prefix(count))
    }

    private struct Candidate001SummaryCard: View {
        let candidates: [Candidate001Candidate]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CANDIDATE 001")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(DeskInk.violet)
                    Spacer()
                    Text("\(candidates.count) SETUP\(candidates.count == 1 ? "" : "S")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                }
                ForEach(candidates) { candidate in
                    HStack(spacing: 8) {
                        Image(systemName: candidate.direction == .bullish ? "arrow.up.right" : "arrow.down.right")
                            .foregroundStyle(candidate.direction == .bullish ? DeskInk.emerald : DeskInk.coral)
                        Text((candidate.triggeredAt ?? candidate.transitions.last!.timestamp)
                            .formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text(candidate.m15Confirmed ? "M15 CONFIRMED" : "M15 NOT USED")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DeskInk.slate)
                        Spacer()
                        Text(candidate.structure.first?.kind.rawValue.uppercased() ?? "STRUCTURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(DeskInk.electric)
                    }
                }
                Text("Markers use only candles visible at the replay step. Candidate 001 is research-only.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DeskInk.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var candidateAnnotations: [Candidate001Candidate] {
        let candles = visibleBars.compactMap { candle -> Candidate001Candle? in
            guard let time = candle.time else { return nil }
            return Candidate001Candle(
                time: Date(timeIntervalSince1970: time / 1000),
                open: candle.bodyOpen,
                high: candle.bodyHigh,
                low: candle.bodyLow,
                close: candle.close
            )
        }
        let m15Candles = aggregateM15(entry.m5Candles)
        return (try? Candidate001Analyzer.analyze(candles: candles, m15Candles: m15Candles)) ?? []
    }

    private func aggregateM15(_ candles: [Candle]) -> [Candidate001Candle] {
        let source = candles.compactMap { candle -> Candidate001Candle? in
            guard let time = candle.time else { return nil }
            return Candidate001Candle(
                time: Date(timeIntervalSince1970: time / 1000),
                open: candle.bodyOpen,
                high: candle.bodyHigh,
                low: candle.bodyLow,
                close: candle.close
            )
        }
        guard source.count >= 3 else { return [] }
        return stride(from: 0, through: source.count - 3, by: 3).compactMap { index in
            let group = Array(source[index..<(index + 3)])
            guard group[1].time.timeIntervalSince(group[0].time) == 300,
                  group[2].time.timeIntervalSince(group[1].time) == 300 else { return nil }
            return Candidate001Candle(
                time: group[0].time,
                open: group[0].open,
                high: group.map(\.high).max()!,
                low: group.map(\.low).min()!,
                close: group[2].close
            )
        }
    }

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
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

                    MiniCandleChart(
                        candles: visibleBars,
                        candidateAnnotations: candidateAnnotations
                    )
                        .equatable()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)

                    if !candidateAnnotations.isEmpty {
                        Candidate001SummaryCard(candidates: candidateAnnotations)
                    }

                    if entry.candles.count > 4 {
                        HStack(spacing: 12) {
                            Button {
                                DeskHaptics.scrubTick()
                                candleStep = max(4, (candleStep ?? entry.candles.count) - 1)
                            } label: {
                                Image(systemName: "backward.frame.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(DeskInk.slate)
                                    .frame(width: 34, height: 32)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            .buttonStyle(.plain)
                            .disabled((candleStep ?? entry.candles.count) <= 4)

                            Spacer()

                            Text("CANDLE \(candleStep ?? entry.candles.count) OF \(entry.candles.count)")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(DeskInk.electric)

                            Spacer()

                            Button {
                                DeskHaptics.scrubTick()
                                candleStep = min(entry.candles.count, (candleStep ?? entry.candles.count) + 1)
                            } label: {
                                Image(systemName: "forward.frame.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(DeskInk.slate)
                                    .frame(width: 34, height: 32)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            .buttonStyle(.plain)
                            .disabled((candleStep ?? entry.candles.count) >= entry.candles.count)
                        }
                    }

                    Text("\(entry.score)")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                        .monospacedDigit()

                    Text(entry.outcome ?? entry.verb)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(verbInk(entry.outcome ?? entry.verb))
                        .opacity((entry.outcome ?? entry.verb) == "WAIT" ? 0.62 : 1)

                    Text(entry.why.isEmpty ? " " : entry.why)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let coach {
                        CoachCard(explanation: coach)
                    }

                    // ── Voice Coach ─────────────────────────────────────────
                    VoiceCoachButton(
                        voiceSession: voiceSession,
                        onAsk: onAsk,
                        onStop: onStopVoice
                    )

                    if let voiceNote = entry.voiceNote, !voiceNote.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DeskInk.violet)
                                Text("Voice Reflection")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DeskInk.violet)
                                Spacer()
                                Text(voiceNote.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DeskInk.slate)
                            }
                            Text(voiceNote.transcript)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(DeskInk.ink.opacity(0.9))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DeskInk.violet.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    Text("Strike \(PriceFormat.px(entry.strike))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)

                    if let veto = entry.veto, !veto.isEmpty {
                        Text(veto)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DeskInk.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Spacer(minLength: 12)

                    Text(entry.fingerprint)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeskInk.slate.opacity(0.6))
                }
                .padding(22)
                .padding(.top, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.pair) \(entry.verb) \(entry.score)")
    }
}
