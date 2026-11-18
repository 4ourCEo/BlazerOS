import Foundation
import BlazerCore

public enum MacResearchSignalEnvironment: String, Sendable, Equatable {
    case practice = "PRACTICE"
    case live = "LIVE"
    case replay = "REPLAY"
}

/// The source label binds provider aliases to one execution environment. Construct
/// OANDA cases from the environment of the loaded authenticated `OandaSession`.
public enum MacResearchSignalSource: Sendable, Equatable {
    case oandaPractice
    case oandaLive
    case replay

    public var environment: MacResearchSignalEnvironment {
        switch self {
        case .oandaPractice: .practice
        case .oandaLive: .live
        case .replay: .replay
        }
    }

    fileprivate var acceptedProviders: Set<String> {
        switch self {
        case .oandaPractice: ["OANDA-PRACTICE", "OANDA"]
        case .oandaLive: ["OANDA-LIVE"]
        case .replay: ["REPLAY", "OANDA-REPLAY"]
        }
    }
}

public enum MacResearchSignalStage: String, Sendable, Equatable {
    case forming = "FORMING"
    case confirmed = "CONFIRMED"
    case actionable = "ACTIONABLE"
}

/// A validated research plan preview. It has no submission or approval authority.
public struct MacResearchPlanPreview: Sendable, Equatable {
    public let entryPrice: Double
    public let stopPrice: Double
    public let targetPrice: Double
    public let rewardRisk: Double
    public let maxSpread: Double
    public let evidenceReferences: [String]

    fileprivate init?(_ plan: V3TradePlan, candidate: AdaptiveOpportunityCandidate) {
        guard plan.instrument == candidate.instrument,
              plan.strategyID == candidate.strategyID,
              plan.strategyVersion == candidate.strategyVersion,
              plan.validation().isEmpty,
              let rewardRisk = plan.rewardRisk, rewardRisk.isFinite,
              plan.side == (candidate.direction == .long ? .long : .short) else { return nil }
        self.entryPrice = plan.entryPrice
        self.stopPrice = plan.stopPrice
        self.targetPrice = plan.targetPrice
        self.rewardRisk = rewardRisk
        self.maxSpread = plan.maxSpread
        self.evidenceReferences = plan.evidenceIDs
    }
}

/// A research observation that can be shown to the user. Any attached plan is a
/// preview only; risk approval and manual Practice execution are separate checks.
public struct MacResearchSignal: Sendable, Equatable, Identifiable {
    public let id: String
    public let profileID: String
    public let strategyID: String
    public let strategyVersion: String
    public let instrument: String
    public let direction: AdaptiveDirection
    public let environment: MacResearchSignalEnvironment
    public let stage: MacResearchSignalStage
    public let timeframe: String?
    public let entryReference: Double?
    public let stopPrice: Double?
    public let targetPrice: Double?
    public let planPreview: MacResearchPlanPreview?
    public let observedAt: Date
    public let validUntil: Date
    public let reasons: [String]
    public let evidenceReferences: [String]
    public let sourceInputIdentity: String
    public let scanGeneration: Int

    public init(id: String, profileID: String, strategyID: String, strategyVersion: String,
                instrument: String, direction: AdaptiveDirection, observedAt: Date,
                validUntil: Date, reasons: [String], evidenceReferences: [String],
                sourceInputIdentity: String, scanGeneration: Int,
                environment: MacResearchSignalEnvironment = .live,
                stage: MacResearchSignalStage = .actionable, timeframe: String? = nil,
                entryReference: Double? = nil, stopPrice: Double? = nil,
                targetPrice: Double? = nil,
                planPreview: MacResearchPlanPreview? = nil) {
        self.id = id; self.profileID = profileID; self.strategyID = strategyID
        self.strategyVersion = strategyVersion; self.instrument = instrument
        self.direction = direction; self.observedAt = observedAt; self.validUntil = validUntil
        self.environment = environment; self.stage = stage; self.timeframe = timeframe
        self.entryReference = entryReference; self.stopPrice = stopPrice
        self.targetPrice = targetPrice
        self.planPreview = planPreview
        self.reasons = reasons; self.evidenceReferences = evidenceReferences
        self.sourceInputIdentity = sourceInputIdentity; self.scanGeneration = scanGeneration
    }
}

/// Pure projection gate for the separate Mac research panel.
public enum MacResearchSignalProjector {
    public static func project(candidates: [AdaptiveOpportunityCandidate],
                               profiles: [StrategyResearchProfile],
                               instrument: String, scanGeneration: Int,
                               sourceInputIdentity: String, now: Date,
                               source: MacResearchSignalSource = .oandaLive) -> [MacResearchSignal] {
        guard !instrument.isEmpty, !sourceInputIdentity.isEmpty,
              now.timeIntervalSince1970.isFinite else { return [] }
        var result: [MacResearchSignal] = []
        var seen = Set<String>()
        for candidate in candidates {
            let provider = candidate.provider.uppercased().replacingOccurrences(of: "_", with: "-")
            let hasLifecycleExpiry = candidate.strategyID == GBPJPYLondonBreakRetestV1.strategyID
            let quoteNeedsRefresh = hasLifecycleExpiry
                && candidate.observedAt.map { now.timeIntervalSince($0) > EntryQuality.maxAgeSeconds } == true
            guard candidate.instrument == instrument,
                  source.acceptedProviders.contains(provider),
                  candidate.direction == .long || candidate.direction == .short,
                  candidate.spreadState == .accepted, candidate.freshness == .fresh,
                  let observedAt = candidate.observedAt, observedAt.timeIntervalSince1970.isFinite,
                  now.timeIntervalSince(observedAt) >= -1,
                  let validUntil = candidate.validUntil, validUntil.timeIntervalSince1970.isFinite,
                  now <= validUntil, validUntil >= observedAt,
                  hasLifecycleExpiry || now.timeIntervalSince(observedAt) <= EntryQuality.maxAgeSeconds,
                  let configDigest = candidate.effectiveConfigurationSHA256,
                  let evaluatorDigest = candidate.evaluatorCodeSHA256,
                  let adapterDigest = candidate.adapterCodeSHA256,
                  let selectorDigest = candidate.selectorCodeSHA256,
                  Self.isSHA256(evaluatorDigest), Self.isSHA256(adapterDigest),
                  Self.isSHA256(selectorDigest),
                  let evaluatorKey = Self.evaluatorDigestKey(for: candidate.strategyID),
                  StrategyImplementationDigests.evaluatorCodeSHA256[evaluatorKey]?
                    .caseInsensitiveCompare(evaluatorDigest) == .orderedSame,
                  StrategyImplementationDigests.adapterCodeSHA256
                    .caseInsensitiveCompare(adapterDigest) == .orderedSame,
                  StrategyImplementationDigests.selectorCodeSHA256
                    .caseInsensitiveCompare(selectorDigest) == .orderedSame,
                  let config = AdaptiveOpportunityAdapters.effectiveConfiguration(
                    strategyID: candidate.strategyID, instrument: instrument),
                  let computedConfigDigest = config.sha256(),
                  computedConfigDigest.caseInsensitiveCompare(configDigest) == .orderedSame else { continue }

            let stage: MacResearchSignalStage
            switch candidate.state {
            case .eligible:
                let hasTechnicalLevels: Bool = {
                    guard let entry = candidate.entryReference,
                          let stop = candidate.stopReference,
                          let target = candidate.targetReference else { return false }
                    switch candidate.direction {
                    case .long: return stop.isFinite && stop < entry && entry < target && target.isFinite
                    case .short: return target.isFinite && target < entry && entry < stop && stop.isFinite
                    case .wait: return false
                    }
                }()
                let technicallyReady = candidate.plan.flatMap { MacResearchPlanPreview($0, candidate: candidate) } != nil
                    || hasTechnicalLevels
                stage = technicallyReady && !quoteNeedsRefresh ? .actionable : .confirmed
            case .rejected:
                let signalReasons = candidate.rejectionReasons.filter { $0 != "candidate_not_eligible" }
                guard !signalReasons.isEmpty,
                      signalReasons.allSatisfy(Self.isFormingReason) else { continue }
                stage = .forming
            case .unavailable:
                continue
            }
            guard seen.insert(candidate.id).inserted else { continue }

            let displayProfile = profiles.first { profile in
                profile.acceptedCandidateIdentities.contains(.init(
                    strategyID: candidate.strategyID, strategyVersion: candidate.strategyVersion))
            }
            let profileID: String
            if candidate.strategyID == GBPJPYLondonBreakRetestV1.strategyID {
                profileID = "GBPJPY_LONDON_PRACTICE_OBSERVATION_PROVISIONAL_0.1.0"
            } else {
                profileID = displayProfile?.id ?? "research:\(candidate.strategyID)"
            }
            result.append(MacResearchSignal(id: candidate.id,
                profileID: profileID,
                strategyID: candidate.strategyID, strategyVersion: candidate.strategyVersion,
                instrument: instrument, direction: candidate.direction, observedAt: observedAt,
                validUntil: validUntil,
                reasons: quoteNeedsRefresh
                    ? Array(Set(candidate.rejectionReasons + ["quote_refresh_required"])).sorted()
                    : candidate.rejectionReasons,
                evidenceReferences: candidate.evidenceReferences,
                sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration,
                environment: source.environment, stage: stage,
                timeframe: Self.timeframe(for: candidate.strategyID),
                entryReference: candidate.plan?.entryPrice ?? candidate.entryReference,
                stopPrice: candidate.plan?.stopPrice ?? candidate.stopReference,
                targetPrice: candidate.plan?.targetPrice ?? candidate.targetReference,
                planPreview: candidate.plan.flatMap { MacResearchPlanPreview($0, candidate: candidate) }))
        }
        return result
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70)
        }
    }

    private static func isFormingReason(_ reason: String) -> Bool {
        switch reason {
        case "before_opening_range", "opening_range_incomplete", "opening_range_forming",
             "range_sealed", "boundary_approaching", "breakout_not_detected",
             "breakout_confirmed_retest_pending", "retest_confirmation_pending": true
        default: false
        }
    }

    private static func evaluatorDigestKey(for strategyID: String) -> String? {
        switch strategyID {
        case "ORB_BREAK_RETEST_V1": "ORB_BREAK_RETEST"
        case "CANDIDATE_001_CHOCH_FVG_FIB": "CHOCH_FVG_FIB"
        case "CANDIDATE_002_AUCTION_FAILURE": "AUCTION_FAILURE"
        case GBPJPYLondonBreakRetestV1.strategyID: "LONDON_BREAK_RETEST"
        case "LEGACY_V1", "JSC_baseline", "JSC_conservative", "JSC_momentum",
             "JSC_reversion", "JSC_volatility": strategyID
        default: nil
        }
    }

    private static func timeframe(for strategyID: String) -> String? {
        switch strategyID {
        case "GBPJPY_LONDON_RANGE_BREAK_RETEST": "M1"
        case "CANDIDATE_001_CHOCH_FVG_FIB", "CANDIDATE_002_AUCTION_FAILURE": "M1 + M15 context"
        case "ORB_BREAK_RETEST_V1": "M1"
        default: nil
        }
    }
}

#if os(macOS)
public enum MacResearchEvaluatorFamily: String, CaseIterable, Sendable, Equatable, Identifiable {
    case orb = "ORB"
    case candidate001 = "Candidate001"
    case candidate002 = "Candidate002"
    case londonBreakRetest = "London Break + Retest"
    case trendPullback = "Trend Pullback"
    case rangeRejection = "Range Rejection"

    public var id: String { rawValue }

    fileprivate var identity: (strategyID: String, strategyVersion: String) {
        switch self {
        case .orb: ("ORB_BREAK_RETEST_V1", "ORB_BREAK_RETEST_V1")
        case .candidate001: ("CANDIDATE_001_CHOCH_FVG_FIB", "candidate-001-v2")
        case .candidate002: ("CANDIDATE_002_AUCTION_FAILURE", "candidate-002-auction-failure-v2")
        case .londonBreakRetest: (GBPJPYLondonBreakRetestV1.strategyID, "GBPJPY_LONDON_RANGE_BREAK_RETEST_V1")
        case .trendPullback: (GBPJPYTrendPullbackV1.strategyID, "PROFILE_REQUIRED")
        case .rangeRejection: (GBPJPYRangeRejectionV1.strategyID, "PROFILE_REQUIRED")
        }
    }

    fileprivate var quoteFreshness: TimeInterval { self == .orb ? 5 : 8 }
}

/// Safe, source-bound summary of one connected evaluator's latest scan result.
/// It deliberately contains no direction, prices, plan, record IDs, or raw errors.
public struct MacResearchEvaluationDiagnostic: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case completedNoCandidate
        case candidateShown
        case candidateWithheld
        case conditionsNotMet
        case evaluationFailed
        case dataUnavailable
        case notConfigured
    }

    public let family: MacResearchEvaluatorFamily
    public let state: State
    public let detail: String?
    public let quoteAsOf: Date
    public let validUntil: Date
    public let sourceInputIdentity: String
    public let scanGeneration: Int
    public var id: String { family.rawValue }

    fileprivate init(family: MacResearchEvaluatorFamily, state: State, detail: String?,
                     quoteAsOf: Date, validUntil: Date,
                     sourceInputIdentity: String, scanGeneration: Int) {
        self.family = family; self.state = state; self.detail = detail
        self.quoteAsOf = quoteAsOf; self.validUntil = validUntil
        self.sourceInputIdentity = sourceInputIdentity; self.scanGeneration = scanGeneration
    }

    public var statusLabel: String {
        switch state {
        case .completedNoCandidate: "Completed · no candidate emitted"
        case .candidateShown: "Eligible candidate shown above"
        case .candidateWithheld: "Candidate withheld by validation"
        case .conditionsNotMet: "Setup detected · conditions not met"
        case .evaluationFailed: "Evaluation failed"
        case .dataUnavailable: "Required market data unavailable"
        case .notConfigured: "Evaluator not configured · approved profile required"
        }
    }
}

/// Projects only source-supported, non-directional evaluator diagnostics.
public enum MacResearchEvaluationDiagnosticProjector {
    public static func project(candidates: [AdaptiveOpportunityCandidate],
                               failedFamilies: Set<MacResearchEvaluatorFamily>,
                               unavailableFamilies: Set<MacResearchEvaluatorFamily> = [],
                               notConfiguredFamilies: Set<MacResearchEvaluatorFamily> = [],
                               conditionsNotMetReasons: [MacResearchEvaluatorFamily: String] = [:],
                               visibleSignalIDs: Set<String>,
                               quoteAsOf: Date?, scanGeneration: Int,
                               currentScanGeneration: Int,
                               sourceInputIdentity: String,
                               expectedSourceInputIdentity: String, now: Date)
        -> [MacResearchEvaluationDiagnostic] {
        guard let quoteAsOf, quoteAsOf.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite,
              now.timeIntervalSince(quoteAsOf) >= -1,
              !sourceInputIdentity.isEmpty,
              sourceInputIdentity == expectedSourceInputIdentity,
              scanGeneration > 0, scanGeneration == currentScanGeneration else { return [] }

        return MacResearchEvaluatorFamily.allCases.compactMap { family in
            let identity = family.identity
            let familyCandidates = candidates.filter { $0.strategyID == identity.strategyID }
            let matching = familyCandidates.filter {
                $0.strategyVersion == identity.strategyVersion
            }
            let quoteDeadline = quoteAsOf.addingTimeInterval(family.quoteFreshness)
            let candidateDeadline = matching.filter {
                family != .orb || $0.direction != .wait
            }.compactMap(\.validUntil).filter { $0.timeIntervalSince1970.isFinite }.min()
            let validUntil = min(quoteDeadline, candidateDeadline ?? quoteDeadline)
            guard now <= validUntil else { return nil }

            if failedFamilies.contains(family) {
                return .init(family: family, state: .evaluationFailed, detail: nil,
                    quoteAsOf: quoteAsOf, validUntil: validUntil,
                    sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
            }
            if unavailableFamilies.contains(family) {
                return .init(family: family, state: .dataUnavailable, detail: "Required candle history is unavailable",
                    quoteAsOf: quoteAsOf, validUntil: validUntil,
                    sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
            }
            if notConfiguredFamilies.contains(family) {
                return .init(family: family, state: .notConfigured,
                    detail: "Approved strategy profile is not configured",
                    quoteAsOf: quoteAsOf, validUntil: quoteDeadline,
                    sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
            }
            if let reason = conditionsNotMetReasons[family] {
                return .init(family: family, state: .conditionsNotMet,
                    detail: safeReasonLabel(reason), quoteAsOf: quoteAsOf,
                    validUntil: validUntil, sourceInputIdentity: sourceInputIdentity,
                    scanGeneration: scanGeneration)
            }

            guard let candidate = matching.first else {
                if !familyCandidates.isEmpty {
                    return .init(family: family, state: .candidateWithheld, detail: nil,
                        quoteAsOf: quoteAsOf, validUntil: quoteDeadline,
                        sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
                }
                let state: MacResearchEvaluationDiagnostic.State = family == .orb
                    ? .conditionsNotMet : .completedNoCandidate
                return .init(family: family, state: state, detail: nil,
                    quoteAsOf: quoteAsOf, validUntil: validUntil,
                    sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
            }

            let isDirectional = candidate.direction == .long || candidate.direction == .short
            let isEligibleAndShown = matching.contains { visibleSignalIDs.contains($0.id) }
            let state: MacResearchEvaluationDiagnostic.State
            if family == .orb && !isDirectional && candidate.state != .unavailable {
                state = .conditionsNotMet
            } else if isEligibleAndShown {
                state = .candidateShown
            } else {
                state = .candidateWithheld
            }
            let detail = matching.flatMap(\.rejectionReasons).compactMap(Self.safeReasonLabel).first
            return .init(family: family, state: state, detail: detail,
                quoteAsOf: quoteAsOf, validUntil: validUntil,
                sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration)
        }
    }

    public static func safeReasonLabel(_ code: String) -> String {
        switch code {
        case "before_opening_range": "Opening range has not formed"
        case "opening_range_forming": "Opening range is still forming"
        case "range_sealed", "boundary_approaching": "Waiting for a confirmed range break"
        case "breakout_confirmed_retest_pending", "retest_confirmation_pending": "Retest confirmation is pending"
        case "retest_failed_boundary": "Retest did not hold the boundary"
        case "setup_expired_without_breakout", "setup_expired_waiting_for_retest": "Setup window expired"
        case "quote_missing": "Quote unavailable"
        case "quote_stale": "Quote is stale"
        case "quote_refresh_required": "Refresh the quote before manual entry"
        case "quote_future": "Quote timestamp is invalid"
        case "spread_rejected": "Spread filter rejected the candidate"
        case "m15_context_unavailable": "15-minute context is unavailable"
        case "m15_confirmation_missing": "15-minute confirmation is missing"
        case "setup_expired", "confirmation_window_expired", "entry_window_expired": "Setup entry window expired"
        case "setup_invalidated": "Setup conditions were invalidated"
        case "trigger_time_missing", "confirmation_missing": "Setup confirmation is incomplete"
        case "conditions_not_met": "Setup conditions were not met"
        default: "Additional validation required"
        }
    }
}
#endif
