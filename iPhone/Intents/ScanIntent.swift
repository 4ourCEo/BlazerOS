import AppIntents
import BlazerCore
import Foundation

/// "Scan with Blazer" opens the existing six-market walk. It does not score or choose a side.
public struct ScanIntent: AppIntent {
    public static let title: LocalizedStringResource = "Scan with Blazer"
    public static let description = IntentDescription("Opens the Lightning Desk and initiates a watchlist scan.")
    public static let openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
        return .result()
    }
}

public struct BlazerShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanIntent(),
            phrases: [
                "Scan with \(.applicationName)",
                "Start \(.applicationName) scan",
                "Scan watchlist in \(.applicationName)"
            ],
            shortTitle: "Scan",
            systemImageName: "bolt.fill"
        )
    }
}

