import Foundation
import Testing
import BlazerCore

private func bar(_ time: Double, _ close: Double) -> Candle {
    Candle(time: time, open: close - 1, high: close + 1, low: close - 1, close: close)
}

@Test func storageIdentityCoversBothTimeframes() {
    let m1 = [bar(60_000, 1.10), bar(120_000, 1.11)]
    let upM5 = [bar(0, 1.09), bar(300_000, 1.10)]
    let downM5 = [bar(0, 1.12), bar(300_000, 1.08)]

    let up = ScanInputSnapshot(pair: "EUR/USD", m1: m1, m5: upM5)
    let down = ScanInputSnapshot(pair: "EUR/USD", m1: m1, m5: downM5)
    let repeatUp = ScanInputSnapshot(pair: "EUR/USD", m1: m1, m5: upM5)

    #expect(up.identity != down.identity)
    #expect(up.identity == repeatUp.identity)
    #expect(ScanFingerprint.isFullIdentity(up.identity))
}

@Test func storageIdentityCoversQuoteSpreadExpiryAndEngine() {
    let m1 = [bar(60_000, 1.10)]
    let base = ScanInputSnapshot(pair: "EUR/USD", m1: m1, bid: 1.0999, ask: 1.1001, spread: 0.0002, expirySeconds: 60, engineSHA: "ENGINE-A")

    let quoteChanged = ScanInputSnapshot(pair: "EUR/USD", m1: m1, bid: 1.0998, ask: 1.1002, spread: 0.0004, expirySeconds: 60, engineSHA: "ENGINE-A")
    let expiryChanged = ScanInputSnapshot(pair: "EUR/USD", m1: m1, bid: 1.0999, ask: 1.1001, spread: 0.0002, expirySeconds: 180, engineSHA: "ENGINE-A")
    let engineChanged = ScanInputSnapshot(pair: "EUR/USD", m1: m1, bid: 1.0999, ask: 1.1001, spread: 0.0002, expirySeconds: 60, engineSHA: "ENGINE-B")
    let pairChanged = ScanInputSnapshot(pair: "GBP/USD", m1: m1, bid: 1.0999, ask: 1.1001, spread: 0.0002, expirySeconds: 60, engineSHA: "ENGINE-A")

    let ids = Set([base.identity, quoteChanged.identity, expiryChanged.identity, engineChanged.identity, pairChanged.identity])
    #expect(ids.count == 5)
}

@Test func commitUsesFullInputIdentity() {
    let m1 = [bar(60_000, 1.10), bar(120_000, 1.11)]
    let signal = EngineSignal(
        asset: "EUR/USD", cabinetSide: "HIGH", call: "CALL", why: "evidence",
        price: 1.11, entryPrice: 1.11, confidence: 72
    )
    let a = ScanKernel.commit(from: signal, bars: m1, m5Bars: [bar(0, 1.05)], scannedAt: Date(timeIntervalSince1970: 1))
    let b = ScanKernel.commit(from: signal, bars: m1, m5Bars: [bar(0, 1.15)], scannedAt: Date(timeIntervalSince1970: 1))

    #expect(a.fingerprint == b.fingerprint)          // display hash stays stable
    #expect(a.fullFingerprint != b.fullFingerprint)  // storage identity does not
    #expect(a.score == 72)
}
