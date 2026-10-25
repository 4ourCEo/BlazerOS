import BlazerCore
import Foundation

struct OTCDeskResearchSnapshot: Sendable {
    let signal: OTCResearchSignal
    let candles: [ShadowCandle]
    let instruments: [OTCInstrumentIdentity]
    let selectedInstrumentID: String
    let payoutPercent: Double?
    let connectionState: ShadowConnectionState
    let issue: String?
}

/// Read-only bridge between a vendor observation provider and the OTC challenger. It fetches one
/// bounded picture (instruments, completed candles, first live tick), evaluates, archives, and
/// returns. It has no order method and no path into the desk's commit, frame, or entry gate.
actor OTCResearchDeskService {
    private let provider: any ShadowMarketObservationProvider
    private let store: OTCResearchSignalStore
    private let now: @Sendable () -> Date
    private let configuration: OTCResearchConfiguration

    init(provider: any ShadowMarketObservationProvider,
         store: OTCResearchSignalStore,
         configuration: OTCResearchConfiguration = .standard,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.store = store
        self.configuration = configuration
        self.now = now
    }

    func refresh(identityID: String, quoteTimeout: TimeInterval = 4) async -> OTCDeskResearchSnapshot? {
        do {
            let availabilities = try await provider.instruments()
            let instruments = OTCInstrumentCatalog.otcWatchlist(from: availabilities)
            // Never substitute a different instrument when the requested one disappears from the
            // provider catalogue. Identity is part of the research contract.
            guard let instrument = instruments.first(where: { $0.instrumentID == identityID })
            else { return nil }
            let availability = availabilities.first { $0.identity == instrument.identity }
            let fetched = try await provider.candles(
                for: instrument.identity,
                intervalSeconds: configuration.intervalSeconds,
                limit: 120)
            // Only closed bars enter the evaluator. The forming candle is not evidence, and using
            // it would let future ticks rewrite the completed-bar history.
            let candles = fetched.filter(\.complete)
            let observation = await firstObservation(
                identity: instrument.identity, timeout: quoteTimeout)
            let evaluatedAt = now()
            let last = candles.last
            let lastClose = last?.providerTimestamp.normalized.addingTimeInterval(
                TimeInterval(configuration.intervalSeconds))
            let quote = observation?.quote ?? ShadowQuote(price: last?.close ?? 0)
            let quoteTimestamp = observation?.providerTimestamp.normalized ?? lastClose ?? evaluatedAt
            let receivedAt = observation?.receivedAt ?? evaluatedAt
            let connection = observation?.connectionState ?? .degraded
            let snapshotID = Self.snapshotID(
                instrument: instrument, candles: candles,
                quoteTimestamp: quoteTimestamp, quote: quote,
                source: provider.sourceIdentity,
                verification: observation?.verification ?? .unverifiedVendorData)
            let input = OTCResearchInput(
                instrument: instrument,
                source: provider.sourceIdentity,
                snapshotID: snapshotID,
                quote: quote,
                quoteTimestamp: quoteTimestamp,
                receivedAt: receivedAt,
                candles: candles,
                payoutPercent: availability?.payoutPercent,
                marketOpen: availability?.isOpen ?? true,
                connectionState: connection,
                verification: observation?.verification ?? .unverifiedVendorData,
                provenance: observation?.provenance
                    ?? "OTC provider candles with last-close reference; no live tick observed",
                evaluatedAt: evaluatedAt)
            let signal = OTCResearchEvaluator.evaluate(input, configuration: configuration)
            try? await store.record(OTCResearchRecord(
                signal: signal, input: input, configuration: configuration))
            return OTCDeskResearchSnapshot(
                signal: signal,
                candles: candles,
                instruments: instruments,
                selectedInstrumentID: instrument.instrumentID,
                payoutPercent: availability?.payoutPercent,
                connectionState: connection,
                issue: observation == nil
                    ? "No live OTC tick arrived; evaluated against the last completed candle."
                    : nil)
        } catch {
            return nil
        }
    }

    /// Waits for the first observation of a short-lived read-only stream. The timeout is a bound on
    /// a stall, not a synthetic tick: without a tick the evaluator receives a degraded feed.
    private func firstObservation(
        identity: ShadowMarketIdentity,
        timeout: TimeInterval
    ) async -> ShadowMarketObservation? {
        do {
            let updates = try await provider.updates(for: [identity])
            // Non-throwing group: a cancelled SSE child finishes with CancellationError during
            // cleanup, and that must not discard a tick that already arrived.
            return await withTaskGroup(of: ShadowMarketObservation?.self) { group in
                group.addTask {
                    do {
                        var iterator = updates.makeAsyncIterator()
                        while let update = try await iterator.next() {
                            switch update {
                            case .observation(let observation):
                                return observation
                            case .connection(let state, _) where state == .disconnected:
                                return nil
                            default:
                                continue
                            }
                        }
                        return nil
                    } catch {
                        return nil
                    }
                }
                group.addTask {
                    try? await Task.sleep(
                        nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
        } catch {
            return nil
        }
    }

    private static func snapshotID(
        instrument: OTCInstrumentIdentity,
        candles: [ShadowCandle],
        quoteTimestamp: Date,
        quote: ShadowQuote,
        source: ShadowDataSourceIdentity,
        verification: ShadowVerificationState
    ) -> String {
        let close = Int((candles.last?.providerTimestamp.normalized.timeIntervalSince1970 ?? 0).rounded())
        let quoteSecond = Int(quoteTimestamp.timeIntervalSince1970.rounded())
        let price = Int((quote.price * 100_000).rounded())
        return "otc-\(instrument.venueSymbol)-\(close)-\(quoteSecond)-\(candles.count)-\(price)-\(source.providerID)-\(verification.rawValue)"
    }
}
