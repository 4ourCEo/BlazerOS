import Combine
import Foundation
import BlazerCore
import BlazerCrypto

/// Desk market mode. `.crypto` uses the shared BlazerCrypto engine; `.fx` uses OANDA.
public enum DeskMarket: String, Sendable, CaseIterable {
    case crypto
    case fx
}

/// Post-settlement receipt. Presentation only: the ledger row is already written.
public struct SettleReceipt: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let outcome: DeskOutcome
    public let pair: String
    public let pips: Double?
    public let payout: Double
    public let labelSource: String

    public init(
        id: UUID = UUID(),
        outcome: DeskOutcome,
        pair: String,
        pips: Double?,
        payout: Double,
        labelSource: String
    ) {
        self.id = id
        self.outcome = outcome
        self.pair = pair
        self.pips = pips
        self.payout = payout
        self.labelSource = labelSource
    }
}

/// One-screen desk state. The frame is derived from the frozen commit. Quotes never rescore it.
@MainActor
public final class LightningDeskModel: ObservableObject {
    public init(storageRoot: URL? = nil) {
        if storageRoot == nil {
            FileLocations.migrateLegacyGroupStorageIfNeeded()
        }
        let root = storageRoot ?? FileLocations.applicationSupport()
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
    }
    @Published public var pair: String = "EUR/USD"
    @Published var feed: FeedStatus = .connecting
    @Published var candles: [Candle] = []
    @Published var scanning = false
    /// Walk label, for example "GBP/USD 2/6". Nil when idle.
    @Published var scanStep: String?
    /// Last full-book read. Display only.
    @Published var book: [BookRow] = Assets.watchlist.map { BookRow(asset: $0, side: "—") }
    @Published var notice: String?
    /// Visible reason the last entry tap was refused. Cleared on the next attempt or scan.
    @Published public private(set) var entryIssue: String?
    @Published public private(set) var frame: DeskFrame?
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
    @Published public var marketMode: DeskMarket = .fx
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
    @Published var draftEnvironment = OandaEnvironment.practice
    @Published var credentialSaveFailed = false
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
    /// Increments each time the app returns to the foreground. Telemetry only.
    @Published public private(set) var foregroundResumeCount = 0

    public func handleAppBackgrounded(now: Date = Date()) {
        backgroundedAt = now
    }

    /// Resume after the user returns (e.g., from the Crypto.com app). Never blocks.
    public func handleAppForegrounded(now: Date = Date()) {
        let suspendedMs = backgroundedAt.map { max(0, now.timeIntervalSince($0) * 1000) } ?? 0
        let decision = ForegroundResume.decide(
            suspendedForMs: suspendedMs,
            lastPollAgeMs: lastFreshPollAt.map { max(0, now.timeIntervalSince($0) * 1000) },
            clockSampleAgeMs: nil
        )
        backgroundedAt = nil
        foregroundResumeCount += 1
        if decision.treatFeedAsDisconnected {
            feed = .connecting
        }
        refreshTrackedStrikePositions()
        Task {
            await refreshActiveTradeQuote()
            await refreshQuote()
            // A Siri request can arrive while a session is already loaded. Consume it here
            // instead of waiting for the next Keychain read.
            await consumePendingScanIfReady()
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
    /// Bumped on every press so a new walk replaces the one in flight.
    private var scanGeneration = 0

    /// Per-asset cache of completed candles so switching pairs never shows a blank chart.
    private var candlesByAsset: [String: [Candle]] = [:]
    /// Timestamp when candles were last fetched per asset.
    private var candlesFetchedAt: [String: Date] = [:]
    /// In-flight candle fetch tasks per asset to deduplicate concurrent requests.
    private var inFlightCandleTasks: [String: Task<[Candle], Never>] = [:]
    /// Per-asset cache of the last committed scan for that pair.
    private var commitsByAsset: [String: ScanCommit] = [:]
    /// Per-asset cache of the cabinet side for that pair.
    private var cabinetSideByAsset: [String: String] = [:]

    /// Watchlist for the active market mode. Crypto uses the shared BlazerCrypto list.
    public var pairs: [String] {
        marketMode == .crypto ? CTAssets.watchlist : Assets.watchlist
    }

    public func select(pair next: String) {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else {
            notice = "Resolve the current outcome before switching pairs"
            return
        }
        guard next != pair else { return }
        pair = next

        // Restore cached bars immediately so chart is never blank
        if let cached = candlesByAsset[next], !cached.isEmpty {
            candles = cached
            if let fetchedAt = candlesFetchedAt[next], Date().timeIntervalSince(fetchedAt) >= 45 {
                Task { await loadCandles(for: next, force: true) }
            }
        } else {
            candles = []
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

    /// Populates the desk with sample market candles from the golden fixture for offline testing.
    public func loadDemoDesk() {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else { return }
        isDemoDesk = true
        let fixture = GoldenFixture.market()
        let bars = GoldenFixture.frozenBars(from: fixture)
        candles = bars
        candlesByAsset[pair] = bars
        candlesFetchedAt[pair] = Date()
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
        book.first(where: { $0.asset == asset })?.side ?? cabinetSideByAsset[asset]
    }

    /// True while a settlement write is in progress. Used to freeze navigation.
    public var isSettlementInFlight: Bool { settlementInFlight }

    public func score(for asset: String) -> Int? {
        commitsByAsset[asset]?.score
    }

    public func candles(for asset: String) -> [Candle] {
        candlesByAsset[asset] ?? []
    }

    public func strike(for asset: String) -> Double? {
        commitsByAsset[asset]?.strike
    }

    /// Fetches recent completed M1 candles from OANDA with in-flight deduplication and TTL caching.
    public func loadCandles(for asset: String, force: Bool = false) async {
        if !force, let cached = candlesByAsset[asset], !cached.isEmpty,
           let fetchedAt = candlesFetchedAt[asset], Date().timeIntervalSince(fetchedAt) < 45 {
            if pair == asset {
                candles = cached
            }
            return
        }

        if let existing = inFlightCandleTasks[asset] {
            let bars = await existing.value
            if !bars.isEmpty && pair == asset {
                candles = bars
            }
            return
        }

        let task = Task<[Candle], Never> { @MainActor [weak self] in
            guard let self, let session = await self.loadSession(allowPrompt: false) else { return [] }
            return await OandaClient.fetchCandles(asset: asset, session: session, granularity: "M1", count: 80)
        }
        inFlightCandleTasks[asset] = task

        let bars = await task.value
        inFlightCandleTasks.removeValue(forKey: asset)

        guard !bars.isEmpty else { return }
        candlesByAsset[asset] = bars
        candlesFetchedAt[asset] = Date()
        if pair == asset {
            candles = bars
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
        // Scan immediately on launch so the desk is never empty. A Siri request that was
        // queued before launch is consumed once, without being overwritten by a second scan.
        let consumedPendingScan = await consumePendingScanIfReady()
        if !consumedPendingScan {
            if marketMode == .crypto {
                await scanCrypto()
            } else if candles.isEmpty {
                Task { await self.loadCandles(for: self.pair) }
            }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLAZER_START_TAB"] == "coach" {
            activeTab = .coach
        }
        if ProcessInfo.processInfo.environment["BLAZER_ASSISTANT_DEMO"] == "1" {
            activeTab = .coach
            await assistant.explainLatestScan()
            await assistant.ask("Why did this scan return WAIT?")
            await assistant.requestDebrief()
        }
        #endif
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.quoteLoop() }
            group.addTask { await self.beamLoop() }
            group.addTask { await self.cryptoQuoteLoop() }
        }
    }

    /// A fresh six-market walk. Nothing from the previous scan is reused.
    public func scan() async {
        entryIssue = nil
        isDemoDesk = false
        switch marketMode {
        case .fx: await scanFx()
        case .crypto: await scanCrypto()
        }
    }

    /// Crypto scan via the shared BlazerCrypto engine. No OANDA credential, no FX session gate.
    public func scanCrypto(asset: String = "BTC/USDT") async {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else {
            notice = "Resolve the current outcome before scanning"
            return
        }
        scanGeneration += 1
        let generation = scanGeneration
        scanning = true
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
        notice = nil
        book = CTAssets.watchlist.map { BookRow(asset: $0, side: "—") }
        publishFrame()
        scanStep = asset
        defer {
            if generation == scanGeneration {
                scanning = false
                scanStep = nil
            }
        }

        let batch = try? await BinanceClient.fetchCryptoBundle(asset: asset)
        guard generation == scanGeneration else { return }
        guard let batch, !batch.candles.isEmpty else {
            diagLog("CRYPTO_SCAN failed: feed unavailable")
            feed = .disconnected
            notice = "Crypto feed unavailable"
            publishFrame()
            return
        }

        let cryptoSignal = CryptoDeskSignal.make(asset: asset, batch: batch)
        diagLog("CRYPTO_SCAN \(asset) side=\(cryptoSignal.cabinetSide) conv=\(cryptoSignal.confidence ?? 0) candles=\(batch.candles.count) mid=\(batch.mid) source=\(batch.source)")
        let bars = batch.candles.map { c in
            Candle(time: c.time, open: c.open, high: c.high, low: c.low, close: c.close)
        }
        let started = Date()
        var next = ScanKernel.commit(
            from: cryptoSignal,
            bars: bars,
            bid: batch.bid,
            ask: batch.ask,
            spread: batch.spread,
            expirySeconds: 60,
            engineSHA: CryptoDeskSignal.engineIdentity,
            policy: CryptoDeskSignal.policy,
            scannedAt: started
        )
        next.veto = CryptoDeskSignal.veto(asset: asset, batch: batch, signal: cryptoSignal)
        if let veto = next.veto {
            diagLog("CRYPTO_VETO \(asset): \(veto)")
        }
        pair = asset
        commit = next
        cabinetSide = cryptoSignal.cabinetSide
        selectedSignal = cryptoSignal
        candles = bars
        candlesByAsset[asset] = bars
        candlesFetchedAt[asset] = Date()
        commitsByAsset[asset] = next
        cabinetSideByAsset[asset] = cryptoSignal.cabinetSide
        book = [BookRow(asset: asset, side: cryptoSignal.cabinetSide)]
        if batch.source == "kraken-synthetic-spread" {
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
            if !(await remember(next, verb: frame.verb)) {
                commit?.veto = "Scan was not saved"
                armedAt = nil
                armID = nil
                notice = "Scan was not saved; scan again"
                publishFrame()
            }
        }
    }

    private func scanFx() async {
        guard activeTrade == nil, !awaitingOutcome, !settlementInFlight else {
            notice = "Resolve the current outcome before scanning"
            return
        }
        scanGeneration += 1
        let generation = scanGeneration
        let clock = Date()
        if !FxSession.isOpen(clock) {
            feed = .disconnected
            notice = FxSession.label(clock)
            return
        }
        scanning = true
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
        notice = nil
        book = pairs.map { BookRow(asset: $0, side: "—") }
        publishFrame()
        scanStep = "\(pairs[0]) 1/\(pairs.count)"
        defer {
            if generation == scanGeneration {
                scanning = false
                scanStep = nil
            }
        }
        guard let session = await loadSession(allowPrompt: true) else {
            feed = .error
            notice = "OANDA token missing"
            return
        }
        guard generation == scanGeneration else { return }
        var bag: [EngineSignal] = []
        var barsByAsset: [String: [Candle]] = [:]
        var rows = book
        for (index, asset) in pairs.enumerated() {
            guard generation == scanGeneration else { return }
            scanStep = "\(asset) \(index + 1)/\(pairs.count)"
            let started = Date()
            do {
                let envelope = try await ScanKernel.fetch(asset: asset, session: session)
                if let signal = envelope.signal {
                    bag.append(signal)
                    let bars = envelope.snapshotBars ?? envelope.candles ?? []
                    barsByAsset[asset] = bars
                    candlesByAsset[asset] = bars
                    candlesFetchedAt[asset] = Date()
                    cabinetSideByAsset[asset] = signal.cabinetSide
                    let assetCommit = ScanKernel.commit(
                        from: signal,
                        bars: bars,
                        m5Bars: envelope.snapshotM5Bars ?? [],
                        bid: envelope.bid,
                        ask: envelope.ask,
                        spread: envelope.spread,
                        expirySeconds: envelope.expirySeconds ?? Timing.expirySec,
                        engineSHA: envelope.engineSHA ?? EngineIdentity.loadedSHA1() ?? "unverified",
                        scannedAt: Self.evaluationDate(signal.asOfMs, fallback: started)
                    )
                    commitsByAsset[asset] = assetCommit
                    rows[index] = BookRow(asset: asset, side: signal.cabinetSide)
                    if signal.cabinetSide == "WAIT" {
                        trapsAvoidedCount += 1
                    }
                }
            } catch {
                let message = error.localizedDescription
                if message == "OANDA token missing" || message == "SCAN ENGINE OFFLINE" {
                    notice = message
                    book = rows
                    return
                }
            }
            book = rows
            let hold = 1.1 - Date().timeIntervalSince(started)
            if hold > 0 {
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            }
        }
        guard generation == scanGeneration else { return }
        guard !bag.isEmpty else {
            notice = "Scan missed the book"
            return
        }
        let picked = await pickedSignal(from: bag)
        guard generation == scanGeneration else { return }
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
        if (side == "HIGH" || side == "LOW"), next.veto == nil {
            let batch = await OandaClient.fetchQuoteBatch(assets: [picked.asset], session: session)
            let fresh = batch.transport == .ok ? batch.quotes.first(where: { $0.asset == picked.asset }) : nil
            next.veto = EntryQuality.veto(signal: picked, quote: fresh)
            if let fresh {
                quote = fresh
                if QuoteFreshness.isFresh(fresh, now: Date()) {
                    lastFreshPollAt = Date()
                }
            }
        }
        pair = picked.asset
        commit = next
        cabinetSide = side
        candles = bars
        candlesByAsset[picked.asset] = bars
        candlesFetchedAt[picked.asset] = Date()
        commitsByAsset[picked.asset] = next
        cabinetSideByAsset[picked.asset] = side
        expired = false
        let armedClock = Date()
        armedAt = (side == "HIGH" || side == "LOW") && next.veto == nil
            ? armedClock.addingTimeInterval(-0.001)
            : nil
        notice = nil
        now = armedClock
        publishFrame()
        liftHero()
        if let frame {
            if !(await remember(next, verb: frame.verb)) {
                commit?.veto = "Scan was not saved"
                armedAt = nil
                armID = nil
                notice = "Scan was not saved; scan again"
                publishFrame()
            }
        }
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
              let settleArmID = armID
        else { return }
        settlementInFlight = true
        defer { settlementInFlight = false }
        awaitingOutcome = false
        pendingLabelSource = labelSource
        pendingOutcome = outcome

        // Capture a fully self-contained settlement record before any await. Nothing below
        // reads mutable desk state that a later task could change.
        let trade = pendingTrade
        let expiry = pendingExpiry
        let windowName = MarketEdgeWindow.current(at: trade?.enteredAt ?? settleCommit.scannedAt).badgeTitle
        let resolvedEntryQuote = entryQuote ?? trade?.brokerEntryPrice ?? trade?.strike ?? settleCommit.strike
        let resolvedExpiryPrice = expiryPrice ?? expiry?.exitPrice
        let horizonSeconds = trade.map { Int($0.durationSec) }
        let enteredAt = trade?.enteredAt
        let expiryObservedMs = expiry?.quoteTimeMs
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
        if let pendingOutcome, let commit {
            await settle(
                pendingOutcome,
                expiryPrice: pendingExpiry?.exitPrice,
                entryQuote: pendingTrade?.strike ?? commit.strike,
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
    private func loadSession(allowPrompt: Bool) async -> OandaSession? {
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
            await consumePendingScanIfReady()
            return ready
        case .locked where allowPrompt:
            let prompted = DeskCredentials.session(allowPrompt: true)
            credentialLookup = prompted
            if case .ready(let ready) = prompted {
                session = ready
                keychainState = .ready
                await consumePendingScanIfReady()
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
        case .none:
            return nil
        }
    }

    /// Saves the phone Keychain and drops the fields from the caller. Does not log the token.
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
        }
    }

    /// A Siri scan is a request to open the existing walk. It does not choose a side.
    /// Returns true when a pending request was consumed.
    @discardableResult
    private func consumePendingScanIfReady() async -> Bool {
        #if os(iOS)
        guard !scanning, activeTrade == nil, !awaitingOutcome, !settlementInFlight else { return false }
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
        case .historical: return "Historical scan; scan again before entry"
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
            fresh = await BinanceClient.fetchQuote(asset: trade.pair)
        } else if let session = await loadSession(allowPrompt: false) {
            let batch = await OandaClient.fetchQuoteBatch(assets: [trade.pair], session: session)
            fresh = batch.transport == .ok
                ? batch.quotes.first(where: { $0.asset == trade.pair })
                : nil
        } else {
            fresh = nil
        }
        guard let fresh, fresh.asset == trade.pair, fresh.bid.isFinite, fresh.ask.isFinite else {
            return
        }
        activeTradeQuote = fresh
        activeTrade?.currentPrice = fresh.mid
    }

    private func refreshCryptoQuote() async {
        guard marketMode == .crypto, CTAssets.watchlist.contains(pair) else { return }
        let clock = Date()
        guard let fresh = await BinanceClient.fetchQuote(asset: pair) else {
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
    public func lockInTrade(duration: Double? = nil, late: Bool = false) async {
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

        guard let commit, let selectedSignal else {
            entryIssue = "Nothing to log. Scan again before recording."
            DeskHaptics.veto()
            return
        }
        let liveQuote = quote.flatMap { $0.asset == commit.asset ? $0 : nil }
        let liveStrike: Double
        if late {
            // A dead feed must not block data capture; fall back to the frozen strike.
            liveStrike = liveQuote?.mid ?? commit.strike
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
        guard [60.0, 180.0, 300.0].contains(durationSec) else {
            entryIssue = "Unsupported expiry"
            DeskHaptics.veto()
            return
        }

        entryInFlight = true
        defer { entryInFlight = false }

        let tradeID = armID ?? "\(commit.fingerprint)-\(Int(Date().timeIntervalSince1970 * 1000))"
        let armedReference = armedAt ?? commit.scannedAt
        let enteredAt = Date()
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
            quote: liveQuote, kind: "manual-entry", regime: selectedSignal.features?.regime, now: enteredAt)
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
        guard let commit, commit.veto == nil, let signal else { return false }
        guard signal.cabinetSide == "HIGH" || signal.cabinetSide == "LOW" else { return false }
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
        let batch = await OandaClient.fetchQuoteBatch(assets: [pair], session: session)
        if batch.transport == .ok, let fresh = batch.quotes.first(where: { $0.asset == pair }) {
            quote = fresh
            if QuoteFreshness.isFresh(fresh, now: clock) {
                lastFreshPollAt = clock
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
            transport: batch.transport,
            quote: quote,
            lastFreshPollAt: lastFreshPollAt,
            now: clock
        )
        if candles.isEmpty && batch.transport == .ok {
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
    private func remember(_ commit: ScanCommit, verb: String) async -> Bool {
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
            await reloadFromDisk()
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

    private func reloadFromDisk() async {
        let restored = await persistence.restore()
        outcomeStats = restored.confirmedStats
        ledgerRows = restored.ledgerRows
        restoreIssues = restored.issues
        pendingSaveCount = restored.pendingSettlements.count
        storedJournal = restored.entries
        journal = restored.entries.map {
            replay($0, bars: restored.bars(for: $0.fullFingerprint ?? $0.fingerprint))
        }
        referenceOutcomes = await referenceStore.outcomes()
        do { executionObservations = try await executionObservationStore.load() }
        catch { executionObservationIssue = "Execution-quality archive unavailable: \(error.localizedDescription)" }
        refreshExecutionIntelligence()
        for entry in journal {
            if candlesByAsset[entry.pair] == nil && !entry.candles.isEmpty {
                candlesByAsset[entry.pair] = entry.candles
            }
        }
        if candles.isEmpty, let saved = candlesByAsset[pair], !saved.isEmpty {
            candles = saved
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

    private func replay(_ entry: JournalEntry, bars: [Candle]) -> ReplayEntry {
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
            if journal.first(where: { $0.id == armID })?.outcome == nil {
                awaitingOutcome = true
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
            awaitingOutcome = true
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
    var scannedAt: Date
    var voiceNote: VoiceNote?
    var tag: Tag?
    var emotion: Emotion?
    var lesson: Lesson?
    var outcome: String?
}

public enum DeskTab: String, CaseIterable, Identifiable, Sendable {
    case desk = "Desk"
    case radar = "Radar"
    case intel = "Intel"
    case coach = "Coach"
    case journal = "Journal"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .desk: return "bolt.fill"
        case .radar: return "scope"
        case .intel: return "clock.badge.checkmark"
        case .coach: return "brain.head.profile"
        case .journal: return "book.closed.fill"
        }
    }
}

#if DEBUG
extension LightningDeskModel {
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
