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

    func update(with frame: DeskFrame?, trade: ActiveTrade? = nil) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let frame else {
            endAllActivities()
            return
        }

        let isLiveTrade = trade != nil && !(trade?.isExpired ?? true)
        let isArmed = frame.isActionable

        if isLiveTrade, let trade {
            let contentState = DeskActivityAttributes.ContentState(
                verb: "\(trade.side) \(Int(trade.durationSec))s",
                endsAt: trade.expiresAt,
                startedAt: trade.enteredAt,
                veto: nil,
                currentPrice: trade.currentPrice
            )

            if let activity = activity(for: trade.fingerprint) {
                currentActivity = activity
                Task {
                    await activity.update(
                        ActivityContent(state: contentState, staleDate: trade.expiresAt)
                    )
                }
            } else {
                endOtherActivities()
                let attributes = DeskActivityAttributes(
                    pair: trade.pair,
                    score: trade.score,
                    strike: trade.strike,
                    fingerprint: trade.fingerprint
                )
                do {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        content: ActivityContent(state: contentState, staleDate: trade.expiresAt),
                        pushType: nil
                    )
                } catch {
                    // Fail gracefully
                }
            }
        } else if isArmed {
            let endsAt = Date().addingTimeInterval(max(0, frame.remainingMs / 1000.0))
            let startedAt = Date().addingTimeInterval(-max(0, (Timing.liveMs - frame.remainingMs) / 1000.0))
            let contentState = DeskActivityAttributes.ContentState(
                verb: frame.verb,
                endsAt: endsAt,
                startedAt: startedAt,
                veto: frame.veto,
                currentPrice: nil
            )

            if let activity = activity(for: frame.fingerprint) {
                currentActivity = activity
                Task {
                    await activity.update(
                        ActivityContent(state: contentState, staleDate: endsAt)
                    )
                }
            } else {
                endOtherActivities()
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
        } else if let activity = activity(for: frame.fingerprint) ?? currentActivity {
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

    /// Finds the activity by fingerprint, including one left behind by a previous launch.
    private func activity(for fingerprint: String) -> Activity<DeskActivityAttributes>? {
        if let currentActivity, currentActivity.attributes.fingerprint == fingerprint {
            return currentActivity
        }
        return Activity<DeskActivityAttributes>.activities.first {
            $0.attributes.fingerprint == fingerprint
        }
    }

    /// Ends every activity except the current one. Recovery does not rely on in-memory state.
    private func endOtherActivities() {
        for activity in Activity<DeskActivityAttributes>.activities
        where activity.id != currentActivity?.id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func endAllActivities() {
        for activity in Activity<DeskActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        currentActivity = nil
    }
}
