import Foundation

/// Completed M1 bar. Incomplete bars are rejected at append.
public struct CompletedBar: Sendable, Equatable {
    public var time: Double
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    /// Must be true — incomplete / forming bars never enter the ring.
    public var complete: Bool

    public init(
        time: Double,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        complete: Bool = true
    ) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.complete = complete
    }

    /// Finite OHLC only — never fabricate missing values into the ring.
    public var isFiniteOHLC: Bool {
        time.isFinite && open.isFinite && high.isFinite && low.isFinite && close.isFinite
    }
}

/// Fixed-capacity circular buffer of completed M1 bars. Timestamp replacement is O(n).
public actor CompletedBarRing {
    private let capacity: Int
    private var slots: [CompletedBar?]
    /// Next write index (oldest when full).
    private var head: Int = 0
    /// Live count, capped at capacity.
    private var stored: Int = 0

    public init(capacity: Int = 128) {
        let cap = max(1, capacity)
        self.capacity = cap
        self.slots = Array(repeating: nil, count: cap)
    }

    /// Append one completed bar. Overwrites the oldest slot when full.
    /// Rejects incomplete / non-finite bars. Same timestamp replaces the prior bar.
    @discardableResult
    public func append(_ bar: CompletedBar) -> Bool {
        guard bar.complete, bar.isFiniteOHLC else { return false }
        if let existing = indexOfTime(bar.time) {
            slots[existing] = bar
            return true
        }
        slots[head] = bar
        head = (head + 1) % capacity
        if stored < capacity {
            stored += 1
        }
        return true
    }

    /// Replace ring contents with a completed batch (one pair’s M1 history for SCAN).
    /// Legacy append-order API: caller supplies ascending timestamps. Invalid bars are
    /// dropped and duplicate timestamps keep the last row. Scans use loadAndFetch instead.
    public func loadCompleted(_ bars: [CompletedBar]) {
        head = 0
        stored = 0
        for i in 0..<capacity {
            slots[i] = nil
        }
        for bar in bars {
            _ = append(bar)
        }
    }

    /// One actor hop prevents a concurrent scan from replacing this scan's history.
    /// Refuse truncation or reordered/invalid inputs: neither may silently change a scan.
    public func loadAndFetch(_ bars: [CompletedBar]) -> [CompletedBar] {
        guard bars.count <= capacity,
              bars.allSatisfy({ $0.complete && $0.isFiniteOHLC }),
              zip(bars, bars.dropFirst()).allSatisfy({ $0.time < $1.time }) else { return [] }
        loadCompleted(bars)
        return fetchLatestBars(count: bars.count)
    }

    /// Newest completed bars in time order.
    public func fetchLatestBars(count: Int) -> [CompletedBar] {
        let want = max(0, min(count, stored))
        guard want > 0 else { return [] }
        var out: [CompletedBar] = []
        out.reserveCapacity(want)
        let start = stored < capacity ? 0 : head
        let first = stored - want
        for i in first..<stored {
            let index = (start + i) % capacity
            if let bar = slots[index], bar.complete, bar.isFiniteOHLC {
                out.append(bar)
            }
        }
        return out
    }

    private func indexOfTime(_ time: Double) -> Int? {
        guard stored > 0 else { return nil }
        let start = stored < capacity ? 0 : head
        for i in 0..<stored {
            let index = (start + i) % capacity
            if slots[index]?.time == time {
                return index
            }
        }
        return nil
    }
}

extension CompletedBarRing {
    /// Process-wide ring. `loadCompleted` replaces the contents on every scan.
    public static let shared = CompletedBarRing(capacity: 128)
}

/// Name the Mac desk already calls.
public typealias EngineSupercharger = CompletedBarRing
