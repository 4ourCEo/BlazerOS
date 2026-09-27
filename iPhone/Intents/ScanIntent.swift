import AppIntents
import BlazerCore
import Foundation

/// "Scan with Blazer" opens the existing six-market walk. It does not score or choose a side.
public struct ScanIntent: AppIntent {
    public static var title: LocalizedStringResource = "Scan with Blazer"
    public static var description = IntentDescription("Opens the Lightning Desk and initiates a watchlist scan.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        defaults?.set(true, forKey: PhoneTarget.pendingScanKey)
        return .result()
    }
}
