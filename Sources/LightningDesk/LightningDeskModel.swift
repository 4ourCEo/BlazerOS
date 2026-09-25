import Combine
import Foundation
import BlazerCore

/// One-screen desk state. The frame is derived from the frozen commit. Quotes never rescore it.
@MainActor
public final class LightningDeskModel: ObservableObject {
    public init() {}
    @Published public var pair: String = "EUR/USD"
    @Published var feed: FeedStatus = .connecting
    @Published var candles: [Candle] = []
    @Published var scanning = false
    /// Walk label, for example "GBP/USD 2/6". Nil when idle.
    @Published var scanStep: String?
    /// Last full-book read. Display only.
    @Published var book: [BookRow] = []
    @Published var notice: String?
    @Published private(set) var frame: DeskFrame?
    /// Brand cover. Dismisses on a real LIVE feed, otherwise after a short beat. Never invents LIVE.
    @Published var showingLaunch = true
    @Published var launchMarkLit = false
    @Published var launchWordLit = false
    /// Brief upward offset after a commit. Display only.
    @Published var heroLift: Double = 0
    /// Frozen scans. Newest first. Display only; quotes never rewrite the score.
    @Published private(set) var journal: [ReplayEntry] = []
    @Published var showingJournal = false
    @Published var openReplayID: String?

    private var session: OandaSession?
    private var commit: ScanCommit?
    private var cabinetSide = "WAIT"
    private var armedAt: Date?
    private var quote: LiveQuote?
    private var lastFreshPollAt: Date?
    private var now = Date()
    private var expired = false
    /// Bumped on every press so a new walk replaces the one in flight.
    private var scanGeneration = 0

    let pairs = Assets.watchlist

    public func select(pair next: String) {
        guard next != pair else { return }
        pair = next
        commit = nil
        cabinetSide = "WAIT"
        armedAt = nil
        expired = false
        candles = []
        quote = nil
        notice = nil
        publishFrame()
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
                    barsByAsset[asset] = envelope.snapshotBars ?? envelope.candles ?? []
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
        pair = picked.asset
        commit = next
        cabinetSide = side
        candles = bars
        expired = false
        let armedClock = Date()
        armedAt = (side == "HIGH" || side == "LOW") && next.veto == nil ? armedClock : nil
        notice = nil
        now = armedClock
        publishFrame()
        liftHero()
        if let frame {
            remember(next, verb: frame.verb)
        }
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
            return ready
        case .locked where allowPrompt:
            let prompted = DeskCredentials.session(allowPrompt: true)
            credentialLookup = prompted
            if case .ready(let ready) = prompted {
                session = ready
                return ready
            }
            return nil
        case .locked, .missing, .none:
            return nil
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
                await refreshQuote()
            }
            try? await Task.sleep(nanoseconds: UInt64(Timing.quotePollMs * 1_000_000))
        }
    }

    private func beamLoop() async {
        while !Task.isCancelled {
            if armedAt != nil {
                now = Date()
                publishFrame()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func refreshQuote() async {
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
            applyLiveVeto(quote: fresh)
        }
        feed = FeedStatusResolver.resolve(
            marketOpen: true,
            sessionReady: true,
            transport: batch.transport,
            quote: quote,
            lastFreshPollAt: lastFreshPollAt,
            now: clock
        )
        publishFrame()
    }

    /// A quote may veto an armed beam. It cannot change the score, hash, or strike.
    private func applyLiveVeto(quote: LiveQuote) {
        guard var commit, commit.veto == nil else { return }
        guard cabinetSide == "HIGH" || cabinetSide == "LOW" else { return }
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
            noteVeto("Slippage", fingerprint: commit.fingerprint)
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
    }

    func closeReplay() {
        openReplayID = nil
    }

    /// Snapshot the commit as it was sealed. Later quotes may add a veto only.
    private func remember(_ commit: ScanCommit, verb: String) {
        let id = "\(commit.fingerprint)-\(Int(commit.scannedAt.timeIntervalSince1970 * 1000))"
        let entry = ReplayEntry(
            id: id,
            pair: commit.asset,
            score: commit.score,
            verb: verb,
            why: commit.evidence,
            strike: commit.strike,
            veto: commit.veto,
            fingerprint: commit.fingerprint,
            candles: commit.candles,
            scannedAt: commit.scannedAt
        )
        journal.insert(entry, at: 0)
        if journal.count > 30 {
            journal.removeLast()
        }
    }

    private func noteVeto(_ veto: String, fingerprint: String) {
        guard let index = journal.firstIndex(where: { $0.fingerprint == fingerprint && $0.veto == nil }) else {
            return
        }
        journal[index].veto = veto
    }

    private func publishFrame() {
        guard let commit else {
            frame = nil
            return
        }
        if expired {
            frame = frozen(commit, verb: "EXPIRED", remainingMs: 0)
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
}
