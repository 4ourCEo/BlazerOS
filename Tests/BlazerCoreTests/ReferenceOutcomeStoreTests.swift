import Foundation
import Testing
@testable import BlazerCore

@Test func referenceOutcomeStoreIsBoundedAndDeduplicated() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-reference-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = ReferenceOutcomeStore(root: root, limit: 2)
    let now = Date()
    func outcome(_ id: String) -> ResearchOutcome {
        ResearchOutcome(
            eventID: id,
            horizon: 60,
            targetExpiry: now,
            observedAt: now,
            quoteTimeMs: now.timeIntervalSince1970 * 1000,
            exitPrice: 1.1,
            resolution: .hit,
            reason: nil,
            labelSource: "oanda-midpoint-proxy"
        )
    }

    #expect(try await store.record(outcome("a")))
    #expect(try await store.record(outcome("b")))
    #expect(try await store.record(outcome("a")) == false)
    #expect(try await store.record(outcome("c")))

    let values = await store.outcomes()
    #expect(values.map(\.eventID) == ["b", "c"])
    #expect(FileManager.default.fileExists(
        atPath: root.appendingPathComponent(ReferenceOutcomeStore.fileName).path
    ))
}
