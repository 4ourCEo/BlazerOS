import Foundation
import Testing
@testable import BlazerCore

private func bars(_ offset: Double) -> [CompletedBar] {
    (0..<64).map { CompletedBar(time: Double($0) * 60_000, open: offset, high: offset + 1, low: offset - 1, close: offset) }
}

@Test func sharedRingKeepsEachConcurrentScanIsolated() async {
    let ring = CompletedBarRing()
    await withTaskGroup(of: Bool.self) { group in
        for index in 1...100 {
            group.addTask {
                let input = bars(Double(index))
                return await ring.loadAndFetch(input) == input
            }
        }
        for await matched in group { #expect(matched) }
    }
}

@Test func scanRingRefusesTruncationAndReordering() async {
    let ring = CompletedBarRing(capacity: 32)
    #expect(await ring.loadAndFetch(bars(10)).isEmpty)
    let full = CompletedBarRing()
    #expect(await full.loadAndFetch(bars(10).reversed()).isEmpty)
    let duplicate = [bars(10)[0], bars(10)[0]]
    #expect(await full.loadAndFetch(duplicate).isEmpty)
}
