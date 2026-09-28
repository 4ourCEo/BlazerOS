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
            VStack(spacing: 22) {
                markImage
                    .frame(width: 104, height: 104)
                    .scaleEffect(markLit ? 1 : 0.94)
                    .opacity(markLit ? 1 : 0)
                    .animation(.easeOut(duration: 0.45), value: markLit)

                Text("BLAZER")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(DeskInk.ink)
                    .opacity(wordLit ? 1 : 0)

                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(DeskInk.slate)
                    .opacity(wordLit ? 1 : 0)
            }
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
