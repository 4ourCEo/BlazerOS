import Foundation

/// Research-only thresholds. These values never configure the entry gate or stake sizing.
/// Cash amounts use recorded stake units. The ledger has no venue-account or currency identity,
/// so those units are never presented as a named currency.
public struct CapitalPreservationPolicy: Codable, Sendable, Equatable {
    public let maximumSessionLoss: Double?
    public let maximumSessionDrawdown: Double?
    public let cooldownAfterConsecutiveLosses: Int?

    public init(
        maximumSessionLoss: Double? = nil,
        maximumSessionDrawdown: Double? = nil,
        cooldownAfterConsecutiveLosses: Int? = nil
    ) {
        self.maximumSessionLoss = maximumSessionLoss
        self.maximumSessionDrawdown = maximumSessionDrawdown
        self.cooldownAfterConsecutiveLosses = cooldownAfterConsecutiveLosses
    }

    /// Illustrative research defaults only: thresholds require explicit user application
    /// and do not become production risk limits.
    public static let conservativeResearch = CapitalPreservationPolicy(
        maximumSessionLoss: nil,
        maximumSessionDrawdown: nil,
        cooldownAfterConsecutiveLosses: 2
    )
}

public enum CapitalPreservationError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidTimeZone
    case invalidAsOf
    case invalidSimulationInputs
    case incompleteConfirmedReturns
    case arithmeticOverflow
}

public struct SessionRiskResearch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let resolved: Int
    public let wins: Int
    public let losses: Int
    public let maximumConsecutiveLosses: Int?
    public let cashCoverageComplete: Bool
    public let netProfit: Double?
    public let maximumDrawdown: Double?
    public let sessionLossLimitReached: Bool?
    public let drawdownLimitReached: Bool?
}

/// Summarizes confirmed execution risk. An unknown cash value remains unknown; partial cash
/// histories never produce a reassuring net or drawdown figure.
public struct CapitalPreservationReport: Codable, Sendable, Equatable {
    public let asOf: Date
    public let timeZoneIdentifier: String
    public let confirmedResolved: Int
    public let excludedUnconfirmed: Int
    public let excludedUnresolved: Int
    public let excludedDuplicateIDs: Int
    public let excludedMissingIdentity: Int
    public let excludedInvalidTimestamps: Int
    public let excludedMissingEntryTime: Int
    public let excludedMissingCashInputs: Int
    public let cashCoverageComplete: Bool
    public let maximumConsecutiveLosses: Int?
    public let currentConsecutiveLosses: Int?
    public let maximumDrawdown: Double?
    public let cooldownSuggested: Bool?
    public let sessions: [SessionRiskResearch]
    public var provenance: String { "venue-confirmed" }
    public var authority: String { "research-only; does not enforce a stop or size trades" }
    public var cashBasisLimitation: String {
        "Recorded stake units are summed as stored; venue account and currency are not identified in the ledger."
    }

    public static func evaluate(
        rows: [LedgerRow],
        asOf: Date,
        timeZoneIdentifier: String,
        policy: CapitalPreservationPolicy = .conservativeResearch
    ) throws -> CapitalPreservationReport {
        guard [policy.maximumSessionLoss, policy.maximumSessionDrawdown].compactMap({ $0 })
            .allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1e100 }),
              policy.cooldownAfterConsecutiveLosses.map({ $0 > 0 }) ?? true else {
            throw CapitalPreservationError.invalidPolicy
        }
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw CapitalPreservationError.invalidTimeZone
        }
        guard asOf.timeIntervalSince1970.isFinite else { throw CapitalPreservationError.invalidAsOf }

        let excludedInvalidTimestamps = rows.filter {
            $0.labelSource == "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)
                && !$0.timestamp.timeIntervalSince1970.isFinite
        }.count
        let eligibleRows = rows.filter {
            $0.timestamp.timeIntervalSince1970.isFinite && $0.timestamp <= asOf
        }
        let groups = Dictionary(grouping: eligibleRows, by: \.outcomeEventID)
        let duplicates = groups.values.filter { $0.count != 1 }.count
        let missingIdentity = eligibleRows.filter {
            $0.labelSource == "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)
                && $0.outcomeEventID.isEmpty
        }.count
        let unique = groups.values.compactMap(\.only).filter { !$0.outcomeEventID.isEmpty }
        let excludedUnconfirmed = unique.filter {
            $0.labelSource != "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)
        }.count
        let resolved = unique.filter {
            $0.labelSource == "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)
        }
        let excludedUnresolved = unique.filter { $0.outcome == "UNRESOLVED" }.count
        let missingEntry = resolved.filter { row in
            guard let enteredAt = row.enteredAt else { return true }
            return !enteredAt.timeIntervalSince1970.isFinite
                || enteredAt > row.timestamp || enteredAt > asOf
        }
        let missingCash = resolved.filter { row in
            guard let stake = row.stake, stake.isFinite, stake > 0 else { return true }
            guard row.outcome == "HIT" else { return false }
            guard let payout = row.payout, payout.isFinite, payout > 0, payout <= 1e100 else { return true }
            return !(stake * payout).isFinite
        }.count

        struct Event {
            let row: LedgerRow
            let sessionID: String
            let profit: Double?
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var events: [Event] = []
        for row in resolved {
            guard let enteredAt = row.enteredAt, enteredAt <= row.timestamp, enteredAt <= asOf else {
                continue
            }
            let profit: Double?
            if let stake = row.stake, stake.isFinite, stake > 0 {
                if row.outcome == "MISS" {
                    profit = -stake
                } else if let payout = row.payout, payout.isFinite, payout > 0, payout <= 1e100,
                          (stake * payout).isFinite {
                    profit = stake * payout
                } else {
                    profit = nil
                }
            } else {
                profit = nil
            }
            events.append(Event(row: row, sessionID: formatter.string(from: enteredAt), profit: profit))
        }

        events.sort {
            let left = $0.row.enteredAt ?? .distantPast
            let right = $1.row.enteredAt ?? .distantPast
            return left == right ? $0.row.outcomeEventID < $1.row.outcomeEventID : left < right
        }
        let cashCoverageComplete = missingCash == 0 && missingEntry.isEmpty && duplicates == 0
            && missingIdentity == 0 && excludedInvalidTimestamps == 0
        let streakCoverageComplete = missingEntry.isEmpty && duplicates == 0
            && missingIdentity == 0 && excludedInvalidTimestamps == 0
        var streak = 0
        var maximumStreak = 0
        for event in events {
            if event.row.outcome == "MISS" {
                streak += 1
                maximumStreak = max(maximumStreak, streak)
            } else {
                streak = 0
            }
        }

        let bySession = Dictionary(grouping: events, by: \.sessionID)
        let sessions = bySession.keys.sorted().map { key -> SessionRiskResearch in
            let cohort = bySession[key, default: []]
            var cashComplete = cashCoverageComplete && cohort.allSatisfy { $0.profit != nil }
            var total = 0.0
            var balance = 0.0
            var peak = 0.0
            var drawdown = 0.0
            var localStreak = 0
            var localMaximumStreak = 0
            for event in cohort {
                if event.row.outcome == "MISS" {
                    localStreak += 1
                    localMaximumStreak = max(localMaximumStreak, localStreak)
                } else {
                    localStreak = 0
                }
                if let profit = event.profit {
                    total += profit
                    if !total.isFinite { cashComplete = false; break }
                    balance += profit
                    if !balance.isFinite { cashComplete = false; break }
                    peak = max(peak, balance)
                    drawdown = max(drawdown, peak - balance)
                }
            }
            let net = cashComplete ? total : nil
            let validDrawdown = cashComplete && drawdown.isFinite ? drawdown : nil
            return SessionRiskResearch(
                id: key,
                resolved: cohort.count,
                wins: cohort.filter { $0.row.outcome == "HIT" }.count,
                losses: cohort.filter { $0.row.outcome == "MISS" }.count,
                maximumConsecutiveLosses: streakCoverageComplete ? localMaximumStreak : nil,
                cashCoverageComplete: cashComplete,
                netProfit: net?.isFinite == true ? net : nil,
                maximumDrawdown: validDrawdown,
                sessionLossLimitReached: net.map { value in
                    policy.maximumSessionLoss.map { value <= -$0 }
                } ?? nil,
                drawdownLimitReached: validDrawdown.map { value in
                    policy.maximumSessionDrawdown.map { value >= $0 }
                } ?? nil
            )
        }
        var cumulative = 0.0
        var peak = 0.0
        var observedDrawdown = 0.0
        var drawdownArithmeticComplete = true
        for event in events {
            guard let profit = event.profit else { break }
            cumulative += profit
            guard cumulative.isFinite else { drawdownArithmeticComplete = false; break }
            peak = max(peak, cumulative)
            observedDrawdown = max(observedDrawdown, peak - cumulative)
            guard observedDrawdown.isFinite else { drawdownArithmeticComplete = false; break }
        }
        let maxDrawdown = cashCoverageComplete && drawdownArithmeticComplete && observedDrawdown.isFinite
            ? observedDrawdown : nil
        let cooldown: Bool? = streakCoverageComplete
            ? policy.cooldownAfterConsecutiveLosses.map { streak >= $0 }
            : nil

        return CapitalPreservationReport(
            asOf: asOf,
            timeZoneIdentifier: timeZoneIdentifier,
            confirmedResolved: resolved.count,
            excludedUnconfirmed: excludedUnconfirmed,
            excludedUnresolved: excludedUnresolved,
            excludedDuplicateIDs: duplicates,
            excludedMissingIdentity: missingIdentity,
            excludedInvalidTimestamps: excludedInvalidTimestamps,
            excludedMissingEntryTime: missingEntry.count,
            excludedMissingCashInputs: missingCash,
            cashCoverageComplete: cashCoverageComplete,
            maximumConsecutiveLosses: streakCoverageComplete ? maximumStreak : nil,
            currentConsecutiveLosses: streakCoverageComplete ? streak : nil,
            maximumDrawdown: maxDrawdown,
            cooldownSuggested: cooldown,
            sessions: sessions
        )
    }
}

/// A deterministic counterfactual using each confirmed row's recorded outcome and payout.
/// It is not a recommendation and must never be written to the execution ledger.
public struct PositionSizingSimulation: Codable, Sendable, Equatable {
    public let initialBankroll: Double
    public let riskFraction: Double
    public let trades: Int
    public let endingBankroll: Double
    public let netProfit: Double
    public let maximumDrawdown: Double
    public let maximumConsecutiveLosses: Int
    public var assumption: String {
        "Research-only; fixed fraction of current simulated bankroll per confirmed historical outcome; excludes fees and future execution differences."
    }
}

/// Compact deterministic facts for the read-only assistant context.
public struct CapitalPreservationSummary: Codable, Sendable, Equatable {
    public let confirmedResolved: Int
    public let cashCoverageComplete: Bool
    public let maximumConsecutiveLosses: Int?
    public let currentConsecutiveLosses: Int?
    public let maximumDrawdown: Double?
    public let latestSessionID: String?
    public let latestSessionNetProfit: Double?
    public let latestSessionMaximumDrawdown: Double?
    public let cooldownSuggested: Bool?
    public let provenance: String
    public let authority: String
    public let cashBasisLimitation: String

    public init(_ report: CapitalPreservationReport) {
        confirmedResolved = report.confirmedResolved
        cashCoverageComplete = report.cashCoverageComplete
        maximumConsecutiveLosses = report.maximumConsecutiveLosses
        currentConsecutiveLosses = report.currentConsecutiveLosses
        maximumDrawdown = report.maximumDrawdown
        let latest = report.sessions.last
        latestSessionID = latest?.id
        latestSessionNetProfit = latest?.netProfit
        latestSessionMaximumDrawdown = latest?.maximumDrawdown
        cooldownSuggested = report.cooldownSuggested
        provenance = report.provenance
        authority = report.authority
        cashBasisLimitation = report.cashBasisLimitation
    }
}

public enum PositionSizingResearch {
    public static func simulate(
        rows: [LedgerRow],
        initialBankroll: Double,
        riskFraction: Double,
        asOf: Date
    ) throws -> PositionSizingSimulation {
        guard initialBankroll.isFinite, initialBankroll > 0, initialBankroll <= 1e100,
              riskFraction.isFinite, riskFraction > 0, riskFraction < 1,
              asOf.timeIntervalSince1970.isFinite else {
            throw CapitalPreservationError.invalidSimulationInputs
        }
        guard !rows.contains(where: {
            $0.labelSource == "venue-confirmed" && ["HIT", "MISS"].contains($0.outcome)
                && !$0.timestamp.timeIntervalSince1970.isFinite
        }) else { throw CapitalPreservationError.incompleteConfirmedReturns }
        let confirmed = rows.filter {
            $0.timestamp <= asOf && $0.labelSource == "venue-confirmed"
                && ["HIT", "MISS"].contains($0.outcome)
        }
        let groups = Dictionary(grouping: confirmed, by: \.outcomeEventID)
        guard groups.values.allSatisfy({ $0.count == 1 }),
              confirmed.allSatisfy({ !$0.outcomeEventID.isEmpty && $0.enteredAt != nil }) else {
            throw CapitalPreservationError.incompleteConfirmedReturns
        }
        var events = confirmed
        guard events.allSatisfy({ row in
            guard let enteredAt = row.enteredAt else { return false }
            return enteredAt <= row.timestamp && enteredAt <= asOf
        }) else { throw CapitalPreservationError.incompleteConfirmedReturns }
        events.sort {
            let a = $0.enteredAt ?? .distantPast
            let b = $1.enteredAt ?? .distantPast
            return a == b ? $0.outcomeEventID < $1.outcomeEventID : a < b
        }
        guard !events.isEmpty else { throw CapitalPreservationError.incompleteConfirmedReturns }
        // Validate the complete cohort before producing a simulation. Never silently omit a row.
        for event in events where event.outcome == "HIT" {
            guard let payout = event.payout, payout.isFinite, payout > 0, payout <= 1e100 else {
                throw CapitalPreservationError.incompleteConfirmedReturns
            }
        }
        var balance = initialBankroll
        var peak = balance
        var maxDrawdown = 0.0
        var streak = 0
        var maxStreak = 0
        for event in events {
            let stake = balance * riskFraction
            guard stake.isFinite else { throw CapitalPreservationError.arithmeticOverflow }
            if event.outcome == "HIT" {
                let profit = stake * (event.payout ?? 0)
                guard profit.isFinite else { throw CapitalPreservationError.arithmeticOverflow }
                balance += profit
                streak = 0
            } else {
                balance -= stake
                streak += 1
                maxStreak = max(maxStreak, streak)
            }
            guard balance.isFinite, balance > 0 else { throw CapitalPreservationError.arithmeticOverflow }
            peak = max(peak, balance)
            maxDrawdown = max(maxDrawdown, peak - balance)
        }
        return PositionSizingSimulation(
            initialBankroll: initialBankroll,
            riskFraction: riskFraction,
            trades: events.count,
            endingBankroll: balance,
            netProfit: balance - initialBankroll,
            maximumDrawdown: maxDrawdown,
            maximumConsecutiveLosses: maxStreak
        )
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
