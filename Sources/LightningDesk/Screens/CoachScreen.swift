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
                    }

                    CoachPrinciplesCard()
                    CoachContractCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
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
