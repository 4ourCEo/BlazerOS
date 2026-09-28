import BlazerActivity
import SwiftUI
import WidgetKit

/// Premium Live Activity for BlazerOS. Displays on Dynamic Island and Lock Screen.
/// Synchronized with 60-second binary options execution and 15-second entry beam.
struct DeskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeskActivityAttributes.self) { context in
            lockScreenBanner(context: context)
                .activityBackgroundTint(Color(red: 12.0 / 255, green: 16.0 / 255, blue: 24.0 / 255))
        } dynamicIsland: { context in
            let tint = verbColor(context.state.verb)
            let isHigh = isCall(context.state.verb)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tint)
                                .frame(width: 7, height: 7)
                                .shadow(color: tint.opacity(0.8), radius: 3)
                            Text(context.attributes.pair)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                        }

                        Text("Strike \(String(format: "%.5f", context.attributes.strike))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))

                        if let live = context.state.currentPrice {
                            Text("Live \(String(format: "%.5f", live))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(tint.opacity(0.9))
                        }
                    }
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(displayVerb(context.state.verb))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.18), in: Capsule())
                            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.75))

                        Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(
                            timerInterval: context.state.startedAt...context.state.endsAt,
                            countsDown: false
                        )
                        .tint(tint)
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)

                        HStack {
                            Text("Score \(context.attributes.score)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                            Spacer()

                            if let veto = context.state.veto {
                                Text("VETO: \(veto)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(red: 240.0 / 255, green: 113.0 / 255, blue: 103.0 / 255))
                            } else {
                                Text(context.state.verb.contains("60s") ? "60s BINARY HORIZON" : "ACTION WINDOW")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(tint.opacity(0.9))
                            }

                            Spacer()

                            Text("#\(context.attributes.fingerprint.prefix(4))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: isHigh ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                    Text(context.attributes.pair)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(minWidth: 32, alignment: .trailing)
            } minimal: {
                Image(systemName: isHigh ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(tint)
            }
        }
    }

    private func lockScreenBanner(context: ActivityViewContext<DeskActivityAttributes>) -> some View {
        let tint = verbColor(context.state.verb)
        let isHigh = isCall(context.state.verb)

        return VStack(alignment: .leading, spacing: 10) {
            // Header: Branding + Countdown
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .shadow(color: tint.opacity(0.9), radius: 3)
                    Text("BLAZER")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.8)
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(context.state.verb.contains("60s") ? "60s BINARY HORIZON" : "ENTRY BEAM")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(tint)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.1), in: Capsule())
            }

            // Main Trade Details Row
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.pair)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(spacing: 8) {
                        Text("Strike \(String(format: "%.5f", context.attributes.strike))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.7))

                        if let live = context.state.currentPrice {
                            Text("Live \(String(format: "%.5f", live))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(tint)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: isHigh ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                        Text(displayVerb(context.state.verb))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.75))

                    Text("Score \(context.attributes.score)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }

            // Progress rail
            ProgressView(
                timerInterval: context.state.startedAt...context.state.endsAt,
                countsDown: false
            )
            .tint(tint)

            // Veto or Footer
            if let veto = context.state.veto {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("VETO: \(veto)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(red: 240.0 / 255, green: 113.0 / 255, blue: 103.0 / 255))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 14.0 / 255, green: 19.0 / 255, blue: 29.0 / 255))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 0.75)
                )
        )
    }

    private func isCall(_ verb: String) -> Bool {
        verb.contains("HIGH") || verb.contains("CALL")
    }

    private func displayVerb(_ verb: String) -> String {
        if verb.contains("60s") {
            return isCall(verb) ? "CALL 60s" : "PUT 60s"
        }
        if verb.contains("HIGH") { return "TAP HIGH" }
        if verb.contains("LOW") { return "TAP LOW" }
        return verb
    }

    private func verbColor(_ verb: String) -> Color {
        if isCall(verb) {
            return Color(red: 16.0 / 255, green: 185.0 / 255, blue: 129.0 / 255)
        } else if verb.contains("LOW") || verb.contains("PUT") {
            return Color(red: 240.0 / 255, green: 113.0 / 255, blue: 103.0 / 255)
        } else {
            return Color(red: 79.0 / 255, green: 70.0 / 255, blue: 229.0 / 255)
        }
    }
}

@main
struct BlazerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DeskLiveActivity()
    }
}
