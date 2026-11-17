import Foundation
import Testing
@testable import BlazerCore

private func userCloseRoot(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("v3-user-close-\(name)-\(UUID().uuidString)")
        .appendingPathComponent("live-oanda", isDirectory: true)
}

private func userClosePlan(_ createdAt: Date) -> V3TradePlan {
    V3TradePlan(id: "close-plan", instrument: "EUR/USD", strategyID: "ORB_BREAK_RETEST_V1",
        strategyVersion: "ORB_BREAK_RETEST_V1", engineVersion: "V3_ORB_ENGINE_1",
        sourceObservationID: "confirm", state: .validated, side: .long,
        entryPrice: 1.1, stopPrice: 1.099, targetPrice: 1.102, units: 10_000,
        maxSpread: 0.0003, riskFraction: 0.005, createdAt: createdAt)
}

private func createUserCloseOpening(_ store: ResearchStore, now: Date) async throws -> V3PositionRecord {
    let plan = userClosePlan(now.addingTimeInterval(-120))
    try await store.record(plan)
    return try await store.recordUserReportedPosition(planID: plan.id, units: 10_000,
        entryPrice: 1.1002, userReportedEnteredAt: now.addingTimeInterval(-60), updatedAt: now)
}

@Test func userReportedCloseIsDistinctBoundedRetryableAndRestartSafe() async throws {
    let root = userCloseRoot("restart")
    let store = ResearchStore(root: root)
    let opening = try await createUserCloseOpening(store, now: Date())
    let closedAt = Date()
    let close = try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
        closedAt: closedAt, exitPrice: 1.101, recordedAt: closedAt)
    #expect(close.planID == opening.planID)
    #expect(close.openingRecordID == opening.id)
    #expect(close.provenance == .manualTradeCloseReport)
    #expect(close.id.hasPrefix("userclose-"))
    #expect(close.closedAt != nil && close.exitPrice == 1.101)
    let retry = try await ResearchStore(root: root).recordUserReportedPositionClose(
        positionID: opening.positionID!, closedAt: closedAt, exitPrice: 1.101,
        recordedAt: closedAt.addingTimeInterval(2))
    #expect(retry == close)
    #expect(try await ResearchStore(root: root).v3UserReportedPositionCloses() == [close])
    #expect(try await ResearchStore(root: root).v3PositionRecords().count == 1)
}

@Test func userReportedCloseChronologyOptionalFactsAndCorrectionPreserveOpeningRevision() async throws {
    let store = ResearchStore(root: userCloseRoot("correction"))
    let now = Date()
    let opening = try await createUserCloseOpening(store, now: now)
    await #expect(throws: V3UserPositionCloseError.chronologyInvalid) {
        try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
            closedAt: now.addingTimeInterval(-90))
    }
    let initial = try await store.recordUserReportedPositionClose(positionID: opening.positionID!)
    #expect(initial.closedAt == nil && initial.exitPrice == nil)
    let openingCorrection = try await store.recordUserReportedPosition(planID: opening.planID!,
        units: 9_000, entryPrice: 1.1003, userReportedEnteredAt: now.addingTimeInterval(-30),
        updatedAt: now.addingTimeInterval(1), supersedesRecordID: opening.id)
    #expect(openingCorrection.id != opening.id)
    let correction = try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
        closedAt: now, exitPrice: 1.101, recordedAt: now.addingTimeInterval(2),
        supersedesCloseID: initial.id)
    let correctionRetry = try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
        closedAt: now, exitPrice: 1.101, recordedAt: now.addingTimeInterval(3),
        supersedesCloseID: initial.id)
    #expect(correctionRetry == correction)
    await #expect(throws: V3UserPositionCloseError.invalidCorrection) {
        try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
            closedAt: now.addingTimeInterval(1), exitPrice: 1.102,
            supersedesCloseID: initial.id)
    }
    #expect(correction.openingRecordID == opening.id)
    #expect(correction.supersedesCloseID == initial.id)
    #expect(try await store.v3UserReportedPositionCloses().count == 2)
}

@Test func userReportedCloseRequiresLiveRootAndRejectsCompetingCloseRoots() async throws {
    let now = Date()
    let root = userCloseRoot("concurrent")
    let storeA = ResearchStore(root: root)
    let storeB = ResearchStore(root: root)
    let opening = try await createUserCloseOpening(storeA, now: now)
    let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
        for (index, store) in [storeA, storeB].enumerated() {
            group.addTask {
                do {
                    _ = try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
                        closedAt: now.addingTimeInterval(1), exitPrice: index == 0 ? 1.101 : 1.102)
                    return true
                } catch { return false }
            }
        }
        var values: [Bool] = []
        for await value in group { values.append(value) }
        return values
    }
    #expect(results.filter { $0 }.count == 1)
    #expect(try await storeA.v3UserReportedPositionCloses().count == 1)
    let proxy = ResearchStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("proxy"))
    await #expect(throws: V3UserPositionCloseError.liveArchiveRequired) {
        try await proxy.recordUserReportedPositionClose(positionID: "position")
    }
}

@Test func userReportedCloseRejectsTimeAfterReportToleranceAndAcceptsBoundary() async throws {
    let root = userCloseRoot("time-tolerance")
    let store = ResearchStore(root: root)
    let now = Date()
    let opening = try await createUserCloseOpening(store, now: now)
    let recordedAt = now.addingTimeInterval(-10)
    let boundary = try await store.recordUserReportedPositionClose(
        positionID: opening.positionID!, closedAt: recordedAt.addingTimeInterval(1),
        recordedAt: recordedAt)
    #expect(abs(boundary.closedAt!.timeIntervalSince(recordedAt.addingTimeInterval(1))) < 0.001)
    await #expect(throws: V3UserPositionCloseError.invalidReport) {
        try await store.recordUserReportedPositionClose(positionID: opening.positionID!,
            closedAt: recordedAt.addingTimeInterval(1.001), recordedAt: recordedAt)
    }
    #expect(try await store.v3UserReportedPositionCloses() == [boundary])
}

@Test func userReportedCloseRejectsCorruptArchiveAndFailedWriteLeavesNoClose() async throws {
    let root = userCloseRoot("corrupt")
    let store = ResearchStore(root: root)
    let opening = try await createUserCloseOpening(store, now: Date())
    let closeDirectory = root.appendingPathComponent("v3-user-position-closes", isDirectory: true)
    try FileManager.default.createDirectory(at: closeDirectory, withIntermediateDirectories: true)
    try Data("corrupt".utf8).write(to: closeDirectory.appendingPathComponent("broken.json"))
    await #expect(throws: (any Error).self) {
        try await store.recordUserReportedPositionClose(positionID: opening.positionID!)
    }
    #expect(try await store.v3PositionRecords().count == 1)
}

@Test func userReportedCloseArchiveRejectsClosedTimeAfterRecordedTimeTolerance() async throws {
    let root = userCloseRoot("future-archive")
    let store = ResearchStore(root: root)
    let now = Date()
    let opening = try await createUserCloseOpening(store, now: now)
    let malicious = V3UserReportedPositionClose(id: "userclose-tampered",
        positionID: opening.positionID!, planID: opening.planID!,
        openingRecordID: opening.id, closedAt: now.addingTimeInterval(2),
        recordedAt: now)
    #expect(malicious.validation().contains("close_time_after_report"))
    let directory = root.appendingPathComponent("v3-user-position-closes", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(malicious).write(to: directory.appendingPathComponent("\(malicious.id).json"))
    await #expect(throws: (any Error).self) {
        try await store.v3UserReportedPositionCloses()
    }
}
