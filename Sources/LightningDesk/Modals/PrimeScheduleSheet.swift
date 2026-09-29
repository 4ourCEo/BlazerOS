import BlazerCore
import SwiftUI

/// Modal sheet detailing the Pacific Time Prime Trading Windows,
/// empirical win-rate calibration, and local notification controls.
public struct PrimeScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsEnabled = MarketNotificationService.shared.isNotificationsEnabled
    @State private var testAlertSent = false
    @State private var isScheduling = false

    public init() {}

    public var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DeskInk.electric)
                                .frame(width: 8, height: 8)
                                .shadow(color: DeskInk.electric.opacity(0.8), radius: 4)
                            Text("PACIFIC TIME PRIME INTEL")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(DeskInk.electric)
                        }
                        Text("Session Intelligence")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(DeskInk.ink)
                    }

                    Spacer()

                    Button {
                        DeskHaptics.tabSwitch()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(DeskInk.slate.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        currentStatusCard
                        scheduleCards
                        notificationsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .task {
            // Check real system authorization status on appear
            let authorized = await MarketNotificationService.shared.checkAuthorizationStatus()
            notificationsEnabled = authorized && MarketNotificationService.shared.isNotificationsEnabled
        }
    }

    // MARK: - Current Live Status Card

    private var currentStatusCard: some View {
        let currentWindow = MarketEdgeWindow.current()
        let isSupreme = currentWindow.isSupremePrime
        let isTactical = currentWindow.isTactical
        let cardColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.violet)

        let statusTitle: String = isSupreme ? "👑 SUPREME PRIME ACTIVE" : (isTactical ? "🌙 TACTICAL LATE-NIGHT (BURSTS ONLY)" : "⚠️ OFF-PEAK CONSOLIDATION")
        let statBadge: String = isSupreme ? "61.2% WR · NY OVERLAP" : (isTactical ? "BURSTS ONLY · THIN LIQUIDITY" : "42.1% WR · PRESERVE CAPITAL")
        let statColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.coral)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(cardColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: isSupreme ? "bolt.fill" : (isTactical ? "bolt.horizontal.fill" : "moon.stars.fill"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(cardColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(cardColor)
                    Text(currentWindow.detailText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.ink.opacity(0.85))
                }

                Spacer()

                Text(statBadge)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(statColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statColor.opacity(0.16), in: Capsule())
            }

            Text(statusExplanation(currentWindow))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineSpacing(2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DeskInk.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            cardColor.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }

    private func statusExplanation(_ window: MarketEdgeWindow) -> String {
        if window.isSupremePrime {
            return "Active London / New York Overlap. Over 70% of daily global FX volume trades during this window. Directional expansion creates maximum 60s binary continuation."
        } else if window.isTactical {
            return "Pre-London institutional positioning. Liquidity is thin and bursty between moves. Focus exclusively on confirmed GBP/USD breakout momentum. Avoid slow range pairs."
        } else {
            return "Market is in consolidation or Asian lull. Low follow-through and high wick risk. Smart schedule preserves capital until the next verified window."
        }
    }

    // MARK: - Prime Window Schedules

    private var scheduleCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALIBRATED TRADING WINDOWS (PACIFIC TIME)")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate.opacity(0.8))
                .padding(.leading, 4)

            // Morning Window Card
            windowCard(
                title: "👑 Morning Supreme Prime (NY Overlap)",
                time: "5:00 AM – 9:00 AM PT",
                utcTime: "12:00 – 16:00 UTC",
                winRate: "61.2% WR · KING",
                topPairs: "GBP/USD, USD/JPY, EUR/USD",
                note: "Peak institutional volume during London / NY overlap. Directional expansion creates deepest liquidity and cleanest 60s binary continuation."
            )

            // Late Night Window Card
            windowCard(
                title: "🌙 Late Night Tactical Scalp",
                time: "11:00 PM – 12:30 AM PT",
                utcTime: "06:00 – 07:30 UTC",
                winRate: "Bursts Only",
                topPairs: "GBP/USD (Confirm Breakouts)",
                note: "Pre-market London positioning. Liquidity is thin between moves. Trade confirmed momentum bursts only; avoid range chop on other pairs."
            )
        }
    }

    private func windowCard(
        title: String,
        time: String,
        utcTime: String,
        winRate: String,
        topPairs: String,
        note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DeskInk.ink)
                    HStack(spacing: 6) {
                        Text(time)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(DeskInk.electric)
                        Text("(\(utcTime))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DeskInk.slate.opacity(0.7))
                    }
                }

                Spacer()

                Text(winRate)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.emerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DeskInk.emerald.opacity(0.18), in: Capsule())
            }

            HStack(spacing: 4) {
                Text("Prime Pairs:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskInk.slate)
                Text(topPairs)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DeskInk.ink)
            }

            Text(note)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DeskInk.slate.opacity(0.85))
                .lineSpacing(2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DeskInk.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALERTS & AUTOMATION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate.opacity(0.8))
                .padding(.leading, 4)

            VStack(spacing: 12) {
                // Toggle row
                Toggle(isOn: Binding(
                    get: { notificationsEnabled },
                    set: { enabled in
                        notificationsEnabled = enabled
                        Task {
                            isScheduling = true
                            if enabled {
                                await MarketNotificationService.shared.schedulePrimeNotifications()
                                let authorized = await MarketNotificationService.shared.checkAuthorizationStatus()
                                notificationsEnabled = authorized
                            } else {
                                MarketNotificationService.shared.cancelPrimeNotifications()
                            }
                            isScheduling = false
                        }
                    }
                )) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(DeskInk.electric.opacity(0.2))
                                .frame(width: 32, height: 32)
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DeskInk.electric)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prime Window Alerts")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DeskInk.ink)
                            Text("Alert at 5:00 AM & 11:00 PM PT")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DeskInk.slate)
                        }
                    }
                }
                .tint(DeskInk.emerald)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Test Alert Button
                HStack {
                    Button {
                        Task {
                            DeskHaptics.commit()
                            testAlertSent = false
                            let ok = await MarketNotificationService.shared.sendTestNotification(delaySec: 2)
                            if ok {
                                testAlertSent = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                    testAlertSent = false
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Send Test Alert (2s)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(DeskInk.electric)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DeskInk.electric.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if testAlertSent {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Alert Dispatched!")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(DeskInk.emerald)
                        .transition(.opacity)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DeskInk.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
                    )
            )
        }
    }
}
