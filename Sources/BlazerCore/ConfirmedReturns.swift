import Foundation

/// Equal-risk expectancy and cash results are different measures. A confirmed MISS is
/// a full fixed-contract loss: -1 risk unit, or -stake in cash when stake was recorded.
/// No mean payout, default payout or default stake is used for actual results.
public struct ConfirmedReturnSummary: Sendable, Equatable {
    public let resolved: Int
    public let unitExpectancy: Double?
    public let netProfit: Double?
    public let meanProfitPerTrade: Double?

    public static func evaluate(_ rows: [LedgerRow]) -> Self {
        let groups = Dictionary(grouping: rows, by: \.outcomeEventID)
        let confirmed = groups.values.filter { $0.count == 1 }.compactMap(\.first)
            .filter { !$0.outcomeEventID.isEmpty && $0.labelSource == "venue-confirmed"
                && ["HIT", "MISS"].contains($0.outcome) }
            .sorted { $0.outcomeEventID < $1.outcomeEventID }
        guard !confirmed.isEmpty else {
            return Self(resolved: 0, unitExpectancy: nil, netProfit: nil, meanProfitPerTrade: nil)
        }
        var units = 0.0, cash = 0.0
        var completeUnits = true, completeCash = true
        for row in confirmed {
            let unit: Double
            if row.outcome == "MISS" {
                unit = -1
            } else if let payout = row.payout, payout.isFinite, payout > 0, payout <= 1e100 {
                unit = payout
            } else {
                completeUnits = false; completeCash = false
                continue
            }
            units += unit / Double(confirmed.count)
            if let stake = row.stake, stake.isFinite, stake > 0 {
                let profit = unit * stake
                if profit.isFinite { cash += profit } else { completeCash = false }
            } else { completeCash = false }
        }
        let net = completeCash && cash.isFinite ? cash : nil
        return Self(resolved: confirmed.count,
            unitExpectancy: completeUnits && units.isFinite ? units : nil,
            netProfit: net, meanProfitPerTrade: net.map { $0 / Double(confirmed.count) })
    }
}
