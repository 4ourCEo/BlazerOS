import BlazerCore
import SwiftUI

struct FloatingNavBar: View {
    @Binding var activeTab: DeskTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DeskTab.allCases) { tab in
                Button {
                    DeskHaptics.tabSwitch()
                    activeTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: activeTab == tab ? .semibold : .regular))
                            .foregroundStyle(activeTab == tab ? DeskInk.ink : DeskInk.slate.opacity(0.6))
                            .frame(height: 20)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: activeTab == tab ? .semibold : .medium))
                            .foregroundStyle(activeTab == tab ? DeskInk.ink : DeskInk.slate.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(activeTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 8)
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
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        .frame(height: 52)
    }
}
