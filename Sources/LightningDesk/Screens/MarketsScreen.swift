import BlazerCore
import SwiftUI

struct MarketsScreen: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markets")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text("Watchlist · 6 Core Pairs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(feedColor)
                        .frame(width: 6, height: 6)
                    Text(feedWord)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(feedColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DeskInk.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(model.pairs, id: \.self) { pair in
                        MarketPairCard(
                            pair: pair,
                            isSelected: pair == model.pair,
                            side: model.side(for: pair) ?? "WAIT"
                        ) {
                            DeskHaptics.tabSwitch()
                            model.selectAndNavigate(pair: pair)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var feedWord: String { model.frame?.feed.rawValue ?? model.feed.rawValue }

    private var feedColor: Color {
        switch model.frame?.feed ?? model.feed {
        case .live:                     return DeskInk.emerald
        case .stale, .error:            return DeskInk.coral
        case .connecting, .disconnected: return DeskInk.slate
        }
    }
}

struct MarketPairCard: View {
    let pair: String
    let isSelected: Bool
    let side: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pair)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DeskInk.ink)
                        if isSelected {
                            Text("DESK")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DeskInk.indigo)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DeskInk.indigo.opacity(0.18), in: Capsule())
                        }
                    }
                    Text(pairDescription(pair))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeskInk.slate.opacity(0.8))
                }

                Spacer()

                Text(sideBadgeText(side))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sideColor(side))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(sideColor(side).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeskInk.slate.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? DeskInk.indigo.opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: isSelected ? 1.0 : 0.5
                    )
            )
        }
        .buttonStyle(SpringPressButtonStyle())
        .accessibilityLabel("\(pair) \(side)")
    }

    private func pairDescription(_ pair: String) -> String {
        switch pair {
        case "EUR/USD": return "Euro / US Dollar"
        case "GBP/USD": return "British Pound / US Dollar"
        case "USD/JPY": return "US Dollar / Japanese Yen"
        case "AUD/USD": return "Australian Dollar / US Dollar"
        case "USD/CAD": return "US Dollar / Canadian Dollar"
        case "NZD/USD": return "New Zealand Dollar / US Dollar"
        default: return "Foreign Exchange"
        }
    }

    private func sideBadgeText(_ side: String) -> String {
        switch side {
        case "HIGH": return "TAP HIGH"
        case "LOW":  return "TAP LOW"
        default:     return side
        }
    }

    private func sideColor(_ side: String) -> Color {
        switch side {
        case "HIGH": return DeskInk.emerald
        case "LOW":  return DeskInk.coral
        default:     return DeskInk.slate
        }
    }
}
