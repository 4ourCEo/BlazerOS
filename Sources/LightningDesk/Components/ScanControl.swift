import SwiftUI

struct SpringPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

/// One control. Scanning changes the fill, aura, and energetic sweep.
struct ScanControl: View {
    var scanning: Bool
    var pair: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Background Gradient
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: scanning
                                ? [DeskInk.violet.opacity(0.92), DeskInk.indigo, DeskInk.electric.opacity(0.85)]
                                : [DeskInk.indigo, DeskInk.electric],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // High-energy scanning sweep
                if scanning {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        let time = context.date.timeIntervalSinceReferenceDate
                        let phase = time.truncatingRemainder(dividingBy: 1.25) / 1.25

                        GeometryReader { geo in
                            // Ambient wide wash
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.12), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.6, height: geo.size.height)
                            .offset(x: -geo.size.width * 0.6 + phase * (geo.size.width * 1.6))

                            // Crisp focused energy beam
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, Color.white.opacity(0.35), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * 0.28, height: geo.size.height)
                                .offset(x: -geo.size.width * 0.28 + phase * (geo.size.width * 1.28))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                    .allowsHitTesting(false)
                }

                // Inner border highlight
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )

                // Label & Icon
                HStack(spacing: 8) {
                    if scanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }

                    Text(scanning ? title : "Scan Watchlist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .shadow(
                color: (scanning ? DeskInk.electric : DeskInk.indigo).opacity(scanning ? 0.45 : 0.25),
                radius: scanning ? 16 : 8,
                x: 0,
                y: scanning ? 6 : 4
            )
        }
        .buttonStyle(SpringPressButtonStyle())
        .disabled(scanning)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: scanning)
        .accessibilityLabel(scanning ? "Scanning \(title)" : "Scan \(pair)")
    }
}
