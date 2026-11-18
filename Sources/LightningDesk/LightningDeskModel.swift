import Combine
import Foundation
import BlazerCore
import BlazerCrypto

private struct FXScanAttempt: Sendable {
    let asset: String
    let snapshot: MarketScanSnapshot?
    let failure: String?
}

enum FXScanScope {
    struct Request: Equatable {
        let asset: String?
        let assets: [String]
    }

    static func request(market: DeskMarket, selectedPair: String,
                        availablePairs: [String], selectedOnly: Bool) -> Request? {
        guard market == .fx else { return nil }
        guard selectedOnly else { return Request(asset: nil, assets: availablePairs) }
        guard availablePairs.contains(selectedPair) else { return nil }
        return Request(asset: selectedPair, assets: [selectedPair])
    }
}

private struct LiveStrategyEvaluation {
    let selection: LiveStrategySelection
    let candidates: [AdaptiveOpportunityCandidate]
    let candidate001Failed: Bool
    let candidate002Failed: Bool
}

#if os(macOS)
public enum MacResearchSignalStatus: Equatable {
    case awaitingFreshScan
    case completedNoCandidate
    case completedWithCandidates
    case conditionsNotMet
    case partialResults
    case failed
    case sourceAttestationUnavailable
}

public struct MacPracticeSizingPreview: Sendable, Equatable {
    public let signalID: String
    public let sourceInputIdentity: String
    public let accountCurrency: String
    public let units: Double
    public let riskBudget: Double
    public let estimatedLoss: Double
    public let estimatedMargin: Double
    public let entryPrice: Double
    public let stopPrice: Double
    public let observedAt: Date
}
#endif

/// Gives each asset an independent, monotonic refresh identity so late async
/// results from an older monitor/scan cannot replace a newer decision.
struct LiveDecisionRefreshGeneration {
    private var counter: UInt64 = 0
    private var latestByAsset: [String: UInt64] = [:]

    mutating func begin(for asset: String) -> UInt64 {
        counter &+= 1
        latestByAsset[asset] = counter
        return counter
    }

    func isCurrent(_ generation: UInt64, for asset: String) -> Bool {
        latestByAsset[asset] == generation
    }

    func latestGeneration(for asset: String) -> UInt64? { latestByAsset[asset] }
}

public enum LiveDecisionAgeLabel {
    public static func text(observedAt: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(observedAt)))
        if seconds < 5 { return "Evaluated just now" }
        if seconds < 60 { return "Evaluated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Evaluated \(minutes)m ago" }
        let hours = minutes / 60
        return "Evaluated \(hours)h ago"
    }
}

/// One-screen desk state. The frame is derived from the frozen commit. Quotes never rescore it.
@MainActor
public final class LightningDeskModel: ObservableObject {
    public convenience init(storageRoot: URL? = nil,
                            liveStrategyProfiles: [StrategyResearchProfile] = StrategyResearchRegistry.profiles,
                            strategyPromotionRecords: [StrategyPromotionRecord] = StrategyResearchRegistry.productionPromotionRecords,
                            macResearchSourceAttestationVerified: Bool = false) {
        self.init(storageRoot: storageRoot, marketData: LiveDeskMarketDataService(),
                  liveStrategyProfiles: liveStrategyProfiles,
                  strategyPromotionRecords: strategyPromotionRecords,
                  macResearchSourceAttestationVerified: macResearchSourceAttestationVerified)
    }

    init(
        storageRoot: URL?,
        marketData: any DeskMarketDataServing,
        candleCache: CandleCache = CandleCache(),
        otcArchive: (any DeskOTCResearchServing)? = nil,
        otcResearchServiceFactory: (@Sendable (String) -> any DeskOTCResearchServing)? = nil,
        pocketOptionResearchServiceFactory: (@Sendable (String) -> any DeskOTCResearchServing)? = nil,
        liveStrategyProfiles: [StrategyResearchProfile] = StrategyResearchRegistry.profiles,
        strategyPromotionRecords: [StrategyPromotionRecord] = StrategyResearchRegistry.productionPromotionRecords,
        macResearchSourceAttestationVerified: Bool = false
    ) {
        if storageRoot == nil {
            #if DEBUG && targetEnvironment(simulator)
            let isReviewInsightUITest = ProcessInfo.processInfo.arguments
                .contains("--ui-testing-review-insight")
            #else
            let isReviewInsightUITest = false
            #endif
            if !isReviewInsightUITest {
                FileLocations.migrateLegacyGroupStorageIfNeeded()
            }
        }
        let root = storageRoot ?? FileLocations.applicationSupport()
        liveDecisionStoreRoot = root.appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent("live-oanda", isDirectory: true)
        self.marketData = marketData
        self.candleCache = candleCache
        self.liveStrategyProfiles = liveStrategyProfiles
        self.strategyPromotionRecords = strategyPromotionRecords
        self.macResearchSourceAttestationVerified = macResearchSourceAttestationVerified
        let otcRoot = root.appendingPathComponent("Research", isDirectory: true)
            .appendingPathComponent("otc-validation", isDirectory: true)
        self.otcArchive = otcArchive ?? LiveOTCResearchService(root: otcRoot)
        self.otcResearchServiceFactory = otcResearchServiceFactory
            ?? LiveOTCResearchService.streamingFactory(root: otcRoot)
        self.pocketOptionResearchServiceFactory = pocketOptionResearchServiceFactory
            ?? LiveOTCResearchService.pocketOptionStreamingFactory(root: otcRoot)
        persistence = PersistenceCoordinator(root: root)
        referenceStore = ReferenceOutcomeStore(
            root: root.appendingPathComponent("Research", isDirectory: true)
                .appendingPathComponent("oanda-proxy", isDirectory: true)
        )
        executionObservationStore = ExecutionObservationStore(
            root: root.appendingPathComponent("Research", isDirectory: true)
                .appendingPathComponent("execution-quality", isDirectory: true))
        strikeStore = StrikeStore(url: root.appendingPathComponent("strike_positions.json"))
        let diagnosticsURL = root.appendingPathComponent("model_diagnostics.jsonl")
        assistant = AssistantSession(diagnosticsURL: diagnosticsURL)
        assistant.contextProvider = { [weak self] in
            guard let self else { return .empty }
            return AssistantContextBuilder.make(journal: self.storedJournal, ledgerRows: self.ledgerRows, observations: self.executionObservations)
        }
        #if os(iOS)
        scanCoordinator.onIdle = { [weak self] in
            guard let self, self.backgroundedAt == nil else { return }
            // Pending Siri ingress runs only after the coordinator relinquishes ownership,
            // detached so the consuming scan never awaits the worker that just exited.
            Task { @MainActor [weak self] in
                await self?.consumePendingScanIfReady()
            }
        }
        #endif
    }
    @Published public var pair: String = "EUR/USD"
    @Published var feed: FeedStatus = .connecting
    @Published public private(set) var exchangeClockOffset: ClockOffset?
    @Published public private(set) var exchangeClockDrift: ClockDrift?
    @Published var candles: [Candle] = []
    @Published var candlesLoading = false
    /// True when the chart is showing restored/cache data that has not yet been refreshed.
    @Published var candlesAreStale = false
    @Published var candleIssue: String?
    @Published var scanning = false
    /// Walk label, for example "GBP/USD 2/6". Nil when idle.
    @Published var scanStep: String?
    /// Last full-book read. Display only.
    @Published var book: [BookRow] = Assets.watchlist.map { BookRow(asset: $0, side: "—") }
    @Published var notice: String?
    /// Visible reason the last entry tap was refused. Cleared on the next attempt or scan.
    @Published public private(set) var entryIssue: String?
    @Published public private(set) var frame: DeskFrame?
    /// Latest deterministic ORB state per FX instrument. This is research state and
    /// never replaces the pinned V1 signal or authorizes an entry.
    @Published public private(set) var orbDecisions: [String: ORBDecision] = [:]
    @Published public private(set) var orbPlans: [String: V3TradePlan] = [:]
    @Published public private(set) var orbLifecycleStatuses: [String: ORBLifecycleEvidenceStatus] = [:]
    @Published public private(set) var orbEntryObservationStatuses: [String: (planID: String, status: String)] = [:]
    @Published public private(set) var liveStrategyDecisions: [String: LiveStrategyDecision] = [:]
    /// Ephemeral, non-actionable shadow results from the latest successful Live FX
    /// strategy evaluation. This is deliberately not stored in ResearchStore.
    @Published public private(set) var liveStrategyResearchObservations: [LiveStrategyResearchObservation] = []
#if os(macOS)
    @Published public private(set) var macResearchSignals: [MacResearchSignal] = []
    @Published public private(set) var macResearchEvaluationDiagnostics: [MacResearchEvaluationDiagnostic] = []
    @Published public private(set) var macResearchSignalStatus: MacResearchSignalStatus = .awaitingFreshScan
    @Published public private(set) var isGBPJPYPracticeMonitoring = false
    @Published public private(set) var practiceSizingPreview: MacPracticeSizingPreview?
    @Published public private(set) var practiceSizingMessage: String?
    private var macResearchExpiryTask: Task<Void, Never>?
    private var gbpJPYPracticeMonitorTask: Task<Void, Never>?
#endif
    private let macResearchSourceAttestationVerified: Bool
    /// Latest adaptive research decision projected for native presentation.
    /// This is intentionally separate from the executable desk frame.
    @Published public private(set) var adaptiveResearchProjection: AdaptiveResearchProjection?
    /// Active 60-second binary trade execution. Nil when not in an active position.
    @Published public private(set) var activeTrade: ActiveTrade?
    /// Predicted outcome based on live price at trade expiry.
    @Published public private(set) var predictedOutcome: DeskOutcome?
    /// Short-lived confirmation shown after a settlement write. Cleared automatically.
    @Published public private(set) var settleReceipt: SettleReceipt?
    private var receiptDismissTask: Task<Void, Never>?
    /// Live mid quote for the selected pair. An entry on another pair never leaks in.
    public var currentPrice: Double? {
        if let trade = activeTrade, trade.pair == pair { return trade.currentPrice }
        if let quote, quote.asset == pair { return quote.mid }
        return nil
    }
    /// Last bid/ask quote for the selected pair, exposed for the desktop market header.
    public var currentFXQuote: LiveQuote? {
        guard let quote, quote.asset == pair else { return nil }
        return quote
    }
    public func orbDecision(for asset: String) -> ORBDecision? { orbDecisions[asset] }
    public func orbPlan(for asset: String) -> V3TradePlan? { orbPlans[asset] }
    public func orbLifecycleStatus(for asset: String) -> ORBLifecycleEvidenceStatus {
        orbLifecycleStatuses[asset] ?? .notAttempted
    }
    public func orbEntryObservationStatus(for asset: String) -> String? {
        guard let plan = orbPlans[asset], let state = orbEntryObservationStatuses[asset],
              state.planID == plan.id else { return nil }
        return state.status
    }

    static func safeQuoteTimestampMilliseconds(_ value: Double) -> Int64? {
        guard value.isFinite, value > 0, value < Double(Int64.max) else { return nil }
        return Int64(value)
    }

    static func isLiveEntryAppendEligible(isCurrent: Bool, selectedPair: String, asset: String,
                                          marketMode: DeskMarket, scanning: Bool,
                                          environment: OandaEnvironment?) -> Bool {
        isCurrent && selectedPair == asset && marketMode == .fx && !scanning && environment == .live
    }

    /// Loads the current user-reported V3 position for one exact plan. This is
    /// research evidence only and is intentionally separate from `activeTrade`.
    public func userReportedPosition(forPlanID planID: String) async throws -> V3PositionRecord? {
        let records = try await liveDecisionStore.v3PositionRecords()
        var related = records.filter {
            $0.planID == planID && $0.state == .userReported
                && $0.provenance == .manualTradeReport
        }
        if related.contains(where: { $0.positionID == nil }) {
            throw V3UserPositionReportError.legacyReportRequiresReview
        }
        related = related.filter { $0.positionID != nil }
        let supersededIDs = Set(related.compactMap(\.supersedesRecordID))
        return related.first { !supersededIDs.contains($0.id) }
    }

    public func terminalLifecycleSourceTime(forPlanID planID: String) async throws -> Date? {
        let events = try await liveDecisionStore.v3SetupLifecycleEvents()
        guard let confirmed = events.first(where: { $0.planID == planID }) else { return nil }
        return events.filter {
            $0.setupID == confirmed.setupID && [.invalidated, .setupExpired].contains($0.state)
        }.compactMap(\.sourceTime).max()
    }

    /// Persists an explicit user statement about a position already opened outside
    /// BlazerOS. It never changes the ORB plan/lifecycle or the legacy binary trade.
    @discardableResult
    public func recordUserReportedPosition(planID: String, units: Double,
                                           entryPrice: Double? = nil,
                                           enteredAt: Date? = nil,
                                           supersedesRecordID: String? = nil) async throws
        -> V3PositionRecord {
        try await liveDecisionStore.recordUserReportedPosition(planID: planID, units: units,
            entryPrice: entryPrice, userReportedEnteredAt: enteredAt,
            updatedAt: Date(), supersedesRecordID: supersedesRecordID)
    }

    public func userReportedPositionCloses(forPlanID planID: String) async throws
        -> [V3UserReportedPositionClose] {
        try await liveDecisionStore.v3UserReportedPositionCloses().filter { $0.planID == planID }
    }

    public func userReportedPositionRevision(positionID: String, recordID: String) async throws
        -> V3PositionRecord? {
        try await liveDecisionStore.v3PositionRecords().first {
            $0.positionID == positionID && $0.id == recordID
        }
    }

    @discardableResult
    public func recordUserReportedPositionClose(positionID: String, closedAt: Date?,
                                                 exitPrice: Double?, supersedesCloseID: String? = nil) async throws
        -> V3UserReportedPositionClose {
        try await liveDecisionStore.recordUserReportedPositionClose(positionID: positionID,
            closedAt: closedAt, exitPrice: exitPrice, supersedesCloseID: supersedesCloseID)
    }
    public func strategyDecision(for asset: String) -> LiveStrategyDecision? { liveStrategyDecisions[asset] }
    public func strategyResearchObservations(for asset: String) -> [LiveStrategyResearchObservation] {
        guard marketMode == .fx, pair == asset else { return [] }
        return liveStrategyResearchObservations
    }
    public var lastScanAt: Date? { commit?.scannedAt }
    public var connectedOandaEnvironment: OandaEnvironment? { session?.environment }
    /// Last successful market observation for the selected desk feed. Display-only.
    public var lastMarketObservationAt: Date? { lastFreshPollAt }
    /// Brand cover. Dismisses on a real LIVE feed, otherwise after a short beat. Never invents LIVE.
    @Published public var showingLaunch = true
    @Published var launchMarkLit = false
    @Published var launchWordLit = false
    /// Brief upward offset after a commit. Display only.
    @Published var heroLift: Double = 0
    @Published public var activeTab: DeskTab = .desk
    /// Which market the Scan button walks. Crypto is the primary mode.
    /// The visible watchlist is derived from `pairs`; `book` sides reset on the next scan.
    /// Never mutate other @Published state here — publishing from inside a SwiftUI view
    /// update crashes the app.
    @Published public var marketMode: DeskMarket = .fx {
        didSet {
#if os(macOS)
            if marketMode != oldValue { clearLiveStrategyResearchObservations() }
#endif
        }
    }
    /// True while the offline fixture is being shown. It suppresses the missing-credential cover
    /// without pretending a live Keychain session exists.
    @Published public private(set) var isDemoDesk = false
    @Published var showingCredentials = false
    /// Frozen scans. Newest first. Display only; quotes never rewrite the score.
    @Published private(set) var journal: [ReplayEntry] = []
    /// Durable journal records. The display model above drops engine metadata; the assistant
    /// must read these original records.
    private var storedJournal: [JournalEntry] = []
    @Published var showingJournal = false
    @Published var openReplayID: String?
    /// Explanation of the open replay. Built from the seal, not from a live quote.
    @Published private(set) var coachExplanation: CoachExplanation?
    /// HIT and MISS are offered only after the beam expires.
    @Published private(set) var awaitingOutcome = false
    /// Reads that failed at launch. Surfaced, never treated as empty history.
    @Published public private(set) var restoreIssues: [RestoreIssue] = []
    /// Outcomes observed but not yet durably written.
    @Published public private(set) var pendingSaveCount: Int = 0
    @Published private(set) var outcomeStats = OutcomeStats.empty
    @Published public private(set) var ledgerRows: [LedgerRow] = []
    /// OANDA midpoint observations recorded at expiry. Reference only; never counted as
    /// venue-confirmed performance and never written to the trading ledger.
    @Published public private(set) var referenceOutcomes: [ResearchOutcome] = []
    /// Keychain presence only. A saved token is not kept here.
    @Published private(set) var keychainState: KeychainState = .unknown
    /// Form drafts. Cleared when the Keychain write succeeds. Never synced.
    @Published var draftToken = ""
    @Published var draftAccount = ""
    @Published var draftEnvironment: OandaEnvironment = .practice
    @Published var isEditingCredentials = false
    @Published var credentialSaveFailed = false
    @Published var credentialConfigurationError: String?
    /// Voice coach session for the open replay. One active session at a time.
    @Published var voiceSession = VoiceSession()

    // MARK: - On-device assistant (explanations only; never execution authority)
    //
    // State and operations live in `AssistantSession`. This model keeps a reference so the
    // desk can offer optional explanations without owning assistant state.

    public let assistant: AssistantSession

    /// Whether spoken audio debriefing plays when a 60s binary position expires.
    @Published public var voiceDebriefEnabled: Bool = UserDefaults.standard.object(forKey: "blazer.voice_debrief_enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(voiceDebriefEnabled, forKey: "blazer.voice_debrief_enabled")
        }
    }
    /// Count of low-edge/chop traps actively avoided during session.
    @Published public private(set) var trapsAvoidedCount: Int = 0

    /// Currently selected binary expiry duration (60s, 180s = 3m, 300s = 5m). Default is 60s.
    @Published public var selectedHorizonSec: Double = 60.0

    // MARK: - AI Copilot (advisory only)
    //
    // Optional, asynchronous, NON-AUTHORITATIVE. It never gates a trade, never produces numbers
    // (those come from StrikeMath), and its failure changes nothing about scanning or tracking.

    /// Advisory copilot output for the current candidate contract. Never authoritative.
    @Published public private(set) var strikeAdvice: StrikeAuditAdvice?
    @Published public private(set) var isAuditingStrike = false
    /// Non-nil when the copilot was unavailable. The desk stays fully functional either way.
    @Published public private(set) var strikeAdviceIssue: String?

    public var copilotProvider: AIProvider = .deepseek
    public var copilotVault: KeychainVault = SystemKeychainVault()
    private let strikeAuditor = LLMStrikeAuditor()

    /// Fire an advisory audit. Returns immediately; scan, the 8s beam, and tracking are untouched.
    public func requestStrikeAudit(_ request: StrikeAuditRequest) {
        guard !isAuditingStrike else { return }
        let provider = copilotProvider
        let storedKey: String?
        do {
            storedKey = try copilotVault.get(provider.keychainKeyName)
        } catch {
            strikeAdviceIssue = "Copilot key unavailable"
            return
        }
        guard let apiKey = storedKey, !apiKey.isEmpty else {
            strikeAdviceIssue = "No copilot API key configured"
            return
        }
        isAuditingStrike = true
        strikeAdviceIssue = nil
        Task {
            do {
                let advice = try await strikeAuditor.audit(
                    request: request, provider: provider, apiKey: apiKey
                )
                self.strikeAdvice = advice
            } catch {
                // Fail closed to deterministic-only mode. Never fabricate advice.
                self.strikeAdviceIssue = "Copilot unavailable — showing local analysis only"
            }
            self.isAuditingStrike = false
        }
    }

    public func clearStrikeAdvice() {
        strikeAdvice = nil
        strikeAdviceIssue = nil
    }

    /// Convenience: build the deterministic assessment + audit request from raw inputs, using the
    /// desk's current reference price. All numbers come from `StrikeMath`, never the model.
    public func requestStrikeAudit(
        symbol: String,
        strike: Double,
        entryPrice: Decimal,
        secondsRemaining: Int,
        side: StrikeSide,
        direction: String,
        score: Int,
        spec: StrikeContractSpec = .currentCrypto
    ) {
        guard let spot = currentPrice else {
            strikeAdviceIssue = "No live reference price"
            return
        }
        let assessment = StrikeAssessment.evaluate(
            spot: spot, strike: strike, entryPrice: entryPrice,
            secondsRemaining: secondsRemaining, spec: spec
        )
        let request = StrikeAuditRequest.make(
            symbol: symbol, assessment: assessment, spot: spot, strike: strike,
            entryPrice: entryPrice, secondsRemaining: secondsRemaining,
            momentumDirection: direction, momentumScore: score, side: side, spec: spec
        )
        requestStrikeAudit(request)
    }

    // MARK: - App lifecycle (foreground resume)

    private var backgroundedAt: Date?
#if DEBUG
    public private(set) var liveStrategyNotificationScheduleAttemptsForTesting = 0
#endif

    private func noteLiveStrategyNotificationScheduleAttempt() {
        #if DEBUG
        liveStrategyNotificationScheduleAttemptsForTesting += 1
        #endif
    }

    private func clearLiveStrategyResearchObservations() {
        liveStrategyResearchObservations = []
#if os(macOS)
        macResearchExpiryTask?.cancel()
        macResearchExpiryTask = nil
        macResearchSignals = []
        macResearchEvaluationDiagnostics = []
        macResearchSignalStatus = .awaitingFreshScan
#endif
    }
    /// Increments each time the app returns to the foreground. Telemetry only.
    @Published public private(set) var foregroundResumeCount = 0

    public func handleAppBackgrounded(now: Date = Date()) {
        backgroundedAt = now
        clearLiveStrategyResearchObservations()
        invalidateScanRequests()
        // A research stream does not survive suspension; stop it explicitly instead of
        // reconnecting invisibly when the app resumes.
        if otcCaptureActive { stopOTCResearchCapture() }
        // Switching to the venue app suspends live refresh. An actionable beam must not
        // become actionable again after the phone resumes without a new frozen scan.
        if armedAt != nil, activeTrade == nil {
            self.now = now
            armedAt = nil
            expired = true
            feed = .stale
            publishFrame()
        }
    }

    /// Resume after the user returns (e.g., from the Crypto.com app). Never blocks.
    public func handleAppForegrounded(now: Date = Date()) {
        let suspendedMs = backgroundedAt.map { max(0, now.timeIntervalSince($0) * 1000) } ?? 0
        let decision = ForegroundResume.decide(
            suspendedForMs: suspendedMs,
            lastPollAgeMs: lastFreshPollAt.map { max(0, now.timeIntervalSince($0) * 1000) },
            clockSampleAgeMs: exchangeClockOffset.map {
                max(0, now.timeIntervalSince($0.measuredAt) * 1000)
            }
        )
        backgroundedAt = nil
        foregroundResumeCount += 1
        if decision.treatFeedAsDisconnected {
            feed = .connecting
        }
        refreshTrackedStrikePositions()
        if marketMode == .crypto, decision.needsClockRemeasure {
            Task { await remeasureExchangeClock() }
        }
        Task {
            await refreshActiveTradeQuote()
            await refreshQuote()
            // A Siri request can arrive while a session is already loaded. Consume it here
            // instead of waiting for the next Keychain read.
            await consumePendingScanIfReady()
        }
    }

    private func remeasureExchangeClock() async {
        do {
            let offset = try await BinanceClient.fetchClockOffset()
            exchangeClockOffset = offset
            exchangeClockDrift = ExchangeClock.drift(of: offset)
            diagLog("EXCHANGE_CLOCK source=\(offset.source) skewMs=\(Int(offset.skewMs)) rttMs=\(Int(offset.roundTripMs))")
        } catch {
            exchangeClockDrift = nil
            diagLog("EXCHANGE_CLOCK_FAILED \(error)")
        }
    }

    // MARK: - Local strike tracking (external contracts)
    //
    // Records a fill the trader placed in Crypto.com. Local accounting only; no order is placed.
    private let strikeStore: StrikeStore
    @Published public private(set) var trackedStrikePositions: [StrikePosition] = []

    public func trackStrikeContract(
        symbol: String,
        side: StrikeSide,
        strike: Double,
        expiry: Date,
        entryPrice: Decimal,
        quantity: Int,
        spec: StrikeContractSpec = .currentCrypto
    ) {
        guard quantity > 0 else { notice = "Contracts must be at least 1"; return }
        let position = StrikePosition(
            id: UUID().uuidString, symbol: symbol, side: side, strike: strike,
            predicate: .aboveStrict, spec: spec, expiry: expiry
        )
        let event = StrikeEvent(
            id: UUID().uuidString, positionID: position.id,
            kind: .open(
                quantity: quantity,
                pricePerContract: entryPrice,
                fee: spec.totalEntryFee * Decimal(quantity),
                at: Date()
            )
        )
        Task {
            do {
                _ = try await strikeStore.create(position, opening: event)
                trackedStrikePositions = await strikeStore.all()
                notice = "Tracked locally — place the order in Crypto.com."
            } catch {
                notice = "Could not record trade locally."
            }
        }
    }

    public func refreshTrackedStrikePositions() {
        Task { trackedStrikePositions = await strikeStore.all() }
    }

    /// Record a settled outcome (user-reported by default; verified is a separate provenance).
    public func settleStrikePosition(
        id: String,
        result: StrikeResult,
        provenance: StrikeOutcomeProvenance = .userReported
    ) {
        let event = StrikeEvent(
            id: UUID().uuidString, positionID: id,
            kind: .settle(result: result, provenance: provenance, at: Date())
        )
        Task {
            do {
                _ = try await strikeStore.apply(event)
                trackedStrikePositions = await strikeStore.all()
            } catch {
                notice = "Could not record settlement."
            }
        }
    }

    /// Record an early exit (partial or full). Only ever reduces owned quantity.
    public func exitStrikePosition(id: String, quantity: Int, pricePerContract: Decimal?) {
        guard quantity > 0 else { notice = "Exit quantity must be at least 1"; return }
        let event = StrikeEvent(
            id: UUID().uuidString, positionID: id,
            kind: .exit(quantity: quantity, pricePerContract: pricePerContract, at: Date())
        )
        Task {
            do {
                _ = try await strikeStore.apply(event)
                trackedStrikePositions = await strikeStore.all()
            } catch {
                notice = "Could not record exit."
            }
        }
    }

    /// The current leader across all scanned pairs based on two-way conviction and score.
    public var radarLeader: (asset: String, score: Int, conviction: Int, side: String)? {
        var topAsset: String?
        var topScore: Int = -1
        var topConviction: Int = -1
        var topSide: String = "WAIT"

        for p in pairs {
            if let commit = commitsByAsset[p] {
                let score = commit.score
                let side = cabinetSideByAsset[p] ?? "WAIT"
                let conviction = score
                let isActionable = side == "HIGH" || side == "LOW"
                let currentIsActionable = topSide == "HIGH" || topSide == "LOW"

                if (isActionable && !currentIsActionable) || (isActionable == currentIsActionable && conviction > topConviction) {
                    topConviction = conviction
                    topScore = score
                    topAsset = p
                    topSide = side
                }
            }
        }
        guard let topAsset, topConviction >= 0 else { return nil }
        return (topAsset, topScore, topConviction, topSide)
    }

    /// Evaluates rich stalking telemetry for the currently selected pair.
    public var stalkingTelemetry: StalkingTelemetry {
        guard let commit else {
            return StalkingTelemetry.evaluate(
                asset: pair,
                score: 0,
                side: "WAIT",
                evidence: "Awaiting scan",
                veto: nil
            )
        }
        return StalkingTelemetry.evaluate(
            asset: pair,
            score: commit.score,
            side: cabinetSide,
            evidence: commit.evidence,
            veto: commit.veto
        )
    }

    private let persistence: PersistenceCoordinator
    private let executionObservationStore: ExecutionObservationStore
    @Published public private(set) var executionObservations: [ExecutionObservation] = []
    @Published public private(set) var executionObservationIssue: String?
    @Published public private(set) var edgeVerificationReport: EdgeVerificationReport?
    private func refreshExecutionIntelligence() {
        do {
            edgeVerificationReport = try ExecutionIntelligence.report(rows: ledgerRows, journal: storedJournal,
                observations: executionObservations, references: referenceOutcomes, asOf: Date())
        } catch { executionObservationIssue = "Evidence report unavailable: \(error.localizedDescription)" }
    }
    private func saveExecutionObservation(_ observation: ExecutionObservation) async {
        do {
            try await executionObservationStore.record(observation)
            executionObservations = try await executionObservationStore.load()
            refreshExecutionIntelligence()
        } catch { executionObservationIssue = "Execution-quality archive unavailable: \(error.localizedDescription)" }
    }

    // MARK: - Personal OTC research (never an execution input)

    /// OTC networking, streaming and validation live behind this research-only service.
    private let otcArchive: any DeskOTCResearchServing
    /// Creates a credential-scoped streaming service. Injectable for tests.
    private let otcResearchServiceFactory: @Sendable (String) -> any DeskOTCResearchServing
    private let pocketOptionResearchServiceFactory: @Sendable (String) -> any DeskOTCResearchServing
    private var otcActiveService: (any DeskOTCResearchServing)?
    private var otcActiveStream: OTCResearchStream?
    public var otcCredentialVault: KeychainVault = SystemKeychainVault(service: "com.blazer.os.otc-research")
    @Published public private(set) var otcAPIKeyConfigured = false
    @Published public private(set) var pocketOptionSessionConfigured = false
    @Published public private(set) var otcConnectionState: ShadowConnectionState = .disabled
    @Published public private(set) var manualBrokerObservations: [ManualBrokerChartObservation] = []
    @Published public private(set) var otcResearchIssue: String?
    /// Research capture session state. Never consulted by the entry gate.
    @Published public private(set) var otcCaptureActive = false
    /// Persisted, rate-limited research samples (at most one per second).
    @Published public private(set) var otcCapturedObservations = 0
    /// Raw ticks observed in this session, refreshed at 1 Hz to avoid per-tick UI churn.
    @Published public private(set) var otcObservedTicks = 0
    @Published public private(set) var otcObservedTickRate: Double?
    /// Local receipt minus normalized provider time. A large value indicates a clock-model drift.
    @Published public private(set) var otcClockSkewSeconds: Double?
    @Published public private(set) var otcConnectionInterruptions = 0
    @Published public private(set) var otcValidationReport: OTCValidationReport?
    private var otcCaptureTask: Task<Void, Never>?
    private var otcCaptureWatchdog: Task<Void, Never>?
    private var otcCaptureRunID: UUID?
    private var otcTicksThisCapture = 0
    private var otcFirstTickAt: Date?
    private var otcLastTickPublishAt: Date?
    private var otcLastPersistAt: Date?

    public func refreshOTCCredentialState() {
        do {
            otcAPIKeyConfigured = try otcCredentialVault.get(KeychainKey.otchartsAPIKey)?.isEmpty == false
            pocketOptionSessionConfigured = try otcCredentialVault
                .get(KeychainKey.pocketOptionReadOnlySession)?.isEmpty == false
            // A scan-triggered reload must not erase a live capture failure message.
            if !otcCaptureActive { otcResearchIssue = nil }
        } catch {
            otcAPIKeyConfigured = false
            pocketOptionSessionConfigured = false
            otcResearchIssue = "OTC provider credential is unavailable"
        }
        // Configuration presence never enables a network connection automatically, and a
        // credential re-read must not overwrite the state of a running capture.
        if !otcCaptureActive { otcConnectionState = .disabled }
    }

    public func saveOTChartsAPIKey(_ candidate: String) {
        let key = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            otcResearchIssue = "Enter an OTCharts API key"
            return
        }
        do {
            try otcCredentialVault.set(key, for: KeychainKey.otchartsAPIKey)
            otcAPIKeyConfigured = true
            if !otcCaptureActive { otcConnectionState = .disabled }
            otcResearchIssue = nil
        } catch {
            otcResearchIssue = "OTC provider key could not be saved"
        }
    }

    public func savePocketOptionReadOnlySession(_ candidate: String) {
        let frame = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PocketOptionReadOnlyProvider.isValidAuthFrame(frame) else {
            otcResearchIssue = "Enter a complete Pocket Option demo auth frame"
            return
        }
        do {
            try otcCredentialVault.set(frame, for: KeychainKey.pocketOptionReadOnlySession)
            pocketOptionSessionConfigured = true
            if !otcCaptureActive { otcConnectionState = .disabled }
            otcResearchIssue = nil
        } catch {
            otcResearchIssue = "Pocket Option session could not be saved"
        }
    }

    public func disconnectAndRemoveOTChartsAPIKey() {
        // Stop the session before touching Keychain so the UI cannot claim connectivity while
        // the credential is being removed.
        stopOTCResearchCapture()
        do {
            try otcCredentialVault.remove(KeychainKey.otchartsAPIKey)
            otcAPIKeyConfigured = false
            otcResearchIssue = nil
        } catch {
            otcAPIKeyConfigured = false
            otcResearchIssue = "OTC provider key removal could not be confirmed"
        }
    }

    public func disconnectAndRemovePocketOptionSession() {
        stopOTCResearchCapture()
        do {
            try otcCredentialVault.remove(KeychainKey.pocketOptionReadOnlySession)
            pocketOptionSessionConfigured = false
            otcResearchIssue = nil
        } catch {
            // Deletion was not confirmed, so the unrestricted session may still be present.
            pocketOptionSessionConfigured = true
            otcResearchIssue = "Pocket Option session removal could not be confirmed"
        }
    }

    /// Starts one explicitly requested, time-bounded, read-only research capture. It never runs
    /// automatically and it never feeds a scan, an entry, or a settlement.
    public func startOTCResearchCapture(duration: TimeInterval = 300) {
        guard !otcCaptureActive else { return }
        guard duration > 0, duration <= 3_600 else {
            otcResearchIssue = "Research capture duration must be between 1 second and 1 hour"
            return
        }
        let credential: String
        let serviceFactory: @Sendable (String) -> any DeskOTCResearchServing
        do {
            if let session = try otcCredentialVault.get(KeychainKey.pocketOptionReadOnlySession),
               !session.isEmpty {
                credential = session
                serviceFactory = pocketOptionResearchServiceFactory
            } else if let key = try otcCredentialVault.get(KeychainKey.otchartsAPIKey),
                      !key.isEmpty {
                credential = key
                serviceFactory = otcResearchServiceFactory
            } else {
                otcResearchIssue = "Add a Pocket Option read-only session before starting a research capture"
                return
            }
        } catch {
            otcResearchIssue = "OTC provider credential is unavailable"
            return
        }

        let service = serviceFactory(credential)
        let runID = UUID()
        otcActiveService = service
        otcCaptureRunID = runID
        otcCaptureActive = true
        otcCapturedObservations = 0
        otcObservedTicks = 0
        otcObservedTickRate = nil
        otcClockSkewSeconds = nil
        otcConnectionInterruptions = 0
        otcTicksThisCapture = 0
        otcFirstTickAt = nil
        otcLastTickPublishAt = nil
        otcLastPersistAt = nil
        otcConnectionState = .connecting
        otcResearchIssue = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runOTCCapture(service: service, runID: runID)
        }
        otcCaptureTask = task
        // Enforce both the declared bound and broker-tick liveness.
        let startedAt = Date()
        otcCaptureWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.otcCaptureRunID == runID else { return }
                let now = Date()
                if now.timeIntervalSince(self.otcLastTickPublishAt ?? startedAt) > 10 {
                    self.otcConnectionState = .degraded
                    self.otcConnectionInterruptions += 1
                    self.otcResearchIssue = "No fresh OTC provider tick arrived for 10 seconds; capture stopped"
                    task.cancel()
                    return
                }
                if now.timeIntervalSince(startedAt) >= duration {
                    task.cancel()
                    return
                }
            }
        }
    }

    /// Immediate stop. Already-persisted research samples stay on disk.
    public func stopOTCResearchCapture() {
        otcCaptureTask?.cancel()
        otcCaptureWatchdog?.cancel()
        otcCaptureTask = nil
        otcCaptureWatchdog = nil
        otcCaptureRunID = nil
        otcActiveService = nil
        otcActiveStream?.cancel()
        otcActiveStream = nil
        otcCaptureActive = false
        otcConnectionState = .disabled
    }

    private func runOTCCapture(service: any DeskOTCResearchServing, runID: UUID) async {
        defer { finishOTCCapture(runID: runID) }
        guard !Task.isCancelled, otcCaptureRunID == runID else { return }
        do {
            let identity = service.researchIdentity
            let instruments = try await service.instruments()
            guard !Task.isCancelled, otcCaptureRunID == runID else { return }
            guard let availability = instruments.first(where: {
                $0.identity == identity
            }) else {
                otcResearchIssue = "The provider did not list EUR/USD OTC; capture stopped"
                otcConnectionState = .degraded
                return
            }
            guard availability.isOpen != false else {
                otcResearchIssue = "EUR/USD OTC is closed according to the provider; capture stopped"
                otcConnectionState = .degraded
                return
            }
            let stream = try await service.updates(for: identity)
            guard !Task.isCancelled, otcCaptureRunID == runID else {
                stream.cancel()
                return
            }
            otcActiveStream = stream
            for try await update in stream.events {
                if Task.isCancelled { break }
                switch update {
                case .connection(let state, _):
                    if otcConnectionState != state {
                        if state == .disconnected || state == .degraded {
                            otcConnectionInterruptions += 1
                        }
                        otcConnectionState = state
                    }
                case .observation(let observation):
                    if otcConnectionState != .live { otcConnectionState = .live }
                    await recordOTCResearchObservation(
                        observation, runID: runID, service: service)
                }
            }
            // A clean end before the declared bound is an incomplete session, not a success.
            if !Task.isCancelled, otcCaptureRunID == runID {
                otcResearchIssue = "Provider stream ended before the capture bound; session incomplete"
            }
        } catch {
            // A user stop or the watchdog is not a provider fault. Never surface raw remote text.
            if !Task.isCancelled {
                diagLog("OTC_CAPTURE_FAILED")
                otcResearchIssue = otcFailureMessage(error)
                otcConnectionState = .degraded
            }
        }
    }

    /// A provider refusal is not a closed market. Keep the two states separate so the desk
    /// never tells the operator Pocket Option is closed when only the data plan is unavailable.
    private func otcFailureMessage(_ error: Error) -> String {
        if let failure = error as? PocketOptionReadOnlyError {
            switch failure {
            case .disabled, .invalidCredential, .authenticationRejected:
                return "The Pocket Option demo session is missing, expired, or rejected. Replace it in Keychain."
            case .wrongInstrument:
                return "Pocket Option returned the wrong instrument; capture was stopped."
            case .staleOrOutOfOrder:
                return "Pocket Option returned a stale, future, or out-of-order tick; capture was stopped."
            case .connectionClosed:
                return "The Pocket Option read-only stream disconnected before the capture completed."
            default:
                return "Pocket Option read-only capture ended; no data became actionable."
            }
        }
        guard let failure = error as? OTChartsError else {
            return "OTC research capture ended (provider or network failure); the market state is unknown"
        }
        switch failure {
        case .httpStatus(402):
            return "OTCharts free API tier is paused; a paid data plan is required. Pocket Option is not reported as closed."
        case .httpStatus(403):
            return "The OTCharts plan does not open this book or instrument."
        case .httpStatus(429):
            return "OTCharts request or stream limit reached; retry later."
        case .throttled:
            return "OTCharts throttled the request; retry later."
        case .disabled, .invalidCredential:
            return "The OTCharts key is missing or no longer valid."
        case .providerClosed(let reason):
            return "Provider closed the stream: \(reason)"
        default:
            return "OTC research capture ended (provider or network failure); the market state is unknown"
        }
    }

    private func finishOTCCapture(runID: UUID) {
        guard otcCaptureRunID == runID else { return }
        otcCaptureTask = nil
        otcCaptureWatchdog?.cancel()
        otcCaptureWatchdog = nil
        otcCaptureRunID = nil
        otcActiveService = nil
        otcActiveStream?.cancel()
        otcActiveStream = nil
        otcCaptureActive = false
        otcConnectionState = .disabled
        Task { await refreshOTCValidationReport() }
    }

    private func recordOTCResearchObservation(_ observation: ShadowMarketObservation,
                                              runID: UUID,
                                              service: any DeskOTCResearchServing) async {
        guard otcCaptureRunID == runID else { return }
        guard observation.identity == service.researchIdentity else {
            otcResearchIssue = "Provider returned an observation for a different instrument"
            return
        }
        guard observation.isValid, observation.verification != .syntheticTestFixture else {
            otcResearchIssue = "Provider returned an invalid research observation"
            return
        }
        let now = Date()
        otcTicksThisCapture += 1
        if otcFirstTickAt == nil { otcFirstTickAt = now }
        // Refresh tick and clock telemetry at most once per second, never per tick.
        if otcLastTickPublishAt.map({ now.timeIntervalSince($0) >= 1 }) ?? true {
            otcObservedTicks = otcTicksThisCapture
            if let first = otcFirstTickAt {
                let elapsed = now.timeIntervalSince(first)
                otcObservedTickRate = elapsed > 0
                    ? Double(max(0, otcTicksThisCapture - 1)) / elapsed : nil
            }
            // A systematic offset means the documented UTC+2 correction may not match the
            // provider's current epoch (for example a DST shift). Surface it, never hide it.
            let clockSkew = now.timeIntervalSince(observation.providerTimestamp.normalized)
            otcClockSkewSeconds = clockSkew
            if abs(clockSkew) > 120, otcResearchIssue == nil {
                otcResearchIssue = "Provider clock offset is \(Int(clockSkew))s from the documented normalization"
            }
            otcLastTickPublishAt = now
        }
        // Persist at most one sample per second so a dense stream cannot flood the archive or
        // the main actor. The 60-second bucket report does not need every tick.
        if let last = otcLastPersistAt, now.timeIntervalSince(last) < 1 { return }
        let reference: ShadowMarketObservation?
        if marketMode == .fx, FxSession.isOpen(now), let quote {
            reference = service.standardReference(from: quote, at: now)
        } else {
            reference = nil
        }
        do {
            try await service.record(otc: observation, standard: reference, capturedAt: now)
            guard otcCaptureRunID == runID else { return }
            otcCapturedObservations += 1
            otcLastPersistAt = now
        } catch {
            guard otcCaptureRunID == runID else { return }
            otcResearchIssue = "OTC research sample could not be saved"
        }
    }

    public func refreshOTCValidationReport() async {
        do {
            otcValidationReport = try await otcArchive.report()
        } catch {
            otcResearchIssue = "OTC validation archive unavailable: \(error.localizedDescription)"
        }
    }

    public func recordManualOTCObservation(
        brokerPrice: String,
        providerPrice: String,
        payoutPercent: String,
        screenshotReference: String,
        candleTimestamp: Date? = nil,
        agreement: ManualAgreement,
        confidence: ManualVerificationConfidence
    ) async {
        guard let broker = Double(brokerPrice), broker.isFinite, broker > 0 else {
            otcResearchIssue = "Broker price must be a positive number"
            return
        }
        let provider = providerPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : Double(providerPrice)
        let payout = payoutPercent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : Double(payoutPercent)
        let screenshot = screenshotReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let observation = ManualBrokerChartObservation(
            identity: otcArchive.researchIdentity,
            observedAt: Date(), brokerDisplayedPrice: broker, providerPrice: provider,
            candleTimestamp: candleTimestamp, payoutPercent: payout,
            screenshotReference: screenshot.isEmpty ? nil : screenshot,
            agreement: agreement, confidence: confidence)
        guard observation.isValid else {
            otcResearchIssue = "Manual observation contains an invalid optional value"
            return
        }
        do {
            try await otcArchive.recordManual(observation)
            manualBrokerObservations = try await otcArchive.manualObservations()
            otcResearchIssue = nil
        } catch {
            otcResearchIssue = "Manual OTC observation could not be saved"
        }
    }

    private let referenceStore: ReferenceOutcomeStore
    private var session: OandaSession?
    private var armID: String?
    private var commit: ScanCommit?
    private var cabinetSide = "WAIT"
    private var armedAt: Date?
    /// Armed time of the manual entry currently being tracked. Persisted with the entry.
    private var activeEntryArmedAt: Date?
    private var quote: LiveQuote?
    /// Last quote observed for the active manual entry, independent of the browsing pair.
    private var activeTradeQuote: LiveQuote?
    private var lastFreshPollAt: Date?
    private var now = Date()
    private var expired = false
    private var settlementInFlight = false
    private var selectedSignal: EngineSignal?
    private var pendingExpiry: ResearchOutcome?
    private var entryInFlight = false
    private var pendingTrade: ActiveTrade?
    /// Label source to reuse when a failed settlement is retried.
    private var pendingLabelSource = "manual-unverified"
    private var pendingOutcome: DeskOutcome?
    /// True when the desk is showing a cached scan. A cached scan is history; it never re-arms.
    private var historical = false
    /// Networking, normalization, freshness and caching stay outside the SwiftUI facade.
    private let marketData: any DeskMarketDataServing
    private let liveStrategyProfiles: [StrategyResearchProfile]
    private let strategyPromotionRecords: [StrategyPromotionRecord]
    private let strategyDeliveredNotificationDefaultsKey = "blazer.strategy.deliveredNotificationIDs"
    private let liveDecisionStoreRoot: URL
    /// Monotonic per-instrument generation for Live strategy refreshes. This prevents an
    /// older monitor or detached scan evaluation from winning after a newer attempt starts.
    private var liveDecisionGeneration = LiveDecisionRefreshGeneration()
    private var liveDecisionStore: ResearchStore {
        ResearchStore(root: liveDecisionStoreRoot)
    }
    private let candleCache: CandleCache
    /// One bounded worker serializes scan ingress; only its latest pending request is retained.
    private let scanCoordinator = ScanOperationCoordinator()
    /// Per-asset cache of the last committed scan for that pair.
    private var commitsByAsset: [String: ScanCommit] = [:]
    /// Per-asset cache of the cabinet side for that pair.
    private var cabinetSideByAsset: [String: String] = [:]

    /// Watchlist for the active market mode. Crypto uses the shared BlazerCrypto list.
    public var pairs: [String] {
        marketMode == .crypto ? CTAssets.watchlist : Assets.watchlist
    }

    public func select(pair next: String) {
#if os(macOS)
        guard !isGBPJPYPracticeMonitoring || next == "GBP/JPY" else {
            notice = "Stop the GBP/JPY Practice monitor before switching pairs"
            return
        }
#endif
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else {
            notice = "Resolve the current outcome before switching pairs"
            return
        }
        guard next != pair else { return }
        let previousPair = pair
        clearLiveStrategyResearchObservations()
        for asset in [previousPair, next] where liveStrategyDecisions[asset]?.action != .wait
            && liveStrategyDecisions[asset] != nil {
            let generation = beginLiveDecisionRefresh(for: asset)
            Task { [weak self] in
                await self?.withdrawLiveStrategyDecision(for: asset,
                    reason: "live_instrument_not_currently_monitored", generation: generation)
            }
        }
        invalidateScanRequests()
        pair = next

        // Restore cached bars immediately so chart is never blank
        let cacheKey = CandleCache.Key(market: marketMode, asset: next)
        let cached = candleCache.cached(cacheKey)
        candlesLoading = false
        candleIssue = nil
        if !cached.isEmpty {
            candles = cached
            candlesAreStale = !candleCache.isFresh(cacheKey)
            if !candleCache.isFresh(cacheKey) {
                Task { await loadCandles(for: next, force: true) }
            }
        } else {
            candles = []
            candlesAreStale = false
            Task { await loadCandles(for: next) }
        }

        if let cachedCommit = commitsByAsset[next] {
            commit = cachedCommit
            cabinetSide = cabinetSideByAsset[next] ?? "WAIT"
            // A cached scan is history. It must never look like a fresh armed beam.
            historical = true
            expired = false
            armedAt = nil
            publishFrame()
        } else {
            commit = nil
            cabinetSide = "WAIT"
            historical = false
            armedAt = nil
            expired = false
            publishFrame()
        }

        quote = nil
        notice = nil
        awaitingOutcome = false
        armID = nil
    }

    public func selectAndNavigate(pair next: String) {
        select(pair: next)
        activeTab = .desk
    }

    /// Notification taps are navigation hints only. The current desk must revalidate
    /// quote freshness and setup state before any plan can be considered actionable.
    public func handleORBDeepLink(_ link: String) {
        guard let components = URLComponents(string: link), components.scheme == "blazer",
              components.host == "trade",
              components.queryItems?.first(where: { $0.name == "strategy" })?.value == "ORB_BREAK_RETEST_V1",
              let instrument = components.queryItems?.first(where: { $0.name == "instrument" })?.value,
              pairs.contains(instrument) else { return }
        selectAndNavigate(pair: instrument)
        notice = "ORB alert opened. Revalidate current OANDA evidence before recording any practice entry."
    }

    /// Populates the desk with sample market candles from the golden fixture for offline testing.
    public func loadDemoDesk() {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else { return }
        invalidateScanRequests()
        selectedSignal = nil
        armedAt = nil
        armID = nil
        pendingTrade = nil
        pendingExpiry = nil
        pendingOutcome = nil
        expired = false
        historical = true
        isDemoDesk = true
        let fixture = GoldenFixture.market()
        let bars = GoldenFixture.frozenBars(from: fixture)
        candles = bars
        // Demo bars are display fixtures, never a fresh transport observation.
        candleCache.store(bars, for: CandleCache.Key(market: marketMode, asset: pair),
                          fetchedAt: .distantPast)
        let signal = EngineSignal(
            asset: pair,
            cabinetSide: "WAIT",
            call: "WAIT",
            why: "Demo desk active. Connect OANDA in settings for live broker feed.",
            price: fixture.lastPrice,
            entryPrice: fixture.lastPrice
        )
        let demoCommit = ScanKernel.commit(from: signal, bars: bars, scannedAt: Date())
        commit = demoCommit
        cabinetSide = "WAIT"
        commitsByAsset[pair] = demoCommit
        cabinetSideByAsset[pair] = "WAIT"
        notice = "Demo Desk (Offline)"
        publishFrame()
    }

    public func side(for asset: String) -> String? {
        guard let bookSide = book.first(where: { $0.asset == asset })?.side,
              bookSide != "—",
              !bookSide.isEmpty
        else {
            return cabinetSideByAsset[asset]
        }
        return bookSide
    }

    /// True while a settlement write is in progress. Used to freeze navigation.
    public var isSettlementInFlight: Bool { settlementInFlight }

    public func score(for asset: String) -> Int? {
        commitsByAsset[asset]?.score
    }

    public func candles(for asset: String) -> [Candle] {
        candleCache.cached(CandleCache.Key(market: marketMode, asset: asset))
    }

    public func strike(for asset: String) -> Double? {
        commitsByAsset[asset]?.strike
    }

    private func restoreLiveStrategyDecisions(allowWithoutLiveSession: Bool = false) async {
        clearLiveStrategyResearchObservations()
        guard (allowWithoutLiveSession || session?.environment == .live),
              let decisions = try? await liveDecisionStore.liveStrategyDecisions() else { return }
        let latestByAsset = Dictionary(grouping: decisions, by: \.instrument).compactMapValues { $0.last }
        for (asset, decision) in latestByAsset where decision.action != .wait {
            let restoreReason = decision.plan == nil
                ? "restored_actionable_decision_without_plan_requires_live_revalidation"
                : "restored_plan_requires_live_revalidation"
            liveStrategyDecisions[asset] = LiveStrategyDecision(
                instrument: asset, action: .wait,
                supportingStrategies: decision.supportingStrategies,
                plan: nil,
                reasons: [restoreReason],
                sourceReferences: decision.sourceReferences,
                observedAt: decision.observedAt)
            // The saved plan remains in append-only history; it is never projected as
            // current until a fresh Live evaluation revalidates it.
            orbPlans.removeValue(forKey: asset)
        }
    }

    /// Restores only the latest persisted adaptive research decision. This is
    /// display state and never feeds the executable desk frame or entry gate.
    public func restoreAdaptiveResearchProjection(now: Date = Date()) async {
        // AdaptiveMarketRehearsalRecord is explicitly Practice-only. Never project a
        // Practice replay beside the Live OANDA feed as if it were today's Live analysis.
        guard session?.environment == .practice else {
            adaptiveResearchProjection = nil
            return
        }
        let store = ResearchStore(root: ResearchStore.defaultRoot())
        guard let records = try? await store.adaptiveRehearsals(),
              let latest = records.filter({
                  $0.environment == .oandaPractice && $0.validation().isEmpty
              }).max(by: { $0.receivedAt < $1.receivedAt }) else {
            adaptiveResearchProjection = nil
            return
        }
        adaptiveResearchProjection = AdaptiveResearchProjection(record: latest, now: now)
    }

    /// Loads normalized completed candles through the service cache. Broker networking and cache
    /// policy are intentionally absent from the SwiftUI facade.
    public func loadCandles(for asset: String, force: Bool = false) async {
        let market = marketMode
        let key = CandleCache.Key(market: market, asset: asset)
        let session = market == .fx ? await loadSession(allowPrompt: false) : nil
        let hasSession = market != .fx || session != nil
        if marketMode == market, pair == asset {
            candlesLoading = true
            candleIssue = nil
            if !candleCache.cached(key).isEmpty {
                candles = candleCache.cached(key)
                candlesAreStale = !candleCache.isFresh(key)
            }
        }
        var feedResult: MarketCandleResult?
        let bars = await candleCache.load(key, force: force) { @MainActor [weak self] in
            guard let self else { return [] }
            let result = await self.marketData.candleResult(
                market: market,
                asset: asset,
                session: session,
                count: 80
            )
            feedResult = result
            return result.candles
        }
        if marketMode == market, pair == asset {
            candlesLoading = false
            if !bars.isEmpty {
                candles = bars
                candlesAreStale = false
                candleIssue = nil
            } else {
                candlesAreStale = !candles.isEmpty
                candleIssue = feedResult?.issue ?? (!hasSession
                    ? "Add OANDA credentials to load candles"
                    : "Candle feed unavailable; retry by switching markets or scanning")
            }
        }
    }

    /// Illuminates the mark, then the word. Leaves as soon as the feed is actually live.
    public func settleLaunch() async {
        launchMarkLit = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        launchWordLit = true
        let start = Date()
        while !Task.isCancelled && showingLaunch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= 2.0 || (elapsed >= 1.6 && feed == .live) {
                showingLaunch = false
            }
        }
    }

    public func run() async {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-review-insight") {
            await seedReviewInsightUITestFixture()
            return
        }
        // Explicit simulator-only accessibility fixture. Return before credential,
        // market, strategy, settlement, or background startup effects can run.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-user-close-correction") {
            await seedUserReportedCloseCorrectionUITestFixture()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-user-report") {
            await seedUserReportedPositionUITestFixture()
            return
        }
        #endif
        // Resolve the saved OANDA account silently during startup, not only after
        // a scan or when the credential settings cover is opened.
        let startupSession = await loadSession(allowPrompt: false, consumePendingScan: false)
        #if DEBUG
        // Diagnostic: boot directly into a market mode to reproduce render issues headlessly.
        if ProcessInfo.processInfo.environment["BLAZER_START_MARKET"] == "fx" {
            marketMode = .fx
        }
        #endif
        // Verify the pinned engine hash and prove it can produce a verdict before any scan.
        // A failed boot leaves isReady false, so ScanKernel reports SCAN ENGINE OFFLINE
        // instead of evaluating on an unverified script.
        let engineBoot = await StrategyEngine.boot()
        if !engineBoot.ok {
            let detail = engineBoot.detail ?? "verification failed"
            diagLog("ENGINE_BOOT_FAILED \(detail)")
            notice = "Scan engine offline: \(detail)"
        } else {
            diagLog("ENGINE_BOOT_OK \(StrategyEngine.engineHealth.sha?.prefix(12) ?? "?")")
        }
        await reloadFromDisk()
        await restoreLiveStrategyDecisions()
        await restoreAdaptiveResearchProjection()
        await refreshOTCValidationReport()
        Task { await assistant.refreshAvailability() }
        // Finish any settlement that was interrupted by a crash or a failed write.
        if pendingSaveCount > 0 {
            let remaining = await persistence.reconcilePendingSettlements()
            pendingSaveCount = remaining.count
            if remaining.isEmpty {
                await reloadFromDisk()
                clearDeskIfResolved()
            } else {
                awaitingOutcome = true
                notice = "An outcome is waiting to be saved"
            }
        }
        // A Siri request that was queued before launch is consumed once, without being
        // overwritten by a second scan. The Mac desk starts with a fresh market scan so a
        // restored signal is never presented as the current live recommendation.
        let consumedPendingScan = await consumePendingScanIfReady()
        if !consumedPendingScan {
            if marketMode == .crypto {
                await scanCrypto()
            } else {
                #if os(macOS)
                if startupSession != nil {
                    await scan()
                } else {
                    // Startup and background recovery never raise Keychain UI.
                    // The user can initiate one credential-authorized scan from the desk.
                    scanning = false
                    candlesLoading = false
                    feed = .error
                    if keychainState == .locked {
                        candleIssue = "OANDA Live credentials are locked in Keychain"
                        notice = "Select SCAN to authorize OANDA access, or manage credentials in Settings."
                    } else {
                        candleIssue = "OANDA Live credentials are not saved in this Mac’s Keychain"
                        notice = "Connect OANDA Live credentials in Settings to load market data."
                    }
                    publishFrame()
                }
                #else
                if candles.isEmpty {
                    Task { await self.loadCandles(for: self.pair) }
                }
                #endif
            }
        }
        if marketMode == .crypto {
            await remeasureExchangeClock()
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLAZER_START_TAB"] == "coach" {
            activeTab = .review
        }
        if ProcessInfo.processInfo.environment["BLAZER_ASSISTANT_DEMO"] == "1" {
            activeTab = .review
            await assistant.explainLatestScan()
            await assistant.ask("Why did this scan return WAIT?")
            await assistant.requestDebrief()
        }
        #endif
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.quoteLoop() }
            group.addTask { await self.beamLoop() }
            group.addTask { await self.cryptoQuoteLoop() }
            group.addTask { await self.orbMonitorLoop() }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func seedReviewInsightUITestFixture() async {
        let createdAt = Date(timeIntervalSince1970: 1_794_700_000)
        let plan = V3TradePlan(id: "ui-test-review-insight-plan-v1", instrument: "EUR/USD",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "ui-test-review-insight-observation-v1",
            state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
            targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003,
            riskFraction: 0.005, createdAt: createdAt)
        do {
            try await liveDecisionStore.record(plan)
            let opening = try await liveDecisionStore.recordUserReportedPosition(planID: plan.id,
                units: 10_000, entryPrice: 1.1002,
                userReportedEnteredAt: createdAt.addingTimeInterval(100),
                updatedAt: createdAt.addingTimeInterval(200))
            guard let positionID = opening.positionID else {
                notice = "UI Review Insight fixture invalid: opening position ID missing"
                return
            }
            _ = try await liveDecisionStore.recordUserReportedPositionClose(positionID: positionID,
                closedAt: nil, exitPrice: nil, recordedAt: createdAt.addingTimeInterval(300))
            pair = plan.instrument
            marketMode = .fx
            isDemoDesk = true
            orbPlans[plan.instrument] = plan
            orbDecisions[plan.instrument] = ORBDecision(stage: .setupConfirmed,
                setupState: .confirmed, sessionStart: createdAt,
                rangeHigh: 1.1010, rangeLow: 1.0990, direction: .long,
                reason: "Process-isolated deterministic Review Insight UI fixture")
            orbLifecycleStatuses[plan.instrument] = .recorded
        } catch {
            // The process-unique test archive must be empty. Any write conflict or
            // persistence error aborts this fixture rather than showing partial facts.
            notice = "UI Review Insight fixture could not be written; no partial fixture accepted"
        }
    }

    private func seedUserReportedPositionUITestFixture() async {
        let createdAt = Date(timeIntervalSince1970: 1_794_700_000)
        let plan = V3TradePlan(id: "ui-test-user-report-plan", instrument: "EUR/USD",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "ui-test-orb-observation",
            state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
            targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003,
            riskFraction: 0.005, createdAt: createdAt)
        do {
            try await liveDecisionStore.record(plan)
            pair = plan.instrument
            marketMode = .fx
            isDemoDesk = true
            orbPlans[plan.instrument] = plan
            orbDecisions[plan.instrument] = ORBDecision(stage: .setupConfirmed,
                setupState: .confirmed, sessionStart: createdAt,
                rangeHigh: 1.1010, rangeLow: 1.0990, direction: .long,
                reason: "Deterministic UI test fixture")
            orbLifecycleStatuses[plan.instrument] = .recorded
        } catch {
            notice = "UI report fixture unavailable"
        }
    }

    private func seedUserReportedCloseCorrectionUITestFixture() async {
        // Stable timestamps and a versioned plan ID make repeated simulator runs
        // idempotent against the app-support archive.
        let now = Date(timeIntervalSince1970: 1_794_867_000)
        let createdAt = now.addingTimeInterval(-1_200)
        let plan = V3TradePlan(id: "ui-test-close-correction-plan-v3", instrument: "EUR/USD",
            strategyID: "ORB_BREAK_RETEST_V1", strategyVersion: "ORB_BREAK_RETEST_V1",
            engineVersion: "V3_ORB_ENGINE_1", sourceObservationID: "ui-test-close-observation",
            state: .validated, side: .long, entryPrice: 1.1002, stopPrice: 1.0992,
            targetPrice: 1.1022, units: 10_000, maxSpread: 0.0003,
            riskFraction: 0.005, createdAt: createdAt)
        do {
            try await liveDecisionStore.record(plan)
            let opening = try await liveDecisionStore.recordUserReportedPosition(planID: plan.id,
                units: 10_000, entryPrice: 1.1002,
                userReportedEnteredAt: now.addingTimeInterval(-1_000),
                updatedAt: now.addingTimeInterval(-900))
            // The close must bind to the original opening revision. Record it
            // before the later entry correction so its effective close time is
            // valid against that immutable revision.
            _ = try await liveDecisionStore.recordUserReportedPositionClose(
                positionID: opening.positionID!, closedAt: now.addingTimeInterval(-700),
                exitPrice: 1.101, recordedAt: now.addingTimeInterval(-600))
            _ = try await liveDecisionStore.recordUserReportedPosition(planID: plan.id,
                units: 9_900, entryPrice: 1.1003,
                userReportedEnteredAt: now.addingTimeInterval(-500),
                updatedAt: now.addingTimeInterval(-400), supersedesRecordID: opening.id)
            pair = plan.instrument
            marketMode = .fx
            isDemoDesk = true
            orbPlans[plan.instrument] = plan
            orbDecisions[plan.instrument] = ORBDecision(stage: .setupConfirmed,
                setupState: .confirmed, sessionStart: createdAt,
                rangeHigh: 1.1010, rangeLow: 1.0990, direction: .long,
                reason: "Deterministic close correction UI fixture")
            orbLifecycleStatuses[plan.instrument] = .recorded
        } catch {
            notice = "UI close correction fixture unavailable"
        }
    }
    #endif

    /// A fresh six-market walk. Nothing from the previous scan is reused.
    public func scan() async {
        entryIssue = nil
        isDemoDesk = false
        let market = marketMode
        let cryptoAsset = CTAssets.watchlist.contains(pair) ? pair : (CTAssets.watchlist.first ?? "BTC/USDT")
        let fxRequest = FXScanScope.request(market: market, selectedPair: pair,
                                            availablePairs: pairs, selectedOnly: false)
        await enqueueScan(
            market: market,
            asset: market == .crypto ? cryptoAsset : fxRequest?.asset,
            assets: market == .crypto ? [cryptoAsset] : (fxRequest?.assets ?? [])
        )
    }

#if os(macOS)
    /// Runs the normal FX scan and Trade decision pipeline for only the current watchlist pair.
    /// The all-market Scan remains a separate action with its existing picker behavior.
    public func scanSelectedFXPair(_ requestedPair: String) async {
        guard marketMode == .fx, pair == requestedPair else { return }
        entryIssue = nil
        isDemoDesk = false
        guard let request = FXScanScope.request(market: .fx, selectedPair: requestedPair,
                                                availablePairs: pairs, selectedOnly: true) else {
            notice = "Selected FX pair is unavailable"
            return
        }
        await enqueueScan(market: .fx, asset: request.asset, assets: request.assets)
    }

    /// Starts bounded, read-only GBP/JPY Practice scans using the existing scan coordinator.
    /// The user must explicitly start this monitor; it never submits broker orders.
    public func toggleGBPJPYPracticeMonitoring() async {
        if isGBPJPYPracticeMonitoring {
            stopGBPJPYPracticeMonitoring()
            return
        }
        guard marketMode == .fx, pair == "GBP/JPY" else {
            notice = "Select GBP/JPY before starting the Practice monitor"
            return
        }
        guard let activeSession = await loadSession(allowPrompt: false),
              activeSession.environment == .practice else {
            notice = "Connect an OANDA Practice account before starting the GBP/JPY monitor"
            return
        }
        isGBPJPYPracticeMonitoring = true
        notice = "GBP/JPY Practice monitor started · scans every minute while the market is open"
        gbpJPYPracticeMonitorTask?.cancel()
        gbpJPYPracticeMonitorTask = Task { [weak self] in
            await self?.runGBPJPYPracticeMonitor()
        }
    }

    public func stopGBPJPYPracticeMonitoring() {
        gbpJPYPracticeMonitorTask?.cancel()
        gbpJPYPracticeMonitorTask = nil
        isGBPJPYPracticeMonitoring = false
        notice = "GBP/JPY Practice monitor stopped"
    }

    /// Calculates a manual-only GBP/JPY Practice size from a fresh OANDA quote,
    /// account equity, instrument commission/margin rules and home conversions.
    public func calculateGBPJPYPracticeSize(signalID: String) async {
        practiceSizingPreview = nil
        practiceSizingMessage = nil
        guard marketMode == .fx, pair == "GBP/JPY",
              let signal = macResearchSignals.first(where: { $0.id == signalID }),
              signal.instrument == "GBP/JPY", signal.environment == .practice,
              signal.stage == .actionable, Date() <= signal.validUntil,
              let stop = signal.stopPrice, stop.isFinite, stop > 0 else {
            practiceSizingMessage = "A current actionable Practice signal with a stop is required."
            return
        }
        guard let activeSession = await loadSession(allowPrompt: false),
              activeSession.environment == .practice else {
            practiceSizingMessage = "Connect the OANDA Practice account to calculate account-sized units."
            return
        }
        let batch = await OandaClient.fetchPracticeGBPYJSizingSnapshot(session: activeSession)
        guard let snapshot = batch.snapshot, snapshot.accountId == activeSession.accountId else {
            practiceSizingMessage = batch.reason.map { "Account sizing unavailable: \($0)." }
                ?? "Account sizing unavailable from OANDA Practice."
            return
        }
        guard let currentSignal = macResearchSignals.first(where: { $0.id == signalID }),
              currentSignal == signal, Date() <= signal.validUntil else {
            practiceSizingMessage = "Signal changed or expired while account data was loading. Scan again."
            return
        }
        let now = Date()
        let quoteAge = now.timeIntervalSince(snapshot.quoteAsOf)
        let conversionAge = now.timeIntervalSince(snapshot.conversionsAsOf)
        guard quoteAge >= -1, quoteAge <= 3,
              conversionAge >= -1, conversionAge <= 3,
              snapshot.bid.isFinite, snapshot.ask.isFinite, snapshot.ask > snapshot.bid else {
            practiceSizingMessage = "OANDA Practice quote is stale or invalid. Refresh the signal and try again."
            return
        }
        let entry = signal.direction == .long ? snapshot.ask : snapshot.bid
        guard signal.direction == .long ? stop < entry : stop > entry,
              let factors = snapshot.sizingFactors(entryPrice: entry),
              let request = snapshot.riskSizingRequest(
                entryPrice: entry, stopPrice: stop,
                spreadCostPerUnit: (snapshot.ask - snapshot.bid) * factors.accountRiskPerPriceUnit) else {
            practiceSizingMessage = "Entry, stop, conversion, margin, or commission data is invalid."
            return
        }
        // Use executable entry side and reserve an additional full spread for
        // stop exit uncertainty, plus OANDA's documented round-trip commission.
        let sizing = V3RiskSizer.size(request)
        guard sizing.accepted,
              let loss = sizing.estimatedWorstCaseLossUSD,
              let margin = sizing.estimatedMarginUSD else {
            practiceSizingMessage = "Practice sizing rejected: \(sizing.rejectionReason ?? "unknown_reason")."
            return
        }
        practiceSizingPreview = MacPracticeSizingPreview(
            signalID: signal.id, sourceInputIdentity: signal.sourceInputIdentity,
            accountCurrency: snapshot.accountCurrency,
            units: sizing.units, riskBudget: sizing.riskBudgetUSD,
            estimatedLoss: loss, estimatedMargin: margin,
            entryPrice: entry, stopPrice: stop, observedAt: snapshot.observedAt)
        practiceSizingMessage = "Estimate only · recheck the trigger and quote before manual entry."
    }

    private func runGBPJPYPracticeMonitor() async {
        var consecutiveFailures = 0
        while !Task.isCancelled, isGBPJPYPracticeMonitoring {
            guard marketMode == .fx, pair == "GBP/JPY" else {
                stopGBPJPYPracticeMonitoring()
                return
            }
            if backgroundedAt != nil {
                try? await Task.sleep(for: .seconds(30))
                continue
            }
            guard let activeSession = await loadSession(allowPrompt: false),
                  activeSession.environment == .practice else {
                stopGBPJPYPracticeMonitoring()
                notice = "Practice session unavailable · GBP/JPY monitoring stopped"
                return
            }

            let now = Date()
            var delay: TimeInterval = 60
            if FxSession.isOpen(now) {
                if !scanning, activeTrade == nil, !awaitingOutcome, !settlementInFlight {
                    await scanSelectedFXPair("GBP/JPY")
                    let scanFailed = feed == .error || macResearchSignalStatus == .failed
                    consecutiveFailures = scanFailed ? min(consecutiveFailures + 1, 3) : 0
                    if scanFailed {
                        delay = min(60 * pow(2, Double(consecutiveFailures)), 300)
                    }
                } else if activeTrade != nil || awaitingOutcome || settlementInFlight {
                    delay = 60
                }
            } else {
                notice = FxSession.label(now)
                delay = 300
            }
            try? await Task.sleep(for: .seconds(delay))
        }
    }
#endif

    /// Crypto scan via the shared BlazerCrypto engine. No OANDA credential, no FX session gate.
    public func scanCrypto(asset: String = "BTC/USDT") async {
        await enqueueScan(market: .crypto, asset: asset, assets: [asset])
    }

    private func enqueueScan(market: DeskMarket, asset: String?, assets: [String]) async {
        if market == .crypto { clearLiveStrategyResearchObservations() }
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else {
            notice = "Resolve the current outcome before scanning"
            return
        }
        guard !entryInFlight else {
            notice = "Entry is being saved; scan again after it completes"
            return
        }
#if os(macOS)
        if market == .fx {
            macResearchExpiryTask?.cancel()
            macResearchSignals = []
            macResearchEvaluationDiagnostics = []
            macResearchSignalStatus = .awaitingFreshScan
        }
#endif
        await scanCoordinator.submit(market: market, asset: asset, assets: assets) { [weak self] request in
            guard let self else { return }
            switch request.market {
            case .fx: await self.performFXScan(request)
            case .crypto: await self.performCryptoScan(request)
            }
        }
    }

    private func isCurrentScan(_ request: ScanRequestScheduler.Request) -> Bool {
        scanCoordinator.isCurrent(request) && marketMode == request.market
    }

    private func invalidateScanRequests() {
        scanCoordinator.invalidate()
        scanning = false
        scanStep = nil
    }

    private func performCryptoScan(_ request: ScanRequestScheduler.Request) async {
        guard isCurrentScan(request) else { return }
        defer {
            if isCurrentScan(request) {
                scanning = false
                scanStep = nil
            }
        }
        guard request.market == .crypto, let asset = request.asset else { return }
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight, !entryInFlight else {
            notice = "Resolve the current outcome before scanning"
            return
        }
        scanning = true
        feed = .connecting
        commit = nil
        cabinetSide = "WAIT"
        armedAt = nil
        historical = false
        expired = false
        awaitingOutcome = false
        activeTrade = nil
        activeTradeQuote = nil
        activeEntryArmedAt = nil
        predictedOutcome = nil
        armID = nil
        candles = []
        candlesLoading = true
        candleIssue = nil
        notice = nil
        book = CTAssets.watchlist.map { BookRow(asset: $0, side: "—") }
        publishFrame()
        scanStep = asset

        let started = Date()
        let snapshot: MarketScanSnapshot?
        do {
            snapshot = try await marketData.scan(market: .crypto, asset: asset, session: nil)
        } catch {
            guard isCurrentScan(request) else { return }
            candlesLoading = false
            candleIssue = error.localizedDescription
            diagLog("CRYPTO_SCAN failed: \(error.localizedDescription)")
            feed = .disconnected
            notice = "Crypto scan failed: \(error.localizedDescription)"
            publishFrame()
            return
        }
        guard isCurrentScan(request) else { return }
        guard let snapshot, !snapshot.candles.isEmpty else {
            diagLog("CRYPTO_SCAN failed: feed unavailable")
            feed = .disconnected
            candlesLoading = false
            candleIssue = "Crypto feed returned no candles"
            notice = "Crypto feed unavailable"
            publishFrame()
            return
        }

        let cryptoSignal = snapshot.signal
        let bars = snapshot.candles
        let mid = (snapshot.bid.flatMap { bid in snapshot.ask.map { (bid + $0) / 2 } }) ?? cryptoSignal.price
        diagLog("CRYPTO_SCAN \(asset) side=\(cryptoSignal.cabinetSide) conv=\(cryptoSignal.confidence ?? 0) candles=\(bars.count) mid=\(mid) source=\(snapshot.source)")
        var next = ScanKernel.commit(
            from: cryptoSignal,
            bars: bars,
            m5Bars: snapshot.m5Candles,
            bid: snapshot.bid,
            ask: snapshot.ask,
            spread: snapshot.spread,
            expirySeconds: snapshot.expirySeconds,
            engineSHA: snapshot.engineSHA,
            policy: snapshot.policy,
            scannedAt: started
        )
        next.veto = snapshot.veto
        if let veto = next.veto {
            diagLog("CRYPTO_VETO \(asset): \(veto)")
        }
        pair = asset
        commit = next
        cabinetSide = cryptoSignal.cabinetSide
        selectedSignal = cryptoSignal
        candles = bars
        candlesLoading = false
        candleIssue = nil
        candleCache.store(bars, for: CandleCache.Key(market: .crypto, asset: asset))
        commitsByAsset[asset] = next
        cabinetSideByAsset[asset] = cryptoSignal.cabinetSide
        book = [BookRow(asset: asset, side: cryptoSignal.cabinetSide)]
        if snapshot.source == "kraken-synthetic-spread" {
            feed = .stale
        } else {
            feed = .live
            lastFreshPollAt = Date()
        }
        let armedClock = Date()
        armedAt = ((cryptoSignal.cabinetSide == "HIGH" || cryptoSignal.cabinetSide == "LOW") && next.veto == nil)
            ? armedClock.addingTimeInterval(-0.001)
            : nil
        now = armedClock
        notice = next.veto
        publishFrame()
        liftHero()
        if let frame {
            let saved = await remember(next, verb: frame.verb, request: request)
            guard isCurrentScan(request) else { return }
            if !saved {
                commit?.veto = "Scan was not saved"
                armedAt = nil
                armID = nil
                notice = "Scan was not saved; scan again"
                publishFrame()
            }
        }
    }

    private func evaluateORB(asset: String, bars: [Candle], asOf: Date) -> ORBDecision {
        let orbBars = makeORBBarEvidence(asset: asset, bars: bars)
        guard !orbBars.isEmpty else {
            return ORBDecision(stage: .noData, setupState: .noData, sessionStart: nil,
                               reason: "no_completed_oanda_m1_bars")
        }
        return ORBBreakRetestV1.evaluate(instrument: asset, bars: orbBars, asOf: asOf)
    }

    private func makeORBBarEvidence(asset: String, bars: [Candle]) -> [ORBBar] {
        bars.compactMap { candle -> ORBBar? in
            guard let milliseconds = candle.time,
                  let open = candle.open, let high = candle.high, let low = candle.low else { return nil }
            let start = Date(timeIntervalSince1970: milliseconds / 1_000)
            return ORBBar(id: "\(asset)-\(milliseconds)", instrument: asset,
                          sourceTime: start, endTime: start.addingTimeInterval(60),
                          open: open, high: high, low: low, close: candle.close)
        }
    }

    private func publishORBDecision(_ decision: ORBDecision, bars: [ORBBar], asOf: Date,
                                    asset: String, generation: UInt64) async {
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        guard marketMode == .fx else {
            orbPlans.removeValue(forKey: asset)
            orbLifecycleStatuses[asset] = .notApplicable
            orbDecisions[asset] = ORBDecision(stage: .unavailable, setupState: .stale,
                sessionStart: nil, reason: "orb_fx_only")
            if pair == asset { publishFrame() }
            return
        }
        guard session?.environment == .live else {
            guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
            orbPlans.removeValue(forKey: asset)
            orbLifecycleStatuses[asset] = .notApplicable
            orbDecisions[asset] = ORBDecision(stage: .unavailable, setupState: .stale,
                sessionStart: nil, reason: "live_session_unavailable")
            if pair == asset { publishFrame() }
            return
        }
        if let plan = decision.candidate?.plan {
            do {
                try await liveDecisionStore.record(plan)
            } catch {
                guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                orbPlans.removeValue(forKey: asset)
                orbLifecycleStatuses[asset] = .unavailable
                orbDecisions[asset] = ORBDecision(stage: .unavailable, setupState: .stale,
                    sessionStart: nil, reason: "live_orb_plan_persistence_failed")
                if pair == asset { publishFrame() }
                return
            }
        }
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        let projectionResult = ORBBreakRetestLifecycleV1.project(decision: decision, bars: bars, asOf: asOf)
        if case let .projected(projection) = projectionResult {
            do {
                let events = try await liveDecisionStore.v3SetupLifecycleEvents()
                guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                let stream = events.filter { $0.setupID == projection.setupID }
                    .sorted { ($0.sourceTime ?? .distantPast) < ($1.sourceTime ?? .distantPast) }
                let previous = stream.last
                if previous?.state == projection.state {
                    if let prior = previous, let priorTime = prior.sourceTime {
                        if projection.sourceTime < priorTime
                            || (projection.sourceTime == priorTime
                                && (projection.inputDigest != prior.inputDigest
                                    || projection.sourceObservationID != prior.sourceObservationID)) {
                            orbLifecycleStatuses[asset] = .unavailable
                        } else {
                            orbLifecycleStatuses[asset] = .noTransition
                        }
                    } else {
                        orbLifecycleStatuses[asset] = .unavailable
                    }
                } else {
                    if let priorTime = previous?.sourceTime, projection.sourceTime <= priorTime {
                        throw ScanError.failed("ORB lifecycle source time did not advance")
                    }
                    let event = ORBBreakRetestLifecycleV1.event(for: projection,
                        previousState: previous?.state)
                    guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                    let appendResult = try await liveDecisionStore.record(event, shouldAppend: { [weak self] in
                        guard let self else { return false }
                        return await self.isCurrentLiveDecisionRefresh(generation, for: asset)
                    })
                    guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                    switch appendResult {
                    case .appended: orbLifecycleStatuses[asset] = .recorded
                    case .duplicate: orbLifecycleStatuses[asset] = .noTransition
                    case .generationSuperseded: orbLifecycleStatuses[asset] = .unavailable
                    }
                }
            } catch ScanError.failed("ORB_STRUCTURE_SUPPRESSED") {
                guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                orbLifecycleStatuses[asset] = .structureSuppressed
            } catch {
                guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
                orbLifecycleStatuses[asset] = .unavailable
            }
        } else if projectionResult == .notApplicable {
            orbLifecycleStatuses[asset] = .notApplicable
        } else {
            orbLifecycleStatuses[asset] = .unavailable
        }
        orbDecisions[asset] = decision
        if let plan = decision.candidate?.plan {
            orbPlans[asset] = plan
            if orbEntryObservationStatuses[asset]?.planID != plan.id {
                orbEntryObservationStatuses[asset] = (plan.id, "Awaiting an eligible fresh quote · hypothetical market entry reference")
            }
        } else {
            orbPlans.removeValue(forKey: asset)
            orbEntryObservationStatuses.removeValue(forKey: asset)
        }
    }

    private func recordORBEntryObservation(quote: LiveQuote, receivedAt: Date,
                                          asset: String, generation: UInt64) async {
        guard let plan = orbPlans[asset], pair == asset, marketMode == .fx,
              session?.environment == .live else { return }
        orbEntryObservationStatuses[asset] = (plan.id, "Awaiting an eligible fresh Live OANDA quote · hypothetical market entry reference")
        guard quote.source.lowercased() == "oanda", quote.asset == plan.instrument,
              let sourceMilliseconds = Self.safeQuoteTimestampMilliseconds(quote.asOfMs) else {
            orbEntryObservationStatuses[asset] = (plan.id, "Unavailable · hypothetical market entry reference")
            return
        }
        let sourceTime = Date(timeIntervalSince1970: Double(sourceMilliseconds) / 1_000)
        let observation = V3MarketObservation(id: "oanda-\(sourceMilliseconds)",
            instrument: quote.asset, provider: "OANDA", environment: .oandaLive,
            bid: quote.bid, ask: quote.ask, sourceTime: sourceTime, receivedAt: receivedAt)
        let entrySide = plan.side == .long ? observation.ask : observation.bid
        let inPlanBand = plan.maxEntryDeviation.map {
            entrySide >= plan.entryPrice - $0 && entrySide <= plan.entryPrice + $0
        } ?? false
        let betweenLevels = entrySide > min(plan.stopPrice, plan.targetPrice)
            && entrySide < max(plan.stopPrice, plan.targetPrice)
        guard observation.validation(now: receivedAt, maxAge: 5).isEmpty,
              observation.sourceTime >= plan.createdAt,
              observation.spread <= plan.maxSpread, inPlanBand, betweenLevels else { return }
        do {
            let result = try await liveDecisionStore.recordLivePlanEntryObservation(
                planID: plan.id, observation: observation, recordedAt: receivedAt,
                shouldAppend: { [weak self] in
                    guard let self else { return false }
                    return await MainActor.run {
                        Self.isLiveEntryAppendEligible(
                            isCurrent: self.isCurrentLiveDecisionRefresh(generation, for: asset),
                            selectedPair: self.pair, asset: asset, marketMode: self.marketMode,
                            scanning: self.scanning, environment: self.session?.environment)
                    }
                })
            guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset,
                  marketMode == .fx, !scanning, orbPlans[asset]?.id == plan.id else { return }
            switch result {
            case .appended, .alreadyRecorded:
                orbEntryObservationStatuses[asset] = (plan.id, "Recorded · hypothetical market entry reference · not an order, fill, or position")
            case .generationSuperseded:
                break
            }
        } catch {
            guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset,
                  orbPlans[asset]?.id == plan.id else { return }
            orbEntryObservationStatuses[asset] = (plan.id, "Unavailable · hypothetical market entry reference")
        }
    }

    private func recordORBShadowStructuralOutcome(quote: LiveQuote, receivedAt: Date,
                                                   asset: String, generation: UInt64) async {
        guard let plan = orbPlans[asset], pair == asset, marketMode == .fx,
              session?.environment == .live, quote.source.lowercased() == "oanda",
              quote.asset == plan.instrument,
              let sourceMilliseconds = Self.safeQuoteTimestampMilliseconds(quote.asOfMs) else { return }
        let observation = V3MarketObservation(id: "oanda-\(sourceMilliseconds)",
            instrument: quote.asset, provider: "OANDA", environment: .oandaLive,
            bid: quote.bid, ask: quote.ask,
            sourceTime: Date(timeIntervalSince1970: Double(sourceMilliseconds) / 1_000),
            receivedAt: receivedAt)
        do {
            _ = try await liveDecisionStore.recordLiveShadowStructuralOutcome(planID: plan.id,
                exitObservation: observation, recordedAt: receivedAt,
                shouldAppend: { [weak self] in
                    guard let self else { return false }
                    return await MainActor.run {
                        Self.isLiveEntryAppendEligible(
                            isCurrent: self.isCurrentLiveDecisionRefresh(generation, for: asset),
                            selectedPair: self.pair, asset: asset, marketMode: self.marketMode,
                            scanning: self.scanning, environment: self.session?.environment)
                    }
                })
        } catch {
            // Shadow outcome failures leave the plan, entry evidence, lifecycle,
            // and position records unchanged; a later quote can retry.
        }
    }

    private func beginLiveDecisionRefresh(for asset: String) -> UInt64 {
        if pair == asset { clearLiveStrategyResearchObservations() }
        return liveDecisionGeneration.begin(for: asset)
    }

    private func isCurrentLiveDecisionRefresh(_ generation: UInt64, for asset: String) -> Bool {
        liveDecisionGeneration.isCurrent(generation, for: asset)
    }

    private func withdrawLiveStrategyDecision(for asset: String, reason: String,
                                             generation: UInt64) async {
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        if pair == asset {
            clearLiveStrategyResearchObservations()
#if os(macOS)
            macResearchSignalStatus = .failed
#endif
        }
        let now = Date()
        let decision = LiveStrategyDecision(instrument: asset, action: .wait,
            supportingStrategies: liveStrategyDecisions[asset]?.supportingStrategies ?? [],
            plan: nil, reasons: [reason],
            sourceReferences: liveStrategyDecisions[asset]?.sourceReferences ?? [], observedAt: now)
        // A failed Live refresh invalidates the current projection, while the immutable
        // plan/decision events already written to ResearchStore remain available as history.
        await publishLiveStrategyDecision(decision, asset: asset, generation: generation)
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        orbPlans.removeValue(forKey: asset)
        orbLifecycleStatuses[asset] = session?.environment == .live ? .unavailable : .notApplicable
        orbDecisions[asset] = ORBDecision(stage: .unavailable, setupState: .stale,
            sessionStart: nil, reason: reason)
        if pair == asset { publishFrame() }
    }

    /// A full-book Live scan strategy-evaluates only its selected instrument. Any
    /// actionable decision for another attempted asset therefore has no current
    /// strategy evaluation and must leave the current projection.
    private func withdrawUnselectedLiveDecisions(scanAssets: [String], pickedAsset: String,
                                                  generations: [String: UInt64]) async {
        for asset in scanAssets where asset != pickedAsset {
            guard liveStrategyDecisions[asset]?.action != .wait,
                  liveStrategyDecisions[asset] != nil,
                  let generation = generations[asset] else { continue }
            await withdrawLiveStrategyDecision(for: asset,
                reason: "live_instrument_not_currently_monitored", generation: generation)
        }
    }

    private func publishLiveStrategyDecision(_ decision: LiveStrategyDecision, asset: String,
                                             generation: UInt64) async {
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        let previous = liveStrategyDecisions[asset]
        var published = decision
        let changed = previous == nil || previous?.action != decision.action
            || previous?.plan?.id != decision.plan?.id
            || previous?.supportingStrategies != decision.supportingStrategies
            || previous?.reasons != decision.reasons
        if changed {
            do {
                if let plan = decision.plan {
                    try await liveDecisionStore.record(plan)
                }
                try await liveDecisionStore.record(decision)
            } catch {
                published = LiveStrategyDecision(instrument: asset, action: .wait,
                    supportingStrategies: decision.supportingStrategies, plan: nil,
                    reasons: ["strategy_decision_persistence_failed"],
                    sourceReferences: decision.sourceReferences, observedAt: Date())
                notice = "Strategy decision could not be saved; waiting for the next Live scan"
                // Fail closed in the UI even if persistence is unavailable. Make a best
                // effort to persist the WAIT transition itself for restart recovery.
                try? await liveDecisionStore.record(published)
            }
        }
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        liveStrategyDecisions[asset] = published
        let planID = published.plan?.id ?? previous?.plan?.id
        guard let planID else { return }
        let newlyActionable = published.action != .wait
            && (previous?.action != published.action || previous?.plan?.id != published.plan?.id)
        let withdrawn = published.action == .wait && previous?.action != .wait
        guard newlyActionable || withdrawn else { return }
        let safeAsset = asset.replacingOccurrences(of: "/", with: "-")
        let event = withdrawn ? "withdrawn" : "signal"
        // The decision ID has millisecond precision. A second-level timestamp can
        // collide for signal → withdrawal → signal transitions within one second.
        let stableID = "blazer-strategy-\(safeAsset)-\(planID)-\(event)-\(published.id)"
        var delivered = Set(UserDefaults.standard.stringArray(forKey: strategyDeliveredNotificationDefaultsKey) ?? [])
        guard !delivered.contains(stableID) else { return }
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        noteLiveStrategyNotificationScheduleAttempt()
        let scheduled = await MarketNotificationService.shared.scheduleLiveStrategyNotification(
            identifier: stableID, decision: published, withdrawn: withdrawn)
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        guard scheduled else { return }
        delivered.insert(stableID)
        UserDefaults.standard.set(Array(delivered.suffix(256)), forKey: strategyDeliveredNotificationDefaultsKey)
    }

    /// Re-evaluate ORB from fresh completed OANDA M1 bars between manual scans.
    /// This keeps setup state alive without using the short legacy action timer
    /// as a setup expiry or an order authorization.
    private func orbMonitorLoop() async {
        while !Task.isCancelled {
            if marketMode == .fx, !scanning {
                if FxSession.isOpen(Date()) {
                    await refreshORBMonitor()
                } else {
                    let asset = pair
                    let generation = beginLiveDecisionRefresh(for: asset)
                    await withdrawLiveStrategyDecision(for: asset, reason: "fx_market_closed",
                                                       generation: generation)
                }
            }
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    private func refreshORBMonitor() async {
        let asset = pair
        let generation = beginLiveDecisionRefresh(for: asset)
        let session = await loadSession(allowPrompt: false)
        guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset,
              marketMode == .fx, !scanning else { return }
        guard let session, session.environment == .live else {
            await withdrawLiveStrategyDecision(for: asset, reason: "live_session_unavailable",
                                               generation: generation)
            return
        }
        async let candleResult = marketData.candleResult(market: .fx, asset: asset,
                                                           session: session, count: 500)
        async let fiveMinuteResult = marketData.candleResult(market: .fx, asset: asset,
            session: session, granularity: "M5", count: 120)
        async let quoteResult = marketData.quotes(market: .fx, assets: [asset], session: session)
        let (result, fiveMinute, quotes) = await (candleResult, fiveMinuteResult, quoteResult)
        guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset,
              marketMode == .fx, !scanning else { return }
        guard result.status == .ok, !result.candles.isEmpty else {
            await withdrawLiveStrategyDecision(for: asset, reason: "live_m1_candles_unavailable",
                                               generation: generation)
            return
        }
        guard fiveMinute.status == .ok, !fiveMinute.candles.isEmpty else {
            await withdrawLiveStrategyDecision(for: asset, reason: "live_m5_candles_unavailable",
                                               generation: generation)
            return
        }
        let receivedAt = Date()
        let bars = result.candles
        let orb = evaluateORB(asset: asset, bars: bars, asOf: receivedAt)
        let orbBars = makeORBBarEvidence(asset: asset, bars: bars)
        await publishORBDecision(orb, bars: orbBars, asOf: receivedAt,
                                 asset: asset, generation: generation)
        let visibleBars = Array(bars.suffix(120))
        candleCache.store(visibleBars, for: CandleCache.Key(market: .fx, asset: asset))
        candles = visibleBars
        candlesAreStale = false
        candleIssue = nil

        guard quotes.status == .ok,
              let quote = quotes.quotes.first(where: { $0.asset == asset }),
              QuoteFreshness.isFresh(quote, now: quotes.receivedAt), quote.bid > 0, quote.ask > quote.bid else {
            await withdrawLiveStrategyDecision(for: asset, reason: "fresh_live_quote_unavailable",
                                               generation: generation)
            return
        }
        await recordORBEntryObservation(quote: quote, receivedAt: quotes.receivedAt,
                                        asset: asset, generation: generation)
        await recordORBShadowStructuralOutcome(quote: quote, receivedAt: quotes.receivedAt,
                                               asset: asset, generation: generation)
        let payloads = bars.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time, open: open, high: high,
                                                low: low, close: candle.close)
        }
        let m5Payloads = fiveMinute.candles.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time, open: open, high: high,
                                                low: low, close: candle.close)
        }
        guard payloads.count >= 20, !m5Payloads.isEmpty else {
            await withdrawLiveStrategyDecision(for: asset, reason: "live_candles_malformed_or_insufficient",
                                               generation: generation)
            return
        }
        let input = StrategyEngine.MarketInput(asset: asset, source: "oanda-live",
            candles1m: payloads, candles5m: m5Payloads, lastPrice: quote.mid,
            bid: quote.bid, ask: quote.ask, spread: quote.ask - quote.bid,
            expirySeconds: Timing.expirySec, quoteAsOfMs: quote.asOfMs,
            evaluatedAtMs: receivedAt.timeIntervalSince1970 * 1_000, policy: .baseline)
        let evaluation = await selectLiveStrategySelection(input: input, asset: asset)
        guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset else { return }
        await publishMacResearchSignals(evaluation, instrument: asset, generation: generation,
            sourceInputIdentity: ScanInputSnapshot(pair: asset, m1: bars,
                m5: fiveMinute.candles, bid: quote.bid, ask: quote.ask,
                spread: quote.ask - quote.bid, quoteAsOfMs: quote.asOfMs,
                expirySeconds: Timing.expirySec).identity,
            quoteAsOfMs: quote.asOfMs)
        await publishLiveStrategySelection(evaluation.selection, asset: asset, generation: generation)
        publishFrame()
    }

    private func performFXScan(_ request: ScanRequestScheduler.Request) async {
        guard isCurrentScan(request) else { return }
        defer {
            if isCurrentScan(request) {
                scanning = false
                scanStep = nil
            }
        }
        guard request.market == .fx else { return }
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight, !entryInFlight else {
            notice = "Resolve the current outcome before scanning"
            return
        }
        let scanAssets = request.assets
        guard !scanAssets.isEmpty else {
            notice = "No markets are available to scan"
            return
        }
        var liveGenerations: [String: UInt64] = [:]
        for asset in scanAssets where liveGenerations[asset] == nil {
            liveGenerations[asset] = beginLiveDecisionRefresh(for: asset)
        }
        let clock = Date()
        if !FxSession.isOpen(clock) {
            feed = .disconnected
            notice = FxSession.label(clock)
            for asset in scanAssets {
                if let generation = liveGenerations[asset] {
                    await withdrawLiveStrategyDecision(for: asset, reason: "fx_market_closed",
                                                       generation: generation)
                }
            }
            return
        }
        scanning = true
        feed = .connecting
        commit = nil
        cabinetSide = "WAIT"
        armedAt = nil
        historical = false
        expired = false
        awaitingOutcome = false
        activeTrade = nil
        activeTradeQuote = nil
        activeEntryArmedAt = nil
        predictedOutcome = nil
        armID = nil
        candlesAreStale = !candles.isEmpty
        candlesLoading = true
        candleIssue = nil
        notice = nil
        book = scanAssets.map { BookRow(asset: $0, side: "—") }
        publishFrame()
        scanStep = "\(scanAssets[0]) 1/\(scanAssets.count)"
        guard let session = await loadSession(allowPrompt: true, consumePendingScan: false) else {
            guard isCurrentScan(request) else { return }
            feed = .error
            candlesLoading = false
            for asset in scanAssets {
                if let generation = liveGenerations[asset] {
                    await withdrawLiveStrategyDecision(for: asset, reason: "live_credentials_unavailable",
                                                       generation: generation)
                }
            }
            if keychainState == .locked {
                candleIssue = "Saved OANDA Live credentials remain locked in Keychain. Unlock them before scanning."
                notice = "Keychain authorization was canceled or unavailable"
            } else if let credentialConfigurationError {
                candleIssue = credentialConfigurationError
                notice = "OANDA credentials could not be read from Keychain"
            } else {
                #if os(macOS)
                candleIssue = "Connect an OANDA Live account to load market data"
                #else
                candleIssue = "Connect an OANDA account to load market data"
                #endif
                notice = "OANDA credentials are missing"
            }
            return
        }
        guard isCurrentScan(request) else { return }
        if session.environment != .live {
            for asset in scanAssets {
                if let generation = liveGenerations[asset] {
                    await withdrawLiveStrategyDecision(for: asset, reason: "live_session_unavailable",
                                                       generation: generation)
                }
            }
        }
        var bag: [EngineSignal] = []
        var firstScanFailure: String?
        var scanFailures: [(asset: String, message: String)] = []
        var barsByAsset: [String: [Candle]] = [:]
        var snapshotsByAsset: [String: MarketScanSnapshot] = [:]
        var rows = book
        let attempts = await withTaskGroup(of: FXScanAttempt.self, returning: [FXScanAttempt].self) { group in
            for asset in scanAssets {
                group.addTask { [marketData] in
                    do {
                        let snapshot = try await marketData.scan(market: .fx, asset: asset, session: session)
                        return FXScanAttempt(asset: asset, snapshot: snapshot, failure: nil)
                    } catch {
                        return FXScanAttempt(asset: asset, snapshot: nil,
                                             failure: error.localizedDescription)
                    }
                }
            }
            var completed: [FXScanAttempt] = []
            for await attempt in group {
                completed.append(attempt)
                scanStep = "Markets returned \(completed.count)/\(scanAssets.count)"
            }
            return completed
        }
        guard isCurrentScan(request) else { return }
        let order = Dictionary(uniqueKeysWithValues: scanAssets.enumerated().map { ($0.element, $0.offset) })
        for attempt in attempts.sorted(by: { (order[$0.asset] ?? 0) < (order[$1.asset] ?? 0) }) {
            guard isCurrentScan(request) else { return }
            let asset = attempt.asset
            let index = order[asset] ?? 0
            scanStep = "\(asset) \(index + 1)/\(scanAssets.count)"
            let started = Date()
            if let snapshot = attempt.snapshot {
                snapshotsByAsset[asset] = snapshot
                let signal = snapshot.signal
                bag.append(signal)
                let strategyBars = snapshot.candles
                // Keep the larger session history for strategy evaluation, while
                // the desk chart and journal retain a readable rolling window.
                let bars = Array(strategyBars.suffix(120))
                barsByAsset[asset] = bars
                let orbAsOf = Self.evaluationDate(signal.asOfMs, fallback: Date())
                let orbBars = makeORBBarEvidence(asset: asset, bars: strategyBars)
                let orb = ORBBreakRetestV1.evaluate(instrument: asset, bars: orbBars, asOf: orbAsOf)
                let generation = liveGenerations[asset] ?? 0
                await publishORBDecision(orb, bars: orbBars, asOf: orbAsOf,
                    asset: asset, generation: generation)
                candleCache.store(bars, for: CandleCache.Key(market: .fx, asset: asset))
                cabinetSideByAsset[asset] = signal.cabinetSide
                var assetCommit = ScanKernel.commit(
                    from: signal,
                    bars: bars,
                    m5Bars: snapshot.m5Candles,
                    bid: snapshot.bid,
                    ask: snapshot.ask,
                    spread: snapshot.spread,
                    expirySeconds: snapshot.expirySeconds,
                    engineSHA: snapshot.engineSHA,
                    policy: snapshot.policy,
                    scannedAt: Self.evaluationDate(signal.asOfMs, fallback: started)
                )
                assetCommit.veto = snapshot.veto
                commitsByAsset[asset] = assetCommit
                rows[index] = BookRow(asset: asset, side: signal.cabinetSide)
                if signal.cabinetSide == "WAIT" {
                    trapsAvoidedCount += 1
                }
            } else {
                let message = attempt.failure ?? "Unknown market data failure"
                if firstScanFailure == nil { firstScanFailure = message }
                scanFailures.append((asset, message))
                if session.environment == .live, let generation = liveGenerations[asset] {
                    await withdrawLiveStrategyDecision(for: asset, reason: "live_scan_failed",
                                                       generation: generation)
                }
            }
            book = rows
        }
        guard isCurrentScan(request) else { return }
        guard !bag.isEmpty else {
            candlesLoading = false
            candleIssue = firstScanFailure
            notice = firstScanFailure.map { "Scan failed: \($0)" } ?? "Scan missed the book"
            feed = .error
            return
        }
        let picked = await pickedSignal(from: bag)
        guard isCurrentScan(request) else { return }
        if session.environment == .live {
            await withdrawUnselectedLiveDecisions(scanAssets: scanAssets,
                pickedAsset: picked.asset, generations: liveGenerations)
        }
        if session.environment == .practice,
           let snapshot = snapshotsByAsset[picked.asset] {
            Task { [weak self] in
                await self?.evaluateAdaptiveSnapshot(snapshot, asset: picked.asset,
                                                     signal: picked, request: request)
            }
        }
        let bars = barsByAsset[picked.asset] ?? []
        var next: ScanCommit
        if picked.why == DeskPickPolicy.unavailableWhy {
            // Do not reuse the directional cache when the picker declined. Freeze the WAIT
            // decision itself so the journal cannot inherit a stale HIGH/LOW commit.
            next = ScanKernel.commit(
                from: picked,
                bars: bars,
                scannedAt: Self.evaluationDate(picked.asOfMs, fallback: Date())
            )
        } else {
            next = commitsByAsset[picked.asset] ?? ScanKernel.commit(
                from: picked,
                bars: bars,
                scannedAt: Self.evaluationDate(picked.asOfMs, fallback: Date())
            )
        }
        let side = picked.cabinetSide
        selectedSignal = picked
        if EngineIdentity.loadedSHA1() != EngineIdentity.pinnedSHA1 {
            next.veto = "Engine pin"
        }
        let quoteBatch = await marketData.quotes(market: .fx, assets: [picked.asset], session: session)
        guard isCurrentScan(request) else { return }
        let fresh = quoteBatch.status == .ok
            ? quoteBatch.quotes.first(where: { $0.asset == picked.asset })
            : nil
        if let fresh {
            quote = fresh
            if QuoteFreshness.isFresh(fresh, now: Date()) {
                lastFreshPollAt = Date()
            }
        }
        if (side == "HIGH" || side == "LOW"), next.veto == nil {
            next.veto = EntryQuality.veto(signal: picked, quote: fresh)
        }
        if session.environment == .live {
            if let fresh, let snapshot = snapshotsByAsset[picked.asset] {
                let generation = liveGenerations[picked.asset] ?? 0
                Task { [weak self] in
                    await self?.evaluateLiveStrategyDecision(snapshot: snapshot, quote: fresh,
                                                            asset: picked.asset, request: request,
                                                            generation: generation)
                }
            } else {
                if let generation = liveGenerations[picked.asset] {
                    await withdrawLiveStrategyDecision(for: picked.asset,
                        reason: "fresh_live_quote_unavailable", generation: generation)
                }
            }
        }
        feed = FeedStatusResolver.resolve(
            marketOpen: true,
            sessionReady: true,
            transport: quoteBatch.status.oandaTransport,
            quote: fresh,
            lastFreshPollAt: lastFreshPollAt,
            now: Date()
        )
        if pair != picked.asset { liveStrategyResearchObservations = [] }
        pair = picked.asset
        commit = next
        cabinetSide = side
        candlesLoading = false
        if !bars.isEmpty {
            candles = bars
            candlesAreStale = false
        } else {
            candlesAreStale = !candles.isEmpty
        }
        candleIssue = bars.isEmpty ? "The scan returned no candles for this market" : nil
        candleCache.store(bars, for: CandleCache.Key(market: .fx, asset: picked.asset))
        commitsByAsset[picked.asset] = next
        cabinetSideByAsset[picked.asset] = side
        expired = false
        let armedClock = Date()
        armedAt = (side == "HIGH" || side == "LOW") && next.veto == nil
            ? armedClock.addingTimeInterval(-0.001)
            : nil
        if !scanFailures.isEmpty {
            let details = scanFailures.prefix(2)
                .map { "\($0.asset): \($0.message)" }
                .joined(separator: " · ")
            let remainder = scanFailures.count > 2 ? " · +\(scanFailures.count - 2) more" : ""
            notice = "Scan complete · \(scanFailures.count)/\(scanAssets.count) markets unavailable: \(details)\(remainder)"
        }
        now = armedClock
        publishFrame()
        liftHero()
        if let frame {
            let saved = await remember(next, verb: frame.verb, request: request)
            guard isCurrentScan(request) else { return }
            if !saved {
                commit?.veto = "Scan was not saved"
                armedAt = nil
                armID = nil
                notice = "Scan was not saved; scan again"
                publishFrame()
            }
        }
    }

    /// Feeds the exact FX observation already returned by the desk scan into
    /// configured strategy evaluation and the user-facing signal projection.
    /// This does not replace `ScanKernel` or submit broker orders.
    private func evaluateAdaptiveSnapshot(_ snapshot: MarketScanSnapshot,
                                          asset: String,
                                          signal: EngineSignal,
                                          request: ScanRequestScheduler.Request) async {
        guard let bid = snapshot.bid, let ask = snapshot.ask,
              let spread = snapshot.spread,
              bid.isFinite, ask.isFinite, spread.isFinite,
              !snapshot.candles.isEmpty, isCurrentScan(request),
              session?.environment == .practice else { return }
        let payloads = snapshot.candles.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time,
                open: open, high: high, low: low, close: candle.close)
        }
        guard payloads.count >= 20 else { return }
        let m5Payloads = snapshot.m5Candles.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time,
                open: open, high: high, low: low, close: candle.close)
        }
        let receivedAt = Date()
        let input = StrategyEngine.MarketInput(asset: asset, source: snapshot.source,
            candles1m: payloads, candles5m: m5Payloads,
            lastPrice: (bid + ask) / 2, bid: bid, ask: ask, spread: spread,
            expirySeconds: snapshot.expirySeconds, quoteAsOfMs: signal.asOfMs,
            evaluatedAtMs: receivedAt.timeIntervalSince1970 * 1_000,
            policy: ScanPolicy(rawValue: snapshot.policy))
        let store = ResearchStore(root: ResearchStore.defaultRoot())
        guard let result = try? await AdaptiveMarketRehearsal.evaluateSnapshot(
            input, observedAt: Self.evaluationDate(signal.asOfMs, fallback: receivedAt),
            receivedAt: receivedAt, environment: .oandaPractice, store: nil) else { return }
        guard isCurrentScan(request), session?.environment == .practice else { return }
        var persistenceFailed = false
        do {
            try await store.record(result.record)
        } catch {
            guard isCurrentScan(request) else { return }
            persistenceFailed = true
        }
        guard isCurrentScan(request), session?.environment == .practice else { return }
        adaptiveResearchProjection = AdaptiveResearchProjection(record: result.record, now: receivedAt)
#if os(macOS)
        guard let activeSession = session, activeSession.environment == .practice,
              marketMode == .fx, pair == asset else { return }
        let sourceInputIdentity = ScanInputSnapshot(pair: asset, m1: snapshot.candles,
            m5: snapshot.m5Candles, bid: bid, ask: ask, spread: spread,
            quoteAsOfMs: signal.asOfMs, expirySeconds: snapshot.expirySeconds,
            engineSHA: snapshot.engineSHA, policy: snapshot.policy).identity
        let visibleSignals = MacResearchSignalProjector.project(
            candidates: result.record.candidates, profiles: [], instrument: asset,
            scanGeneration: Int(clamping: request.generation),
            sourceInputIdentity: sourceInputIdentity, now: receivedAt, source: .oandaPractice)
        var failedFamilies = Set<MacResearchEvaluatorFamily>()
        var unavailableFamilies = Set<MacResearchEvaluatorFamily>()
        var notConfiguredFamilies = Set<MacResearchEvaluatorFamily>()
        var conditionReasons = [MacResearchEvaluatorFamily: String]()
        for outcome in result.record.evaluatorOutcomes ?? [] {
            let family: MacResearchEvaluatorFamily?
            switch outcome.strategyID {
            case "CANDIDATE_001_CHOCH_FVG_FIB": family = .candidate001
            case "CANDIDATE_002_AUCTION_FAILURE": family = .candidate002
            case GBPJPYLondonBreakRetestV1.strategyID: family = .londonBreakRetest
            case GBPJPYTrendPullbackV1.strategyID: family = .trendPullback
            case GBPJPYRangeRejectionV1.strategyID: family = .rangeRejection
            default: family = nil
            }
            guard let family else { continue }
            switch outcome.state {
            case .failed: failedFamilies.insert(family)
            case .dataUnavailable: unavailableFamilies.insert(family)
            case .notConfigured: notConfiguredFamilies.insert(family)
            case .conditionsNotMet:
                conditionReasons[family] = outcome.rawDiagnostics?.first?.reasonCode ?? outcome.reasonCode
            case .completed: break
            }
        }
        let diagnostics = MacResearchEvaluationDiagnosticProjector.project(
            candidates: result.record.candidates, failedFamilies: failedFamilies,
            unavailableFamilies: unavailableFamilies, notConfiguredFamilies: notConfiguredFamilies,
            conditionsNotMetReasons: conditionReasons,
            visibleSignalIDs: Set(visibleSignals.map(\.id)),
            quoteAsOf: signal.asOfMs.flatMap {
                $0.isFinite ? Date(timeIntervalSince1970: $0 / 1_000) : nil
            },
            scanGeneration: Int(clamping: request.generation),
            currentScanGeneration: Int(clamping: request.generation),
            sourceInputIdentity: sourceInputIdentity,
            expectedSourceInputIdentity: sourceInputIdentity, now: receivedAt)
        guard isCurrentScan(request), session?.environment == .practice, pair == asset else { return }
        macResearchSignals = visibleSignals
        macResearchEvaluationDiagnostics = diagnostics
        updateMacResearchSignalStatus()
        scheduleMacResearchSignalExpiry()
        if persistenceFailed {
            notice = "Signal evaluation is visible, but this scan could not be saved to history"
        }
#endif
        if let candidate = result.record.decision.selectedCandidateID.flatMap({ id in
            result.record.candidates.first { $0.id == id }
        }), let notification = AdaptiveNotificationPlanner.plan(
            state: result.record.decisionState, selectedCandidate: candidate,
            instrument: result.record.instrument, sourceTime: result.record.observedAt,
            now: receivedAt) {
            _ = await MarketNotificationService.shared.scheduleAdaptiveNotification(notification,
                                                                                       now: receivedAt)
        }
    }

    /// Runs all existing V1 policy variants against the exact Live snapshot and
    /// combines their directional votes with the structural ORB candidate.
    /// This produces only a strategy decision; it never crosses the order API.
    private func evaluateLiveStrategyDecision(snapshot: MarketScanSnapshot, quote: LiveQuote,
                                             asset: String,
                                             request: ScanRequestScheduler.Request,
                                             generation: UInt64) async {
        guard isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        guard quote.asset == asset,
              quote.bid.isFinite, quote.ask.isFinite, quote.ask > quote.bid,
              quote.bid > 0, quote.mid.isFinite,
              QuoteFreshness.isFresh(quote, now: Date()),
              !snapshot.candles.isEmpty else {
            await withdrawLiveStrategyDecision(for: asset,
                reason: quote.asset == asset ? "fresh_live_quote_unavailable" : "live_strategy_snapshot_invalid",
                generation: generation)
            return
        }
        let payloads = snapshot.candles.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time, open: open, high: high,
                                                low: low, close: candle.close)
        }
        guard payloads.count >= 20 else {
            await withdrawLiveStrategyDecision(for: asset,
                reason: "insufficient_completed_candles", generation: generation)
            return
        }
        let m5Payloads = snapshot.m5Candles.compactMap { candle -> StrategyEngine.CandlePayload? in
            guard let time = candle.time, let open = candle.open,
                  let high = candle.high, let low = candle.low else { return nil }
            return StrategyEngine.CandlePayload(time: time, open: open, high: high,
                                                low: low, close: candle.close)
        }
        guard !m5Payloads.isEmpty else {
            await withdrawLiveStrategyDecision(for: asset,
                reason: "live_m5_candles_unavailable", generation: generation)
            return
        }
        let receivedAt = Date()
        let input = StrategyEngine.MarketInput(asset: asset, source: "oanda-live",
            candles1m: payloads, candles5m: m5Payloads,
            lastPrice: quote.mid, bid: quote.bid, ask: quote.ask,
            spread: quote.ask - quote.bid, expirySeconds: snapshot.expirySeconds,
            quoteAsOfMs: quote.asOfMs, evaluatedAtMs: receivedAt.timeIntervalSince1970 * 1_000,
            policy: .baseline)
        let evaluation = await selectLiveStrategySelection(input: input, asset: asset)
        guard isCurrentScan(request), isCurrentLiveDecisionRefresh(generation, for: asset) else { return }
        await publishMacResearchSignals(evaluation, instrument: asset, generation: generation,
            sourceInputIdentity: ScanInputSnapshot(pair: asset, m1: snapshot.candles,
                m5: snapshot.m5Candles, bid: quote.bid, ask: quote.ask,
                spread: quote.ask - quote.bid, quoteAsOfMs: quote.asOfMs,
                expirySeconds: snapshot.expirySeconds,
                engineSHA: snapshot.engineSHA, policy: snapshot.policy).identity,
            quoteAsOfMs: quote.asOfMs)
        await publishLiveStrategySelection(evaluation.selection, asset: asset, generation: generation)
        publishFrame()
    }

    private func selectLiveStrategySelection(input: StrategyEngine.MarketInput,
                                             asset: String) async -> LiveStrategyEvaluation {
        let receivedAt = Date()
        var candidates: [AdaptiveOpportunityCandidate] = []
        var candidate001Failed = false
        var candidate002Failed = false
        for policy in ScanPolicy.allCases {
            do {
                candidates.append(try await AdaptiveOpportunityAdapters.evaluateEngine(input, policy: policy))
            } catch {
                continue
            }
        }
        switch AdaptiveOpportunityAdapters.evaluateCandidate001Result(input, asOf: receivedAt,
                                                                        startedAt: receivedAt) {
        case .completed(let results): candidates.append(contentsOf: results)
        case .failed:
            candidate001Failed = true
        }
        switch AdaptiveOpportunityAdapters.evaluateCandidate002Result(input, asOf: receivedAt,
                                                                        startedAt: receivedAt) {
        case .completed(let results): candidates.append(contentsOf: results)
        case .failed:
            candidate002Failed = true
        }
        candidates.append(AdaptiveOpportunityAdapters.evaluateORB(input, asOf: receivedAt,
                                                                   startedAt: receivedAt))
        let selection = LiveStrategySelector.evaluate(instrument: asset, candidates: candidates,
            now: Date(), profiles: liveStrategyProfiles, promotionRecords: strategyPromotionRecords)
        return LiveStrategyEvaluation(selection: selection, candidates: candidates,
            candidate001Failed: candidate001Failed, candidate002Failed: candidate002Failed)
    }

    private func publishMacResearchSignals(_ evaluation: LiveStrategyEvaluation,
                                           instrument: String, generation: UInt64,
                                           sourceInputIdentity: String,
                                           quoteAsOfMs: Double?) async {
#if os(macOS)
        guard isCurrentLiveDecisionRefresh(generation, for: instrument), pair == instrument else { return }
        macResearchExpiryTask?.cancel()
        macResearchSignals = []
        macResearchEvaluationDiagnostics = []
        guard marketMode == .fx, pair == instrument else {
            macResearchSignalStatus = .awaitingFreshScan
            return
        }
        guard macResearchSourceAttestationVerified else {
            macResearchSignalStatus = .sourceAttestationUnavailable
            return
        }
        let signals = MacResearchSignalProjector.project(candidates: evaluation.candidates,
            profiles: macResearchProfilesBound(to: instrument), instrument: instrument,
            scanGeneration: Int(clamping: generation), sourceInputIdentity: sourceInputIdentity,
            now: Date())
        var failedFamilies = Set<MacResearchEvaluatorFamily>()
        if evaluation.candidate001Failed { failedFamilies.insert(.candidate001) }
        if evaluation.candidate002Failed { failedFamilies.insert(.candidate002) }
        let diagnostics = MacResearchEvaluationDiagnosticProjector.project(
            candidates: evaluation.candidates, failedFamilies: failedFamilies,
            visibleSignalIDs: Set(signals.map(\.id)),
            quoteAsOf: quoteAsOfMs.flatMap {
                $0.isFinite ? Date(timeIntervalSince1970: $0 / 1_000) : nil
            },
            scanGeneration: Int(clamping: generation),
            currentScanGeneration: Int(clamping: liveDecisionGeneration.latestGeneration(for: instrument) ?? 0),
            sourceInputIdentity: sourceInputIdentity,
            expectedSourceInputIdentity: sourceInputIdentity,
            now: Date())
        guard isCurrentLiveDecisionRefresh(generation, for: instrument), pair == instrument else { return }
        macResearchSignals = signals
        macResearchEvaluationDiagnostics = diagnostics
        updateMacResearchSignalStatus()
        scheduleMacResearchSignalExpiry()
#endif
    }

#if os(macOS)
    private func updateMacResearchSignalStatus() {
        if macResearchEvaluationDiagnostics.contains(where: { $0.state == .dataUnavailable }) {
            macResearchSignalStatus = .partialResults
        } else if !macResearchSignals.isEmpty
            || macResearchEvaluationDiagnostics.contains(where: {
                $0.state == .candidateShown || $0.state == .candidateWithheld
            }) {
            macResearchSignalStatus = .completedWithCandidates
        } else if macResearchEvaluationDiagnostics.contains(where: { $0.state == .evaluationFailed }) {
            macResearchSignalStatus = .failed
        } else if macResearchEvaluationDiagnostics.contains(where: { $0.state == .conditionsNotMet }) {
            macResearchSignalStatus = .conditionsNotMet
        } else if macResearchEvaluationDiagnostics.isEmpty {
            macResearchSignalStatus = .awaitingFreshScan
        } else {
            macResearchSignalStatus = .completedNoCandidate
        }
    }

    private func scheduleMacResearchSignalExpiry() {
        let deadline = (macResearchSignals.map(\.validUntil)
            + macResearchEvaluationDiagnostics.map(\.validUntil)).min()
        guard let deadline else { return }
        let delay = max(0, deadline.timeIntervalSinceNow)
        macResearchExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(min(delay, 86_400) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.macResearchSignals = self.macResearchSignals.filter { Date() <= $0.validUntil }
            self.macResearchEvaluationDiagnostics = self.macResearchEvaluationDiagnostics.filter {
                Date() <= $0.validUntil
            }
            self.updateMacResearchSignalStatus()
            if !self.macResearchSignals.isEmpty || !self.macResearchEvaluationDiagnostics.isEmpty {
                self.scheduleMacResearchSignalExpiry()
            }
        }
    }

    private func macResearchProfilesBound(to instrument: String) -> [StrategyResearchProfile] {
        liveStrategyProfiles.map { profile in
            guard profile.decisionRole == .shadow,
                  profile.configurationSHA256ByInstrument?[instrument] == nil,
                  let identity = profile.acceptedCandidateIdentities.first(where: {
                      AdaptiveOpportunityAdapters.effectiveConfiguration(
                          strategyID: $0.strategyID, instrument: instrument) != nil
                  }),
                  let digest = AdaptiveOpportunityAdapters.effectiveConfiguration(
                      strategyID: identity.strategyID, instrument: instrument)?.sha256() else {
                return profile
            }
            return StrategyResearchProfile(id: profile.id, version: profile.version,
                family: profile.family, status: profile.status,
                sourceReferences: profile.sourceReferences,
                mayAuthorizeOrder: profile.mayAuthorizeOrder, decisionRole: profile.decisionRole,
                acceptedCandidateIdentities: profile.acceptedCandidateIdentities,
                configurationSHA256: profile.configurationSHA256,
                configurationSHA256ByInstrument: [instrument: digest],
                selectorPolicySHA256: profile.selectorPolicySHA256,
                evaluatorCodeSHA256: profile.evaluatorCodeSHA256,
                adapterCodeSHA256: profile.adapterCodeSHA256,
                selectorCodeSHA256: profile.selectorCodeSHA256)
        }
    }
#endif

    private func publishLiveStrategySelection(_ selection: LiveStrategySelection,
                                              asset: String, generation: UInt64) async {
        guard isCurrentLiveDecisionRefresh(generation, for: asset), pair == asset,
              marketMode == .fx else { return }
        liveStrategyResearchObservations = selection.researchObservations
        await publishLiveStrategyDecision(selection.decision, asset: asset, generation: generation)
    }

    /// Records the expired arm once, then leaves the hero. A second call does not append.
    public func settle(
        _ outcome: DeskOutcome,
        expiryPrice: Double? = nil,
        entryQuote: Double? = nil,
        labelSource: String = "manual-unverified"
    ) async {
        guard !settlementInFlight,
              let settleCommit = commit,
              let settleArmID = armID,
              activeTrade == nil,
              let expiry = pendingExpiry,
              Date() >= expiry.targetExpiry
        else { return }
        settlementInFlight = true
        defer { settlementInFlight = false }
        awaitingOutcome = false
        pendingLabelSource = labelSource
        pendingOutcome = outcome

        // Capture a fully self-contained settlement record before any await. Nothing below
        // reads mutable desk state that a later task could change.
        let trade = pendingTrade
        let windowName = MarketEdgeWindow.current(at: trade?.enteredAt ?? settleCommit.scannedAt).badgeTitle
        let resolvedEntryQuote = entryQuote ?? trade?.brokerEntryPrice
        let resolvedExpiryPrice = expiryPrice ?? expiry.exitPrice
        let horizonSeconds = trade.map { Int($0.durationSec) }
        let enteredAt = trade?.enteredAt
        let expiryObservedMs = expiry.quoteTimeMs
        let evaluationAgeMs = trade?.evaluationAgeMs
        let recordingDelayMs = trade?.recordingDelayMs
        let remainingBeamMs = trade?.remainingBeamMs
        let row = LedgerRow(
            timestamp: Date(),
            pair: settleCommit.asset,
            hash: settleCommit.fingerprint,
            score: settleCommit.score,
            side: settleCommit.engineCall,
            veto: settleCommit.veto != nil,
            drift: settleCommit.driftPips ?? 0,
            outcome: outcome.rawValue,
            outcomeEventID: settleArmID,
            payout: trade?.payout,
            stake: trade?.stake,
            marketWindow: windowName,
            engineSHA: settleCommit.engineSHA,
            fullFingerprint: settleCommit.fullFingerprint,
            entryQuote: resolvedEntryQuote,
            expiryPrice: resolvedExpiryPrice,
            labelSource: labelSource,
            horizonSeconds: horizonSeconds,
            enteredAt: enteredAt,
            expiryObservedMs: expiryObservedMs,
            evaluationAgeMs: evaluationAgeMs,
            recordingDelayMs: recordingDelayMs,
            remainingBeamMs: remainingBeamMs
        )
        let snapshot = SnapshotRecord(
            hash: settleCommit.fingerprint,
            fullFingerprint: settleCommit.fullFingerprint,
            pair: settleCommit.asset,
            bars: settleCommit.candles,
            m5Bars: settleCommit.m5Candles,
            bid: settleCommit.bid,
            ask: settleCommit.ask,
            spread: settleCommit.spread,
            expirySeconds: settleCommit.expirySeconds,
            engineSHA: settleCommit.engineSHA,
            policy: settleCommit.policy,
            strike: settleCommit.strike,
            score: settleCommit.score,
            side: settleCommit.engineCall
        )
        do {
            let wrote = try await persistence.settle(armID: settleArmID, row: row, snapshot: snapshot)
            if !wrote {
                let restored = await persistence.restore()
                guard restored.entries.first(where: { $0.id == settleArmID })?.outcome != nil else {
                    awaitingOutcome = true
                    pendingSaveCount = await persistence.pendingSettlements().count
                    notice = "Outcome was not saved; retry"
                    return
                }
            }
            try? await persistence.clearOpenPosition()
            await reloadFromDisk()
        } catch {
            awaitingOutcome = true
            pendingSaveCount = await persistence.pendingSettlements().count
            notice = "Outcome was not saved; retry"
            return
        }
        pendingSaveCount = await persistence.pendingSettlements().count
        pendingOutcome = nil
        pendingLabelSource = "manual-unverified"
        notice = nil
        guard self.armID == settleArmID else { return }

        // Show closure before the desk clears. The ledger row is already durable at this point.
        let receiptPips: Double? = {
            guard let exit = resolvedExpiryPrice else { return nil }
            let pip = Assets.pipScale(for: settleCommit.asset)
            guard pip > 0 else { return nil }
            let signed = settleCommit.engineCall.contains("HIGH")
                ? exit - settleCommit.strike
                : settleCommit.strike - exit
            return signed / pip
        }()
        showSettleReceipt(
            SettleReceipt(
                outcome: outcome,
                pair: settleCommit.asset,
                pips: receiptPips,
                payout: trade?.payout ?? EntryQuality.assumedPayout,
                labelSource: labelSource
            )
        )
        DeskHaptics.outcomeConfirmed(outcome)

        self.armID = nil
        self.commit = nil
        cabinetSide = "WAIT"
        armedAt = nil
        expired = false
        activeTrade = nil
        activeTradeQuote = nil
        activeEntryArmedAt = nil
        pendingTrade = nil
        pendingExpiry = nil
        predictedOutcome = nil
        candles = []
        publishFrame()
    }

    private func showSettleReceipt(_ receipt: SettleReceipt) {
        receiptDismissTask?.cancel()
        settleReceipt = receipt
        receiptDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            self?.settleReceipt = nil
        }
    }

    public func dismissSettleReceipt() {
        receiptDismissTask?.cancel()
        settleReceipt = nil
    }

    /// The only path that records a broker outcome: the user confirms the real venue result.
    /// Reference observations stay labelled as reference.
    public func confirmVenueOutcome(_ outcome: DeskOutcome) async {
        let source: String
        switch outcome {
        case .hit, .miss: source = "venue-confirmed"
        case .unresolved: source = "operator-unsure"
        }
        await settle(outcome, labelSource: source)
    }

    /// Retries a settlement that failed to save. Never invents or changes the outcome.
    public func retryPendingSettlement() async {
        guard !settlementInFlight else { return }
        if let pendingOutcome {
            await settle(
                pendingOutcome,
                expiryPrice: pendingExpiry?.exitPrice,
                entryQuote: pendingTrade?.brokerEntryPrice,
                labelSource: pendingLabelSource
            )
            return
        }
        settlementInFlight = true
        defer { settlementInFlight = false }
        let issues = await persistence.reconcilePendingSettlements()
        pendingSaveCount = await persistence.pendingSettlements().count
        if issues.isEmpty {
            notice = nil
            await reloadFromDisk()
            clearDeskIfResolved()
        } else {
            notice = "Outcome still not saved; check storage"
        }
    }

    /// Empirical statistics computed directly from the local ledger for any pair.
    public func edgeStats(for asset: String) -> PairEdgeStats {
        LedgerStatsEngine.evaluate(pair: asset, rows: ledgerRows, payoutRatio: 0.88)
    }

    /// Reference suggestion for the arm awaiting confirmation. Prefers the in-memory expiry
    /// observation, then the persisted reference history so a relaunch does not lose it.
    /// This is an OANDA midpoint label, never a venue settlement.
    public var referenceSuggestion: DeskOutcome? {
        if let predictedOutcome { return predictedOutcome }
        guard let armID else { return nil }
        return referenceOutcomes.last(where: { $0.eventID == armID })?.deskSuggestion
    }

    /// Frozen entry fields for the settle panel. The commit itself stays private.
    public var settleAsset: String? { commit?.asset }
    public var settleStrike: Double? { commit?.strike }
    public var settleSide: String? { commit?.engineCall }

    /// Reference exit price for the arm awaiting confirmation. Falls back to the persisted
    /// reference history so the settle panel still shows numbers after a relaunch.
    public var expiryReferencePrice: Double? {
        if let price = pendingExpiry?.exitPrice { return price }
        guard let armID else { return nil }
        return referenceOutcomes.last(where: { $0.eventID == armID })?.exitPrice
    }

    /// Signed pips from strike, positive when the selected side finished in the money.
    public var expiryReferenceDeltaPips: Double? {
        guard let price = expiryReferencePrice, let commit else { return nil }
        let pip = Assets.pipScale(for: commit.asset)
        guard pip > 0 else { return nil }
        let signed = commit.engineCall.contains("HIGH") ? price - commit.strike : commit.strike - price
        return signed / pip
    }

    /// Why the desk can or cannot suggest a result. Shown above the HIT/MISS buttons.
    public var referenceSuggestionNote: String? {
        guard let armID else { return nil }
        if let suggestion = referenceSuggestion {
            return "Reference suggests \(suggestion.rawValue). Confirm what the venue settled."
        }
        guard let observation = referenceOutcomes.last(where: { $0.eventID == armID }) else {
            return "No reference observation was captured. Confirm the venue result."
        }
        switch observation.resolution {
        case .tie:
            return "Expiry tied at the reference mid. Confirm the venue result."
        case .unresolved:
            let reason = observation.reason ?? "quote unavailable"
            return "No timely expiry print (\(reason)). Confirm the venue result."
        default:
            return "Confirm the venue result."
        }
    }

    /// Reference observations that belong to a desk entry. These are OANDA midpoint results,
    /// not venue settlements, and are excluded from `outcomeStats`.
    public var referenceHistory: [ResearchOutcome] {
        let ids = Set(journal.map(\.id))
        return referenceOutcomes
            .filter { ids.contains($0.eventID) }
            .sorted { $0.targetExpiry > $1.targetExpiry }
    }

    /// Empirical average drift in pips computed from local settled trades.
    public func averageDrift(for asset: String) -> Double? {
        let settled = ledgerRows.filter { $0.pair == asset && ($0.outcome == "HIT" || $0.outcome == "MISS") }
        guard !settled.isEmpty else { return nil }
        let sum = settled.reduce(0.0) { $0 + $1.drift }
        return sum / Double(settled.count)
    }

    /// Engine pick. If the desk pick is unavailable, stay on WAIT. Never invent HIGH or LOW.
    private func pickedSignal(from bag: [EngineSignal]) async -> EngineSignal {
        guard let base = bag.first else {
            return DeskPickPolicy.unavailable(
                asset: "—",
                price: 0,
                asOfMs: nil,
                source: "unavailable"
            )
        }
        do {
            let desk = try await StrategyEngine.pickDesk(
                signals: bag,
                trades: [],
                payoutPercent: EntryQuality.assumedPayout * 100,
                preferAsset: nil
            )
            if let asset = desk.asset, let match = bag.first(where: { $0.asset == asset }) {
                return match
            }
            // The JS picker declined every candidate (for example, all were stale).
            // That decision is authoritative: do not recover a direction in Swift.
            return DeskPickPolicy.unavailable(basedOn: base)
        } catch {
            return DeskPickPolicy.unavailable(basedOn: base)
        }
    }

    private var credentialLookup: CredentialGate?

    /// One keychain pass. A prompt happens only when Scan asks for it, on the main actor.
    private func loadSession(allowPrompt: Bool, consumePendingScan: Bool = true) async -> OandaSession? {
        if let session { return session }
        if credentialLookup == nil {
            credentialLookup = await Task.detached(priority: .userInitiated) {
                DeskCredentials.session(allowPrompt: false)
            }.value
        }
        switch credentialLookup {
        case .ready(let ready):
            session = ready
            keychainState = .ready
            if consumePendingScan { await consumePendingScanIfReady() }
            return ready
        case .locked where allowPrompt:
            let prompted = DeskCredentials.session(allowPrompt: true)
            credentialLookup = prompted
            if case .ready(let ready) = prompted {
                session = ready
                keychainState = .ready
                if consumePendingScan { await consumePendingScanIfReady() }
                return ready
            }
            noteKeychain(prompted)
            return nil
        case .locked:
            keychainState = .locked
            return nil
        case .missing:
            keychainState = .missing
            return nil
        case .invalid(let message):
            keychainState = .missing
            credentialConfigurationError = message
            return nil
        case .none:
            return nil
        }
    }

    /// Saves this device's Keychain and drops the fields from the caller. Does not log the token.
    public func storeCredentials(token: String, accountId: String, environment: OandaEnvironment) -> Bool {
        guard DeskCredentials.store(token: token, accountId: accountId, environment: environment) else {
            return false
        }
        let ready = OandaSession(token: token, accountId: accountId, environment: environment)
        session = ready
        credentialLookup = .ready(ready)
        keychainState = .ready
        isDemoDesk = false
        draftToken = ""
        draftAccount = ""
        credentialSaveFailed = false
        isEditingCredentials = false
        candleIssue = nil
        Task { await loadCandles(for: pair, force: true) }
        Task { await consumePendingScanIfReady() }
        return true
    }

    private func noteKeychain(_ gate: CredentialGate) {
        switch gate {
        case .ready:
            keychainState = .ready
        case .locked:
            keychainState = .locked
        case .missing:
            keychainState = .missing
        case .invalid(let message):
            keychainState = .missing
            credentialConfigurationError = message
        }
    }

    /// A Siri scan is a request to open the existing walk. It does not choose a side.
    /// Returns true when a pending request was consumed.
    @discardableResult
    private func consumePendingScanIfReady() async -> Bool {
        #if os(iOS)
        guard backgroundedAt == nil, !scanning, activeTrade == nil,
              !awaitingOutcome, !settlementInFlight,
              scanCoordinator.isIdle else { return false }
        guard takePendingScanRequest() else { return false }
        await scan()
        return true
        #else
        return false
        #endif
    }

    /// Consumes the Siri pending request exactly once. Internal so the cached-session path
    /// can be regression-tested without launching a network scan.
    @discardableResult
    func takePendingScanRequest() -> Bool {
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        guard defaults?.bool(forKey: PhoneTarget.pendingScanKey) == true else { return false }
        defaults?.set(false, forKey: PhoneTarget.pendingScanKey)
        return true
    }

    private func diagLog(_ message: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLAZER_DIAG"] == "1" {
            // stderr is unbuffered, so the line survives an abrupt kill.
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        #endif
    }

    /// Journal time is when the engine evaluated, not when a six-pair walk happened to end.
    /// A future or absent timestamp falls back to the local clock.
    static func evaluationDate(_ asOfMs: Double?, fallback: Date) -> Date {
        guard let asOfMs, asOfMs.isFinite, asOfMs > 0 else { return fallback }
        let date = Date(timeIntervalSince1970: asOfMs / 1000)
        return date > fallback.addingTimeInterval(5) ? fallback : date
    }

    static func message(for failure: EntryGateFailure) -> String {
        switch failure {
        case .expiredBeam: return "Beam expired; scan again"
        case .staleFeed: return "Entry quote stale or unavailable"
        case .vetoed(let reason): return reason
        case .notDirectional: return "No directional setup"
        case .historical: return "Previous scan restored. SCAN for current market evidence before entry."
        case .activePositionExists: return "Resolve the current position before entry"
        case .noArmedBeam: return "No armed beam to enter"
        case .unsupportedExpiry: return "Unsupported expiry"
        }
    }

    private func liftHero() {
        heroLift = -4
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            heroLift = 0
        }
    }

    private func quoteLoop() async {
        while !Task.isCancelled {
            if !scanning {
                await refreshActiveTradeQuote()
                await refreshQuote()
            }
            try? await Task.sleep(nanoseconds: UInt64(Timing.quotePollMs * 1_000_000))
        }
    }

    /// Live crypto price loop. Runs while crypto is selected or an entry is still open.
    private func cryptoQuoteLoop() async {
        while !Task.isCancelled {
            if !scanning, marketMode == .crypto || activeTrade != nil {
                await refreshActiveTradeQuote()
                if marketMode == .crypto {
                    await refreshCryptoQuote()
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// The active manual entry owns its pair. It keeps updating while the user browses,
    /// switches markets, or returns from another app.
    private func refreshActiveTradeQuote() async {
        guard let trade = activeTrade else {
            activeTradeQuote = nil
            return
        }
        let fresh: LiveQuote?
        if CTAssets.watchlist.contains(trade.pair) {
            let batch = await marketData.quotes(market: .crypto, assets: [trade.pair], session: nil)
            fresh = batch.status == .ok
                ? batch.quotes.first(where: { $0.asset == trade.pair })
                : nil
        } else if let session = await loadSession(allowPrompt: false) {
            let batch = await marketData.quotes(market: .fx, assets: [trade.pair], session: session)
            fresh = batch.status == .ok
                ? batch.quotes.first(where: { $0.asset == trade.pair })
                : nil
        } else {
            fresh = nil
        }
        guard let fresh, fresh.asset == trade.pair,
              fresh.bid.isFinite, fresh.ask.isFinite, fresh.mid.isFinite,
              fresh.bid > 0, fresh.ask > fresh.bid else {
            return
        }
        guard let current = activeTrade,
              current.id == trade.id, current.pair == trade.pair else { return }
        if let existing = activeTradeQuote, existing.asset == fresh.asset,
           existing.asOfMs > fresh.asOfMs { return }
        activeTradeQuote = fresh
        activeTrade?.currentPrice = fresh.mid
    }

    private func refreshCryptoQuote() async {
        guard marketMode == .crypto, CTAssets.watchlist.contains(pair) else { return }
        let clock = Date()
        let batch = await marketData.quotes(market: .crypto, assets: [pair], session: nil)
        guard batch.status == .ok,
              let fresh = batch.quotes.first(where: { $0.asset == pair }) else {
            // A failed poll must never leave a stale LIVE badge on screen.
            let state = CryptoFeedHealth.state(
                connected: false,
                everReceivedTick: lastFreshPollAt != nil,
                lastTickAt: lastFreshPollAt,
                now: clock
            )
            feed = CryptoFeedHealth.feedStatus(for: state)
            publishFrame()
            return
        }
        if fresh.asset == pair {
            quote = fresh
            if QuoteFreshness.isFresh(fresh, now: clock) {
                lastFreshPollAt = clock
            }
        }
        let state = CryptoFeedHealth.state(
            connected: true,
            everReceivedTick: lastFreshPollAt != nil,
            lastTickAt: lastFreshPollAt,
            now: clock
        )
        feed = CryptoFeedHealth.feedStatus(for: state)
        if let trade = activeTrade, fresh.asset == trade.pair {
            activeTrade?.currentPrice = fresh.mid
        }
        publishFrame()
    }

    private func beamLoop() async {
        while !Task.isCancelled {
            if armedAt != nil || activeTrade != nil {
                now = Date()
                if let trade = activeTrade, trade.isExpired {
                    await handleTradeExpiry(trade)
                }
                publishFrame()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Locks in an active binary trade horizon on the armed setup (60s, 3m, or 5m).
    /// The recovery copy is written before the desk treats the entry as tracked.
    /// Records a manual entry. `late` skips the actionable-beam check for data capture after
    /// the eight-second action window; the delay is still recorded so research can flag it.
    public func lockInTrade(
        duration: Double? = nil,
        late: Bool = false,
        actualEntryTime: Date? = nil
    ) async {
        guard !entryInFlight else { return }

        if late {
            guard canLogLateEntry else {
                entryIssue = "Nothing to log. Scan again before recording."
                DeskHaptics.veto()
                return
            }
        } else {
            let context = DeskEntryGate.Context(
                commit: commit,
                frame: frame,
                signal: selectedSignal,
                quote: quote,
                lastFreshPollAt: lastFreshPollAt,
                activeTrade: activeTrade,
                awaitingOutcome: awaitingOutcome,
                settlementInFlight: settlementInFlight,
                scanning: scanning,
                historical: historical,
                armedAt: armedAt,
                armID: armID
            )
            if let failure = DeskEntryGate.veto(context) {
                entryIssue = Self.message(for: failure)
                DeskHaptics.veto()
                if let commit, let armID {
                    await saveExecutionObservation(ExecutionObservation(armID: armID, commit: commit,
                        quote: quote, kind: "rejected", reason: Self.message(for: failure), regime: selectedSignal?.features?.regime))
                }
                return
            }
        }

        guard let commit, let selectedSignal, selectedSignal.asset == commit.asset else {
            entryIssue = "Nothing to log. Scan again before recording."
            DeskHaptics.veto()
            return
        }
        let liveQuote = quote.flatMap { $0.asset == commit.asset ? $0 : nil }
        let liveStrike: Double
        if late {
            // A current quote is not the historical broker fill. Keep the frozen reference
            // separate; brokerEntryPrice remains nil unless the user supplies it.
            liveStrike = commit.strike
        } else {
            guard let liveQuote else {
                entryIssue = Self.message(for: .staleFeed)
                DeskHaptics.veto()
                return
            }
            liveStrike = liveQuote.mid
        }
        let signalSide = selectedSignal.cabinetSide
        guard signalSide == "HIGH" || signalSide == "LOW" else {
            entryIssue = Self.message(for: .notDirectional)
            DeskHaptics.veto()
            return
        }
        let durationSec = duration ?? selectedHorizonSec
        guard [60.0, 180.0, 300.0, 600.0].contains(durationSec) else {
            entryIssue = "Unsupported expiry"
            DeskHaptics.veto()
            return
        }

        entryInFlight = true
        defer { entryInFlight = false }

        let recordedAt = Date()
        let enteredAt: Date
        if late {
            guard let actualEntryTime,
                  actualEntryTime.timeIntervalSince1970.isFinite,
                  actualEntryTime >= commit.scannedAt,
                  actualEntryTime <= recordedAt else {
                entryIssue = "Actual broker entry time is required for late logging"
                DeskHaptics.veto()
                return
            }
            enteredAt = actualEntryTime
        } else {
            enteredAt = recordedAt
        }
        let tradeID = armID ?? "\(commit.fingerprint)-\(Int(recordedAt.timeIntervalSince1970 * 1000))"
        let armedReference = armedAt ?? commit.scannedAt
        let recordingDelayMs = max(0, enteredAt.timeIntervalSince(armedReference) * 1000)
        let evaluationAgeMs = max(0, enteredAt.timeIntervalSince(commit.scannedAt) * 1000)
        let remainingBeamMs = late ? 0 : max(0, Timing.liveMs - recordingDelayMs)
        let trade = ActiveTrade(
            id: tradeID,
            pair: commit.asset,
            side: signalSide,
            strike: liveStrike,
            score: commit.score,
            enteredAt: enteredAt,
            durationSec: durationSec,
            currentPrice: liveQuote?.mid ?? liveStrike,
            brokerEntryPrice: nil,
            evaluationAgeMs: evaluationAgeMs,
            remainingBeamMs: remainingBeamMs,
            recordingDelayMs: recordingDelayMs,
            fingerprint: commit.fingerprint
        )
        activeEntryArmedAt = armedAt
        armID = tradeID
        guard await persistOpenPosition(trade, commit: commit, armID: tradeID) else {
            entryIssue = "Could not save the entry; position not tracked"
            DeskHaptics.veto()
            return
        }
        let entryObservation = ExecutionObservation(armID: tradeID, commit: commit,
            quote: liveQuote, kind: "manual-entry", regime: selectedSignal.features?.regime,
            now: recordedAt)
        activeTrade = trade
        activeTradeQuote = liveQuote
        pendingTrade = trade
        pendingExpiry = nil
        armedAt = nil
        entryIssue = nil
        DeskHaptics.tradeLocked()
        publishFrame()
        await saveExecutionObservation(entryObservation)
    }

    /// True when a signal still exists but the eight-second action window has closed, so the
    /// entry can be recorded for data without claiming it was actionable.
    public var canLogLateEntry: Bool {
        Self.canLogLateEntry(
            commit: commit,
            signal: selectedSignal,
            activeTrade: activeTrade,
            awaitingOutcome: awaitingOutcome,
            settlementInFlight: settlementInFlight,
            scanning: scanning,
            historical: historical,
            now: Date()
        )
    }

    /// Records that a broker trade was reported but its actual execution time is unknown.
    /// This is a research gap, not an active trade, so no expiry or outcome is fabricated.
    public func recordUnknownLateEntryTime() async {
        guard canLogLateEntry, let commit, let signal = selectedSignal,
              signal.asset == commit.asset else {
            entryIssue = "This signal is no longer available for late evidence"
            return
        }
        let id = armID ?? "\(commit.fingerprint)-unknown-entry-time"
        await saveExecutionObservation(ExecutionObservation(
            armID: id, commit: commit, quote: nil,
            kind: "late-entry-unknown-time",
            reason: "Broker trade reported without actual execution timestamp",
            regime: signal.features?.regime))
        entryIssue = "Recorded as incomplete evidence; no expiry was inferred"
    }

    /// Pure decision so the window and safety conditions are testable without a live desk.
    nonisolated public static func canLogLateEntry(
        commit: ScanCommit?,
        signal: EngineSignal?,
        activeTrade: ActiveTrade?,
        awaitingOutcome: Bool,
        settlementInFlight: Bool,
        scanning: Bool,
        historical: Bool,
        now: Date
    ) -> Bool {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight, !scanning, !historical else {
            return false
        }
        guard let commit, commit.veto == nil, let signal,
              signal.asset == commit.asset else { return false }
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return false }
        let call = commit.engineCall.uppercased()
        if signal.cabinetSide == "HIGH", !call.contains("HIGH"), !call.contains("CALL") { return false }
        if signal.cabinetSide == "LOW", !call.contains("LOW"), !call.contains("PUT") { return false }
        // Bound the window: an old scan is not a trade the operator just placed.
        return now.timeIntervalSince(commit.scannedAt) <= 10 * 60
    }

    /// Optional broker details supplied by the user after placing the manual trade.
    /// Missing values remain missing; nothing is inferred.
    public func updateActiveEntryDetails(
        brokerEntryPrice: Double?,
        stake: Double?,
        payout: Double?
    ) async {
        guard var trade = activeTrade, let commit else { return }
        trade.brokerEntryPrice = brokerEntryPrice
        trade.stake = stake
        trade.payout = payout
        activeTrade = trade
        pendingTrade = trade
        if await persistOpenPosition(trade, commit: commit, armID: trade.id) {
            notice = "Broker details saved locally."
        } else {
            notice = "Broker details were not saved; retry."
        }
    }

    /// The position is durable before the desk treats it as tracked. A write failure is
    /// reported and the entry is refused rather than tracked without a recovery copy.
    private func persistOpenPosition(_ trade: ActiveTrade, commit: ScanCommit, armID: String) async -> Bool {
        let record = ActivePositionRecord(
            armID: armID,
            trade: trade,
            fullFingerprint: commit.fullFingerprint,
            scanInput: commit.inputSnapshot,
            armedAt: activeEntryArmedAt
        )
        do {
            try await persistence.saveOpenPosition(record)
            return true
        } catch {
            return false
        }
    }

    private func handleTradeExpiry(_ trade: ActiveTrade) async {
        let matchingQuote: LiveQuote?
        if let activeTradeQuote, activeTradeQuote.asset == trade.pair {
            matchingQuote = activeTradeQuote
        } else if let quote, quote.asset == trade.pair {
            matchingQuote = quote
        } else {
            matchingQuote = nil
        }
        let observation = ResearchOutcome.resolve(eventID: trade.id, horizon: Int(trade.durationSec),
            entryTime: trade.enteredAt, strike: trade.strike, side: trade.side,
            quote: matchingQuote, observedAt: Date())
        if observation.resolution == .unresolved && Date().timeIntervalSince(trade.expiresAt) <= 5 { return }
        pendingExpiry = observation

        // Reference observation only. The OANDA midpoint is not the venue's settlement,
        // so it can never be recorded as a broker outcome on its own.
        let referenceIsHit = observation.resolution == .hit
        let referenceAvailable = referenceIsHit || observation.resolution == .miss
        predictedOutcome = referenceAvailable ? (referenceIsHit ? .hit : .miss) : nil
        activeTrade = nil
        activeTradeQuote = nil
        activeEntryArmedAt = nil
        expired = true
        awaitingOutcome = true
        DeskHaptics.settleAlert()

        if referenceAvailable {
            notice = "Reference: OANDA mid suggests \(referenceIsHit ? "HIT" : "MISS"). Confirm the venue result."
        } else if observation.resolution == .tie {
            notice = "Expiry tied; confirm the venue result"
        } else {
            notice = "Expiry unverified; confirm the venue result"
        }

        if voiceDebriefEnabled {
            voiceSession.speakAnnouncement("Expiry reached on \(trade.pair). Confirm the venue result.")
        }

        publishFrame()

        // Record the OANDA midpoint observation automatically as reference history. This is
        // deliberately separate from the ledger: only the user's venue confirmation is a
        // confirmed result.
        if referenceAvailable || observation.resolution == .tie {
            await recordReference(observation)
        }
    }

    private func recordReference(_ observation: ResearchOutcome) async {
        do {
            if try await referenceStore.record(observation) {
                referenceOutcomes.append(observation)
            }
        } catch {
            // Reference history is best-effort. It never blocks or changes venue confirmation.
        }
    }

    /// Clears the desk only when the current arm's outcome is durably in the journal.
    /// An unresolved arm stays on screen.
    private func clearDeskIfResolved() {
        guard activeTrade == nil else { return }
        guard let armID,
            let outcome = journal.first(where: { $0.id == armID })?.outcome,
            !outcome.isEmpty
        else { return }
        awaitingOutcome = false
        expired = false
        commit = nil
        self.armID = nil
        cabinetSide = "WAIT"
        armedAt = nil
        pendingTrade = nil
        pendingExpiry = nil
        pendingOutcome = nil
        predictedOutcome = nil
        candles = []
        publishFrame()
    }

    private func refreshQuote() async {
        if notice == "Demo Desk (Offline)" {
            return
        }
        // Crypto mode has its own feed; the OANDA quote loop must not clobber its state.
        if marketMode == .crypto {
            return
        }
        let clock = Date()
        guard FxSession.isOpen(clock) else {
            feed = .disconnected
            notice = commit == nil ? FxSession.label(clock) : notice
            publishFrame()
            return
        }
        guard let session = await loadSession(allowPrompt: false) else {
            if case .locked = credentialLookup {
                feed = .connecting
            } else {
                feed = .error
                if commit == nil { notice = "OANDA token missing" }
            }
            publishFrame()
            return
        }
        let batch = await marketData.quotes(market: .fx, assets: [pair], session: session)
        let responseReceivedAt = Date()
        let freshQuote = batch.status == .ok
            ? batch.quotes.first(where: { $0.asset == pair })
            : nil
        if let fresh = freshQuote {
            quote = fresh
            if QuoteFreshness.isFresh(fresh, now: responseReceivedAt) {
                lastFreshPollAt = responseReceivedAt
            }
            if let trade = activeTrade {
                // A manual entry is bound to its own immutable pair. A browsing change or a
                // mismatched feed response must never write another pair's price into it.
                if fresh.asset == trade.pair {
                    let wasITM = trade.isInTheMoney
                    activeTrade?.currentPrice = fresh.mid
                    if let isITM = activeTrade?.isInTheMoney, wasITM != isITM {
                        if isITM {
                            DeskHaptics.flipITM()
                        }
                    }
                }
            } else {
                applyLiveVeto(quote: fresh)
            }
        }
        feed = FeedStatusResolver.resolve(
            marketOpen: true,
            sessionReady: true,
            transport: batch.status.oandaTransport,
            // Do not let an older displayed quote make an empty successful poll
            // look live. The last known quote remains visible, while feed state
            // reflects only this response and the age of the last good poll.
            quote: freshQuote,
            lastFreshPollAt: lastFreshPollAt,
            now: responseReceivedAt
        )
        if candles.isEmpty && batch.status == .ok {
            await loadCandles(for: pair)
        }
        publishFrame()
    }

    /// A quote may veto an armed beam. It cannot change the score, hash, or strike.
    private func applyLiveVeto(quote: LiveQuote) {
        guard var commit, commit.veto == nil else { return }
        guard cabinetSide == "HIGH" || cabinetSide == "LOW" else { return }
        guard armedAt != nil else { return }

        guard quote.bid.isFinite, quote.ask.isFinite, quote.bid > 0, quote.ask >= quote.bid else {
            commit.veto = "Bad quote"
            armedAt = nil
            noteVeto("Bad quote")
            self.commit = commit
            publishFrame()
            return
        }

        let gate = StrategyEngine.slippageGate(
            asset: commit.asset,
            side: cabinetSide,
            strike: commit.strike,
            bid: quote.bid,
            ask: quote.ask
        )
        commit.driftPips = gate.adverseDriftPips
        if gate.veto {
            // A nil reason means the gate evaluated and refused; a reason means it could not run.
            let veto = gate.reason == nil ? "Slippage" : "Gate offline"
            commit.veto = veto
            armedAt = nil
            noteVeto(veto)
            if let reason = gate.reason { diagLog("SLIPPAGE_GATE \(reason)") }
        }
        self.commit = commit
    }

    func showJournal() {
        showingJournal = true
    }

    func hideJournal() {
        openReplayID = nil
        showingJournal = false
    }

    func openReplay(_ id: String) {
        openReplayID = id
        coachExplanation = nil
        Task { await explainReplay(id) }
    }

    func closeReplay() {
        voiceSession.cancel()
        openReplayID = nil
        coachExplanation = nil
    }

    /// Start voice coaching for the currently open replay entry.
    /// The session records the spoken question, sends it to the Coach, and reads the answer aloud.
    /// No live quote is passed. The Coach sees only seal + evidence + question.
    func askCoach(for entry: ReplayEntry) {
        let seal = ParitySeal(
            engineSHA1: EngineIdentity.loadedSHA1() ?? "unverified",
            fingerprint: entry.fingerprint,
            score: entry.score,
            side: entry.verb,
            strike: entry.strike,
            candleCount: entry.candles.count
        )
        voiceSession.start(
            seal: seal,
            evidence: entry.why,
            using: assistant.coachService()
        )
    }

    func stopVoice() {
        voiceSession.cancel()
    }

    /// Ask the coach about the latest recorded scan without opening a replay modal.
    public func askCoachLatest() {
        guard let entry = journal.first else { return }
        askCoach(for: entry)
    }

    // MARK: - On-device assistant actions (explanations only)

    /// Saves a generated annotation only after the user explicitly confirms it.
    /// The original voice note is never overwritten.
    public func saveAssistantJournalDraft(_ draft: JournalDraft, entryID: String) async {
        guard storedJournal.contains(where: { $0.id == entryID }) else { return }
        let emotion = draft.emotion.lowercased() == "not stated" ? nil : Emotion(name: draft.emotion)
        let tag = draft.tags.first.map { Tag(label: $0) }
        do {
            try await persistence.annotate(
                entryID: entryID,
                tag: tag,
                emotion: emotion,
                lesson: Lesson(text: draft.lesson)
            )
            await reloadFromDisk()
            assistant.setError(nil)
        } catch {
            assistant.setError("The journal draft could not be saved.")
        }
    }

    public func assistantDiagnostics(limit: Int = 20) async -> [AssistantDiagnostic] {
        await assistant.diagnostics(limit: limit)
    }

    /// Save a spoken voice note to a journal entry.
    public func saveVoiceNote(_ transcript: String, for entryID: String) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = VoiceNote(transcript: trimmed, createdAt: Date())
        try? await persistence.annotate(entryID: entryID, voiceNote: note)
        await reloadFromDisk()
    }


    private func explainReplay(_ id: String) async {
        guard let entry = journal.first(where: { $0.id == id }) else { return }
        let brief = CoachBrief(
            pair: entry.pair,
            score: entry.score,
            evidence: entry.why,
            hash: entry.fingerprint
        )
        coachExplanation = PromptBuilder.sealedCard(brief)
        guard let outcome = await assistant.explain(scanID: id) else { return }
        guard openReplayID == id else { return }
        let explanation = outcome.explanation
        let scan = outcome.scan
        let evidence = explanation.evidenceUsed.isEmpty
            ? "No evidence was recorded."
            : explanation.evidenceUsed.joined(separator: " · ")
        coachExplanation = CoachExplanation(
            summary: explanation.summary,
            confidence: "Sealed",
            bullets: [
                "Engine: \(scan.engineCall) · score \(scan.score)",
                "Evidence: \(evidence)",
                explanation.coachNote,
            ]
        )
    }

    /// Sealed coach explanation for the latest recorded scan, or the currently open replay.
    public var latestCoachExplanation: CoachExplanation? {
        if let coachExplanation { return coachExplanation }
        guard let latest = journal.first else { return nil }
        let brief = CoachBrief(
            pair: latest.pair,
            score: latest.score,
            evidence: latest.why,
            hash: latest.fingerprint
        )
        return PromptBuilder.sealedCard(brief)
    }

    /// Writes the frozen scan to disk, then reloads the journal from that file.
    private func remember(
        _ commit: ScanCommit,
        verb: String,
        request: ScanRequestScheduler.Request? = nil
    ) async -> Bool {
        if let request, !isCurrentScan(request) { return false }
        let id = "\(commit.fingerprint)-\(Int(commit.scannedAt.timeIntervalSince1970 * 1000))"
        armID = id
        let entry = JournalEntry(
            id: id,
            fingerprint: commit.fingerprint,
            fullFingerprint: commit.fullFingerprint,
            pair: commit.asset,
            score: commit.score,
            side: commit.engineCall,
            verb: verb,
            why: commit.evidence,
            strike: commit.strike,
            veto: commit.veto,
            scannedAt: commit.scannedAt,
            engineSHA: commit.engineSHA,
            expirySeconds: commit.expirySeconds,
            m1Count: commit.candles.count,
            m5Count: commit.m5Candles.count,
            evaluationQuote: commit.strike,
            evaluationSpread: commit.spread
        )
        let snapshot = SnapshotRecord(
            hash: commit.fingerprint,
            fullFingerprint: commit.fullFingerprint,
            pair: commit.asset,
            bars: commit.candles,
            m5Bars: commit.m5Candles,
            bid: commit.bid,
            ask: commit.ask,
            spread: commit.spread,
            expirySeconds: commit.expirySeconds,
            engineSHA: commit.engineSHA,
            policy: commit.policy,
            strike: commit.strike,
            score: commit.score,
            side: commit.engineCall
        )
        do {
            try await persistence.recordScan(entry, snapshot: snapshot)
            // The historical record remains valid even if a newer scan superseded it while
            // the disk append was in flight. Do not let its completion replace current UI.
            if let request, !isCurrentScan(request) { return true }
            await reloadFromDisk(request: request)
            return true
        } catch {
            return false
        }
    }

    private func noteVeto(_ veto: String) {
        guard let armID, let index = journal.firstIndex(where: { $0.id == armID && $0.veto == nil }) else {
            return
        }
        journal[index].veto = veto
        Task { try? await persistence.noteVeto(armID: armID, veto: veto) }
    }

    private func reloadFromDisk(request: ScanRequestScheduler.Request? = nil) async {
        let restored = await persistence.restore()
        let restoredReferenceOutcomes = await referenceStore.outcomes()
        let restoredExecutionObservations: [ExecutionObservation]
        let executionLoadIssue: String?
        do {
            restoredExecutionObservations = try await executionObservationStore.load()
            executionLoadIssue = nil
        } catch {
            restoredExecutionObservations = []
            executionLoadIssue = "Execution-quality archive unavailable: \(error.localizedDescription)"
        }
        let restoredManualObservations: [ManualBrokerChartObservation]
        let manualLoadIssue: String?
        do {
            restoredManualObservations = try await otcArchive.manualObservations()
            manualLoadIssue = nil
        } catch {
            restoredManualObservations = []
            manualLoadIssue = "Manual OTC archive unavailable: \(error.localizedDescription)"
        }
        if let request, !isCurrentScan(request) { return }
        outcomeStats = restored.confirmedStats
        ledgerRows = restored.ledgerRows
        restoreIssues = restored.issues
        pendingSaveCount = restored.pendingSettlements.count
        storedJournal = restored.entries
        journal = restored.entries.map {
            replay($0,
                bars: restored.bars(for: $0.fullFingerprint ?? $0.fingerprint),
                m5Bars: restored.m5Bars(for: $0.fullFingerprint ?? $0.fingerprint))
        }
        referenceOutcomes = restoredReferenceOutcomes
        executionObservations = restoredExecutionObservations
        executionObservationIssue = executionLoadIssue
        manualBrokerObservations = restoredManualObservations
        if let manualLoadIssue { otcResearchIssue = manualLoadIssue }
        refreshOTCCredentialState()
        refreshExecutionIntelligence()
        // Attribute restored bars by persisted engine identity, not the mutable live watchlist.
        let entryMarkets = Dictionary(
            storedJournal.map { entry -> (String, DeskMarket) in
                let crypto = entry.engineSHA == CryptoDeskSignal.engineIdentity
                    || (entry.engineSHA == nil && CTAssets.watchlist.contains(entry.pair))
                return (entry.id, crypto ? .crypto : .fx)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for entry in journal {
            let entryMarket = entryMarkets[entry.id] ?? .fx
            let key = CandleCache.Key(market: entryMarket, asset: entry.pair)
            if candleCache.cached(key).isEmpty && !entry.candles.isEmpty {
                // Restored bars are display history, never a fresh transport observation.
                candleCache.store(entry.candles, for: key, fetchedAt: .distantPast)
            }
        }
        let selectedKey = CandleCache.Key(market: marketMode, asset: pair)
        let saved = candleCache.cached(selectedKey)
        if candles.isEmpty, !saved.isEmpty {
            candles = saved
            candlesAreStale = true
        }
        if let issue = restored.issues.first, notice == nil {
            notice = issue.userMessage
        }

        // A position that survived the app being killed is restored, never dropped.
        // A position whose journal entry already has an outcome is not resurrected.
        if let position = restored.activePosition, activeTrade == nil,
           let entry = journal.first(where: { $0.id == position.armID }) {
            if entry.outcome != nil {
                Task { try? await persistence.clearOpenPosition() }
            } else {
                restoreOpenPosition(position, entry: entry)
            }
        }
    }

    /// Rebuilds the frozen commit for a restored position so settlement keeps the same identity.
    private func restoreOpenPosition(_ position: ActivePositionRecord, entry: ReplayEntry) {
        armID = position.armID
        historical = false
        commit = ScanCommit(
            asset: entry.pair,
            engineCall: entry.verb.isEmpty ? position.trade.side : entry.verb,
            score: entry.score,
            evidence: entry.why,
            strike: entry.strike,
            fingerprint: entry.fingerprint,
            fullFingerprint: position.fullFingerprint,
            candleCount: entry.candles.count,
            candles: entry.candles,
            m5Candles: position.scanInput?.m5 ?? [],
            bid: position.scanInput?.bid,
            ask: position.scanInput?.ask,
            spread: position.scanInput?.spread,
            expirySeconds: position.scanInput?.expirySeconds ?? Timing.expirySec,
            engineSHA: position.scanInput?.engineSHA ?? EngineIdentity.loadedSHA1() ?? "unverified",
            policy: position.scanInput?.policy ?? "baseline",
            scannedAt: entry.scannedAt,
            veto: entry.veto
        )
        cabinetSide = position.trade.side
        activeEntryArmedAt = position.armedAt
        selectedSignal = nil
        pendingTrade = position.trade
        if position.trade.isExpired {
            activeTrade = nil
            activeTradeQuote = nil
            activeEntryArmedAt = nil
            pendingExpiry = ResearchOutcome.resolve(
                eventID: position.trade.id,
                horizon: Int(position.trade.durationSec),
                entryTime: position.trade.enteredAt,
                strike: position.trade.strike,
                side: position.trade.side,
                quote: nil,
                observedAt: Date())
            expired = true
            awaitingOutcome = true
            notice = "Position expired while closed; confirm the venue result"
        } else {
            activeTrade = position.trade
            expired = false
            awaitingOutcome = false
            notice = "Tracking position opened before relaunch"
        }
        publishFrame()
    }

    private func replay(_ entry: JournalEntry, bars: [Candle], m5Bars: [Candle] = []) -> ReplayEntry {
        ReplayEntry(
            id: entry.id,
            pair: entry.pair,
            score: entry.score,
            verb: entry.verb,
            why: entry.why,
            strike: entry.strike,
            veto: entry.veto,
            fingerprint: entry.fingerprint,
            candles: bars,
            m5Candles: m5Bars,
            scannedAt: entry.scannedAt,
            voiceNote: entry.voiceNote,
            tag: entry.tag,
            emotion: entry.emotion,
            lesson: entry.lesson,
            outcome: entry.outcome
        )
    }


    private func publishFrame() {
        guard let commit else {
            frame = nil
            return
        }
        if let trade = activeTrade {
            let verb = "\(trade.side) ACTIVE"
            frame = DeskFrame(
                pair: trade.pair,
                feed: feed,
                score: trade.score,
                why: commit.evidence,
                strike: trade.strike,
                verb: verb,
                remainingMs: trade.remainingMs,
                veto: nil,
                fingerprint: trade.fingerprint,
                isActionable: false
            )
            return
        }
        if expired {
            frame = frozen(commit, verb: "EXPIRED", remainingMs: 0)
            if pendingTrade != nil,
               journal.first(where: { $0.id == armID })?.outcome == nil {
                awaitingOutcome = true
            } else if pendingTrade == nil {
                // An expired signal is not a trade. Keep late manual logging and navigation
                // available without presenting a fictitious settlement workflow.
                awaitingOutcome = false
            }
            return
        }
        let elapsed: Double
        if let armedAt, commit.veto == nil {
            elapsed = max(0, now.timeIntervalSince(armedAt) * 1000)
        } else {
            elapsed = 0
        }
        let next = DeskFrame.make(
            commit: commit,
            feed: feed,
            cabinetSide: cabinetSide,
            elapsedMs: elapsed,
            historical: historical
        )
        if next.verb == "EXPIRED" {
            expired = true
            armedAt = nil
            frame = frozen(commit, verb: "EXPIRED", remainingMs: 0)
            awaitingOutcome = pendingTrade != nil
            return
        }
        let armed = next.isActionable
        frame = armed ? next : frozen(commit, verb: next.verb, remainingMs: 0)
    }

    private func frozen(_ commit: ScanCommit, verb: String, remainingMs: Double) -> DeskFrame {
        DeskFrame(
            pair: commit.asset,
            feed: feed,
            score: commit.score,
            why: commit.evidence,
            strike: commit.strike,
            verb: verb,
            remainingMs: remainingMs,
            veto: commit.veto,
            fingerprint: commit.fingerprint,
            isActionable: false
        )
    }
}

/// One market from the last full-book scan.
struct BookRow: Equatable, Identifiable {
    var id: String { asset }
    var asset: String
    var side: String
}

enum KeychainState: Equatable {
    case unknown
    case ready
    case locked
    case missing
}

/// One committed scan, frozen for the journal. Not a second engine result.
struct ReplayEntry: Identifiable, Equatable {
    var id: String
    var pair: String
    var score: Int
    var verb: String
    var why: String
    var strike: Double
    var veto: String?
    var fingerprint: String
    var candles: [Candle]
    var m5Candles: [Candle]
    var scannedAt: Date
    var voiceNote: VoiceNote?
    var tag: Tag?
    var emotion: Emotion?
    var lesson: Lesson?
    var outcome: String?
}

public enum DeskTab: String, CaseIterable, Identifiable, Sendable {
    case desk = "Trade"
    case radar = "Markets"
    case review = "Review"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .desk: return "bolt.fill"
        case .radar: return "scope"
        case .review: return "book.closed.fill"
        }
    }
}

#if DEBUG
extension LightningDeskModel {
    /// Exercises the ORB persistence/projection boundary without credentials or network access.
    public func publishORBDecisionForTesting(_ decision: ORBDecision, asset: String,
                                             live: Bool, bars: [ORBBar] = [],
                                             asOf: Date = Date(),
                                             market: DeskMarket = .fx,
                                             supersedeBeforePublish: Bool = false) async {
        marketMode = market
        session = live ? OandaSession(token: "test-only", accountId: "test-only", environment: .live) : nil
        let generation = beginLiveDecisionRefresh(for: asset)
        if supersedeBeforePublish { _ = beginLiveDecisionRefresh(for: asset) }
        await publishORBDecision(decision, bars: bars, asOf: asOf,
                                 asset: asset, generation: generation)
    }

    /// Test seam for the real selection publication path; no Keychain or broker call.
    public func publishLiveStrategySelectionForTesting(_ selection: LiveStrategySelection) async {
        let generation = beginLiveDecisionRefresh(for: selection.decision.instrument)
        await publishLiveStrategySelection(selection, asset: selection.decision.instrument,
                                           generation: generation)
    }

    /// Seeds only ephemeral research UI state to prove it is never persisted/restored.
    public func clearLiveStrategyResearchObservationsForTesting() {
        clearLiveStrategyResearchObservations()
    }

#if DEBUG && os(macOS)
    func installMacResearchStateForTesting(signals: [MacResearchSignal],
                                           diagnostics: [MacResearchEvaluationDiagnostic]) {
        macResearchSignals = signals
        macResearchEvaluationDiagnostics = diagnostics
    }

    func beginLiveDecisionRefreshForTesting(for asset: String) -> UInt64 {
        beginLiveDecisionRefresh(for: asset)
    }
#endif

    public func beginCryptoScanForTesting() {
        if marketMode == .crypto { clearLiveStrategyResearchObservations() }
    }

    public func installLiveStrategyResearchObservationsForTesting(
        _ observations: [LiveStrategyResearchObservation]
    ) {
        liveStrategyResearchObservations = observations
    }

    /// Test-only seam: seed an already-published Live decision without Keychain/network access.
    public func installLiveStrategyDecisionForTesting(_ decision: LiveStrategyDecision) {
        _ = beginLiveDecisionRefresh(for: decision.instrument)
        liveStrategyDecisions[decision.instrument] = decision
        if let plan = decision.plan { orbPlans[decision.instrument] = plan }
    }

    /// Test-only seam: exercise restore policy without reading credentials or opening a session.
    public func restoreLiveStrategyDecisionsForTesting() async {
        await restoreLiveStrategyDecisions(allowWithoutLiveSession: true)
    }

    /// Test-only seam: exercise the production fail-closed publication path in an isolated store.
    public func withdrawLiveStrategyDecisionForTesting(_ asset: String, reason: String) async {
        let generation = beginLiveDecisionRefresh(for: asset)
        await withdrawLiveStrategyDecision(for: asset, reason: reason, generation: generation)
    }

    /// Test-only seam: exercise the post-pick full-book invalidation without a broker scan.
    public func withdrawUnselectedLiveDecisionsForTesting(scanAssets: [String],
                                                           pickedAsset: String) async {
        var generations: [String: UInt64] = [:]
        for asset in scanAssets where generations[asset] == nil {
            generations[asset] = beginLiveDecisionRefresh(for: asset)
        }
        await withdrawUnselectedLiveDecisions(scanAssets: scanAssets,
            pickedAsset: pickedAsset, generations: generations)
    }

    /// Test-only seam: install a frozen armed scan without a network or Keychain.
    /// Compiled out of Release builds.
    public func installArmedScanForTesting(
        commit: ScanCommit,
        signal: EngineSignal,
        quote: LiveQuote,
        armedAt: Date = Date().addingTimeInterval(-1),
        historical: Bool = false
    ) {
        self.commit = commit
        self.selectedSignal = signal
        self.quote = quote
        self.cabinetSide = signal.cabinetSide
        self.feed = .live
        self.lastFreshPollAt = Date()
        self.historical = historical
        self.armedAt = historical ? nil : armedAt
        self.armID = "arm-test"
        self.scanning = false
        self.activeTrade = nil
        self.activeTradeQuote = nil
        self.now = Date()
        self.publishFrame()
    }

    /// Test-only seam: run the same on-disk restore path used at launch.
    public func restoreForTesting() async {
        await reloadFromDisk()
    }

    /// Test-only seam: force the active trade past expiry without waiting.
    public func expireActiveTradeForTesting() async {
        guard var trade = activeTrade else { return }
        let now = Date()
        trade.enteredAt = now.addingTimeInterval(-trade.durationSec - 1)
        trade.expiresAt = trade.enteredAt.addingTimeInterval(trade.durationSec)
        activeTrade = trade
        await handleTradeExpiry(trade)
    }

    /// Test-only seam: persist the frozen scan exactly as a real scan does.
    public func rememberForTesting() async -> Bool {
        guard let commit, let frame else { return false }
        return await remember(commit, verb: frame.verb)
    }
}
#endif
