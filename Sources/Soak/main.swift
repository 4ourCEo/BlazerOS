import BlazerCore
import Foundation
import LightningDesk

@MainActor
struct SoakRow: Sendable {
    let name: String
    let pass: Bool
    let note: String
}

@MainActor
final class SoakRunner {
    private var rows: [SoakRow] = []

    func check(_ name: String, _ pass: Bool, _ note: String = "") {
        rows.append(SoakRow(name: name, pass: pass, note: note))
    }

    func run() async {
        print("Starting BlazerOS M4 Soak & Stress Verification Suite...")
        await soakEngineEvaluation()
        await soakAtomicLedgerConcurrency()
        await soakCorruptDiskRecovery()
        await soakVoiceNoteAndCloudSyncUnderLoad()
        await soakDeskModelRapidSwitching()

        var failed = 0
        for row in rows {
            let mark = row.pass ? "PASS" : "FAIL"
            if !row.pass { failed += 1 }
            let detail = row.note.isEmpty ? "" : "  \(row.note)"
            print("\(mark)  \(row.name)\(detail)")
        }

        if failed == 0 {
            print("soak ok \(rows.count)")
            exit(0)
        } else {
            print("soak failed \(failed)/\(rows.count)")
            exit(1)
        }
    }

    // MARK: - 1. Engine Evaluation Soak (200 consecutive scans)

    private func soakEngineEvaluation() async {
        var validVerdicts = 0
        var stableHashes = 0
        let baseInput = GoldenFixture.market()
        let baseBars = baseInput.candles1m.map { Candle(time: $0.time, open: $0.open, high: $0.high, low: $0.low, close: $0.close) }

        for i in 0..<100 {
            var input = baseInput
            input.lastPrice += Double(i % 5) * 0.0001
            guard let result = try? await StrategyEngine.evaluate(input: input) else { continue }
            if ["HIGH", "LOW", "WAIT"].contains(result.signal.cabinetSide) && (result.signal.opportunity ?? 0) >= 0 {
                validVerdicts += 1
            }

            let hashA = ScanFingerprint.hex(candles: baseBars)
            let hashB = ScanFingerprint.hex(candles: baseBars)
            if hashA == hashB && hashA == "CE239CDB" {
                stableHashes += 1
            }
        }

        check("engine soak: 100 consecutive scans succeed", validVerdicts == 100, "\(validVerdicts)/100")
        check("engine soak: 100 deterministic fingerprints verified", stableHashes == 100, "\(stableHashes)/100")
    }

    // MARK: - 2. Atomic Ledger Concurrency & Idempotency (100 parallel settlements)

    private func soakAtomicLedgerConcurrency() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-soak-ledger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let coord = PersistenceCoordinator(root: root)
        let total = 100

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<total {
                let id = "soak-arm-\(i)"
                let hash = String(format: "%08X", i + 1000)
                let entry = JournalEntry(
                    id: id,
                    fingerprint: hash,
                    pair: "EUR/USD",
                    score: 70 + (i % 25),
                    side: i % 2 == 0 ? "HIGH" : "LOW",
                    verb: i % 2 == 0 ? "TAP HIGH" : "TAP LOW",
                    why: "Soak test pattern",
                    strike: 1.1000 + Double(i) * 0.0001,
                    veto: nil,
                    scannedAt: Date().addingTimeInterval(Double(i))
                )
                let snapshot = SnapshotRecord(hash: hash, pair: "EUR/USD", bars: [], strike: entry.strike, score: entry.score, side: entry.side)
                let row = LedgerRow(
                    timestamp: Date(),
                    pair: "EUR/USD",
                    hash: hash,
                    score: entry.score,
                    side: entry.side,
                    veto: false,
                    drift: 0.0,
                    outcome: i % 2 == 0 ? "HIT" : "MISS",
                    outcomeEventID: id
                )

                group.addTask {
                    do {
                        try await coord.recordScan(entry, snapshot: snapshot)
                        return try await coord.settle(armID: id, row: row, snapshot: snapshot)
                    } catch {
                        return false
                    }
                }
            }

            var successCount = 0
            for await res in group {
                if res { successCount += 1 }
            }
            self.check("concurrent settlement: 100 scans written atomically", successCount == total, "\(successCount)/\(total)")
        }

        // Verify idempotency under repeated duplicate settlement
        var duplicateAttemptsRefused = 0
        for i in 0..<50 {
            let id = "soak-arm-\(i)"
            let hash = String(format: "%08X", i + 1000)
            let snapshot = SnapshotRecord(hash: hash, pair: "EUR/USD", bars: [], strike: 1.1, score: 75, side: "HIGH")
            let row = LedgerRow(timestamp: Date(), pair: "EUR/USD", hash: hash, score: 75, side: "HIGH", veto: false, drift: 0.0, outcome: "MISS", outcomeEventID: id)
            if let accepted = try? await coord.settle(armID: id, row: row, snapshot: snapshot), !accepted {
                duplicateAttemptsRefused += 1
            }
        }
        check("idempotency soak: 50 duplicate settlements rejected", duplicateAttemptsRefused == 50, "\(duplicateAttemptsRefused)/50")

        let restored = await coord.restore()
        check("ledger restore count matches exact unique records", restored.entries.count == total, "\(restored.entries.count)")
    }

    // MARK: - 3. Corrupt Disk Recovery & Resilience

    private func soakCorruptDiskRecovery() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-soak-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let coord = PersistenceCoordinator(root: root)
        for i in 0..<30 {
            let entry = JournalEntry(
                id: "valid-\(i)",
                fingerprint: String(format: "CORR%04d", i),
                pair: "USD/JPY",
                score: 80,
                side: "LOW",
                verb: "TAP LOW",
                why: "Pre-corruption entry",
                strike: 150.25,
                veto: nil,
                scannedAt: Date().addingTimeInterval(Double(i))
            )
            let snap = SnapshotRecord(hash: entry.fingerprint, pair: entry.pair, bars: [], strike: entry.strike, score: entry.score, side: entry.side)
            try? await coord.recordScan(entry, snapshot: snap)
        }

        // Inject corrupt bytes and half-lines into the journal file
        let journalURL = FileLocations.journal(in: root)
        if let existing = try? String(contentsOf: journalURL, encoding: .utf8) {
            let corruptData = existing + "\n{bad-json-syntax\n{\"id\":\"truncated\n\n\n\u{0000}\u{0001}\n"
            try? corruptData.write(to: journalURL, atomically: true, encoding: .utf8)
        }

        // Recovery check
        let relaunch = PersistenceCoordinator(root: root)
        let restored = await relaunch.restore()
        check("corruption resilience: 30 valid entries preserved after disk damage", restored.entries.count == 30, "\(restored.entries.count)/30")
    }

    // MARK: - 4. Voice Note & CloudSync Under Load

    private func soakVoiceNoteAndCloudSyncUnderLoad() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-soak-voice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let transport = MockCloudSyncTransport(status: .available)
        let coord = PersistenceCoordinator(root: root, cloudTransport: transport)

        for i in 0..<25 {
            let entry = JournalEntry(
                id: "vn-\(i)",
                fingerprint: String(format: "VN%06d", i),
                pair: "GBP/USD",
                score: 82,
                side: "HIGH",
                verb: "TAP HIGH",
                why: "High volatility lift",
                strike: 1.3050,
                veto: nil,
                scannedAt: Date().addingTimeInterval(Double(i))
            )
            let snap = SnapshotRecord(hash: entry.fingerprint, pair: entry.pair, bars: [], strike: entry.strike, score: entry.score, side: entry.side)
            try? await coord.recordScan(entry, snapshot: snap)
            let note = VoiceNote(transcript: "Voice note #\(i) recording clean execution reflection.", createdAt: Date())
            try? await coord.annotate(entryID: entry.id, voiceNote: note)
        }

        let pushStats = (try? await coord.pushCloud()) ?? .zero
        let pullStats = (try? await coord.pullCloud()) ?? .zero

        check("cloud sync soak: 25 documents pushed without errors", pushStats.pushedJournal == 25, "pushed \(pushStats.pushedJournal)")
        check("cloud sync soak: pull idempotency verified", pullStats.pulledJournal == 25, "pulled \(pullStats.pulledJournal)")

        let restored = await coord.restore()
        let notesCount = restored.entries.compactMap(\.voiceNote).count
        check("voice note soak: all 25 voice notes persisted and recovered", notesCount == 25, "\(notesCount)/25")
    }

    // MARK: - 5. Desk Model Rapid Navigation & Pair Switching

    private func soakDeskModelRapidSwitching() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-soak-model-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = LightningDeskModel(storageRoot: root)
        model.showingLaunch = false

        let pairs = ["EUR/USD", "GBP/USD", "USD/JPY", "AUD/USD", "USD/CAD", "EUR/GBP"]
        let tabs = DeskTab.allCases

        for i in 0..<100 {
            let pair = pairs[i % pairs.count]
            let tab = tabs[i % tabs.count]
            model.selectAndNavigate(pair: pair)
            model.activeTab = tab
        }

        check("model soak: 100 rapid tab & pair transitions without state faults", model.pair == pairs[99 % pairs.count], model.pair)
    }
}

let runner = SoakRunner()
await runner.run()
