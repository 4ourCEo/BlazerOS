import Foundation
import BlazerCore

/// A display-only research observation. It intentionally carries no plan, price,
/// ranking score, or order authority.
public struct MacResearchSignal: Sendable, Equatable, Identifiable {
    public let id: String
    public let profileID: String
    public let strategyID: String
    public let strategyVersion: String
    public let instrument: String
    public let direction: AdaptiveDirection
    public let observedAt: Date
    public let validUntil: Date
    public let reasons: [String]
    public let evidenceReferences: [String]
    public let sourceInputIdentity: String
    public let scanGeneration: Int

    public init(id: String, profileID: String, strategyID: String, strategyVersion: String,
                instrument: String, direction: AdaptiveDirection, observedAt: Date,
                validUntil: Date, reasons: [String], evidenceReferences: [String],
                sourceInputIdentity: String, scanGeneration: Int) {
        self.id = id; self.profileID = profileID; self.strategyID = strategyID
        self.strategyVersion = strategyVersion; self.instrument = instrument
        self.direction = direction; self.observedAt = observedAt; self.validUntil = validUntil
        self.reasons = reasons; self.evidenceReferences = evidenceReferences
        self.sourceInputIdentity = sourceInputIdentity; self.scanGeneration = scanGeneration
    }
}

/// Pure projection gate for the separate Mac research panel.
public enum MacResearchSignalProjector {
    public static func project(candidates: [AdaptiveOpportunityCandidate],
                               profiles: [StrategyResearchProfile],
                               instrument: String, scanGeneration: Int,
                               sourceInputIdentity: String, now: Date) -> [MacResearchSignal] {
        guard !instrument.isEmpty, !sourceInputIdentity.isEmpty,
              now.timeIntervalSince1970.isFinite else { return [] }
        var result: [MacResearchSignal] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard candidate.instrument == instrument,
                  candidate.provider.uppercased().replacingOccurrences(of: "_", with: "-") == "OANDA-LIVE",
                  candidate.state == .eligible, candidate.direction == .long || candidate.direction == .short,
                  candidate.spreadState == .accepted, candidate.freshness == .fresh,
                  let observedAt = candidate.observedAt, observedAt.timeIntervalSince1970.isFinite,
                  now.timeIntervalSince(observedAt) >= -1,
                  now.timeIntervalSince(observedAt) <= EntryQuality.maxAgeSeconds,
                  let validUntil = candidate.validUntil, validUntil.timeIntervalSince1970.isFinite,
                  now <= validUntil, validUntil >= observedAt,
                  let configDigest = candidate.effectiveConfigurationSHA256,
                  let evaluatorDigest = candidate.evaluatorCodeSHA256,
                  let adapterDigest = candidate.adapterCodeSHA256,
                  let selectorDigest = candidate.selectorCodeSHA256,
                  let config = AdaptiveOpportunityAdapters.effectiveConfiguration(
                    strategyID: candidate.strategyID, instrument: instrument),
                  let computedConfigDigest = config.sha256(),
                  computedConfigDigest.caseInsensitiveCompare(configDigest) == .orderedSame else { continue }

            let exact = profiles.filter { profile in
                profile.acceptedCandidateIdentities.contains(.init(
                    strategyID: candidate.strategyID, strategyVersion: candidate.strategyVersion))
            }
            guard exact.count == 1, let profile = exact.first,
                  profile.decisionRole == .shadow, !profile.mayAuthorizeOrder,
                  profile.status == .researchCandidate || profile.status == .partialResearch,
                  profile.configurationSHA256ByInstrument?[instrument]?.caseInsensitiveCompare(configDigest) == .orderedSame,
                  profile.evaluatorCodeSHA256?.caseInsensitiveCompare(evaluatorDigest) == .orderedSame,
                  profile.adapterCodeSHA256?.caseInsensitiveCompare(adapterDigest) == .orderedSame,
                  profile.selectorCodeSHA256?.caseInsensitiveCompare(selectorDigest) == .orderedSame,
                  seen.insert(candidate.id).inserted else { continue }

            result.append(MacResearchSignal(id: candidate.id, profileID: profile.id,
                strategyID: candidate.strategyID, strategyVersion: candidate.strategyVersion,
                instrument: instrument, direction: candidate.direction, observedAt: observedAt,
                validUntil: validUntil, reasons: candidate.rejectionReasons,
                evidenceReferences: candidate.evidenceReferences,
                sourceInputIdentity: sourceInputIdentity, scanGeneration: scanGeneration))
        }
        return result
    }
}

#if os(macOS)
public enum MacResearchEvaluatorFamily: String, CaseIterable, Sendable, Equatable, Identifiable {
    case orb = "ORB"
    case candidate001 = "Candidate001"
    case candidate002 = "Candidate002"

    public var id: String { rawValue }

    fileprivate var identity: (strategyID: String, strategyVersion: String) {
        switch self {
        case .orb: ("ORB_BREAK_RETEST_V1", "ORB_BREAK_RETEST_V1")
        case .candidate001: ("CANDIDATE_001_CHOCH_FVG_FIB", "candidate-001-v2")
        case .candidate002: ("CANDIDATE_002_AUCTION_FAILURE", "candidate-002-auction-failure-v2")
        }
    }

    fileprivate var quoteFreshness: TimeInterval { self == .orb ? 5 : 8 }
}

/// Safe, source-bound summary of one connected evaluator's latest scan result.
/// It deliberately contains no direction, prices, plan, record IDs, or raw errors.
public struct MacResearchEvaluationDiagnostic: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case completedNoCandidate
        case conditionsNotMet
        case candidateShown
        case candidateWithheld
        case evaluationFailed
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
        case .conditionsNotMet: "Completed · candidate conditions not met"
        case .candidateShown: "Eligible candidate shown above"
        case .candidateWithheld: "Candidate withheld by validation"
        case .evaluationFailed: "Evaluation failed"
        }
    }
}

/// Projects only source-supported, non-directional evaluator diagnostics.
public enum MacResearchEvaluationDiagnosticProjector {
    public static func project(candidates: [AdaptiveOpportunityCandidate],
                               failedFamilies: Set<MacResearchEvaluatorFamily>,
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
            let isEligibleAndShown = matching.contains {
                $0.state == .eligible && ($0.direction == .long || $0.direction == .short)
                    && visibleSignalIDs.contains($0.id)
            }
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
        case "quote_future": "Quote timestamp is invalid"
        case "spread_rejected": "Spread filter rejected the candidate"
        case "m15_context_unavailable": "15-minute context is unavailable"
        default: "Additional validation required"
        }
    }
}
#endif
