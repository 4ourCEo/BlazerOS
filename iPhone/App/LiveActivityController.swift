import ActivityKit
import BlazerActivity
import BlazerCore
import Foundation

/// Coordinates Dynamic Island and Lock Screen Live Activities during an armed 8s beam.
/// The desk pushes state updates. This controller does not score or decide sides.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var currentActivity: Activity<DeskActivityAttributes>?

    func update(with frame: DeskFrame?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let frame else {
            endCurrentActivity()
            return
        }

        let isArmed = (frame.verb == "TAP HIGH" || frame.verb == "TAP LOW") && frame.remainingMs > 0

        if isArmed {
            let endsAt = Date().addingTimeInterval(max(0, frame.remainingMs / 1000.0))
            let contentState = DeskActivityAttributes.ContentState(
                verb: frame.verb,
                endsAt: endsAt,
                veto: frame.veto
            )

            if let activity = currentActivity, activity.attributes.fingerprint == frame.fingerprint {
                Task {
                    await activity.update(
                        ActivityContent(state: contentState, staleDate: endsAt)
                    )
                }
            } else {
                endCurrentActivity()
                let attributes = DeskActivityAttributes(
                    pair: frame.pair,
                    score: frame.score,
                    strike: frame.strike,
                    fingerprint: frame.fingerprint
                )
                do {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: contentState, staleDate: endsAt),
                        pushType: nil
                    )
                } catch {
                    // Fail gracefully if permission is denied or device does not support it
                }
            }
        } else if let activity = currentActivity {
            let contentState = DeskActivityAttributes.ContentState(
                verb: frame.verb,
                endsAt: Date(),
                veto: frame.veto
            )
            Task {
                await activity.end(
                    ActivityContent(state: contentState, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(2.5))
                )
            }
            currentActivity = nil
        }
    }

    private func endCurrentActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }
}
