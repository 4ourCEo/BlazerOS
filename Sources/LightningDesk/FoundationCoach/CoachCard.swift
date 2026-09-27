import BlazerCore
import SwiftUI

/// Renders a sealed explanation. It does not show a side or a second score.
struct CoachCard: View {
    var explanation: CoachExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Coach")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeskInk.violet)
                Spacer()
                Text(explanation.confidence)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
            }
            Text(explanation.summary)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DeskInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(explanation.bullets.enumerated()), id: \.offset) { _, bullet in
                Text(bullet)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DeskInk.violet.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach \(explanation.confidence). \(explanation.summary)")
    }
}
