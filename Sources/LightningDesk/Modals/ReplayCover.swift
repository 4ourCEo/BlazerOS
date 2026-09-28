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

// MARK: - Voice Coach Button

/// Mic button + live state feedback. Observes VoiceSession directly.
struct VoiceCoachButton: View {
    @ObservedObject var voiceSession: VoiceSession
    var onAsk: () -> Void
    var onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !voiceSession.transcript.isEmpty || isActive {
                transcriptArea
            }

            Button {
                switch voiceSession.state {
                case .idle, .denied, .error:
                    onAsk()
                case .listening, .thinking, .speaking:
                    onStop()
                case .requestingPermission:
                    break
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: micIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolEffect(.variableColor.iterative.reversing,
                                      isActive: !reduceMotion && voiceSession.state == .listening)
                    Text(buttonLabel)
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(buttonInk)
                .padding(.vertical, 12)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(buttonSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(voiceSession.state == .requestingPermission || voiceSession.state == .thinking)
            .accessibilityLabel(buttonLabel)
            .accessibilityHint(accessibilityHint)

            if case .denied = voiceSession.state {
                Text("Microphone or speech recognition access denied. Enable it in Settings.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if case .error(let msg) = voiceSession.state {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isActive: Bool {
        switch voiceSession.state {
        case .listening, .thinking, .speaking: return true
        default: return false
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !voiceSession.transcript.isEmpty {
                Text(voiceSession.transcript)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(DeskInk.ink.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Your question: \(voiceSession.transcript)")
            }
            if case .speaking(let text) = voiceSession.state {
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DeskInk.violet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Coach answer: \(text)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DeskInk.violet.opacity(0.18), lineWidth: 0.5)
        )
    }

    private var micIcon: String {
        switch voiceSession.state {
        case .idle, .denied, .error, .requestingPermission: return "mic"
        case .listening:  return "mic.fill"
        case .thinking:   return "brain"
        case .speaking:   return "speaker.wave.2.fill"
        }
    }

    private var buttonLabel: String {
        switch voiceSession.state {
        case .idle, .denied, .error:    return "Ask Coach"
        case .requestingPermission:     return "Requesting…"
        case .listening:                return "Listening… (tap to stop)"
        case .thinking:                 return "Thinking…"
        case .speaking:                 return "Speaking… (tap to stop)"
        }
    }

    private var buttonInk: Color {
        switch voiceSession.state {
        case .idle, .denied, .error, .requestingPermission: return DeskInk.violet
        case .listening: return DeskInk.emerald
        case .thinking:  return DeskInk.slate
        case .speaking:  return DeskInk.electric
        }
    }

    private var buttonSurface: Color {
        switch voiceSession.state {
        case .idle, .denied, .error, .requestingPermission: return DeskInk.violet.opacity(0.12)
        case .listening: return DeskInk.emerald.opacity(0.12)
        case .thinking:  return DeskInk.surface
        case .speaking:  return DeskInk.electric.opacity(0.10)
        }
    }

    private var accessibilityHint: String {
        switch voiceSession.state {
        case .idle, .denied, .error:
            return "Speak a question about this scan and the Coach will answer aloud."
        case .listening:
            return "Recording your question. Tap to stop early."
        case .speaking:
            return "Coach is reading the answer. Tap to stop."
        default:
            return ""
        }
    }
}
