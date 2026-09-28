import BlazerCore
import SwiftUI

struct ReplayScreen: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replay")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text(model.journal.isEmpty ? "No recorded sessions" : "\(model.journal.count) Recorded Sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if model.journal.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 38))
                        .foregroundStyle(DeskInk.violet.opacity(0.7))
                    Text("No Replay Sessions")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text("Committed scans freeze completed candle snapshots, verdict score, and coach evidence here for instant verification.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(model.journal) { entry in
                            Button {
                                DeskHaptics.tabSwitch()
                                model.openReplay(entry.id)
                            } label: {
                                ReplayCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.pair) \(entry.outcome ?? entry.verb) \(entry.score)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

struct ReplayCard: View {
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
