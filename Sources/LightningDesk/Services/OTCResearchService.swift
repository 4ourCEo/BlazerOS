import BlazerCore
import Foundation

/// Normalized research update handed to the desk. It carries no order authority.
enum OTCResearchEvent: Sendable, Equatable {
    case connection(ShadowConnectionState, reason: String?)
    case observation(ShadowMarketObservation)
}

/// Cancellable research stream. `cancel()` finishes the consumer even when the provider never
/// yields another element, so a stopped or backgrounded session cannot leave a socket or task
/// alive indefinitely.
struct OTCResearchStream: @unchecked Sendable {
    let events: AsyncThrowingStream<OTCResearchEvent, any Error>
    private let cancelHandler: @Sendable () -> Void

    init(events: AsyncThrowingStream<OTCResearchEvent, any Error>,
         cancel: @escaping @Sendable () -> Void) {
        self.events = events
        self.cancelHandler = cancel
    }

    func cancel() { cancelHandler() }
}

/// Research-only OTC boundary for `LightningDeskModel`. The service owns provider construction,
/// streaming, validation persistence and the manual archive. It deliberately exposes no order,
/// account, transfer or settings method.
protocol DeskOTCResearchServing: Sendable {
    var researchIdentity: ShadowMarketIdentity { get }
    func instruments() async throws -> [ShadowInstrumentAvailability]
    func updates(for identity: ShadowMarketIdentity) async throws -> OTCResearchStream
    func standardReference(from quote: LiveQuote, at now: Date) -> ShadowMarketObservation?
    func record(otc: ShadowMarketObservation, standard: ShadowMarketObservation?,
                capturedAt: Date) async throws
    func report() async throws -> OTCValidationReport
    func manualObservations() async throws -> [ManualBrokerChartObservation]
    func recordManual(_ observation: ManualBrokerChartObservation) async throws
}

/// Concrete service used in production. The provider is optional so the same service can own the
/// local research archive without a credential or an open connection.
struct LiveOTCResearchService: DeskOTCResearchServing {
    let researchIdentity = ShadowMarketDataFixtures.pocketOptionEURUSDOTC

    private let provider: (any ShadowMarketObservationProvider)?
    private let pipeline: OTCValidationPipeline
    private let manualStore: ManualBrokerObservationStore

    init(root: URL, provider: (any ShadowMarketObservationProvider)? = nil) {
        self.provider = provider
        self.pipeline = OTCValidationPipeline(root: root)
        self.manualStore = ManualBrokerObservationStore(root: root)
    }

    init(root: URL, configuration: OTChartsConfiguration) {
        self.init(root: root, provider: OTChartsProvider(configuration: configuration))
    }

    func instruments() async throws -> [ShadowInstrumentAvailability] {
        guard let provider else { throw ShadowMarketDataError.disabled }
        return try await provider.instruments()
    }

    func updates(for identity: ShadowMarketIdentity) async throws -> OTCResearchStream {
        guard let provider else { throw ShadowMarketDataError.disabled }
        let upstream = try await provider.updates(for: [identity])
        let control = OTCStreamControl()
        let events = AsyncThrowingStream<OTCResearchEvent, any Error> { continuation in
            control.attach(continuation)
            let task = Task {
                do {
                    for try await update in upstream {
                        switch update {
                        case .connection(let state, let reason):
                            continuation.yield(.connection(state, reason: reason))
                        case .observation(let observation):
                            continuation.yield(.observation(observation))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            control.attach(task)
            continuation.onTermination = { _ in
                task.cancel()
                control.cancel()
            }
        }
        return OTCResearchStream(events: events) { control.cancel() }
    }

    func standardReference(from quote: LiveQuote, at now: Date) -> ShadowMarketObservation? {
        guard quote.asset == "EUR/USD", quote.asOfMs > 0,
              quote.bid.isFinite, quote.ask.isFinite, quote.mid.isFinite,
              quote.bid > 0, quote.ask >= quote.bid else { return nil }
        let asOf = quote.asOfMs / 1_000
        guard asOf <= now.timeIntervalSince1970,
              now.timeIntervalSince1970 - asOf <= 5 else { return nil }
        let observation = ShadowMarketObservation(
            source: ShadowDataSourceIdentity(providerID: "oanda.standard.v1",
                displayName: "OANDA", venueID: "oanda", directBrokerConnection: false),
            identity: ShadowMarketDataFixtures.standardEURUSD,
            quote: ShadowQuote(price: quote.mid, bid: quote.bid, ask: quote.ask),
            providerTimestamp: ShadowProviderTimestamp(rawUnixSeconds: asOf),
            receivedAt: now, connectionState: .live,
            verification: .unverifiedVendorData,
            provenance: "OANDA midpoint reference; not Pocket Option settlement")
        return observation.isValid ? observation : nil
    }

    func record(otc: ShadowMarketObservation, standard: ShadowMarketObservation?,
                capturedAt: Date) async throws {
        let sample = OTCValidationSample(
            capturedAt: capturedAt,
            standard: standard,
            otc: otc,
            standardOrigin: standard == nil ? nil : .independentAPI,
            otcOrigin: otc.source.directBrokerConnection ? .directBrokerData : .independentAPI
        )
        try await pipeline.record(sample)
    }

    func report() async throws -> OTCValidationReport {
        try await pipeline.report()
    }

    func manualObservations() async throws -> [ManualBrokerChartObservation] {
        try await manualStore.observations()
    }

    func recordManual(_ observation: ManualBrokerChartObservation) async throws {
        try await manualStore.record(observation)
    }
}

extension LiveOTCResearchService {
    /// Credential-scoped factory used by the desk. Provider types stay inside this service.
    static func streamingFactory(root: URL)
        -> @Sendable (String) -> any DeskOTCResearchServing {
        { key in
            LiveOTCResearchService(
                root: root,
                configuration: OTChartsConfiguration(apiKey: key, enabled: true)
            )
        }
    }

    /// Direct account-session factory. The supplied frame is read from Keychain only when the
    /// user explicitly starts a bounded capture; the provider exposes no trading operation.
    static func pocketOptionStreamingFactory(root: URL)
        -> @Sendable (String) -> any DeskOTCResearchServing {
        { authFrame in
            LiveOTCResearchService(
                root: root,
                provider: PocketOptionReadOnlyProvider(
                    configuration: PocketOptionReadOnlyConfiguration(
                        authFrame: authFrame,
                        enabled: true
                    )
                )
            )
        }
    }
}

/// Thread-safe holder so an explicit stop can finish the stream before the next provider yield.
private final class OTCStreamControl: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<OTCResearchEvent, any Error>.Continuation?
    private var task: Task<Void, Never>?
    private var cancelled = false

    func attach(_ continuation: AsyncThrowingStream<OTCResearchEvent, any Error>.Continuation) {
        lock.lock()
        self.continuation = continuation
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { continuation.finish(throwing: CancellationError()) }
    }

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let continuation = self.continuation
        let task = self.task
        lock.unlock()
        task?.cancel()
        continuation?.finish(throwing: CancellationError())
    }
}
