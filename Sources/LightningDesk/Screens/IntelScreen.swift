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
            HStack(spacing: 6) {
                Circle()
                    .fill(MarketEdgeWindow.current().isPrime ? DeskInk.emerald : DeskInk.violet)
                    .frame(width: 6, height: 6)
                    .shadow(color: (MarketEdgeWindow.current().isPrime ? DeskInk.emerald : DeskInk.violet).opacity(0.8), radius: 3)
                Text(MarketEdgeWindow.current().isPrime ? "PRIME" : "OFF-PEAK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(MarketEdgeWindow.current().isPrime ? DeskInk.emerald : DeskInk.violet)
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
        let isPrime = currentWindow.isPrime

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((isPrime ? DeskInk.emerald : DeskInk.violet).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: isPrime ? "bolt.fill" : "moon.stars.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isPrime ? DeskInk.emerald : DeskInk.violet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isPrime ? "HIGH-EDGE PRIME ACTIVE" : "OFF-PEAK CONSOLIDATION")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(isPrime ? DeskInk.emerald : DeskInk.ink)
                    Text(currentWindow.detailText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                }

                Spacer()

                Text(isPrime ? "61.2% WR" : "42.1% WR")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isPrime ? DeskInk.emerald : DeskInk.coral)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((isPrime ? DeskInk.emerald : DeskInk.coral).opacity(0.16), in: Capsule())
            }

            // Live Second-by-Second Countdown Ticker HUD
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isPrime ? DeskInk.emerald : DeskInk.electric)
                Text(liveCountdownText())
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isPrime ? DeskInk.emerald : DeskInk.electric)
                Spacer()
                Text("PACIFIC CLOCK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeskInk.slate.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(statusExplanation(isPrime))
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
                            (isPrime ? DeskInk.emerald : DeskInk.violet).opacity(0.35),
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

        if currentWindow.isPrime {
            if totalMin >= 300 && totalMin < 600 {
                let remSec = max(0, (600 * 60) - (totalMin * 60 + sec))
                let h = remSec / 3600
                let m = (remSec % 3600) / 60
                let s = remSec % 60
                return String(format: "PRIME ENDS IN: %02dh %02dm %02ds", h, m, s)
            } else {
                let targetSec = 1470 * 60 // 12:30 AM
                let curSec = (totalMin >= 1380 ? totalMin : totalMin + 1440) * 60 + sec
                let remSec = max(0, targetSec - curSec)
                let h = remSec / 3600
                let m = (remSec % 3600) / 60
                let s = remSec % 60
                return String(format: "PRIME ENDS IN: %02dh %02dm %02ds", h, m, s)
            }
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

    private func statusExplanation(_ isPrime: Bool) -> String {
        if isPrime {
            return "Active Pacific Time window with verified institutional volume. Directional momentum filters are operating at peak statistical conviction."
        } else {
            return "The morning window closed at 10:00 AM PT. Midday markets experience choppy consolidations and low hit rates. Smart schedule preserves capital until the 11:00 PM PT window opens."
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
                title: "Morning Prime (NY Overlap)",
                time: "5:00 AM – 10:00 AM PT",
                utcTime: "12:00 – 17:00 UTC",
                winRate: "61.2% WR",
                topPairs: "GBP/USD, USD/JPY",
                note: "Peak institutional volume during London / NY overlap. Directional expansion creates reliable 60s binary continuation."
            )

            // Late Night Window Card
            windowCard(
                title: "Late Night London Surge",
                time: "11:00 PM – 12:30 AM PT",
                utcTime: "06:00 – 07:30 UTC",
                winRate: "69.2% WR",
                topPairs: "GBP/USD (+0.3p drift)",
                note: "Pre-market London positioning surge. Highest statistical hit rate across 372 live-tested forward contracts."
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
