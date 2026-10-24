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
    @State private var otcAPIKeyDraft = ""
    @State private var brokerPriceDraft = ""
    @State private var providerPriceDraft = ""
    @State private var payoutDraft = ""
    @State private var screenshotDraft = ""
    @State private var candleTimeDraft = ""
    @State private var manualAgreement: ManualAgreement = .notAssessed
    @State private var manualConfidence: ManualVerificationConfidence = .low

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
                    executionEvidenceCard
                    otcResearchCard
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

    private var otcResearchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("POCKET OPTION OTC · READ-ONLY RESEARCH")
                .font(.system(size: 11, weight: .bold))
            Text("OTCharts adapter: \(model.otcConnectionState.rawValue.uppercased()) · disabled by default")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(model.otcAPIKeyConfigured ? DeskInk.electric : DeskInk.slate)
            Text("An API key enables only the independent research adapter. It is stored in this device's Keychain and is never supplied to the trading engine or Foundation Models.")
                .font(.system(size: 10))

            if model.otcAPIKeyConfigured {
                HStack {
                    Button(model.otcCaptureActive ? "Stop research capture" : "Start 5-minute capture") {
                        if model.otcCaptureActive { model.stopOTCResearchCapture() }
                        else { model.startOTCResearchCapture() }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("Refresh report") {
                        Task { await model.refreshOTCValidationReport() }
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                Text("Session: \(model.otcConnectionState.rawValue.uppercased()) · \(model.otcCapturedObservations) saved · \(model.otcObservedTicks) ticks\(model.otcObservedTickRate.map { String(format: " · %.1f/s", $0) } ?? "") · research-only")
                    .font(.system(size: 10, design: .monospaced))
                if let report = model.otcValidationReport {
                    Text("Samples \(report.totalSamples) · 60s transitions \(report.sixtySecondComparableTransitions) · agreements \(report.sixtySecondDirectionAgreements)")
                        .font(.system(size: 10, design: .monospaced))
                    Text(report.status)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(report.capturedLiveVendorData ? DeskInk.electric : DeskInk.slate)
                }
                Button("Disconnect and remove API key") {
                    model.disconnectAndRemoveOTChartsAPIKey()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeskInk.coral)
            } else {
                SecureField("OTCharts API key", text: $otcAPIKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Button("Save key to device Keychain") {
                    model.saveOTChartsAPIKey(otcAPIKeyDraft)
                    if model.otcAPIKeyConfigured { otcAPIKeyDraft = "" }
                }
                .font(.system(size: 11, weight: .semibold))
            }

            Divider().overlay(Color.white.opacity(0.12))
            Text("VISIBLE CHART CHECK · EUR/USD OTC")
                .font(.system(size: 10, weight: .bold))
            TextField("Broker displayed price", text: $brokerPriceDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Provider price (optional)", text: $providerPriceDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Displayed payout % (optional)", text: $payoutDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Screenshot filename/reference (optional)", text: $screenshotDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Candle time, ISO 8601 (optional)", text: $candleTimeDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker("Agreement", selection: $manualAgreement) {
                    Text("Not assessed").tag(ManualAgreement.notAssessed)
                    Text("Agrees").tag(ManualAgreement.agrees)
                    Text("Discrepancy").tag(ManualAgreement.discrepancy)
                }
                Picker("Confidence", selection: $manualConfidence) {
                    Text("Low").tag(ManualVerificationConfidence.low)
                    Text("Medium").tag(ManualVerificationConfidence.medium)
                    Text("High").tag(ManualVerificationConfidence.high)
                }
            }
            .font(.system(size: 10))
            Button("Capture timestamped chart observation") {
                Task {
                    await model.recordManualOTCObservation(
                        brokerPrice: brokerPriceDraft, providerPrice: providerPriceDraft,
                        payoutPercent: payoutDraft, screenshotReference: screenshotDraft,
                        candleTimestamp: ISO8601DateFormatter().date(from: candleTimeDraft),
                        agreement: manualAgreement, confidence: manualConfidence)
                    if model.otcResearchIssue == nil {
                        brokerPriceDraft = ""
                        providerPriceDraft = ""
                        payoutDraft = ""
                        screenshotDraft = ""
                        candleTimeDraft = ""
                    }
                }
            }
            .font(.system(size: 11, weight: .semibold))
            Text("Saved checks: \(model.manualBrokerObservations.count) · research-only · never settles a trade")
                .font(.system(size: 10, design: .monospaced))
            if let issue = model.otcResearchIssue {
                Text(issue).font(.system(size: 10)).foregroundStyle(DeskInk.coral)
            }
        }
        .foregroundStyle(DeskInk.slate)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var executionEvidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VERIFIED EDGE · EXECUTION QUALITY")
                .font(.system(size: 11, weight: .bold))
            Text(model.edgeVerificationReport?.status ?? "INSUFFICIENT EVIDENCE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeskInk.electric)
            if let report = model.edgeVerificationReport {
                Text("Confirmed \(report.wins)/\(report.resolved) · Candidate blocks \(report.candidateBlocks) · Effective N \(String(format: "%.1f", report.effectiveSampleSize))")
                    .font(.system(size: 11, design: .monospaced))
                Text(report.actualExpectancy.map { "Recorded payout EV: \(String(format: "%+.4f", $0)) per unit risk" }
                    ?? "Recorded payout EV unavailable · payout coverage \(report.payoutCoverage)/\(report.resolved)")
                    .font(.system(size: 11))
                Text(report.quality.meanScanToRecordMs.map { "Mean scan-to-record: \(String(format: "%.1f", $0 / 1000))s · timing records \(report.quality.timingCoverage)" }
                    ?? "Entry timing unavailable for historical records")
                    .font(.system(size: 11))
                Text("Rejected attempts \(report.quality.rejectedAttempts) · Closed scans without recorded entry \(report.quality.closedScansWithoutRecordedEntry)")
                    .font(.system(size: 11))
                DisclosureGroup("Evidence quality and market / expiry breakdown") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quote-age coverage: \(report.quality.quoteCoverage) · Reference disagreements: \(report.quality.referenceDisagreements)/\(report.quality.referenceComparisons)")
                        ForEach(report.cohorts.prefix(8), id: \.key) { cohort in
                            Text("\(cohort.key) · \(cohort.wins)/\(cohort.resolved) · " + (cohort.actualExpectancy.map { String(format: "EV %+.4f", $0) } ?? "payout incomplete"))
                        }
                        if let finding = report.findings.first {
                            Text("Research finding: \(finding.hypothesis). \(finding.evidence) \(finding.limitation)")
                        }
                        Text("Block independence remains unverified. At least 250 independent clustered prime-window events across the six-asset basket and independent prospective validation are required. Recording time is not venue fill time.")
                    }
                    .font(.system(size: 10))
                }
            }
            if let issue = model.executionObservationIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(DeskInk.coral)
            }
        }
        .foregroundStyle(DeskInk.slate)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 16))
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
            let cryptoMode = model.marketMode == .crypto
            let otcMode = model.marketMode == .otc
            let headerColor: Color = otcMode
                ? (model.otcSignalConnectionState == .live ? DeskInk.emerald : DeskInk.violet)
                : (cryptoMode
                    ? cryptoFeedTint(model.feed)
                    : (isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.violet)))
            let headerText: String = otcMode
                ? "OTC RESEARCH"
                : (cryptoMode
                    ? "₿ \(model.feed.rawValue)"
                    : (isSupreme ? "SUPREME PRIME" : (isTactical ? "TACTICAL" : "OFF-PEAK")))

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

    private func cryptoFeedTint(_ status: FeedStatus) -> Color {
        switch status {
        case .live: return DeskInk.emerald
        case .stale: return DeskInk.electric
        case .connecting: return DeskInk.violet
        case .disconnected, .error: return DeskInk.coral
        }
    }

    private var currentStatusCard: some View {
        let currentWindow = MarketEdgeWindow.current(at: now)
        let isSupreme = currentWindow.isSupremePrime
        let isTactical = currentWindow.isTactical
        let cardColor: Color = isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.violet)

        let otcMode = model.marketMode == .otc
        let statusTitle: String = otcMode
            ? "🔬 OTC RESEARCH · \(model.otcSignalConnectionState.rawValue.uppercased())"
            : (model.marketMode == .crypto
                ? "₿ CRYPTO DESK · \(model.feed.rawValue)"
                : (isSupreme ? "👑 SUPREME PRIME ACTIVE" : (isTactical ? "🌙 TACTICAL LATE-NIGHT (BURSTS ONLY)" : "⚠️ OFF-PEAK CONSOLIDATION")))
        let statBadge: String = otcMode
            ? "READ-ONLY · NOT AN ENTRY SIGNAL"
            : (isSupreme ? "MORNING RESEARCH WINDOW" : (isTactical ? "BURSTS ONLY · THIN LIQUIDITY" : "OUTSIDE RESEARCH WINDOW"))
        let statColor: Color = otcMode
            ? DeskInk.violet
            : (isSupreme ? DeskInk.emerald : (isTactical ? DeskInk.electric : DeskInk.coral))

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
        if model.marketMode == .otc {
            return "60s OTC RESEARCH HORIZON · NO EXECUTION GATE"
        }
        if model.marketMode == .crypto {
            return "₿ CRYPTO · 24/7 — NO FX SESSION GATE"
        }

        // Window arithmetic lives in MarketEdgeWindow so this screen cannot drift from it.
        let countdown = MarketEdgeWindow.countdown(at: now)
        switch countdown.phase {
        case .primeEndsIn(let remaining):
            if countdown.window.isSupremePrime {
                return "SUPREME PRIME ENDS IN: \(Self.hoursMinutesSeconds(remaining))"
            }
            return "BURST WINDOW ENDS IN: \(Self.minutesSeconds(remaining)) · NEXT SUPREME: 5:00 AM PT"
        case .nextPrimeIn(let remaining):
            return "NEXT PRIME IN: \(Self.hoursMinutesSeconds(remaining))"
        case .marketClosed(let remaining):
            return "FX MARKET CLOSED · OPENS IN: \(Self.hoursMinutesSeconds(remaining))"
        }
    }

    private static func hoursMinutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02dh %02dm %02ds", total / 3600, (total % 3600) / 60, total % 60)
    }

    private static func minutesSeconds(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02dm %02ds", total / 60, total % 60)
    }

    private func statusExplanation(_ window: MarketEdgeWindow) -> String {
        if model.marketMode == .otc {
            return "OTC research is read-only. The deterministic HIGH/LOW/WAIT score is a feature ranking, not a calibrated probability, and it cannot authorize an entry. Real Pocket Option observations and broker-confirmed outcomes remain unverified."
        }
        if model.marketMode == .crypto {
            return "Crypto trades 24/7. No London/New York overlap gate and no weekend closure. Trade when the feed is live and the setup is valid."
        }
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
            Text("RESEARCH TRADING WINDOWS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate.opacity(0.8))
                .padding(.leading, 4)

            // Morning Window Card
            windowCard(
                title: "👑 Morning Supreme Prime (NY Overlap)",
                time: "5:00 AM – 10:00 AM PT",
                utcTime: "UTC shifts with Pacific daylight saving",
                winRate: "WIN RATE UNVERIFIED",
                topPairs: "GBP/USD, USD/JPY, EUR/USD",
                note: "Scheduled morning research window. Validate setup quality, entry timing and outcomes before treating this period as an edge."
            )

            // Late Night Window Card
            windowCard(
                title: "🌙 Late Night Tactical Scalp",
                time: "11:00 PM – 12:30 AM PT",
                utcTime: "UTC shifts with Pacific daylight saving",
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
                ForEach(Assets.watchlist, id: \.self) { pair in
                    dynamicConvictionRow(pair: pair)
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                // Quarantined pairs
                VStack(spacing: 6) {
                    HStack {
                        Text("QUARANTINED PAIRS (EXCLUDED FROM BASKET)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DeskInk.coral.opacity(0.9))
                        Spacer()
                    }
                    dynamicConvictionRow(pair: "USD/CAD")
                    dynamicConvictionRow(pair: "EUR/GBP")
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)

                HStack {
                    Text("Break-even: 53.2% (at 88% payout)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DeskInk.slate)
                    Spacer()
                    Text("Intervals depend on local evidence")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DeskInk.slate.opacity(0.8))
                }

                Text(EdgeEvidence.standardCaveat)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DeskInk.slate.opacity(0.75))
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
    }

    private func dynamicConvictionRow(pair: String) -> some View {
        let stats = model.edgeStats(for: pair)
        let ratePct = stats.sampleSize > 0
            ? String(format: "%.1f%% [%.1f–%.1f]", stats.winRate * 100, stats.lower95 * 100, stats.upper95 * 100)
            : "unavailable"
        let isEdge = stats.isProvenEdge
        let isWarning = stats.statusBadge.contains("CHOP")
        let driftStr: String
        if let avgDrift = model.averageDrift(for: pair) {
            let sign = avgDrift >= 0 ? "+" : ""
            driftStr = "\(sign)\(String(format: "%.1f", avgDrift))p"
        } else {
            driftStr = "unavailable"
        }
        return convictionRow(
            pair: pair,
            tag: stats.statusBadge,
            winRate: ratePct,
            drift: driftStr,
            isEdge: isEdge,
            isWarning: isWarning
        )
    }

    private func convictionRow(pair: String, tag: String, winRate: String, drift: String, isEdge: Bool, isWarning: Bool = false) -> some View {
        let tint = isWarning ? DeskInk.coral : (isEdge ? DeskInk.emerald : DeskInk.slate)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(pair)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Text(winRate)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            }
            HStack(alignment: .top, spacing: 8) {
                Text(tag)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Drift \(drift)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate.opacity(0.8))
            }
        }
        .padding(.vertical, 3)
    }
}
