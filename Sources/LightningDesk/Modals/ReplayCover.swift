import BlazerCore
import SwiftUI

struct ReplayCover: View {
    var entry: ReplayEntry
    var coach: CoachExplanation?
    @ObservedObject var voiceSession: VoiceSession
    var onAsk: () -> Void
    var onStopVoice: () -> Void
    var close: () -> Void

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

                    MiniCandleChart(candles: entry.candles)
                        .equatable()
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)

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


