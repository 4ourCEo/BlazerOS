import SwiftUI
import BlazerCore
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

// MARK: - Color Palette

enum DeskInk {
    static let background = Color(red: 7.0 / 255, green: 16.0 / 255, blue: 21.0 / 255)
    static let surface = Color(red: 13.0 / 255, green: 27.0 / 255, blue: 36.0 / 255)
    static let card = Color(red: 16.0 / 255, green: 35.0 / 255, blue: 45.0 / 255)
    static let indigo = Color(red: 9.0 / 255, green: 184.0 / 255, blue: 171.0 / 255)
    static let electric = Color(red: 41.0 / 255, green: 230.0 / 255, blue: 189.0 / 255)
    static let emerald = Color(red: 41.0 / 255, green: 230.0 / 255, blue: 189.0 / 255)
    static let coral = Color(red: 255.0 / 255, green: 102.0 / 255, blue: 126.0 / 255)
    static let violet = Color(red: 139.0 / 255, green: 124.0 / 255, blue: 255.0 / 255)
    static let ink = Color(red: 242.0 / 255, green: 247.0 / 255, blue: 250.0 / 255)
    static let slate = Color(red: 139.0 / 255, green: 164.0 / 255, blue: 180.0 / 255)
}

// MARK: - Haptics

@MainActor
enum DeskHaptics {
    static func commit() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        #endif
    }

    static func veto() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.55)
        #endif
    }

    static func tabSwitch() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func scrubTick() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func tradeLocked() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.95)
        #endif
    }

    static func settleAlert() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #elseif os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Distinct confirmation pulse: success for HIT, warning for MISS.
    static func outcomeConfirmed(_ outcome: DeskOutcome) {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #elseif os(iOS)
        switch outcome {
        case .hit:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .miss:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }

    static func flipITM() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #elseif os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        #endif
    }
}

// MARK: - Safe Area Inset

struct ReferencePhoneInset: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .padding(.top, PhoneTarget.topInset)
            .padding(.bottom, PhoneTarget.bottomInset)
        #else
        content
        #endif
    }
}

// MARK: - Shared Helpers

func verbInk(_ verb: String) -> Color {
    switch verb {
    case "TAP HIGH", "HIT":
        return DeskInk.emerald
    case "TAP LOW", "MISS":
        return DeskInk.coral
    case "EXPIRED", "WAIT", "SCAN":
        return DeskInk.slate
    default:
        return DeskInk.slate
    }
}

func bookInk(_ side: String) -> Color {
    switch side {
    case "HIGH":
        return DeskInk.emerald
    case "LOW":
        return DeskInk.coral
    default:
        return DeskInk.slate
    }
}
