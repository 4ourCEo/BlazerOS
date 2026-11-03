import Foundation

/// Owns the asynchronous worker around `ScanRequestScheduler`. The scheduler remains the source
/// of request identity; this coordinator owns cancellation and worker lifetime. The desk still
/// decides whether a request may publish and remains authoritative for execution state.
@MainActor
final class ScanOperationCoordinator {
    typealias Operation = @MainActor (ScanRequestScheduler.Request) async -> Void

    private let scheduler: ScanRequestScheduler
    private var workerTask: Task<Void, Never>?
    private var activeOperation: Task<Void, Never>?
    private var operation: Operation?
    /// Runs once whenever the worker returns to idle with nothing pending. The facade uses this
    /// to consume a Siri request only after scan ownership has been relinquished.
    var onIdle: (@MainActor () -> Void)?

    init(scheduler: ScanRequestScheduler = ScanRequestScheduler()) {
        self.scheduler = scheduler
    }

    var isIdle: Bool {
        workerTask == nil && activeOperation == nil && scheduler.pending == nil
    }

    var currentGeneration: UInt64 { scheduler.generation }

    @discardableResult
    func submit(
        market: DeskMarket,
        asset: String?,
        assets: [String],
        operation: @escaping Operation
    ) async -> ScanRequestScheduler.Request {
        let request = scheduler.submit(market: market, asset: asset, assets: assets)
        self.operation = operation
        activeOperation?.cancel()
        if workerTask == nil {
            workerTask = Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
        await workerTask?.value
        return request
    }

    func isCurrent(_ request: ScanRequestScheduler.Request) -> Bool {
        !Task.isCancelled && scheduler.isCurrent(request)
    }

    func invalidate() {
        scheduler.invalidate()
        activeOperation?.cancel()
    }

    private func drain() async {
        while !Task.isCancelled, let request = scheduler.takePending() {
            guard scheduler.isCurrent(request), let operation else { continue }
            let task = Task { @MainActor in
                await operation(request)
            }
            activeOperation = task
            await task.value
            activeOperation = nil
        }
        workerTask = nil
        if scheduler.pending == nil { onIdle?() }
    }
}
