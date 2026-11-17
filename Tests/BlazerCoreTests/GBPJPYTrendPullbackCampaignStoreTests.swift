import Foundation
import Darwin
import Testing
@testable import BlazerCore

struct GBPJPYTrendPullbackCampaignStoreTests {
    private struct Fixture {
        let configuration: GBPJPYTrendPullbackConfiguration
        let definition: GBPJPYTrendPullbackCampaignDefinition
        let lower: [GBPJPYTrendPullbackBar]
        let higher: [GBPJPYTrendPullbackBar]
        let contexts: [GBPJPYTrendPullbackContext]
        let provenance: GBPJPYTrendPullbackDiscoveryProvenance
        let root: URL

        func emptyProposal(revision: UInt64 = 0,
                           cursor: GBPJPYTrendPullbackEventCursor = .init(consumedKeys: []),
                           bars: [GBPJPYTrendPullbackBar]? = nil,
                           contexts suppliedContexts: [GBPJPYTrendPullbackContext]? = nil) -> GBPJPYTrendPullbackCampaignProposal {
            let lowerBars = bars ?? Array(lower.prefix(6))
            let contexts = suppliedContexts ?? self.contexts
            let window = GBPJPYTrendPullbackWindow(firstLowerBarID: lowerBars[0].id,
                                                   lastLowerBarID: lowerBars[lowerBars.count - 1].id)
            let asOf = lowerBars.last!.startTime.addingTimeInterval(61)
            let batch = GBPJPYTrendPullbackV1.discoverBreakEventBatch(lowerBars: lowerBars,
                higherBars: higher, contexts: contexts, provenance: provenance, asOf: asOf,
                window: window, cursor: cursor, configuration: configuration)
            let evidence = GBPJPYTrendPullbackDiscoveryEvidence(batch: batch, lowerBars: lowerBars,
                higherBars: higher, contexts: contexts, provenance: provenance, cursor: cursor)
            let points = lowerBars.map { GBPJPYTrendPullbackCampaignBarPoint(id: $0.id, startTime: $0.startTime) }
            return GBPJPYTrendPullbackCampaignProposal(expectedRevision: revision,
                priorCursorDigest: cursor.digest, window: GBPJPYTrendPullbackCampaignWindow(points: points),
                discovery: evidence, evaluations: [])
        }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("campaign-\(UUID().uuidString)")
        let start = Date(timeIntervalSince1970: 1_800_006_000)
        let config = GBPJPYTrendPullbackConfiguration(version: "synthetic-test-v1", instrument: "GBP/JPY", provider: "synthetic",
            allowedEnvironments: ["practice"], pipSize: 0.01, priceTickSize: 0.001,
            lowerTimeframeSeconds: 60, higherTimeframeSeconds: 300, gridOriginUTCSeconds: 0,
            lowerLeftBars: 2, lowerRightBars: 2, higherLeftBars: 2, higherRightBars: 2,
            maximumContextAgeSeconds: 7_200, atrLookbackBars: 3, minimumBreakATR: 0.5,
            pullbackToleranceATR: 0.2, invalidationBufferATR: 0.1, continuationBufferATR: 0.1,
            maximumBarsFromBreak: 8, maximumBarsAfterPullback: 5, stopBufferATR: 0.2, targetR: 2,
            maximumSourceQuoteAgeSeconds: 5, maximumReceiptQuoteAgeSeconds: 5,
            quoteSamplingPolicy: "synthetic-complete", maximumSpreadPips: 2,
            maximumAdverseDriftPips: 2, additionalRoundTripCostPips: 0.1,
            minimumRewardToCost: 2, sessionCalendarDigest: "calendar-test", timeZoneID: "UTC",
            allowedSessions: ["test-session"], regimeVersion: "regime-test-v1", allowedRegimes: ["trend"],
            buildIdentityPolicy: "explicit", digestVersion: "sha256-sorted-json-v1")
        let codeDigest = String(repeating: "a", count: 64)
        let definition = GBPJPYTrendPullbackCampaignDefinition(configuration: config, environment: "practice",
            buildID: "synthetic-build", codeDigest: codeDigest, sessionID: "test-session",
            sessionOpen: start, sessionClose: start.addingTimeInterval(3_600))
        let values: [(Double, Double, Double, Double)] = [
            (180, 180.1, 179.9, 180), (180, 180.2, 179.9, 180.1),
            (180.2, 180.4, 180, 180.2), (180.8, 181, 180.1, 180.8),
            (180.6, 180.9, 180.3, 180.6), (180.6, 180.8, 180.2, 180.6)
        ]
        let lower = values.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "l\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: start.addingTimeInterval(Double(i * 60)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
        let htfStart = start.addingTimeInterval(-3_600)
        let hValues: [(Double, Double, Double, Double)] = [
            (180, 180.5, 179.5, 180), (180, 180.6, 179.6, 180.1),
            (180, 180.4, 179, 180.2), (180.2, 180.6, 179.4, 180.3),
            (180.5, 181, 179.5, 180.8), (180.4, 180.8, 179.6, 180.3),
            (180.3, 180.7, 179.2, 180.4), (180.4, 180.8, 179.7, 180.5),
            (180.6, 181.2, 179.6, 180.9), (180.7, 180.9, 179.7, 180.8),
            (180.5, 180.9, 179.8, 180.4), (180.4, 180.8, 179.9, 180.5)
        ]
        let higher = hValues.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "h\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: htfStart.addingTimeInterval(Double(i * 300)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
        let context = GBPJPYTrendPullbackContext(sessionID: "test-session", sessionCalendarDigest: "calendar-test",
            timeZoneID: "UTC", regime: "trend", regimeVersion: "regime-test-v1", digest: "context-test",
            sourceIDs: ["calendar-source", "regime-source"], measuredAt: start.addingTimeInterval(-1_800),
            sessionOpen: start.addingTimeInterval(-1_800), sessionClose: start.addingTimeInterval(3_600))
        let provenance = GBPJPYTrendPullbackDiscoveryProvenance(provider: "synthetic", environment: "practice",
            buildID: "synthetic-build", codeDigest: codeDigest, snapshotDigest: "source-snapshot",
            lineageIsProviderNative: true, sourceIDs: ["discovery-feed", "discovery-build"])
        return Fixture(configuration: config, definition: definition, lower: lower, higher: higher,
            contexts: [context], provenance: provenance, root: root)
    }

    private func eventBars(_ f: Fixture) -> [GBPJPYTrendPullbackBar] {
        let values: [(Double, Double, Double, Double)] = [
            (180, 180.1, 179.9, 180), (180, 180.2, 179.9, 180.1),
            (180.2, 180.4, 180, 180.2), (180.8, 181, 180.1, 180.8),
            (180.6, 180.9, 180.3, 180.6), (180.6, 180.8, 180.2, 180.6),
            (180.8, 181.5, 180.5, 181.4), (181, 181.3, 180.9, 181),
            (181.1, 181.6, 181, 181.5), (181.4, 181.7, 181.2, 181.5),
            (181.8, 182, 181.4, 181.8), (181.6, 181.8, 181.3, 181.6),
            (181.5, 181.7, 181.2, 181.5), (182.3, 182.7, 181.5, 182.6),
            (181.4, 181.6, 181.3, 181.5), (181.5, 181.7, 181.4, 181.6)
        ]
        let start = f.lower[0].startTime
        return values.enumerated().map { i, v in
            GBPJPYTrendPullbackBar(id: "l\(i)", instrument: "GBP/JPY", provider: "synthetic",
                startTime: start.addingTimeInterval(Double(i * 60)), open: v.0, high: v.1,
                low: v.2, close: v.3, complete: true)
        }
    }

    private func eventProposal(_ f: Fixture, bars: [GBPJPYTrendPullbackBar],
        windowIndices: ClosedRange<Int>, revision: UInt64, cursor: GBPJPYTrendPullbackEventCursor,
        active: [GBPJPYTrendPullbackCampaignEventRecord]) -> GBPJPYTrendPullbackCampaignProposal {
        let selected = Array(bars[windowIndices])
        let causalBars = Array(bars.prefix(windowIndices.upperBound + 1))
        let sourceWindow = GBPJPYTrendPullbackWindow(firstLowerBarID: selected[0].id,
                                                      lastLowerBarID: selected[selected.count - 1].id)
        let asOf = selected.last!.startTime.addingTimeInterval(61)
        let batch = GBPJPYTrendPullbackV1.discoverBreakEventBatch(lowerBars: causalBars,
            higherBars: f.higher, contexts: f.contexts, provenance: f.provenance,
            asOf: asOf, window: sourceWindow, cursor: cursor, configuration: f.configuration)
        let discovery = GBPJPYTrendPullbackDiscoveryEvidence(batch: batch, lowerBars: causalBars,
            higherBars: f.higher, contexts: f.contexts, provenance: f.provenance, cursor: cursor)
        let activeByID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = active.map { ($0.descriptor, $0.discovery, $0.quoteContinuationCursor) }
            + batch.descriptors.map { ($0, discovery, nil as GBPJPYTrendPullbackQuoteContinuationCursor?) }
        let evaluations = candidates.map { candidate, eventDiscovery, priorCursor in
            let quoteCursor = priorCursor ?? GBPJPYTrendPullbackQuoteContinuationCursor(
                discovery: eventDiscovery, candidate: candidate, configuration: f.configuration)
            let inputs = GBPJPYTrendPullbackCampaignEvaluation.Inputs(lowerBars: causalBars,
                higherBars: f.higher, quotes: [], contexts: f.contexts,
                provenance: GBPJPYTrendPullbackProvenance(environment: "practice",
                    buildID: "synthetic-build", codeDigest: String(repeating: "a", count: 64),
                    snapshotDigest: "evaluation-\(Int(asOf.timeIntervalSince1970))",
                    lineageIsProviderNative: true, quoteWindowComplete: false,
                    quoteSamplingPolicy: "synthetic-complete"),
                asOf: asOf, quoteCursor: quoteCursor, quoteWindowAttestation: nil)
            let decision = GBPJPYTrendPullbackV1.evaluateActiveEvent(discovery: eventDiscovery,
                candidate: candidate, evaluationLowerBars: causalBars, evaluationHigherBars: f.higher,
                quotes: [], evaluationContexts: f.contexts, quoteCursor: quoteCursor,
                quoteWindowAttestation: nil, provenance: inputs.provenance, asOf: asOf,
                configuration: f.configuration)
            return GBPJPYTrendPullbackCampaignEvaluation(eventID: candidate.id,
                inputs: inputs, decision: decision)
        }
        _ = activeByID
        let points = selected.map { GBPJPYTrendPullbackCampaignBarPoint(id: $0.id, startTime: $0.startTime) }
        return GBPJPYTrendPullbackCampaignProposal(expectedRevision: revision,
            priorCursorDigest: cursor.digest, window: GBPJPYTrendPullbackCampaignWindow(points: points),
            discovery: discovery, evaluations: evaluations)
    }

    @Test func emptyCheckpointPersistsAndReplaysAfterNewInstance() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        let initial = try await store.initialize()
        let proposal = f.emptyProposal()
        #expect(proposal.discovery.batch.status == .completeEmpty)
        let receipt = try await store.commit(proposal)
        #expect(receipt.revision == 1)
        let relaunched = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        let snapshot = try await relaunched.load()
        #expect(snapshot.revision == 1)
        #expect(snapshot.transactions.count == 1)
        #expect(snapshot.transactions[0].proposal == proposal)
        #expect(snapshot.transactions[0].previousSnapshotDigest == initial.digest)
    }

    @Test func exactRetryFromNewInstanceReturnsOriginalRevision() async throws {
        let f = try fixture()
        let first = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await first.initialize()
        let proposal = f.emptyProposal()
        let committed = try await first.commit(proposal)
        let second = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        let retry = try await second.commit(proposal)
        #expect(retry.disposition == .duplicate)
        #expect(retry.transactionID == committed.transactionID)
        #expect(retry.revision == committed.revision)
    }

    @Test func staleRevisionAndReusedIdentityWithChangedContentFailClosed() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let proposal = f.emptyProposal()
        _ = try await store.commit(proposal)
        let exactRetry = try await store.commit(proposal)
        #expect(exactRetry.disposition == .duplicate)
        let alteredEvidence = GBPJPYTrendPullbackDiscoveryEvidence(batch: proposal.discovery.batch,
            lowerBars: proposal.discovery.lowerBars, higherBars: proposal.discovery.higherBars,
            contexts: [], provenance: proposal.discovery.provenance, cursor: proposal.discovery.cursor)
        let altered = GBPJPYTrendPullbackCampaignProposal(expectedRevision: proposal.expectedRevision,
            priorCursorDigest: proposal.priorCursorDigest, window: proposal.window,
            discovery: alteredEvidence, evaluations: proposal.evaluations)
        do {
            _ = try await store.commit(altered)
            Issue.record("expected same-identity content conflict")
        } catch let error as GBPJPYTrendCampaignError {
            #expect(error == .transactionConflict(altered.transactionID(campaignID: f.definition.campaignID)))
        }
    }

    @Test func changedWindowOnStaleBaseIsRejected() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let first = f.emptyProposal()
        _ = try await store.commit(first)
        let changedPoints = first.window.points.enumerated().map { index, point in
            GBPJPYTrendPullbackCampaignBarPoint(id: index == 0 ? "changed-\(point.id)" : point.id,
                                                startTime: point.startTime)
        }
        let changedWindow = GBPJPYTrendPullbackCampaignWindow(points: changedPoints)
        let stale = GBPJPYTrendPullbackCampaignProposal(expectedRevision: 0,
            priorCursorDigest: first.priorCursorDigest, window: changedWindow,
            discovery: first.discovery, evaluations: [])
        do {
            _ = try await store.commit(stale)
            Issue.record("expected stale revision")
        } catch let error as GBPJPYTrendCampaignError {
            #expect(error == .staleRevision(expected: 0, actual: 1))
        }
    }

    @Test func invalidWindowEvidenceDoesNotAdvance() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let original = f.emptyProposal()
        let points = original.window.points.enumerated().map { index, point in
            GBPJPYTrendPullbackCampaignBarPoint(id: point.id,
                startTime: point.startTime.addingTimeInterval(index == 3 ? 1 : 0))
        }
        let invalid = GBPJPYTrendPullbackCampaignProposal(expectedRevision: 0,
            priorCursorDigest: original.priorCursorDigest,
            window: GBPJPYTrendPullbackCampaignWindow(points: points),
            discovery: original.discovery, evaluations: [])
        do {
            _ = try await store.commit(invalid)
            Issue.record("expected window evidence mismatch")
        } catch let error as GBPJPYTrendCampaignError {
            guard case .invalidTransaction = error else { Issue.record("unexpected error: \(error)"); return }
        }
        let unchanged = try await store.load()
        #expect(unchanged.revision == 0)
    }

    @Test func corruptSnapshotFailsClosedInsteadOfResetting() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let snapshotURL = f.root.appendingPathComponent(f.definition.campaignID + ".json")
        try Data("not-json".utf8).write(to: snapshotURL)
        do {
            _ = try await store.initialize()
            Issue.record("expected corrupt snapshot")
        } catch let error as GBPJPYTrendCampaignError {
            guard case .corruptSnapshot = error else { Issue.record("unexpected error: \(error)"); return }
        }
    }

    @Test func lockContentionTimesOutAndCanBeRetried() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition, lockTimeout: 0.05)
        _ = try await store.initialize()
        let lockURL = f.root.appendingPathComponent(f.definition.campaignID + ".lock")
        let descriptor = open(lockURL.path, O_RDWR)
        #expect(descriptor >= 0)
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        do {
            _ = try await store.load()
            Issue.record("expected bounded lock timeout")
        } catch let error as GBPJPYTrendCampaignError {
            #expect(error == .lockTimedOut)
        }
        #expect(flock(descriptor, LOCK_UN) == 0)
        close(descriptor)
        let recovered = try await store.load()
        #expect(recovered.revision == 0)
    }

    @Test func discoveryFromAnotherSessionCannotEnterCampaign() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let lower = Array(f.lower.prefix(6))
        let window = GBPJPYTrendPullbackWindow(firstLowerBarID: lower[0].id, lastLowerBarID: lower[5].id)
        let foreignContext = GBPJPYTrendPullbackContext(sessionID: "other-session",
            sessionCalendarDigest: "calendar-test", timeZoneID: "UTC", regime: "range",
            regimeVersion: "regime-test-v1", digest: "other-context", sourceIDs: ["other-source"],
            measuredAt: f.contexts[0].measuredAt, sessionOpen: f.contexts[0].sessionOpen,
            sessionClose: f.contexts[0].sessionClose)
        let batch = GBPJPYTrendPullbackV1.discoverBreakEventBatch(lowerBars: lower,
            higherBars: f.higher, contexts: [foreignContext], provenance: f.provenance,
            asOf: lower[5].startTime.addingTimeInterval(61), window: window,
            cursor: .init(consumedKeys: []), configuration: f.configuration)
        #expect(batch.status == .completeEmpty)
        let evidence = GBPJPYTrendPullbackDiscoveryEvidence(batch: batch, lowerBars: lower,
            higherBars: f.higher, contexts: [foreignContext], provenance: f.provenance,
            cursor: .init(consumedKeys: []))
        let proposal = GBPJPYTrendPullbackCampaignProposal(expectedRevision: 0,
            priorCursorDigest: evidence.cursor.digest,
            window: GBPJPYTrendPullbackCampaignWindow(points: lower.map {
                GBPJPYTrendPullbackCampaignBarPoint(id: $0.id, startTime: $0.startTime)
            }), discovery: evidence, evaluations: [])
        do {
            _ = try await store.commit(proposal)
            Issue.record("expected campaign session identity rejection")
        } catch let error as GBPJPYTrendCampaignError {
            guard case .invalidTransaction(let issues) = error else { Issue.record("unexpected error: \(error)"); return }
            #expect(issues.contains("discovery_session_identity_mismatch"))
        }
    }

    @Test func disallowedCampaignSessionIsRejectedBeforeCreatingSnapshot() async throws {
        let f = try fixture()
        let definition = GBPJPYTrendPullbackCampaignDefinition(configuration: f.configuration,
            environment: "practice", buildID: "synthetic-build",
            codeDigest: String(repeating: "a", count: 64), sessionID: "not-allowed",
            sessionOpen: f.definition.sessionOpen, sessionClose: f.definition.sessionClose)
        do {
            _ = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: definition)
            Issue.record("expected disallowed campaign session rejection")
        } catch let error as GBPJPYTrendCampaignError {
            guard case .invalidDefinition(let issues) = error else { Issue.record("unexpected error: \(error)"); return }
            #expect(issues.contains("campaign_session_not_allowed"))
        }
        #expect(!FileManager.default.fileExists(atPath: f.root.appendingPathComponent(definition.campaignID + ".json").path))
    }

    @Test func failedAtomicReplacementLeavesPriorSnapshotReadable() async throws {
        let f = try fixture()
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let failedStore = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition,
            lockTimeout: 1, snapshotWriter: { _, _ in throw CocoaError(.fileWriteUnknown) })
        do {
            _ = try await failedStore.commit(f.emptyProposal())
            Issue.record("expected injected atomic replacement failure")
        } catch let error as GBPJPYTrendCampaignError {
            #expect(error == .persistenceFailure("atomic_snapshot_write_failed"))
        }
        let unchanged = try await store.load()
        #expect(unchanged.revision == 0)
    }

    @Test func twoInstancesRacingOnOneBaseHaveOneWinner() async throws {
        let f = try fixture()
        let a = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        let b = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await a.initialize()
        let p1 = f.emptyProposal()
        let original = f.contexts[0]
        let changedContext = GBPJPYTrendPullbackContext(sessionID: original.sessionID,
            sessionCalendarDigest: original.sessionCalendarDigest, timeZoneID: original.timeZoneID,
            regime: original.regime, regimeVersion: original.regimeVersion,
            digest: "context-v2", sourceIDs: original.sourceIDs + ["context-revision"],
            measuredAt: original.measuredAt.addingTimeInterval(1),
            sessionOpen: original.sessionOpen, sessionClose: original.sessionClose)
        let p2 = f.emptyProposal(contexts: [changedContext])
        #expect(p2.discovery.batch.status == .completeEmpty)
        #expect(p1.transactionID(campaignID: f.definition.campaignID)
            != p2.transactionID(campaignID: f.definition.campaignID))
        let p1Validation = try GBPJPYTrendPullbackCampaignStore(
            root: f.root.appendingPathComponent("p1-validation"), definition: f.definition)
        let p2Validation = try GBPJPYTrendPullbackCampaignStore(
            root: f.root.appendingPathComponent("p2-validation"), definition: f.definition)
        _ = try await p1Validation.initialize()
        _ = try await p2Validation.initialize()
        #expect(try await p1Validation.commit(p1).disposition == .committed)
        #expect(try await p2Validation.commit(p2).disposition == .committed)
        let taskOne = Task { try await a.commit(p1) }
        let taskTwo = Task { try await b.commit(p2) }
        let outcomes = [await taskOne.result, await taskTwo.result]
        #expect(outcomes.filter { if case .success = $0 { true } else { false } }.count == 1)
        let errors = outcomes.compactMap { outcome -> GBPJPYTrendCampaignError? in
            guard case .failure(let error) = outcome else { return nil }
            return error as? GBPJPYTrendCampaignError
        }
        #expect(errors.count == 1)
        if let error = errors.first { #expect(error == .staleRevision(expected: 0, actual: 1)) }
        let final = try await a.load()
        #expect(final.revision == 1)
    }

    @Test func overlappingEventsContinueAcrossEmptyCheckpointAndRetainQuoteCursors() async throws {
        let f = try fixture()
        let bars = eventBars(f)
        let store = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        _ = try await store.initialize()
        let emptyCursor = GBPJPYTrendPullbackEventCursor(consumedKeys: [])
        let first = eventProposal(f, bars: bars, windowIndices: 0...13, revision: 0,
                                  cursor: emptyCursor, active: [])
        #expect(first.discovery.batch.status == .completeWithEvents)
        #expect(first.discovery.batch.descriptors.count == 2)
        #expect(first.evaluations.allSatisfy { evaluation in
            evaluation.inputs.lowerBars.allSatisfy {
                $0.startTime.addingTimeInterval(60) <= evaluation.inputs.asOf
            } && !evaluation.decision.reasonCodes.contains("BAR_DATA_INVALID")
        })
        _ = try await store.commit(first)
        let afterFirst = try await store.load()
        #expect(afterFirst.activeEvents.count == 2)
        let firstCursors = Dictionary(afterFirst.activeEvents.map { ($0.id, $0.quoteContinuationCursor) },
                                      uniquingKeysWith: { first, _ in first })
        #expect(firstCursors.values.allSatisfy { $0 != nil })

        let second = eventProposal(f, bars: bars, windowIndices: 14...14, revision: 1,
            cursor: afterFirst.cursor, active: afterFirst.activeEvents)
        #expect(second.discovery.batch.status == .completeEmpty)
        _ = try await store.commit(second)
        let relaunch = try GBPJPYTrendPullbackCampaignStore(root: f.root, definition: f.definition)
        let afterSecond = try await relaunch.load()
        #expect(afterSecond.transactions[1].proposal.discovery.batch.status == .completeEmpty)
        #expect(afterSecond.activeEvents.count == 1)
        #expect(afterSecond.activeEvents[0].descriptor.breakBarID == "l6")
        #expect(afterSecond.transactions[1].evaluatedEvents.count == 2)
        let terminalAfterEmptyCheckpoint = try #require(afterSecond.transactions[1].evaluatedEvents.first {
            $0.decision.disposition == .terminal
        })
        #expect(terminalAfterEmptyCheckpoint.descriptor.breakBarID == "l13")
        #expect(afterSecond.transactions[1].evaluatedEvents.first(where: {
            $0.decision.disposition == .active
        })?.descriptor.breakBarID == "l6")
        for record in afterSecond.activeEvents {
            let priorCursor = try #require(firstCursors[record.id]!)
            let currentCursor = try #require(record.quoteContinuationCursor)
            #expect(currentCursor.eventID == priorCursor.eventID)
            #expect(currentCursor.evidencePrefix == priorCursor.evidencePrefix)
            #expect(currentCursor == priorCursor)
        }
        let duplicateAfterProgress = try await relaunch.commit(first)
        #expect(duplicateAfterProgress.disposition == .duplicate)
        #expect(duplicateAfterProgress.snapshotDigest == afterFirst.digest)

        let third = eventProposal(f, bars: bars, windowIndices: 15...15, revision: 2,
            cursor: afterSecond.cursor, active: afterSecond.activeEvents)
        _ = try await relaunch.commit(third)
        let afterThird = try await relaunch.load()
        #expect(afterThird.transactions[2].proposal.evaluations.count == 1)
        #expect(afterThird.activeEvents.count == 1)
        #expect(afterThird.transactions[2].evaluatedEvents.count == 1)
        #expect(afterThird.activeEvents[0].descriptor.breakBarID == "l6")
        #expect(afterThird.transactions[2].evaluatedEvents[0].decision.disposition == .active)
    }
}
