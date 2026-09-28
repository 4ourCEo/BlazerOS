import SwiftUI

/// One control. Scanning changes the fill and the word inside the same bounds.
struct ScanControl: View {
    var scanning: Bool
    var pair: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: scanning
                                ? [DeskInk.violet.opacity(0.85), DeskInk.indigo.opacity(0.9)]
                                : [DeskInk.indigo, DeskInk.electric],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                if scanning {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.35) / 1.35
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: geo.size.width * 0.34, height: geo.size.height)
                                .offset(x: -geo.size.width * 0.34 + phase * (geo.size.width * 1.34))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .allowsHitTesting(false)
                }

                Text(scanning ? title : "Scan")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .disabled(scanning)
        .animation(.easeInOut(duration: 0.35), value: scanning)
        .accessibilityLabel(scanning ? "Scanning \(title)" : "Scan \(pair)")
    }
}
