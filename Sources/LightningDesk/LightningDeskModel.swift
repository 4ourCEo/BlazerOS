import Combine
import Foundation
import BlazerCore

/// One-screen desk state. The frame is derived from the frozen commit. Quotes never rescore it.
@MainActor
public final class LightningDeskModel: ObservableObject {
    public init(storageRoot: URL? = nil) {
        persistence = PersistenceCoordinator(root: storageRoot ?? FileLocations.applicationSupport())
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
    @Published public private(set) var frame: DeskFrame?
    /// Active 60-second binary trade execution. Nil when not in an active position.
    @Published public private(set) var activeTrade: ActiveTrade?
    /// Predicted outcome based on live price at trade expiry.
    @Published public private(set) var predictedOutcome: DeskOutcome?
    /// Live mid quote for telemetry and chart horizon.
    public var currentPrice: Double? {
        activeTrade?.currentPrice ?? quote?.mid
    }
    /// Brand cover. Dismisses on a real LIVE feed, otherwise after a short beat. Never invents LIVE.
    @Published public var showingLaunch = true
    @Published var launchMarkLit = false
    @Published var launchWordLit = false
    /// Brief upward offset after a commit. Display only.
    @Published var heroLift: Double = 0
    @Published public var activeTab: DeskTab = .desk
    @Published var showingCredentials = false
    /// Frozen scans. Newest first. Display only; quotes never rewrite the score.
    @Published private(set) var journal: [ReplayEntry] = []
    @Published var showingJournal = false
    @Published var openReplayID: String?
    /// Explanation of the open replay. Built from the seal, not from a live quote.
    @Published private(set) var coachExplanation: CoachExplanation?
    /// HIT and MISS are offered only after the beam expires.
    @Published private(set) var awaitingOutcome = false
    @Published private(set) var outcomeStats = OutcomeStats.empty
    /// Keychain presence only. A saved token is not kept here.
    @Published private(set) var keychainState: KeychainState = .unknown
    /// Form drafts. Cleared when the Keychain write succeeds. Never synced.
    @Published var draftToken = ""
    @Published var draftAccount = ""
    @Published var draftEnvironment = OandaEnvironment.practice
    @Published var credentialSaveFailed = false
    /// Voice coach session for the open replay. One active session at a time.
    @Published var voiceSession = VoiceSession()

    private let persistence: PersistenceCoordinator
    private var session: OandaSession?
    private var armID: String?
    private var commit: ScanCommit?
    private var cabinetSide = "WAIT"
    private var armedAt: Date?
    private var quote: LiveQuote?
    private var lastFreshPollAt: Date?
    private var now = Date()
    private var expired = false
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

    public let pairs = Assets.watchlist

    public func select(pair next: String) {
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
            expired = false
            armedAt = nil
            publishFrame()
        } else {
            commit = nil
            cabinetSide = "WAIT"
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
        try? await Task.sleep(nanoseconds: 280_000_000)
        launchWordLit = true
        let start = Date()
        while !Task.isCancelled && showingLaunch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let elapsed = Date().timeIntervalSince(start)
            if elapsed >= 1.6 || (elapsed >= 0.7 && feed == .live) {
                showingLaunch = false
            }
        }
    }

    public func run() async {
        await reloadFromDisk()
        if candles.isEmpty {
            Task { await self.loadCandles(for: self.pair) }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.quoteLoop() }
            group.addTask { await self.beamLoop() }
        }
    }

    /// A fresh six-market walk. Nothing from the previous scan is reused.
    public func scan() async {
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
        expired = false
        awaitingOutcome = false
        activeTrade = nil
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
                    let assetCommit = ScanKernel.commit(from: signal, bars: bars, scannedAt: started)
                    commitsByAsset[asset] = assetCommit
                    rows[index] = BookRow(asset: asset, side: signal.cabinetSide)
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
        var next = ScanKernel.commit(from: picked, bars: bars, scannedAt: Date())
        let side = picked.cabinetSide
        if EngineIdentity.loadedSHA1() != EngineIdentity.pinnedSHA1 {
            next.veto = "Engine pin"
        }
        if (side == "HIGH" || side == "LOW"), next.veto == nil {
            let batch = await OandaClient.fetchQuoteBatch(assets: [picked.asset], session: session)
            if batch.transport == .ok, let fresh = batch.quotes.first(where: { $0.asset == picked.asset }) {
                next = ScanCommit(
                    asset: next.asset,
                    engineCall: next.engineCall,
                    score: next.score,
                    evidence: next.evidence,
                    strike: fresh.mid,
                    fingerprint: next.fingerprint,
                    candleCount: next.candleCount,
                    candles: next.candles,
                    scannedAt: next.scannedAt,
                    veto: next.veto,
                    driftPips: next.driftPips
                )
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
        armedAt = (side == "HIGH" || side == "LOW") && next.veto == nil ? armedClock : nil
        notice = nil
        now = armedClock
        publishFrame()
        liftHero()
        if let frame {
            await remember(next, verb: frame.verb)
        }
    }

    /// Records the expired arm once, then leaves the hero. A second call does not append.
    public func settle(_ outcome: DeskOutcome) async {
        guard awaitingOutcome, let commit, let armID else { return }
        awaitingOutcome = false
        let row = LedgerRow(
            timestamp: Date(),
            pair: commit.asset,
            hash: commit.fingerprint,
            score: commit.score,
            side: commit.engineCall,
            veto: commit.veto != nil,
            drift: commit.driftPips ?? 0,
            outcome: outcome.rawValue,
            outcomeEventID: armID
        )
        let snapshot = SnapshotRecord(
            hash: commit.fingerprint,
            pair: commit.asset,
            bars: commit.candles,
            strike: commit.strike,
            score: commit.score,
            side: commit.engineCall
        )
        do {
            _ = try await persistence.settle(armID: armID, row: row, snapshot: snapshot)
            await reloadFromDisk()
        } catch {
            notice = "Outcome was not saved"
        }
        self.armID = nil
        self.commit = nil
        cabinetSide = "WAIT"
        armedAt = nil
        expired = false
        activeTrade = nil
        predictedOutcome = nil
        candles = []
        publishFrame()
    }

    /// Engine pick. If the desk pick is unavailable, stay on WAIT. Never invent HIGH or LOW.
    private func pickedSignal(from bag: [EngineSignal]) async -> EngineSignal {
        do {
            let desk = try await StrategyEngine.pickDesk(
                signals: bag,
                trades: [],
                payoutPercent: 85,
                preferAsset: nil
            )
            if let asset = desk.asset, let match = bag.first(where: { $0.asset == asset }) {
                return match
            }
            if let wait = bag.first(where: { $0.cabinetSide == "WAIT" }) {
                return wait
            }
            return bag[0]
        } catch {
            let base = bag.first(where: { $0.cabinetSide == "WAIT" }) ?? bag[0]
            return EngineSignal(
                asset: base.asset,
                cabinetSide: "WAIT",
                call: "WAIT",
                why: "Scan engine offline.",
                price: base.price,
                entryPrice: base.entryPrice ?? base.price,
                invalidation: nil,
                confidence: 0,
                asOfMs: base.asOfMs,
                printMs: base.printMs,
                source: base.source
            )
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
    private func consumePendingScanIfReady() async {
        #if os(iOS)
        guard keychainState == .ready, !scanning else { return }
        let defaults = UserDefaults(suiteName: PhoneTarget.appGroup)
        guard defaults?.bool(forKey: PhoneTarget.pendingScanKey) == true else { return }
        defaults?.set(false, forKey: PhoneTarget.pendingScanKey)
        await scan()
        #endif
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
                await refreshQuote()
            }
            try? await Task.sleep(nanoseconds: UInt64(Timing.quotePollMs * 1_000_000))
        }
    }

    private func beamLoop() async {
        while !Task.isCancelled {
            if armedAt != nil || activeTrade != nil {
                now = Date()
                if let trade = activeTrade, trade.isExpired {
                    handleTradeExpiry(trade)
                }
                publishFrame()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Locks in an active 60-second binary trade horizon on the armed setup.
    public func lockInTrade() {
        guard let commit, armedAt != nil || (frame?.verb == "TAP HIGH" || frame?.verb == "TAP LOW") else {
            return
        }
        guard cabinetSide == "HIGH" || cabinetSide == "LOW" else { return }
        let tradeID = armID ?? "\(commit.fingerprint)-\(Int(Date().timeIntervalSince1970 * 1000))"
        armID = tradeID
        let liveStrike = commit.strike
        let trade = ActiveTrade(
            id: tradeID,
            pair: commit.asset,
            side: cabinetSide,
            strike: liveStrike,
            score: commit.score,
            enteredAt: Date(),
            durationSec: 60.0,
            currentPrice: quote?.mid ?? liveStrike,
            fingerprint: commit.fingerprint
        )
        activeTrade = trade
        armedAt = nil
        DeskHaptics.tradeLocked()
        publishFrame()
    }

    private func handleTradeExpiry(_ trade: ActiveTrade) {
        let isWin = trade.isInTheMoney ?? false
        predictedOutcome = isWin ? .hit : .miss
        expired = true
        activeTrade = nil
        awaitingOutcome = true
        DeskHaptics.settleAlert()
        publishFrame()
    }

    private func refreshQuote() async {
        if notice == "Demo Desk (Offline)" {
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
            if activeTrade != nil {
                let wasITM = activeTrade?.isInTheMoney
                activeTrade?.currentPrice = fresh.mid
                if let wasITM, let isITM = activeTrade?.isInTheMoney, wasITM != isITM {
                    if isITM {
                        DeskHaptics.flipITM()
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
        guard let gate = StrategyEngine.slippageGate(
            asset: commit.asset,
            side: cabinetSide,
            strike: commit.strike,
            bid: quote.bid,
            ask: quote.ask
        ) else { return }
        commit.driftPips = gate.adverseDriftPips
        if gate.veto {
            commit.veto = "Slippage"
            armedAt = nil
            noteVeto("Slippage")
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
            engineSHA1: EngineIdentity.pinnedSHA1,
            fingerprint: entry.fingerprint,
            score: entry.score,
            side: entry.verb,
            strike: entry.strike,
            candleCount: entry.candles.count
        )
        voiceSession.start(seal: seal, evidence: entry.why, using: FoundationCoachService())
    }

    func stopVoice() {
        voiceSession.cancel()
    }

    /// Ask the coach about the latest recorded scan without opening a replay modal.
    public func askCoachLatest() {
        guard let entry = journal.first else { return }
        askCoach(for: entry)
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
        let card = await FoundationCoachService().card(for: brief)
        guard openReplayID == id else { return }
        coachExplanation = card
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
    private func remember(_ commit: ScanCommit, verb: String) async {
        let id = "\(commit.fingerprint)-\(Int(commit.scannedAt.timeIntervalSince1970 * 1000))"
        armID = id
        let entry = JournalEntry(
            id: id,
            fingerprint: commit.fingerprint,
            pair: commit.asset,
            score: commit.score,
            side: commit.engineCall,
            verb: verb,
            why: commit.evidence,
            strike: commit.strike,
            veto: commit.veto,
            scannedAt: commit.scannedAt
        )
        let snapshot = SnapshotRecord(
            hash: commit.fingerprint,
            pair: commit.asset,
            bars: commit.candles,
            strike: commit.strike,
            score: commit.score,
            side: commit.engineCall
        )
        do {
            try await persistence.recordScan(entry, snapshot: snapshot)
            await reloadFromDisk()
        } catch {
            journal.insert(replay(entry, bars: commit.candles), at: 0)
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
        outcomeStats = restored.stats
        journal = restored.entries.map { replay($0, bars: restored.bars(for: $0.fingerprint)) }
        for entry in journal {
            if candlesByAsset[entry.pair] == nil && !entry.candles.isEmpty {
                candlesByAsset[entry.pair] = entry.candles
            }
        }
        if candles.isEmpty, let saved = candlesByAsset[pair], !saved.isEmpty {
            candles = saved
        }
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
                fingerprint: trade.fingerprint
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
            elapsedMs: elapsed
        )
        if next.verb == "EXPIRED" {
            expired = true
            armedAt = nil
            frame = frozen(commit, verb: "EXPIRED", remainingMs: 0)
            awaitingOutcome = true
            return
        }
        let armed = next.verb == "TAP HIGH" || next.verb == "TAP LOW"
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
            fingerprint: commit.fingerprint
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
    case markets = "Markets"
    case replay = "Replay"
    case coach = "Coach"
    case journal = "Journal"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .desk: return "bolt.fill"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .replay: return "arrow.counterclockwise"
        case .coach: return "brain.head.profile"
        case .journal: return "book.closed.fill"
        }
    }
}
