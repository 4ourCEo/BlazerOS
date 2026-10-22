import Foundation
import CloudKit
import BlazerCore

struct Check {
    var name: String
    var pass: Bool
    var detail: String
}

/// Collects results for the checks below.
///
/// The helpers are `@MainActor` and used to receive a `(String, Bool, String) -> Void` closure.
/// Passing them a local function required converting a non-sendable value into a sending
/// function type, which the Swift 6.1 toolchain used by CI rejects. Taking the collector
/// instead keeps every call on the main actor and removes the conversion entirely.
final class CheckResults {
    private(set) var rows: [Check] = []

    func check(_ name: String, _ pass: Bool, _ detail: String = "") {
        rows.append(Check(name: name, pass: pass, detail: detail))
    }
}

@main
struct PersistCheck {
    @MainActor
    static func main() async {
        let results = CheckResults()

        phoneTarget(results)
        coach(results)
        await coachService(results)
        await ledgerOnce(results)
        await malformedLedger(results)
        await malformedSnapshot(results)
        await relaunch(results)
        await malformedJournal(results)
        await voiceNoteAndJournalAnnotation(results)
        await cloudSecurityGate(results)
        slippageGateFailClosed(results)
        wilsonIntervalCheck(results)
        marketEdgeWindowCheck(results)
        await ledgerV2AndStatsEngineCheck(results)
        await cloudSyncRoundTrip(results)
        await cloudLedgerIdempotency(results)
        await cloudOfflineGraceful(results)

        var failed = 0
        for row in results.rows {
            let mark = row.pass ? "PASS" : "FAIL"
            if !row.pass { failed += 1 }
            let detail = row.detail.isEmpty ? "" : "  \(row.detail)"
            print("\(mark)  \(row.name)\(detail)")
        }
        print(failed == 0 ? "persist ok \(results.rows.count)" : "persist failed \(failed)/\(results.rows.count)")
        exit(failed == 0 ? 0 : 1)
    }

    @MainActor
    private static func phoneTarget(_ results: CheckResults) {
        results.check(
            "iPhone 16 point size",
            PhoneTarget.model == "iPhone 16" && PhoneTarget.width == 393 && PhoneTarget.height == 852,
            "\(PhoneTarget.width)x\(PhoneTarget.height)"
        )
        results.check(
            "iPhone 16 pixel size",
            PhoneTarget.scale == 3
                && PhoneTarget.pixelWidth == 1179
                && PhoneTarget.pixelHeight == 2556
                && PhoneTarget.width * PhoneTarget.scale == PhoneTarget.pixelWidth
                && PhoneTarget.height * PhoneTarget.scale == PhoneTarget.pixelHeight,
            ""
        )
        results.check(
            "iPhone 16 safe areas",
            PhoneTarget.topInset == 59 && PhoneTarget.bottomInset == 34 && PhoneTarget.hasDynamicIsland,
            ""
        )
        results.check(
            "iPhone 16 is not Pro",
            !PhoneTarget.hasAlwaysOnDisplay && !PhoneTarget.hasProMotion && PhoneTarget.systemVersion == "26.0",
            ""
        )
        results.check(
            "iPhone 16 identity",
            PhoneTarget.bundleIdentifier == "com.blazer.os" && PhoneTarget.appGroup == "group.com.blazer.os",
            ""
        )
    }

    @MainActor
    private static func coach(_ results: CheckResults) {
        let brief = CoachBrief(pair: "EUR/USD", score: 76, evidence: "Completed bars.", hash: "F9813E3C")
        let prompt = PromptBuilder.prompt(for: brief)
        results.check(
            "coach prompt is the seal only",
            prompt.contains("EUR/USD") && prompt.contains("76") && prompt.contains("Completed bars.") && prompt.contains("F9813E3C"),
            ""
        )
        results.check(
            "coach prompt has no live price",
            !prompt.contains("bid") && !prompt.contains("ask") && !PromptBuilder.instructions.contains("bid"),
            ""
        )
        let sealed = PromptBuilder.sealedCard(brief)
        let again = PromptBuilder.sealedCard(brief)
        results.check(
            "sealed coach card is stable",
            sealed == again && sealed.confidence == "Sealed" && sealed.bullets.count == 3 && sealed.summary == "Completed bars.",
            sealed.summary
        )
        results.check(
            "coach card has no side",
            !sealed.summary.contains("TAP HIGH") && !sealed.summary.contains("TAP LOW") && !sealed.bullets.joined().contains("TAP"),
            ""
        )
        let parsed = PromptBuilder.parse("Summary: Restates the seal.\nConfidence: Sealed\nBullets: Pair EUR/USD | Engine score 76 | Hash F9813E3C\n")
        results.check("coach parse keeps an explanation", parsed?.confidence == "Sealed" && parsed?.bullets.count == 3, "")
        let refused = PromptBuilder.parse("Summary: Take TAP HIGH now.\nConfidence: 99\nBullets: go\n")
        results.check("coach parse refuses a side and a new score", refused == nil, "")
    }

    @MainActor
    private static func coachService(_ results: CheckResults) async {
        let brief = CoachBrief(pair: "EUR/USD", score: 76, evidence: "Completed bars.", hash: "F9813E3C")
        let card = await FoundationCoachService(allowsModel: false).card(for: brief)
        results.check("coach service stays on the sealed card", card == PromptBuilder.sealedCard(brief), card.summary)
    }

    @MainActor
    private static func ledgerOnce(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let row = sampleRow(hash: "F9813E3C", arm: "arm-1", outcome: "HIT")
        let store = LedgerStore(root: root)
        do {
            let wrote = try await store.record(row)
            let duplicate = try await store.record(row)
            results.check("ledger writes once", wrote && !duplicate, "")
            let reopened = LedgerStore(root: root)
            let afterRelaunch = try await reopened.record(
                sampleRow(hash: "F9813E3C", arm: "arm-2", outcome: "MISS")
            )
            let rows = try await reopened.rows()
            results.check("ledger relaunch keeps one row", !afterRelaunch && rows.count == 1 && rows[0].outcome == "HIT", "")
            let stats = try await reopened.stats()
            results.check("ledger stats count the one HIT", stats == OutcomeStats(hits: 1, misses: 0), "")
            let csv = try String(contentsOf: FileLocations.ledgerCSV(in: root), encoding: .utf8)
            results.check(
                "ledger header is canonical",
                csv.hasPrefix(LedgerStore.csvHeader + "\n") && !csv.contains("theirPrice"),
                ""
            )
            results.check("ledger has no token", !csv.contains("token") && !csv.contains("Bearer"), "")
            let refused = try await store.record(sampleRow(hash: "CE239CDB", arm: "", outcome: "HIT"))
            results.check("empty arm id is refused", !refused, "")
        } catch {
            results.check("ledger writes once", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func malformedLedger(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let csv = """
        \(LedgerStore.csvHeader)
        this is not a row
        2020-01-01T00:00:00Z,EUR/USD,AAAA1111,70,HIGH,false,0.0000,HIT
        "broken
        """
        do {
            try csv.write(to: FileLocations.ledgerCSV(in: root), atomically: true, encoding: .utf8)
            let store = LedgerStore(root: root)
            let loaded = try await store.rows()
            results.check("malformed ledger keeps the valid row", loaded.map(\.hash) == ["AAAA1111"], "\(loaded.map(\.hash))")
            let wrote = try await store.record(sampleRow(hash: "BBBB2222", arm: "arm-9", outcome: "MISS"))
            let rows = try await store.rows()
            let stats = try await store.stats()
            results.check(
                "malformed ledger accepts a new row",
                wrote && rows.map(\.hash) == ["AAAA1111", "BBBB2222"] && stats == OutcomeStats(hits: 1, misses: 1),
                "\(rows.map(\.hash))"
            )
        } catch {
            results.check("malformed ledger keeps the valid row", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func malformedSnapshot(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let record = sampleSnapshot(hash: "F9813E3C")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let good = try encoder.encode(record)
            var text = "{bad json\n"
            text += String(decoding: good, as: UTF8.self)
            text += "\n"
            try text.write(to: FileLocations.snapshots(in: root), atomically: true, encoding: .utf8)
            let store = SnapshotStore(root: root)
            let loaded = try await store.load()
            results.check("malformed snapshot keeps the valid record", loaded == [record], "")
            let inserted = try await store.archive(sampleSnapshot(hash: "CE239CDB"))
            let again = try await store.archive(record)
            let hashes = try await store.load().map(\.hash)
            results.check(
                "snapshot hash is not rewritten",
                inserted && !again && hashes == ["F9813E3C", "CE239CDB"],
                hashes.joined(separator: ",")
            )
        } catch {
            results.check("malformed snapshot keeps the valid record", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func relaunch(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = sampleEntry(id: "F9813E3C-1000", hash: "F9813E3C")
        let snapshot = sampleSnapshot(hash: "F9813E3C")
        do {
            let coordinator = PersistenceCoordinator(root: root)
            try await coordinator.recordScan(entry, snapshot: snapshot)
            let restored = await PersistenceCoordinator(root: root).restore()
            results.check(
                "relaunch restores the journal and snapshot bars",
                restored.entries.map(\.id) == ["F9813E3C-1000"]
                    && restored.bars(for: "F9813E3C").map(\.close) == [1.15]
                    && restored.stats == .empty,
                ""
            )
            let row = sampleRow(hash: "F9813E3C", arm: entry.id, outcome: "HIT")
            let reopened = PersistenceCoordinator(root: root)
            let wrote = try await reopened.settle(armID: entry.id, row: row, snapshot: snapshot)
            let second = try await reopened.settle(armID: entry.id, row: row, snapshot: snapshot)
            results.check("HIT writes once", wrote && !second, "")
            let afterQuit = await PersistenceCoordinator(root: root).restore()
            let refused = try await PersistenceCoordinator(root: root).settle(
                armID: entry.id,
                row: sampleRow(hash: "F9813E3C", arm: entry.id, outcome: "MISS"),
                snapshot: snapshot
            )
            let csv = try String(contentsOf: FileLocations.ledgerCSV(in: root), encoding: .utf8)
            results.check(
                "quit restores HIT and refuses a second outcome",
                afterQuit.entries.first?.outcome == "HIT"
                    && afterQuit.bars(for: "F9813E3C").count == 1
                    && afterQuit.stats == OutcomeStats(hits: 1, misses: 0)
                    && !refused
                    && csv.split(separator: "\n").count == 2,
                ""
            )
        } catch {
            results.check("relaunch restores the journal and snapshot bars", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func malformedJournal(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = sampleEntry(id: "arm-7", hash: "CE239CDB")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let good = try encoder.encode(entry)
            var text = "not-json\n"
            text += String(decoding: good, as: UTF8.self)
            text += "\n"
            try text.write(to: FileLocations.journal(in: root), atomically: true, encoding: .utf8)
            let store = JournalStore(root: root)
            let loaded = try await store.load()
            results.check("malformed journal keeps the valid entry", loaded.map(\.id) == ["arm-7"], "")
            try await store.upsert(sampleEntry(id: "arm-8", hash: "F9813E3C"))
            let saved = try await store.load()
            results.check("journal upsert keeps both entries", saved.map(\.id) == ["arm-7", "arm-8"], saved.map(\.id).joined(separator: ","))
        } catch {
            results.check("malformed journal keeps the valid entry", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func voiceNoteAndJournalAnnotation(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let coord = PersistenceCoordinator(root: root)
        let entry = sampleEntry(id: "arm-vn-1", hash: "F9813E3C")
        let snapshot = sampleSnapshot(hash: "F9813E3C")

        do {
            try await coord.recordScan(entry, snapshot: snapshot)
            let note = VoiceNote(transcript: "Clean high wick rejection at 1.17350.", createdAt: Date())
            let tag = Tag(label: "KeyLevelBreak")
            let emotion = Emotion(name: "Calm")
            let lesson = Lesson(text: "Patience on the 8s beam paid off.")
            try await coord.annotate(entryID: entry.id, voiceNote: note, tag: tag, emotion: emotion, lesson: lesson)

            // Simulate app relaunch
            let relaunchCoord = PersistenceCoordinator(root: root)
            let restored = await relaunchCoord.restore()
            let recovered = restored.entries.first(where: { $0.id == entry.id })

            results.check(
                "voice note survives app relaunch",
                recovered?.voiceNote?.transcript == "Clean high wick rejection at 1.17350.",
                recovered?.voiceNote?.transcript ?? "nil"
            )
            results.check(
                "tags and lessons survive app relaunch",
                recovered?.tag?.label == "KeyLevelBreak"
                    && recovered?.emotion?.name == "Calm"
                    && recovered?.lesson?.text == "Patience on the 8s beam paid off.",
                recovered?.lesson?.text ?? "nil"
            )
        } catch {
            results.check("voice note survives app relaunch", false, error.localizedDescription)
            results.check("tags and lessons survive app relaunch", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func cloudSecurityGate(_ results: CheckResults) async {
        let badTokenRecord = CKRecord(recordType: CloudRecordType.ledger)
        badTokenRecord["oandaToken"] = "secret-token-123" as CKRecordValue
        results.check("security gate catches oandaToken key", !CloudSecurityGate.validate(record: badTokenRecord), "")

        let badBearerRecord = CKRecord(recordType: CloudRecordType.ledger)
        badBearerRecord["auth"] = "Bearer oanda_secret" as CKRecordValue
        results.check("security gate catches bearer in values", !CloudSecurityGate.validate(record: badBearerRecord), "")

        let badQuoteRecord = CKRecord(recordType: CloudRecordType.ledger)
        badQuoteRecord["liveQuote"] = "1.0850" as CKRecordValue
        results.check("security gate catches liveQuote key", !CloudSecurityGate.validate(record: badQuoteRecord), "")

        let safeWordsRecord = CKRecord(recordType: CloudRecordType.journal)
        safeWordsRecord["task"] = "Review London session" as CKRecordValue
        safeWordsRecord["midnightNote"] = "Consolidation observed" as CKRecordValue
        results.check("security gate allows task and midnightNote keys", CloudSecurityGate.validate(record: safeWordsRecord), "")

        let leakedTokenRecord = CKRecord(recordType: CloudRecordType.journal)
        leakedTokenRecord["why"] = "Setup note with token 4a9f1234567890abcdef1234567890abcdef4a9f1234567890abcdef1234567890abcdef" as CKRecordValue
        results.check("security gate catches token-shaped string in free-text", !CloudSecurityGate.validate(record: leakedTokenRecord), "")

        let transport = MockCloudSyncTransport()
        var refused = false
        do {
            _ = try await transport.modifyRecords(toSave: [badTokenRecord], toDelete: [])
        } catch CloudSyncError.securityGateViolation {
            refused = true
        } catch {}
        results.check("transport refuses forbidden security gate records", refused, "")
    }

    @MainActor
    private static func cloudSyncRoundTrip(_ results: CheckResults) async {
        let rootA = makeRoot()
        let rootB = makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let transport = MockCloudSyncTransport(status: .available)
        let coordA = PersistenceCoordinator(root: rootA, cloudTransport: transport)
        let coordB = PersistenceCoordinator(root: rootB, cloudTransport: transport)

        let entry = sampleEntry(id: "cloud-arm-1", hash: "F9813E3C")
        let snapshot = sampleSnapshot(hash: "F9813E3C")
        let row = sampleRow(hash: "F9813E3C", arm: entry.id, outcome: "HIT")

        do {
            try await coordA.recordScan(entry, snapshot: snapshot)
            _ = try await coordA.settle(armID: entry.id, row: row, snapshot: snapshot)

            let pushed = try await coordA.pushCloud()
            results.check("cloud push saves documents", pushed.pushedLedger == 1 && pushed.pushedSnapshots == 1 && pushed.pushedJournal == 1, "")

            let pulled = try await coordB.pullCloud()
            results.check("cloud pull receives documents", pulled.pulledLedger == 1 && pulled.pulledSnapshots == 1 && pulled.pulledJournal == 1, "")

            let restoredB = await coordB.restore()
            results.check(
                "device B restores synced HIT, bars, and journal",
                restoredB.stats == OutcomeStats(hits: 1, misses: 0)
                    && restoredB.entries.first?.outcome == "HIT"
                    && restoredB.bars(for: "F9813E3C").count == 1,
                ""
            )
        } catch {
            results.check("cloud sync round trip", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func cloudLedgerIdempotency(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MockCloudSyncTransport(status: .available)
        let coord = PersistenceCoordinator(root: root, cloudTransport: transport)

        let entry = sampleEntry(id: "cloud-arm-2", hash: "CE239CDB")
        let snapshot = sampleSnapshot(hash: "CE239CDB")
        let row = sampleRow(hash: "CE239CDB", arm: entry.id, outcome: "HIT")

        do {
            try await coord.recordScan(entry, snapshot: snapshot)
            _ = try await coord.settle(armID: entry.id, row: row, snapshot: snapshot)
            _ = try await coord.pushCloud()

            let secondPull = try await coord.pullCloud()
            results.check("second pull does not duplicate ledger", secondPull.pulledLedger == 0, "")

            let csv = try String(contentsOf: FileLocations.ledgerCSV(in: root), encoding: .utf8)
            results.check("ledger csv has exactly one row", csv.split(separator: "\n").count == 2, "")
        } catch {
            results.check("cloud ledger idempotency", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func cloudOfflineGraceful(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = MockCloudSyncTransport(status: .noAccount)
        let coord = PersistenceCoordinator(root: root, cloudTransport: transport)

        let entry = sampleEntry(id: "cloud-arm-3", hash: "AAAA1111")
        let snapshot = sampleSnapshot(hash: "AAAA1111")
        let row = sampleRow(hash: "AAAA1111", arm: entry.id, outcome: "MISS")

        do {
            try await coord.recordScan(entry, snapshot: snapshot)
            let settled = try await coord.settle(armID: entry.id, row: row, snapshot: snapshot)
            results.check("local settle succeeds when cloud is unauthenticated", settled, "")

            var pushRefused = false
            do {
                _ = try await coord.pushCloud()
            } catch CloudSyncError.unauthenticated {
                pushRefused = true
            }
            results.check("push fails gracefully with unauthenticated error", pushRefused, "")

            let restored = await coord.restore()
            results.check("local restore works offline", restored.stats == OutcomeStats(hits: 0, misses: 1), "")
        } catch {
            results.check("cloud offline graceful", false, error.localizedDescription)
        }
    }

    @MainActor
    private static func slippageGateFailClosed(_ results: CheckResults) {
        let nanResult = StrategyEngine.slippageGate(asset: "EUR/USD", side: "HIGH", strike: Double.nan, bid: 1.0850, ask: 1.0852)
        results.check("slippage gate vetoes NaN strike", nanResult.veto == true, "")

        let nanQuote = StrategyEngine.slippageGate(asset: "EUR/USD", side: "HIGH", strike: 1.0850, bid: Double.nan, ask: 1.0852)
        results.check("slippage gate vetoes NaN quote", nanQuote.veto == true, "")

        let crossed = StrategyEngine.slippageGate(asset: "EUR/USD", side: "HIGH", strike: 1.0850, bid: 1.0855, ask: 1.0850)
        results.check("slippage gate vetoes crossed quote", crossed.veto == true, "")

        let zeroBid = StrategyEngine.slippageGate(asset: "EUR/USD", side: "HIGH", strike: 1.0850, bid: 0.0, ask: 1.0852)
        results.check("slippage gate vetoes zero bid", zeroBid.veto == true, "")
    }

    @MainActor
    private static func wilsonIntervalCheck(_ results: CheckResults) {
        let zero = EdgeEvidence.wilsonScoreInterval(wins: 0, total: 0)
        results.check("wilson interval 0/0 is 0", zero.lower == 0 && zero.upper == 0, "")

        let w50 = EdgeEvidence.wilsonScoreInterval(wins: 50, total: 100)
        let w50Correct = abs(w50.lower - 0.4038) < 0.01 && abs(w50.upper - 0.5962) < 0.01
        results.check("wilson interval 50/100 bounds match", w50Correct, "\(w50.lower)...\(w50.upper)")

        let ev = EdgeEvidence(wins: 35, sampleSize: 60)
        results.check("edge evidence win rate and confidence", abs(ev.winRate - (35.0 / 60.0)) < 0.001 && ev.lower95 > 0.45 && ev.upper95 < 0.72, "")
        results.check("edge evidence has standard caveat", ev.caveat == EdgeEvidence.standardCaveat, "")
    }

    @MainActor
    private static func marketEdgeWindowCheck(_ results: CheckResults) {
        var cal = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return }
        cal.timeZone = utc
        let comps = DateComponents(year: 2026, month: 10, day: 3, hour: 14, minute: 0)
        if let sat = cal.date(from: comps) {
            let win = MarketEdgeWindow.current(at: sat)
            results.check("saturday FX closed returns offPeak", !win.isPrime && !win.isTactical, win.badgeTitle)
        }
    }

    @MainActor
    private static func ledgerV2AndStatsEngineCheck(_ results: CheckResults) async {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LedgerStore(root: root)

        let rowV2 = LedgerRow(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pair: "GBP/USD",
            hash: "F9813E3C",
            score: 76,
            side: "HIGH",
            veto: false,
            drift: 0.3,
            outcome: "HIT",
            outcomeEventID: "arm-v2-1",
            payout: 0.88,
            stake: 10.0,
            marketWindow: "SUPREME PRIME",
            engineSHA: "1a1d264d44eec606ded991cb4814df953bc07b34",
            fullFingerprint: "F9813E3C",
            entryQuote: 1.27500,
            expiryPrice: 1.27530
        )

        do {
            let written = try await store.record(rowV2)
            results.check("ledger v2 record written", written, "")

            let loaded = try await store.rows()
            results.check("ledger v2 loads row", loaded.count == 1, "\(loaded.count)")
            if let first = loaded.first {
                results.check(
                    "ledger v2 preserves metadata",
                    first.payout == 0.88
                        && first.stake == 10.0
                        && first.marketWindow == "SUPREME PRIME"
                        && first.entryQuote == 1.27500
                        && first.expiryPrice == 1.27530,
                    first.marketWindow ?? "nil"
                )
            }

            let statsEmpty = LedgerStatsEngine.evaluate(pair: "EUR/USD", rows: loaded)
            results.check("stats engine marks missing calibration provenance", statsEmpty.statusBadge == "UNVERIFIED PRIOR" && statsEmpty.sampleSize == 0, statsEmpty.statusBadge)

            let statsGBP = LedgerStatsEngine.evaluate(pair: "GBP/USD", rows: loaded)
            results.check(
                "unlabelled row is reference, not measured performance",
                statsGBP.sampleSize == 0 && statsGBP.referenceSampleSize == 1 && statsGBP.wins == 0,
                statsGBP.statusBadge
            )

            var confirmedRow = rowV2
            confirmedRow.outcomeEventID = "arm-v2-2"
            confirmedRow.labelSource = "venue-confirmed"
            let measured = LedgerStatsEngine.evaluate(pair: "GBP/USD", rows: loaded + [confirmedRow])
            results.check(
                "venue-confirmed row is measured",
                measured.sampleSize == 1 && measured.wins == 1 && measured.winRate == 1.0,
                measured.statusBadge
            )

            var syntheticRows: [LedgerRow] = []
            for i in 0..<50 {
                syntheticRows.append(
                    LedgerRow(
                        timestamp: Date(),
                        pair: "USD/JPY",
                        hash: "HASH\(i)",
                        score: 70,
                        side: "HIGH",
                        veto: false,
                        drift: 0.1,
                        outcome: i < 35 ? "HIT" : "MISS",
                        outcomeEventID: "arm-synth-\(i)"
                    )
                )
            }
            let statsJPY = LedgerStatsEngine.evaluate(pair: "USD/JPY", rows: syntheticRows)
            results.check("stats engine does not certify unverified outcomes", !statsJPY.isProvenEdge && statsJPY.statusBadge.contains("UNVERIFIED"), statsJPY.statusBadge)
        } catch {
            results.check("ledger v2 and stats engine check", false, error.localizedDescription)
        }
    }

    private static func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("blazer-persist-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func sampleRow(hash: String, arm: String, outcome: String) -> LedgerRow {
        LedgerRow(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            pair: "EUR/USD",
            hash: hash,
            score: 76,
            side: "HIGH",
            veto: false,
            drift: 0,
            outcome: outcome,
            outcomeEventID: arm
        )
    }

    private static func sampleSnapshot(hash: String) -> SnapshotRecord {
        SnapshotRecord(
            hash: hash,
            pair: "EUR/USD",
            bars: [Candle(time: 60, open: 1.1, high: 1.2, low: 1.0, close: 1.15)],
            strike: 1.17342,
            score: 76,
            side: "HIGH"
        )
    }

    private static func sampleEntry(id: String, hash: String) -> JournalEntry {
        JournalEntry(
            id: id,
            fingerprint: hash,
            pair: "EUR/USD",
            score: 76,
            side: "HIGH",
            verb: "TAP HIGH",
            why: "Completed bars.",
            strike: 1.17342,
            veto: nil,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
