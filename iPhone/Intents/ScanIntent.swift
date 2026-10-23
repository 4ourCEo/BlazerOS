import AppIntents
import Foundation

/// "Scan with Blazer" opens the existing six-market walk. It does not score or choose a side.
public struct ScanIntent: AppIntent {
    public static let title: LocalizedStringResource = "Scan with Blazer"
    public static let description = IntentDescription("Opens the Lightning Desk and initiates a watchlist scan.")
    public static let openAppWhenRun: Bool = true

    public init() {}

    /// Mirrors `PhoneTarget` in BlazerCore. The Intents framework deliberately does not link
    /// the engine: a framework loaded into the app that links BlazerCore makes Xcode build a
    /// dynamic copy alongside the app's static one, which duplicates every class in the process.
    private static let appGroup = "group.com.blazer.os"
    private static let pendingScanKey = "blazer.pendingScan"

    @MainActor
    public func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: Self.appGroup)
        defaults?.set(true, forKey: Self.pendingScanKey)
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

