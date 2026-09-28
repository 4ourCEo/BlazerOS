import BlazerCore
import SwiftUI

/// Mic button + live state feedback. Observes VoiceSession directly.
public struct VoiceCoachButton: View {
    public init(
        voiceSession: VoiceSession,
        title: String? = nil,
        onAsk: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.voiceSession = voiceSession
        self.customTitle = title
        self.onAsk = onAsk
        self.onStop = onStop
    }

    @ObservedObject var voiceSession: VoiceSession
    var customTitle: String?
    var onAsk: () -> Void
    var onStop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DeskInk.emerald)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Coach: \(text)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var micIcon: String {
        switch voiceSession.state {
        case .listening:               return "waveform"
        case .thinking:                return "ellipsis.circle"
        case .speaking:                return "speaker.wave.2.fill"
        case .requestingPermission:    return "lock.circle"
        case .denied, .error:          return "mic.slash"
        case .idle:                    return "mic.fill"
        }
    }

    private var buttonLabel: String {
        switch voiceSession.state {
        case .idle:
            return customTitle ?? "Ask Coach (Spoken Query)"
        case .requestingPermission:
            return "Requesting Mic Access…"
        case .listening:
            return "Listening… Tap to Stop"
        case .thinking:
            return "Coach Thinking…"
        case .speaking:
            return "Coach Speaking… Tap to Silence"
        case .denied:
            return "Microphone Access Denied"
        case .error:
            return "Try Again"
        }
    }

    private var buttonInk: Color {
        switch voiceSession.state {
        case .idle:                    return DeskInk.violet
        case .listening:               return DeskInk.coral
        case .thinking:                return DeskInk.slate
        case .speaking:                return DeskInk.emerald
        case .denied, .error:          return DeskInk.coral
        case .requestingPermission:    return DeskInk.slate
        }
    }

    private var buttonSurface: Color {
        switch voiceSession.state {
        case .listening:               return DeskInk.coral.opacity(0.16)
        case .speaking:                return DeskInk.emerald.opacity(0.16)
        case .denied, .error:          return DeskInk.coral.opacity(0.12)
        default:                       return DeskInk.surface
        }
    }

    private var accessibilityHint: String {
        switch voiceSession.state {
        case .idle:                    return "Double-tap to ask a spoken question about this scan."
        case .listening:               return "Double-tap to finish speaking and send to coach."
        case .speaking:                return "Double-tap to interrupt coach speech."
        default:                       return ""
        }
    }
}
