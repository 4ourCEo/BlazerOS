import BlazerCore
import SwiftUI

struct CoachScreen: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text("Foundation AI Intelligence")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(DeskInk.violet)
                        .frame(width: 6, height: 6)
                    Text("SEALED")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(DeskInk.violet)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DeskInk.violet.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(DeskInk.violet.opacity(0.25), lineWidth: 0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if let explanation = model.latestCoachExplanation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest Session Analysis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DeskInk.slate)
                            CoachCard(explanation: explanation)
                        }

                        VoiceCoachButton(
                            voiceSession: model.voiceSession,
                            title: "Ask Coach about Scan",
                            onAsk: { model.askCoachLatest() },
                            onStop: { model.stopVoice() }
                        )
                    }

                    CoachVoiceDebriefCard(model: model)
                    CoachExpectancyMathCard()
                    CoachPrinciplesCard()
                    CoachContractCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

struct CoachExpectancyMathCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "function")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DeskInk.emerald)
                Text("The Math of Trading")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Text("EV & RISK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DeskInk.emerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DeskInk.emerald.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expectancy = (P(Win) × Payout) − (P(Loss) × Risk)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.electric)
                Text("At an assumed 88% broker payout, break-even requires 53.2% verified wins. Directional score is not win probability; sizing must follow disciplined account risk.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
            }
            .padding(12)
            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Break-Even (88%)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                    Text("53.2%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DeskInk.ink)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Risk Ceiling")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                    Text("1% – 2%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DeskInk.ink)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posture in Chop")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                    Text("STAY FLAT")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DeskInk.coral)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct CoachVoiceDebriefCard: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.voiceDebriefEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 18))
                .foregroundStyle(model.voiceDebriefEnabled ? DeskInk.violet : DeskInk.slate)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("Spoken Trade Debrief")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Text(model.voiceDebriefEnabled ? "Audio debriefing as binary positions settle" : "Voice announcements muted")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
            }

            Spacer()

            Toggle("", isOn: $model.voiceDebriefEnabled)
                .labelsHidden()
                .tint(DeskInk.violet)
        }
        .padding(14)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

struct CoachPrinciplesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Execution Principles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DeskInk.ink)

            principleRow(
                number: "1",
                title: "Complete Bar Authority",
                body: "Only closed M1 candles inform signal formation. Wicks and bodies are cryptographically hashed."
            )

            principleRow(
                number: "2",
                title: "Zero Re-Scoring",
                body: "Quotes never alter a frozen verdict. Live ticks cannot mutate historical scan decisions."
            )

            principleRow(
                number: "3",
                title: "Slippage & Veto Transparency",
                body: "Spread spikes, abnormal prints, and high volatility vetoes are surfaced immediately without delay."
            )

            principleRow(
                number: "4",
                title: "Flat is a Position",
                body: "In uncalibrated chop or when mathematical expectancy is non-positive, staying flat preserves capital."
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func principleRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DeskInk.violet)
                .frame(width: 22, height: 22)
                .background(DeskInk.violet.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CoachContractCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Engine Contract")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DeskInk.ink)
            Text("The Foundation Coach interprets the deterministic JavaScript engine output on-device. It never generates trade sides, alters scores, or connects to external unverified servers.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
