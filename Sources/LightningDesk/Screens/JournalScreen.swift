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
                    VStack(spacing: 12) {
                        ForEach(model.journal) { entry in
                            Button {
                                DeskHaptics.tabSwitch()
                                model.openReplay(entry.id)
                            } label: {
                                JournalRowCard(entry: entry)
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
