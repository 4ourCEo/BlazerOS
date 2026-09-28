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
    static let background = Color(red: 11.0 / 255, green: 15.0 / 255, blue: 23.0 / 255)
    static let surface = Color(red: 21.0 / 255, green: 29.0 / 255, blue: 42.0 / 255)
    static let indigo = Color(red: 79.0 / 255, green: 70.0 / 255, blue: 229.0 / 255)
    static let electric = Color(red: 47.0 / 255, green: 128.0 / 255, blue: 255.0 / 255)
    static let emerald = Color(red: 16.0 / 255, green: 185.0 / 255, blue: 129.0 / 255)
    static let coral = Color(red: 240.0 / 255, green: 113.0 / 255, blue: 103.0 / 255)
    static let violet = Color(red: 139.0 / 255, green: 124.0 / 255, blue: 255.0 / 255)
    static let ink = Color.white
    static let slate = Color(red: 148.0 / 255, green: 163.0 / 255, blue: 184.0 / 255)
}

// MARK: - Haptics

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
