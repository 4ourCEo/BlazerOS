import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

/// Deterministic launch branding. Status is passed in; never invents LIVE.
struct LaunchCover: View {
    var status: String
    var markLit: Bool
    var wordLit: Bool

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()

            // Ambient background radial aura
            RadialGradient(
                colors: [
                    DeskInk.emerald.opacity(markLit ? 0.16 : 0.0),
                    DeskInk.electric.opacity(markLit ? 0.08 : 0.0),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 180
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.6), value: markLit)

            // 1. Center Crystal Emblem - pixel-aligned with iOS UILaunchScreen
            markImage
                .frame(width: 120, height: 120)
                .scaleEffect(markLit ? 1 : 0.88)
                .opacity(markLit ? 1 : 0)
                .shadow(color: DeskInk.emerald.opacity(markLit ? 0.4 : 0), radius: 24, x: -8, y: -8)
                .shadow(color: DeskInk.coral.opacity(markLit ? 0.4 : 0), radius: 24, x: 8, y: 8)
                .animation(.spring(response: 0.5, dampingFraction: 0.72), value: markLit)

            // 2. Brand Typography - revealed beneath the centered emblem
            VStack(spacing: 8) {
                Text("BLAZER")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(DeskInk.ink)

                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(status == "LIVE" ? DeskInk.emerald : DeskInk.slate)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill((status == "LIVE" ? DeskInk.emerald : DeskInk.slate).opacity(0.15))
                    )
            }
            .offset(y: (120 / 2) + 44)
            .opacity(wordLit ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: wordLit)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blazer \(status)")
    }

    @ViewBuilder
    private var markImage: some View {
        if let url = Bundle.module.url(forResource: "BlazerMark", withExtension: "png") {
            #if os(macOS)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #elseif os(iOS)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
            #endif
        }
    }
}
