import BlazerActivity
import SwiftUI
import WidgetKit

/// Live Activity for an armed 8-second beam. Displays on Dynamic Island and Lock Screen.
/// The desk pushes state updates. The Live Activity does not score.
struct DeskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeskActivityAttributes.self) { context in
            lockScreenBanner(context: context)
                .activityBackgroundTint(Color(red: 11.0 / 255, green: 15.0 / 255, blue: 23.0 / 255))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.pair)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Strike \(String(format: "%.5f", context.attributes.strike))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.verb)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(verbColor(context.state.verb))
                        Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Score \(context.attributes.score)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                        Spacer()
                        if let veto = context.state.veto {
                            Text("VETO: \(veto)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(red: 231.0 / 255, green: 76.0 / 255, blue: 60.0 / 255))
                        } else {
                            Text("#\(context.attributes.fingerprint.prefix(4))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Text(context.attributes.pair)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            } compactTrailing: {
                Text(context.state.verb)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(verbColor(context.state.verb))
            } minimal: {
                Text("B")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(verbColor(context.state.verb))
            }
        }
    }

    private func lockScreenBanner(context: ActivityViewContext<DeskActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BLAZER")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.pair)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Strike \(String(format: "%.5f", context.attributes.strike))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.verb)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(verbColor(context.state.verb))
                    Text("Score \(context.attributes.score)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }

            if let veto = context.state.veto {
                Text("VETO: \(veto)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 231.0 / 255, green: 76.0 / 255, blue: 60.0 / 255))
            }
        }
        .padding(16)
    }

    private func verbColor(_ verb: String) -> Color {
        switch verb {
        case "TAP HIGH":
            return Color(red: 46.0 / 255, green: 204.0 / 255, blue: 113.0 / 255)
        case "TAP LOW":
            return Color(red: 231.0 / 255, green: 76.0 / 255, blue: 60.0 / 255)
        default:
            return Color.white.opacity(0.6)
        }
    }
}

@main
struct BlazerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DeskLiveActivity()
    }
}
