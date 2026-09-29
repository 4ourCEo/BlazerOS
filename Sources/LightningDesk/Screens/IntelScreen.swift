import BlazerCore
import SwiftUI

/// Dedicated Pacific Time Intelligence Center.
/// Displays live session status, calibrated edge windows, empirical win rates, and push notification controls.
public struct IntelScreen: View {
    @ObservedObject var model: LightningDeskModel
    @State private var notificationsEnabled = MarketNotificationService.shared.isNotificationsEnabled
    @State private var testAlertSent = false
    @State private var isScheduling = false
    @State private var now = Date()

    public init(model: LightningDeskModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    currentStatusCard
                    scheduleCards
                    notificationsSection
                    pairConvictionSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .task {
            let authorized = await MarketNotificationService.shared.checkAuthorizationStatus()
            notificationsEnabled = authorized && MarketNotificationService.shared.isNotificationsEnabled

            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Intel")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Text("Pacific Time Prime Windows · America/Los_Angeles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
            }
            Spacer()
            let currentWindow = MarketEdgeWindow.current(at: now)
            let isSupreme = currentWindow.isSupremePrime
            let isTactical = currentWindow.isTactical
            let headerColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.violet)
            let headerText: String = isSupreme ? "SUPREME PRIME" : (isTactical ? "TACTICAL" : "OFF-PEAK")

            HStack(spacing: 6) {
                Circle()
                    .fill(headerColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: headerColor.opacity(0.8), radius: 3)
                Text(headerText)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(headerColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DeskInk.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    // MARK: - Current Live Status Card

    private var currentStatusCard: some View {
        let currentWindow = MarketEdgeWindow.current(at: now)
        let isSupreme = currentWindow.isSupremePrime
        let isTactical = currentWindow.isTactical
        let cardColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.violet)

        let statusTitle: String = isSupreme ? "👑 SUPREME PRIME ACTIVE" : (isTactical ? "🌙 TACTICAL LATE-NIGHT (BURSTS ONLY)" : "⚠️ OFF-PEAK CONSOLIDATION")
        let statBadge: String = isSupreme ? "61.2% WR · NY OVERLAP" : (isTactical ? "BURSTS ONLY · THIN LIQUIDITY" : "42.1% WR · PRESERVE CAPITAL")
        let statColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.coral)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(cardColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: isSupreme ? "bolt.fill" : (isTactical ? "bolt.horizontal.fill" : "moon.stars.fill"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(cardColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(cardColor)
                    Text(currentWindow.detailText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                }

                Spacer()

                Text(statBadge)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(statColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statColor.opacity(0.16), in: Capsule())
            }

            // Live Second-by-Second Countdown Ticker HUD
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(cardColor)
                Text(liveCountdownText())
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(cardColor)
                Spacer()
                Text("PACIFIC CLOCK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeskInk.slate.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(statusExplanation(currentWindow))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .lineSpacing(2.5)

            if model.trapsAvoidedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DeskInk.emerald)
                    Text("\(model.trapsAvoidedCount) chop traps avoided today · Capital preserved")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeskInk.emerald)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DeskInk.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DeskInk.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            cardColor.opacity(0.35),
                            lineWidth: 1
                        )
                )
        )
    }

    private func liveCountdownText() -> String {
        let currentWindow = MarketEdgeWindow.current(at: now)
        guard let ptZone = TimeZone(identifier: "America/Los_Angeles") else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = ptZone

        let hour = cal.component(.hour, from: now)
        let min = cal.component(.minute, from: now)
        let sec = cal.component(.second, from: now)
        let totalMin = hour * 60 + min

        if currentWindow.isSupremePrime {
            let remSec = max(0, (9 * 3600) - (totalMin * 60 + sec))
            let h = remSec / 3600
            let m = (remSec % 3600) / 60
            let s = remSec % 60
            return String(format: "SUPREME PRIME ENDS IN: %02dh %02dm %02ds", h, m, s)
        } else if currentWindow.isTactical {
            let targetSec = 1470 * 60 // 12:30 AM
            let curSec = (totalMin >= 1380 ? totalMin : totalMin + 1440) * 60 + sec
            let remSec = max(0, targetSec - curSec)
            let m = (remSec % 3600) / 60
            let s = remSec % 60
            return String(format: "BURST WINDOW ENDS IN: %02dm %02ds · NEXT SUPREME: 5:00 AM PT", m, s)
        } else {
            let nextTargetTotalSec: Int
            let nowSec = totalMin * 60 + sec
            if totalMin < 300 {
                nextTargetTotalSec = 300 * 60
            } else if totalMin < 1380 {
                nextTargetTotalSec = 1380 * 60
            } else {
                nextTargetTotalSec = (1440 + 300) * 60
            }
            let diff = max(0, nextTargetTotalSec - nowSec)
            let h = diff / 3600
            let m = (diff % 3600) / 60
            let s = diff % 60
            return String(format: "NEXT PRIME IN: %02dh %02dm %02ds", h, m, s)
        }
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
            Text("CALIBRATED TRADING WINDOWS")
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
                        .font(.system(size: 15, weight: .bold))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("ALERTS & AUTOMATION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate.opacity(0.8))
                .padding(.leading, 4)

            VStack(spacing: 12) {
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
                                .frame(width: 34, height: 34)
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 14, weight: .bold))
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

    // MARK: - Pair Conviction Matrix

    private var pairConvictionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATISTICAL PAIR CONVICTION")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate.opacity(0.8))
                .padding(.leading, 4)

            VStack(spacing: 8) {
                convictionRow(pair: "GBP/USD", tag: "EDGE PRIME", winRate: "57.8%", drift: "+0.3p", isEdge: true)
                convictionRow(pair: "USD/JPY", tag: "EDGE PRIME", winRate: "54.2%", drift: "+0.3p", isEdge: true)
                convictionRow(pair: "EUR/USD", tag: "BALANCED", winRate: "50.0%", drift: "0.0p", isEdge: false)
                convictionRow(pair: "AUD/USD", tag: "BALANCED", winRate: "52.7%", drift: "0.0p", isEdge: false)
                convictionRow(pair: "USD/CAD", tag: "CHOP RISK", winRate: "36.4%", drift: "-0.4p", isEdge: false, isWarning: true)
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

    private func convictionRow(pair: String, tag: String, winRate: String, drift: String, isEdge: Bool, isWarning: Bool = false) -> some View {
        HStack {
            Text(pair)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(DeskInk.ink)

            Text(tag)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(isWarning ? DeskInk.coral : (isEdge ? DeskInk.emerald : DeskInk.slate))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isWarning ? DeskInk.coral : (isEdge ? DeskInk.emerald : DeskInk.slate)).opacity(0.16), in: RoundedRectangle(cornerRadius: 4))

            Spacer()

            Text("Drift \(drift)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DeskInk.slate.opacity(0.8))

            Text(winRate)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(isWarning ? DeskInk.coral : (isEdge ? DeskInk.emerald : DeskInk.slate))
        }
    }
}
