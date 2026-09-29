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

            // 1. Center Emblem - pixel-aligned with iOS UILaunchScreen
            markImage
                .frame(width: 104, height: 104)
                .scaleEffect(markLit ? 1 : 0.94)
                .opacity(markLit ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: markLit)

            // 2. Brand Typography - revealed beneath the centered emblem
            VStack(spacing: 8) {
                Text("BLAZER")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(DeskInk.ink)

                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(DeskInk.slate)
            }
            .offset(y: (104 / 2) + 38)
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
