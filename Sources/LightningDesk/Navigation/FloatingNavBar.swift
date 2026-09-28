import BlazerCore
import SwiftUI

struct FloatingNavBar: View {
    @Binding var activeTab: DeskTab
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DeskTab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                        activeTab = tab
                    }
                    DeskHaptics.tabSwitch()
                } label: {
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [DeskInk.indigo.opacity(0.38), DeskInk.electric.opacity(0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(DeskInk.electric.opacity(0.45), lineWidth: 0.75)
                                )
                                .matchedGeometryEffect(id: "activeTabPill", in: tabNamespace)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 3)
                                .shadow(color: DeskInk.electric.opacity(0.2), radius: 6, x: 0, y: 0)
                        }

                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate.opacity(0.55))
                                .frame(height: 18)
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(DeskInk.surface.opacity(0.92))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 5)
        .frame(height: 52)
    }
}
