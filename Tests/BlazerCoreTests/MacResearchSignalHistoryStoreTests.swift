#if os(macOS)
import Foundation
import Testing
import BlazerCore
@testable import LightningDesk

private func historySignal(id: String = "setup-1", stage: MacResearchSignalStage,
                           generation: Int, observedAt: Date,
                           validUntil: Date, inputIdentity: String = String(repeating: "a", count: 64),
                           environment: MacResearchSignalEnvironment = .practice) -> MacResearchSignal {
    MacResearchSignal(id: id, profileID: "GBPJPY_LONDON_PRACTICE_OBSERVATION_PROVISIONAL_0.1.0",
        strategyID: "GBPJPY_LONDON_RANGE_BREAK_RETEST", strategyVersion: "v1",
        instrument: "GBP/JPY", direction: .long, observedAt: observedAt, validUntil: validUntil,
        reasons: ["test_reason"], evidenceReferences: ["bar-1"],
        sourceInputIdentity: inputIdentity, scanGeneration: generation,
        environment: environment, stage: stage, timeframe: "M1",
        entryReference: 190.1, stopPrice: 189.9, targetPrice: 190.5)
}

private func historyTemporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("signal-history-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func practiceHistoryAppendsMonotonicStagesAndRestoresAfterStoreRecreation() async throws {
    let root = try historyTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let forming = historySignal(stage: .forming, generation: 1, observedAt: start,
                                validUntil: start.addingTimeInterval(600))
    let confirmed = historySignal(stage: .confirmed, generation: 2,
        observedAt: start.addingTimeInterval(60), validUntil: start.addingTimeInterval(660),
        inputIdentity: String(repeating: "b", count: 64))
    let actionable = historySignal(stage: .actionable, generation: 3,
        observedAt: start.addingTimeInterval(120), validUntil: start.addingTimeInterval(720),
        inputIdentity: String(repeating: "c", count: 64))
    let refreshedButUntriggered = historySignal(stage: .confirmed, generation: 4,
        observedAt: start.addingTimeInterval(180), validUntil: start.addingTimeInterval(780),
        inputIdentity: String(repeating: "f", count: 64))

    let store = MacResearchSignalHistoryStore(root: root)
    #expect(try await store.recordObservation(forming) == .appended)
    #expect(try await store.recordObservation(forming) == .duplicate)
    #expect(try await store.recordObservation(confirmed) == .appended)
    #expect(try await store.recordObservation(actionable) == .appended)
    #expect(try await store.recordObservation(refreshedButUntriggered) == .appended)

    let restored = try await MacResearchSignalHistoryStore(root: root).events()
    #expect(restored.count == 4)
    #expect(restored.map(\.observedStage) == [.forming, .confirmed, .actionable, .confirmed])
    #expect(restored.map(\.lifecycle) == [.forming, .confirmed, .actionable, .actionable])
}

@Test func terminalExpiryIsDurableAndPreventsSetupReactivation() async throws {
    let root = try historyTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let actionable = historySignal(stage: .actionable, generation: 1, observedAt: start,
                                   validUntil: start.addingTimeInterval(60))
    let store = MacResearchSignalHistoryStore(root: root)
    #expect(try await store.recordObservation(actionable) == .appended)
    await #expect(throws: MacResearchSignalHistoryError.self) {
        try await store.recordExpiry(for: actionable, at: start.addingTimeInterval(59))
    }
    #expect(try await store.recordExpiry(for: actionable, at: start.addingTimeInterval(60)) == .appended)
    #expect(try await store.events().last?.lifecycle == .expired)
}

@Test func elapsedSetupExpiresOnRestoreAndCannotBeReactivated() async throws {
    let root = try historyTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let signal = historySignal(stage: .confirmed, generation: 1, observedAt: start,
                               validUntil: start.addingTimeInterval(60))
    let store = MacResearchSignalHistoryStore(root: root)
    #expect(try await store.recordObservation(signal) == .appended)
    #expect(try await store.expireElapsedSignals(asOf: start.addingTimeInterval(60)) == 1)
    #expect(try await store.expireElapsedSignals(asOf: start.addingTimeInterval(61)) == 0)

    let revived = historySignal(stage: .actionable, generation: 2,
        observedAt: start.addingTimeInterval(62), validUntil: start.addingTimeInterval(122),
        inputIdentity: String(repeating: "d", count: 64))
    #expect(try await store.recordObservation(revived) == .terminalSetup)
    let events = try await store.events()
    #expect(events.count == 2)
    #expect(events.last?.lifecycle == .expired)
    #expect(events.last?.kind == .expired)
}

@Test func staleGenerationAndLiveSignalCannotPollutePracticeHistory() async throws {
    let root = try historyTemporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let store = MacResearchSignalHistoryStore(root: root)
    let newer = historySignal(stage: .confirmed, generation: 5, observedAt: start,
                              validUntil: start.addingTimeInterval(60))
    let older = historySignal(stage: .forming, generation: 4,
        observedAt: start.addingTimeInterval(-1), validUntil: start.addingTimeInterval(59),
        inputIdentity: String(repeating: "e", count: 64))
    #expect(try await store.recordObservation(newer) == .appended)
    #expect(try await store.recordObservation(older) == .superseded)

    let live = historySignal(id: "live-setup", stage: .actionable, generation: 6,
        observedAt: start, validUntil: start.addingTimeInterval(60),
        environment: .live)
    await #expect(throws: MacResearchSignalHistoryError.invalidPracticeSignal) {
        try await store.recordObservation(live)
    }
    #expect(try await store.events().count == 1)
}
#endif
