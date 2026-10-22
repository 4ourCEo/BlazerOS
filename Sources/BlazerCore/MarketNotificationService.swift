import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Manages local push notifications for high-conviction Pacific Time prime trading windows.
/// Configured for 5:00 AM PT (Morning NY Overlap) and 11:00 PM PT (Late Night London Surge).
public final class MarketNotificationService: NSObject, @unchecked Sendable {
    public static let shared = MarketNotificationService()

    public static let morningNotificationID = "blazer.prime.morning"
    public static let lateNightNotificationID = "blazer.prime.latenight"
    public static let testNotificationID = "blazer.prime.test"

    private let userDefaultsKey = "blazer.notifications.prime_windows_enabled"

    /// `UNUserNotificationCenter.current()` traps when the process has no application bundle
    /// (the unit-test runner, command-line tools, XPC agents). Those callers still get a sane
    /// answer: notifications are unavailable.
    private static var hasAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public var isNotificationsEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    public override init() {
        super.init()
        #if canImport(UserNotifications)
        if Self.hasAppBundle {
            UNUserNotificationCenter.current().delegate = self
        }
        #endif
    }

    /// Check if notifications are currently authorized
    public func checkAuthorizationStatus() async -> Bool {
        #if canImport(UserNotifications)
        guard Self.hasAppBundle else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        #else
        return false
        #endif
    }

    /// Request notification authorization from the user
    public func requestAuthorization() async -> Bool {
        #if canImport(UserNotifications)
        guard Self.hasAppBundle else { return false }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                center.delegate = self
            }
            return granted
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Schedule recurring Pacific Time prime window alerts
    public func schedulePrimeNotifications() async {
        #if canImport(UserNotifications)
        guard Self.hasAppBundle else { return }
        let center = UNUserNotificationCenter.current()

        let granted = await requestAuthorization()
        guard granted else { return }

        center.removePendingNotificationRequests(withIdentifiers: [
            Self.morningNotificationID,
            Self.lateNightNotificationID
        ])

        guard let ptZone = TimeZone(identifier: "America/Los_Angeles") else { return }

        // 1. Morning Prime Window (5:00 AM PT)
        let morningContent = UNMutableNotificationContent()
        morningContent.title = "⚡ Morning Prime Window Active"
        morningContent.subtitle = "NY Overlap (5:00 AM – 10:00 AM PT)"
        morningContent.body = "Morning research window is open. Check setup and entry quality; the schedule does not establish a winning probability."
        morningContent.sound = .default

        var morningComponents = DateComponents()
        morningComponents.timeZone = ptZone
        morningComponents.hour = 5
        morningComponents.minute = 0

        let morningTrigger = UNCalendarNotificationTrigger(dateMatching: morningComponents, repeats: true)
        let morningRequest = UNNotificationRequest(
            identifier: Self.morningNotificationID,
            content: morningContent,
            trigger: morningTrigger
        )

        // 2. Late Night Prime Window (11:00 PM PT)
        let lateNightContent = UNMutableNotificationContent()
        lateNightContent.title = "⚡ Late Night Prime Window Active"
        lateNightContent.subtitle = "Pre-London Surge (11:00 PM – 12:30 AM PT)"
        lateNightContent.body = "Late-night research window is open. Validate the setup and observed outcomes before treating this period as an edge."
        lateNightContent.sound = .default

        var lateNightComponents = DateComponents()
        lateNightComponents.timeZone = ptZone
        lateNightComponents.hour = 23
        lateNightComponents.minute = 0

        let lateNightTrigger = UNCalendarNotificationTrigger(dateMatching: lateNightComponents, repeats: true)
        let lateNightRequest = UNNotificationRequest(
            identifier: Self.lateNightNotificationID,
            content: lateNightContent,
            trigger: lateNightTrigger
        )

        do {
            try await center.add(morningRequest)
            try await center.add(lateNightRequest)
            isNotificationsEnabled = true
        } catch {
            print("[MarketNotificationService] Failed to schedule prime notifications: \(error)")
        }
        #endif
    }

    /// Cancel prime window notifications
    public func cancelPrimeNotifications() {
        #if canImport(UserNotifications)
        guard Self.hasAppBundle else {
            isNotificationsEnabled = false
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.morningNotificationID,
            Self.lateNightNotificationID
        ])
        isNotificationsEnabled = false
        #endif
    }

    /// Send a quick test alert (after e.g. 3 seconds) so the user can verify on their iPhone
    public func sendTestNotification(delaySec: TimeInterval = 3) async -> Bool {
        #if canImport(UserNotifications)
        guard Self.hasAppBundle else { return false }
        let center = UNUserNotificationCenter.current()
        let granted = await requestAuthorization()
        guard granted else { return false }

        center.delegate = self

        let content = UNMutableNotificationContent()
        content.title = "⚡ Pacific Time Prime Window Test"
        content.subtitle = "Pacific Edge Alert System Verified"
        content.body = "Research windows: 5:00–10:00 AM PT and 11:00 PM–12:30 AM PT. Window win rates remain unverified."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delaySec), repeats: false)
        let request = UNNotificationRequest(identifier: Self.testNotificationID, content: content, trigger: trigger)

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

#if canImport(UserNotifications)
extension MarketNotificationService: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, macOS 11.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
}
#endif
