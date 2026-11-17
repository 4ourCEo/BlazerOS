import CryptoKit
import Foundation

/// Provider-native completed candle. IDs are immutable source identities.
public struct GBPJPYTrendPullbackBar: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let provider: String
    public let startTime: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let complete: Bool

    public init(id: String, instrument: String, provider: String, startTime: Date,
                open: Double, high: Double, low: Double, close: Double, complete: Bool) {
        self.id = id; self.instrument = instrument; self.provider = provider
        self.startTime = startTime; self.open = open; self.high = high
        self.low = low; self.close = close; self.complete = complete
    }

    public func isValid() -> Bool {
        !id.isEmpty && !instrument.isEmpty && !provider.isEmpty
            && startTime.timeIntervalSince1970.isFinite
            && [open, high, low, close].allSatisfy { $0.isFinite && $0 > 0 }
            && high >= max(open, close) && low <= min(open, close) && low <= high
    }
}

public struct GBPJPYTrendPullbackQuote: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let instrument: String
    public let provider: String
    public let environment: String
    public let sequence: Int64
    public let sourceTime: Date
    public let receivedAt: Date
    public let bid: Double
    public let ask: Double
    public let correctionOfDigest: String?
    public init(id: String, instrument: String, provider: String, environment: String,
                sequence: Int64, sourceTime: Date, receivedAt: Date, bid: Double, ask: Double,
                correctionOfDigest: String? = nil) {
        self.id = id; self.instrument = instrument; self.provider = provider
        self.environment = environment; self.sequence = sequence
        self.sourceTime = sourceTime; self.receivedAt = receivedAt; self.bid = bid; self.ask = ask
        self.correctionOfDigest = correctionOfDigest
    }
    public var contentDigest: String {
        GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            QuoteContentIdentity(id: id, instrument: instrument, provider: provider, environment: environment,
                sequence: sequence, sourceTime: sourceTime, receivedAt: receivedAt, bid: bid, ask: ask)))
    }
}

private struct QuoteContentIdentity: Encodable {
    let id: String; let instrument: String; let provider: String; let environment: String
    let sequence: Int64; let sourceTime: Date; let receivedAt: Date; let bid: Double; let ask: Double
}

/// Caller-owned attestation of a completed source window. The digest is over the ordered observations,
/// and the sequence policy is explicit so gaps cannot be silently skipped.
public struct GBPJPYTrendPullbackQuoteWindowAttestation: Codable, Sendable, Equatable {
    public let sourceSnapshotDigest: String
    public let coverageStart: Date
    public let completeThrough: Date
    public let firstSequence: Int64?
    public let lastSequence: Int64?
    public let sequencePolicy: String
    public let observationsDigest: String
    public let priorAttestationDigest: String?
    public let digest: String

    public init(sourceSnapshotDigest: String, coverageStart: Date, completeThrough: Date,
                firstSequence: Int64?, lastSequence: Int64?, sequencePolicy: String,
                observations: [GBPJPYTrendPullbackQuote], priorAttestationDigest: String? = nil) {
        self.sourceSnapshotDigest = sourceSnapshotDigest; self.coverageStart = coverageStart
        self.completeThrough = completeThrough; self.firstSequence = firstSequence
        self.lastSequence = lastSequence; self.sequencePolicy = sequencePolicy
        observationsDigest = GBPJPYTrendPullbackConfiguration.sha256(
            GBPJPYTrendPullbackConfiguration.canonical(observations))
        self.priorAttestationDigest = priorAttestationDigest
        digest = GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            QuoteWindowAttestationIdentity(sourceSnapshotDigest: sourceSnapshotDigest,
                coverageStart: coverageStart, completeThrough: completeThrough, firstSequence: firstSequence,
                lastSequence: lastSequence, sequencePolicy: sequencePolicy,
                observationsDigest: observationsDigest, priorAttestationDigest: priorAttestationDigest)))
    }
    fileprivate func isValid(observations: [GBPJPYTrendPullbackQuote], expectedStart: Date,
                             asOf: Date, snapshotDigest: String) -> Bool {
        guard isSelfConsistent, sourceSnapshotDigest == snapshotDigest, coverageStart == expectedStart,
              completeThrough == asOf, sequencePolicy == "CONTIGUOUS_SEQUENCE_V1",
              observationsDigest == GBPJPYTrendPullbackConfiguration.sha256(
                GBPJPYTrendPullbackConfiguration.canonical(observations)),
              firstSequence == observations.first?.sequence,
              lastSequence == observations.last?.sequence else { return false }
        if let firstSequence, let lastSequence {
            return lastSequence >= firstSequence
                && lastSequence - firstSequence + 1 == Int64(observations.count)
        }
        return observations.isEmpty && firstSequence == nil && lastSequence == nil
    }
    fileprivate var isSelfConsistent: Bool {
        digest == GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            QuoteWindowAttestationIdentity(sourceSnapshotDigest: sourceSnapshotDigest,
                coverageStart: coverageStart, completeThrough: completeThrough, firstSequence: firstSequence,
                lastSequence: lastSequence, sequencePolicy: sequencePolicy,
                observationsDigest: observationsDigest, priorAttestationDigest: priorAttestationDigest)))
    }
}

private struct QuoteWindowAttestationIdentity: Encodable {
    let sourceSnapshotDigest: String; let coverageStart: Date; let completeThrough: Date
    let firstSequence: Int64?; let lastSequence: Int64?; let sequencePolicy: String
    let observationsDigest: String; let priorAttestationDigest: String?
}

public struct GBPJPYTrendPullbackQuoteContinuationCursor: Codable, Sendable, Equatable {
    public let eventID: String; public let discoveryDigest: String; public let profileDigest: String
    public let instrument: String; public let provider: String; public let environment: String
    public let quoteSamplingPolicy: String; public let asOf: Date
    public let confirmationEnd: Date?
    public let evidencePrefix: [GBPJPYTrendPullbackQuote]
    public let lockedFirstQuoteID: String?; public let lockedFirstQuoteSequence: Int64?
    public let lockedFirstQuoteSourceTime: Date?; public let lockedFirstQuoteReceivedAt: Date?
    public let lockedFirstQuoteContentDigest: String?
    public let attestation: GBPJPYTrendPullbackQuoteWindowAttestation?
    public let digest: String

    public init(discovery: GBPJPYTrendPullbackDiscoveryEvidence,
                candidate: GBPJPYTrendPullbackBreakDescriptor,
                configuration: GBPJPYTrendPullbackConfiguration) {
        eventID = candidate.id; discoveryDigest = discovery.batch.inputDigest
        profileDigest = configuration.digest(); instrument = configuration.instrument
        provider = configuration.provider; environment = discovery.batch.environment
        quoteSamplingPolicy = configuration.quoteSamplingPolicy; asOf = discovery.batch.asOf
        confirmationEnd = nil; evidencePrefix = []; lockedFirstQuoteID = nil
        lockedFirstQuoteSequence = nil; lockedFirstQuoteSourceTime = nil
        lockedFirstQuoteReceivedAt = nil; lockedFirstQuoteContentDigest = nil
        attestation = nil
        digest = Self.makeDigest(eventID: eventID, discoveryDigest: discoveryDigest,
            profileDigest: profileDigest, instrument: instrument, provider: provider,
            environment: environment, quoteSamplingPolicy: quoteSamplingPolicy, asOf: asOf,
            confirmationEnd: nil, evidencePrefix: [], lockedFirstQuoteID: nil,
            lockedFirstQuoteSequence: nil, lockedFirstQuoteSourceTime: nil,
            lockedFirstQuoteReceivedAt: nil, lockedFirstQuoteContentDigest: nil, attestation: nil)
    }

    fileprivate func advancing(quotes: [GBPJPYTrendPullbackQuote], asOf newAsOf: Date,
                               confirmationEnd newConfirmationEnd: Date?,
                               attestation newAttestation: GBPJPYTrendPullbackQuoteWindowAttestation?) -> Self {
        let boundary = confirmationEnd ?? newConfirmationEnd
        var lockedID = lockedFirstQuoteID
        var lockedSequence = lockedFirstQuoteSequence
        var lockedSource = lockedFirstQuoteSourceTime
        var lockedReceived = lockedFirstQuoteReceivedAt
        var lockedDigest = lockedFirstQuoteContentDigest
        if lockedID == nil, let boundary,
           let first = quotes.first(where: { $0.sourceTime > boundary && $0.sourceTime <= newAsOf && $0.receivedAt <= newAsOf }) {
            lockedID = first.id; lockedSequence = first.sequence; lockedSource = first.sourceTime
            lockedReceived = first.receivedAt; lockedDigest = first.contentDigest
        } else if let lockedID, let lockedSequence, let lockedSource,
                  let replacement = quotes.first(where: { $0.id == lockedID && $0.sequence == lockedSequence && $0.sourceTime == lockedSource }) {
            lockedReceived = replacement.receivedAt; lockedDigest = replacement.contentDigest
        }
        return Self(eventID: eventID, discoveryDigest: discoveryDigest, profileDigest: profileDigest,
            instrument: instrument, provider: provider, environment: environment,
            quoteSamplingPolicy: quoteSamplingPolicy, asOf: newAsOf, confirmationEnd: boundary,
            evidencePrefix: quotes, lockedFirstQuoteID: lockedID, lockedFirstQuoteSequence: lockedSequence,
            lockedFirstQuoteSourceTime: lockedSource, lockedFirstQuoteReceivedAt: lockedReceived,
            lockedFirstQuoteContentDigest: lockedDigest, attestation: newAttestation)
    }

    fileprivate var isValid: Bool {
        (attestation?.isSelfConsistent ?? true)
        && digest == Self.makeDigest(eventID: eventID, discoveryDigest: discoveryDigest,
            profileDigest: profileDigest, instrument: instrument, provider: provider,
            environment: environment, quoteSamplingPolicy: quoteSamplingPolicy, asOf: asOf,
            confirmationEnd: confirmationEnd, evidencePrefix: evidencePrefix,
            lockedFirstQuoteID: lockedFirstQuoteID, lockedFirstQuoteSequence: lockedFirstQuoteSequence,
            lockedFirstQuoteSourceTime: lockedFirstQuoteSourceTime,
            lockedFirstQuoteReceivedAt: lockedFirstQuoteReceivedAt,
            lockedFirstQuoteContentDigest: lockedFirstQuoteContentDigest, attestation: attestation)
    }

    private init(eventID: String, discoveryDigest: String, profileDigest: String, instrument: String,
                 provider: String, environment: String, quoteSamplingPolicy: String, asOf: Date,
                 confirmationEnd: Date?, evidencePrefix: [GBPJPYTrendPullbackQuote],
                 lockedFirstQuoteID: String?, lockedFirstQuoteSequence: Int64?,
                 lockedFirstQuoteSourceTime: Date?, lockedFirstQuoteReceivedAt: Date?,
                 lockedFirstQuoteContentDigest: String?, attestation: GBPJPYTrendPullbackQuoteWindowAttestation?) {
        self.eventID = eventID; self.discoveryDigest = discoveryDigest; self.profileDigest = profileDigest
        self.instrument = instrument; self.provider = provider; self.environment = environment
        self.quoteSamplingPolicy = quoteSamplingPolicy; self.asOf = asOf
        self.confirmationEnd = confirmationEnd; self.evidencePrefix = evidencePrefix
        self.lockedFirstQuoteID = lockedFirstQuoteID; self.lockedFirstQuoteSequence = lockedFirstQuoteSequence
        self.lockedFirstQuoteSourceTime = lockedFirstQuoteSourceTime
        self.lockedFirstQuoteReceivedAt = lockedFirstQuoteReceivedAt
        self.lockedFirstQuoteContentDigest = lockedFirstQuoteContentDigest
        self.attestation = attestation
        digest = Self.makeDigest(eventID: eventID, discoveryDigest: discoveryDigest,
            profileDigest: profileDigest, instrument: instrument, provider: provider,
            environment: environment, quoteSamplingPolicy: quoteSamplingPolicy, asOf: asOf,
            confirmationEnd: confirmationEnd, evidencePrefix: evidencePrefix,
            lockedFirstQuoteID: lockedFirstQuoteID, lockedFirstQuoteSequence: lockedFirstQuoteSequence,
            lockedFirstQuoteSourceTime: lockedFirstQuoteSourceTime,
            lockedFirstQuoteReceivedAt: lockedFirstQuoteReceivedAt,
            lockedFirstQuoteContentDigest: lockedFirstQuoteContentDigest, attestation: attestation)
    }

    private static func makeDigest(eventID: String, discoveryDigest: String, profileDigest: String,
                 instrument: String, provider: String, environment: String, quoteSamplingPolicy: String,
                 asOf: Date, confirmationEnd: Date?, evidencePrefix: [GBPJPYTrendPullbackQuote],
                 lockedFirstQuoteID: String?, lockedFirstQuoteSequence: Int64?,
                 lockedFirstQuoteSourceTime: Date?, lockedFirstQuoteReceivedAt: Date?,
                 lockedFirstQuoteContentDigest: String?, attestation: GBPJPYTrendPullbackQuoteWindowAttestation?) -> String {
        GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            QuoteCursorIdentity(eventID: eventID, discoveryDigest: discoveryDigest, profileDigest: profileDigest,
                instrument: instrument, provider: provider, environment: environment,
                quoteSamplingPolicy: quoteSamplingPolicy, asOf: asOf, confirmationEnd: confirmationEnd,
                evidencePrefix: evidencePrefix, lockedFirstQuoteID: lockedFirstQuoteID,
                lockedFirstQuoteSequence: lockedFirstQuoteSequence, lockedFirstQuoteSourceTime: lockedFirstQuoteSourceTime,
                lockedFirstQuoteReceivedAt: lockedFirstQuoteReceivedAt,
                lockedFirstQuoteContentDigest: lockedFirstQuoteContentDigest, attestation: attestation)))
    }
}

private struct QuoteCursorIdentity: Encodable {
    let eventID: String; let discoveryDigest: String; let profileDigest: String
    let instrument: String; let provider: String; let environment: String; let quoteSamplingPolicy: String
    let asOf: Date; let confirmationEnd: Date?; let evidencePrefix: [GBPJPYTrendPullbackQuote]
    let lockedFirstQuoteID: String?; let lockedFirstQuoteSequence: Int64?
    let lockedFirstQuoteSourceTime: Date?; let lockedFirstQuoteReceivedAt: Date?
    let lockedFirstQuoteContentDigest: String?
    let attestation: GBPJPYTrendPullbackQuoteWindowAttestation?
}

/// Context records are supplied by a versioned caller and may only be measured before use.
public struct GBPJPYTrendPullbackContext: Codable, Sendable, Equatable {
    public let sessionID: String
    public let sessionCalendarDigest: String
    public let timeZoneID: String
    public let regime: String
    public let regimeVersion: String
    public let digest: String
    public let sourceIDs: [String]
    public let measuredAt: Date
    public let sessionOpen: Date
    public let sessionClose: Date
    public init(sessionID: String, sessionCalendarDigest: String, timeZoneID: String,
                regime: String, regimeVersion: String, digest: String, sourceIDs: [String],
                measuredAt: Date, sessionOpen: Date, sessionClose: Date) {
        self.sessionID = sessionID; self.sessionCalendarDigest = sessionCalendarDigest
        self.timeZoneID = timeZoneID; self.regime = regime; self.regimeVersion = regimeVersion
        self.digest = digest; self.sourceIDs = sourceIDs; self.measuredAt = measuredAt
        self.sessionOpen = sessionOpen; self.sessionClose = sessionClose
    }
}

public struct GBPJPYTrendPullbackProvenance: Codable, Sendable, Equatable {
    public let environment: String
    public let buildID: String
    public let codeDigest: String
    public let snapshotDigest: String
    public let lineageIsProviderNative: Bool
    public let quoteWindowComplete: Bool
    public let quoteSamplingPolicy: String
    public init(environment: String, buildID: String, codeDigest: String, snapshotDigest: String,
                lineageIsProviderNative: Bool, quoteWindowComplete: Bool, quoteSamplingPolicy: String) {
        self.environment = environment; self.buildID = buildID; self.codeDigest = codeDigest
        self.snapshotDigest = snapshotDigest; self.lineageIsProviderNative = lineageIsProviderNative
        self.quoteWindowComplete = quoteWindowComplete; self.quoteSamplingPolicy = quoteSamplingPolicy
    }
}

public struct GBPJPYTrendPullbackWindow: Codable, Sendable, Equatable {
    public let firstLowerBarID: String
    public let lastLowerBarID: String
    public init(firstLowerBarID: String, lastLowerBarID: String) {
        self.firstLowerBarID = firstLowerBarID; self.lastLowerBarID = lastLowerBarID
    }
}

public struct GBPJPYTrendPullbackConsumedKey: Codable, Sendable, Equatable, Hashable {
    public let frozenSwingID: String
    public let direction: GBPJPYTrendPullbackDirection
    public init(frozenSwingID: String, direction: GBPJPYTrendPullbackDirection) {
        self.frozenSwingID = frozenSwingID; self.direction = direction
    }
}

/// Caller-owned immutable cursor snapshot. Constructing `[]` explicitly represents the empty cursor.
public struct GBPJPYTrendPullbackEventCursor: Codable, Sendable, Equatable {
    public let consumedKeys: [GBPJPYTrendPullbackConsumedKey]
    public let digest: String
    public init(consumedKeys: [GBPJPYTrendPullbackConsumedKey]) {
        let sorted = consumedKeys.sorted {
            $0.frozenSwingID == $1.frozenSwingID
                ? $0.direction.rawValue < $1.direction.rawValue
                : $0.frozenSwingID < $1.frozenSwingID
        }
        self.consumedKeys = sorted
        self.digest = GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(sorted))
    }
    public var isValid: Bool {
        let canonicalOrder = consumedKeys.sorted {
            $0.frozenSwingID == $1.frozenSwingID
                ? $0.direction.rawValue < $1.direction.rawValue
                : $0.frozenSwingID < $1.frozenSwingID
        }
        return consumedKeys == canonicalOrder
            && !consumedKeys.contains(where: { $0.frozenSwingID.isEmpty || $0.direction == .wait })
            && Set(consumedKeys).count == consumedKeys.count
            && digest == GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(consumedKeys))
    }
}

public struct GBPJPYTrendPullbackBreakDescriptor: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let strategyID: String
    public let strategyVersion: String
    public let profileDigest: String
    public let cursorDigest: String
    public let windowDigest: String
    public let firstLowerBarID: String
    public let lastLowerBarID: String
    public let frozenSwingID: String
    public let direction: GBPJPYTrendPullbackDirection
    public let breakBarID: String
    public let breakBarEnd: Date
    public let higherTimeframeContextCutoff: Date
    public let sourceIDs: [String]
}

public struct GBPJPYTrendPullbackDiscoveryProvenance: Codable, Sendable, Equatable {
    public let provider: String; public let environment: String
    public let buildID: String; public let codeDigest: String; public let snapshotDigest: String
    public let lineageIsProviderNative: Bool; public let sourceIDs: [String]
    public init(provider: String, environment: String, buildID: String, codeDigest: String,
                snapshotDigest: String, lineageIsProviderNative: Bool, sourceIDs: [String]) {
        self.provider = provider; self.environment = environment; self.buildID = buildID
        self.codeDigest = codeDigest; self.snapshotDigest = snapshotDigest
        self.lineageIsProviderNative = lineageIsProviderNative
        self.sourceIDs = Array(Set(sourceIDs)).sorted()
    }
}

public enum GBPJPYTrendPullbackDiscoveryStatus: Codable, Sendable, Equatable {
    case completeWithEvents
    case completeEmpty
    case retryableDataQuality(GBPJPYTrendPullbackReasonCode)
    case integrityRejected(GBPJPYTrendPullbackReasonCode)
}

public struct GBPJPYTrendPullbackDiscoveryBatch: Codable, Sendable, Equatable {
    public let status: GBPJPYTrendPullbackDiscoveryStatus
    public let descriptors: [GBPJPYTrendPullbackBreakDescriptor]
    public let strategyVersion: String; public let profileDigest: String; public let inputDigest: String
    public let instrument: String; public let provider: String; public let environment: String
    public let window: GBPJPYTrendPullbackWindow; public let cursorDigest: String
    public let asOf: Date; public let sourceIDs: [String]
    public let diagnosticReasonCodes: [GBPJPYTrendPullbackReasonCode]
}

public struct GBPJPYTrendPullbackDiscoveryEvidence: Codable, Sendable, Equatable {
    public let batch: GBPJPYTrendPullbackDiscoveryBatch
    public let lowerBars: [GBPJPYTrendPullbackBar]
    public let higherBars: [GBPJPYTrendPullbackBar]
    public let contexts: [GBPJPYTrendPullbackContext]
    public let provenance: GBPJPYTrendPullbackDiscoveryProvenance
    public let cursor: GBPJPYTrendPullbackEventCursor
    public init(batch: GBPJPYTrendPullbackDiscoveryBatch, lowerBars: [GBPJPYTrendPullbackBar],
                higherBars: [GBPJPYTrendPullbackBar], contexts: [GBPJPYTrendPullbackContext],
                provenance: GBPJPYTrendPullbackDiscoveryProvenance,
                cursor: GBPJPYTrendPullbackEventCursor) {
        self.batch = batch; self.lowerBars = lowerBars; self.higherBars = higherBars
        self.contexts = contexts; self.provenance = provenance; self.cursor = cursor
    }
}

public enum GBPJPYTrendPullbackDisposition: String, Codable, Sendable {
    case active = "ACTIVE", terminal = "TERMINAL", integrityRejected = "INTEGRITY_REJECTED"
}

public enum GBPJPYTrendPullbackReasonCode: String, Codable, Sendable, CaseIterable {
    case versionMissing = "version_missing"
    case instrumentMissing = "instrument_missing"
    case providerMissing = "provider_missing"
    case quoteSamplingPolicyMissing = "quote_sampling_policy_missing"
    case sessionCalendarDigestMissing = "session_calendar_digest_missing"
    case timezoneMissing = "timezone_missing"
    case regimeVersionMissing = "regime_version_missing"
    case buildIdentityPolicyMissing = "build_identity_policy_missing"
    case digestVersionMissing = "digest_version_missing"
    case instrumentNotGBPJPY = "instrument_not_gbp_jpy"
    case environmentAllowlistInvalid = "environment_allowlist_invalid"
    case priceUnitsInvalid = "price_units_invalid"
    case timeframesInvalid = "timeframes_invalid"
    case gridOriginInvalid = "grid_origin_invalid"
    case lookbacksInvalid = "lookbacks_invalid"
    case barLimitsInvalid = "bar_limits_invalid"
    case contextAgeInvalid = "context_age_invalid"
    case minimumBreakATRInvalid = "minimum_break_atr_invalid"
    case invalidationBufferATRInvalid = "invalidation_buffer_atr_invalid"
    case continuationBufferATRInvalid = "continuation_buffer_atr_invalid"
    case stopBufferATRInvalid = "stop_buffer_atr_invalid"
    case targetRInvalid = "target_r_invalid"
    case maximumSpreadPipsInvalid = "maximum_spread_pips_invalid"
    case minimumRewardToCostInvalid = "minimum_reward_to_cost_invalid"
    case pullbackToleranceATRInvalid = "pullback_tolerance_atr_invalid"
    case maximumAdverseDriftPipsInvalid = "maximum_adverse_drift_pips_invalid"
    case additionalRoundTripCostPipsInvalid = "additional_round_trip_cost_pips_invalid"
    case sourceQuoteAgeInvalid = "source_quote_age_invalid"
    case receiptQuoteAgeInvalid = "receipt_quote_age_invalid"
    case timezoneInvalid = "timezone_invalid"
    case allowedSessionsInvalid = "allowed_sessions_invalid"
    case allowedRegimesInvalid = "allowed_regimes_invalid"
    case configurationIncomplete = "CONFIGURATION_INCOMPLETE"
    case configurationInvalid = "CONFIGURATION_INVALID"
    case provenanceMissing = "provenance_missing"
    case provenanceInvalid = "provenance_invalid"
    case derivedLineageUnverified = "derived_lineage_unverified"
    case cursorInvalid = "cursor_invalid"
    case evaluationWindowInvalid = "evaluation_window_invalid"
    case candidateDescriptorMismatch = "candidate_descriptor_mismatch"
    case candidateBreakUnknown = "candidate_break_unknown"
    case candidateBreakOutOfWindow = "candidate_break_out_of_window"
    case candidateBreakNotFirst = "candidate_break_not_first_eligible_event"
    case barsInvalidOrUnordered = "bars_invalid_or_unordered"
    case barDataInvalid = "BAR_DATA_INVALID"
    case barIdentityMismatch = "BAR_IDENTITY_MISMATCH"
    case barOrderInvalid = "BAR_ORDER_INVALID"
    case lowerHistoryInsufficient = "LOWER_HISTORY_INSUFFICIENT"
    case higherHistoryInsufficient = "HIGHER_HISTORY_INSUFFICIENT"
    case missingGridInterval = "missing_grid_interval"
    case contextDataUnavailable = "CONTEXT_DATA_UNAVAILABLE"
    case contextMeasuredDisallowed = "CONTEXT_MEASURED_DISALLOWED"
    case contextIdentityMismatch = "CONTEXT_IDENTITY_MISMATCH"
    case contextIneligible = "CONTEXT_INELIGIBLE"
    case awaitingFirstPullback = "AWAITING_FIRST_PULLBACK"
    case awaitingContinuation = "AWAITING_CONTINUATION"
    case pullbackWindowExpired = "PULLBACK_WINDOW_EXPIRED"
    case confirmationWindowExpired = "CONFIRMATION_WINDOW_EXPIRED"
    case sessionClosed = "SESSION_CLOSED"
    case entryIntervalUnresolved = "ENTRY_INTERVAL_UNRESOLVED"
    case entryTooLate = "ENTRY_TOO_LATE"
    case quoteSequenceInvalid = "quote_sequence_invalid"
    case quoteCursorMismatch = "quote_cursor_mismatch"
    case quoteWindowAttestationInvalid = "quote_window_attestation_invalid"
    case quoteIdentityMismatch = "QUOTE_IDENTITY_MISMATCH"
    case quoteDataInvalid = "QUOTE_DATA_INVALID"
    case priceOffTick = "PRICE_OFF_TICK"
    case spreadLimit = "SPREAD_LIMIT"
    case adverseDriftLimit = "ADVERSE_DRIFT_LIMIT"
    case rewardToCostBelowMinimum = "REWARD_TO_COST_BELOW_MINIMUM"
    case structuralInvalidation = "STRUCTURAL_INVALIDATION"
    case firstTouchInvalidated = "FIRST_TOUCH_INVALIDATED"
    case stopDirectionInvalid = "STOP_DIRECTION_INVALID"
    case stopTouchedBeforeEntry = "STOP_TOUCHED_BEFORE_ENTRY"
    case roundedLevelOrderInvalid = "ROUNDED_LEVEL_ORDER_INVALID"
    case costDenominatorInvalid = "COST_DENOMINATOR_INVALID"
    case stopCrossedInQuoteWindow = "STOP_CROSSED_IN_QUOTE_WINDOW"
    case researchCandidate = "RESEARCH_CANDIDATE"
    case dataQualityHold = "DATA_QUALITY_HOLD"
    case evaluationIdentityMismatch = "evaluation_identity_mismatch"
    case evaluationTimeBeforeDiscovery = "evaluation_time_before_discovery"
}

/// All rule inputs are mandatory. This type deliberately supplies no initializer defaults.
public struct GBPJPYTrendPullbackConfiguration: Codable, Sendable, Equatable {
    public let version: String; public let instrument: String; public let provider: String
    public let allowedEnvironments: [String]; public let pipSize: Double; public let priceTickSize: Double
    public let lowerTimeframeSeconds: Int; public let higherTimeframeSeconds: Int
    public let gridOriginUTCSeconds: Int
    public let lowerLeftBars: Int; public let lowerRightBars: Int
    public let higherLeftBars: Int; public let higherRightBars: Int; public let maximumContextAgeSeconds: TimeInterval
    public let atrLookbackBars: Int; public let minimumBreakATR: Double
    public let pullbackToleranceATR: Double; public let invalidationBufferATR: Double
    public let continuationBufferATR: Double; public let maximumBarsFromBreak: Int
    public let maximumBarsAfterPullback: Int; public let stopBufferATR: Double; public let targetR: Double
    public let maximumSourceQuoteAgeSeconds: TimeInterval; public let maximumReceiptQuoteAgeSeconds: TimeInterval
    public let quoteSamplingPolicy: String; public let maximumSpreadPips: Double
    public let maximumAdverseDriftPips: Double; public let additionalRoundTripCostPips: Double
    public let minimumRewardToCost: Double; public let sessionCalendarDigest: String
    public let timeZoneID: String; public let allowedSessions: [String]
    public let regimeVersion: String; public let allowedRegimes: [String]
    public let buildIdentityPolicy: String; public let digestVersion: String

    public init(version: String, instrument: String, provider: String, allowedEnvironments: [String],
                pipSize: Double, priceTickSize: Double, lowerTimeframeSeconds: Int,
                higherTimeframeSeconds: Int, gridOriginUTCSeconds: Int,
                lowerLeftBars: Int, lowerRightBars: Int, higherLeftBars: Int, higherRightBars: Int,
                maximumContextAgeSeconds: TimeInterval, atrLookbackBars: Int, minimumBreakATR: Double,
                pullbackToleranceATR: Double, invalidationBufferATR: Double, continuationBufferATR: Double,
                maximumBarsFromBreak: Int, maximumBarsAfterPullback: Int, stopBufferATR: Double,
                targetR: Double, maximumSourceQuoteAgeSeconds: TimeInterval,
                maximumReceiptQuoteAgeSeconds: TimeInterval, quoteSamplingPolicy: String,
                maximumSpreadPips: Double, maximumAdverseDriftPips: Double,
                additionalRoundTripCostPips: Double, minimumRewardToCost: Double,
                sessionCalendarDigest: String, timeZoneID: String, allowedSessions: [String],
                regimeVersion: String, allowedRegimes: [String], buildIdentityPolicy: String,
                digestVersion: String) {
        self.version = version; self.instrument = instrument; self.provider = provider
        self.allowedEnvironments = allowedEnvironments; self.pipSize = pipSize
        self.priceTickSize = priceTickSize; self.lowerTimeframeSeconds = lowerTimeframeSeconds
        self.higherTimeframeSeconds = higherTimeframeSeconds; self.gridOriginUTCSeconds = gridOriginUTCSeconds
        self.lowerLeftBars = lowerLeftBars; self.lowerRightBars = lowerRightBars
        self.higherLeftBars = higherLeftBars; self.higherRightBars = higherRightBars
        self.maximumContextAgeSeconds = maximumContextAgeSeconds; self.atrLookbackBars = atrLookbackBars
        self.minimumBreakATR = minimumBreakATR; self.pullbackToleranceATR = pullbackToleranceATR
        self.invalidationBufferATR = invalidationBufferATR; self.continuationBufferATR = continuationBufferATR
        self.maximumBarsFromBreak = maximumBarsFromBreak; self.maximumBarsAfterPullback = maximumBarsAfterPullback
        self.stopBufferATR = stopBufferATR; self.targetR = targetR
        self.maximumSourceQuoteAgeSeconds = maximumSourceQuoteAgeSeconds
        self.maximumReceiptQuoteAgeSeconds = maximumReceiptQuoteAgeSeconds
        self.quoteSamplingPolicy = quoteSamplingPolicy; self.maximumSpreadPips = maximumSpreadPips
        self.maximumAdverseDriftPips = maximumAdverseDriftPips
        self.additionalRoundTripCostPips = additionalRoundTripCostPips
        self.minimumRewardToCost = minimumRewardToCost; self.sessionCalendarDigest = sessionCalendarDigest
        self.timeZoneID = timeZoneID; self.allowedSessions = allowedSessions
        self.regimeVersion = regimeVersion; self.allowedRegimes = allowedRegimes
        self.buildIdentityPolicy = buildIdentityPolicy; self.digestVersion = digestVersion
    }

    public func validationIssues() -> [String] {
        var issues: [String] = []
        for (field, value) in [("version", version), ("instrument", instrument), ("provider", provider),
                               ("quote_sampling_policy", quoteSamplingPolicy), ("session_calendar_digest", sessionCalendarDigest),
                               ("timezone", timeZoneID), ("regime_version", regimeVersion),
                               ("build_identity_policy", buildIdentityPolicy), ("digest_version", digestVersion)] where value.isEmpty {
            issues.append("\(field)_missing")
        }
        if instrument != "GBP/JPY" { issues.append("instrument_not_gbp_jpy") }
        if allowedEnvironments.isEmpty || allowedEnvironments.contains(where: \.isEmpty) { issues.append("environment_allowlist_invalid") }
        if ![pipSize, priceTickSize].allSatisfy({ $0.isFinite && $0 > 0 }) { issues.append("price_units_invalid") }
        if lowerTimeframeSeconds <= 0 || higherTimeframeSeconds <= lowerTimeframeSeconds
            || higherTimeframeSeconds % lowerTimeframeSeconds != 0 { issues.append("timeframes_invalid") }
        if gridOriginUTCSeconds < 0 || gridOriginUTCSeconds >= lowerTimeframeSeconds { issues.append("grid_origin_invalid") }
        if [lowerLeftBars, lowerRightBars, higherLeftBars, higherRightBars, atrLookbackBars].contains(where: { $0 < 1 }) { issues.append("lookbacks_invalid") }
        if [maximumBarsFromBreak, maximumBarsAfterPullback].contains(where: { $0 < 1 }) { issues.append("bar_limits_invalid") }
        if !maximumContextAgeSeconds.isFinite || maximumContextAgeSeconds <= 0 { issues.append("context_age_invalid") }
        let positive: [(String, Double)] = [("minimum_break_atr", minimumBreakATR), ("invalidation_buffer_atr", invalidationBufferATR),
            ("continuation_buffer_atr", continuationBufferATR), ("stop_buffer_atr", stopBufferATR), ("target_r", targetR),
            ("maximum_spread_pips", maximumSpreadPips), ("minimum_reward_to_cost", minimumRewardToCost)]
        for (field, value) in positive where !value.isFinite || value <= 0 { issues.append("\(field)_invalid") }
        for (field, value) in [("pullback_tolerance_atr", pullbackToleranceATR),
                               ("maximum_adverse_drift_pips", maximumAdverseDriftPips),
                               ("additional_round_trip_cost_pips", additionalRoundTripCostPips)] where !value.isFinite || value < 0 {
            issues.append("\(field)_invalid")
        }
        for (field, value) in [("source_quote_age", maximumSourceQuoteAgeSeconds), ("receipt_quote_age", maximumReceiptQuoteAgeSeconds)] where !value.isFinite || value <= 0 {
            issues.append("\(field)_invalid")
        }
        if TimeZone(identifier: timeZoneID) == nil { issues.append("timezone_invalid") }
        if allowedSessions.isEmpty || allowedSessions.contains(where: \.isEmpty) { issues.append("allowed_sessions_invalid") }
        if allowedRegimes.isEmpty || allowedRegimes.contains(where: \.isEmpty) { issues.append("allowed_regimes_invalid") }
        return issues.sorted()
    }
    public func digest() -> String { Self.sha256(Self.canonical(self)) }
    fileprivate static func canonical<T: Encodable>(_ value: T) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(value)) ?? Data()
    }
    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum GBPJPYTrendPullbackDirection: String, Codable, Sendable, Hashable { case long = "LONG", short = "SHORT", wait = "WAIT" }
public enum GBPJPYTrendPullbackState: String, Codable, Sendable { case signal = "RESEARCH_SIGNAL", waiting = "WAIT", rejected = "REJECTED", expired = "EXPIRED" }

/// A research observation, never an order or fill. `eventID` is stable across quote refreshes.
public struct GBPJPYTrendPullbackDecision: Codable, Sendable, Equatable {
    public let strategyID: String; public let strategyVersion: String
    public let state: GBPJPYTrendPullbackState; public let direction: GBPJPYTrendPullbackDirection
    public let reasonCodes: [String]; public let configurationDigest: String; public let inputDigest: String
    public var typedReasonCodes: [GBPJPYTrendPullbackReasonCode] {
        reasonCodes.compactMap(GBPJPYTrendPullbackReasonCode.init(rawValue:))
    }
    public let disposition: GBPJPYTrendPullbackDisposition
    public let eventID: String?; public let eventStart: Date?; public let eventEnd: Date?
    public let higherTimeframeContextCutoff: Date?
    public let quoteConfirmationEnd: Date?
    public let quoteContinuationCursor: GBPJPYTrendPullbackQuoteContinuationCursor?
    public let cursorDigest: String?; public let firstLowerBarID: String?; public let lastLowerBarID: String?
    public let snapshotDigest: String?
    public let buildID: String?; public let codeDigest: String?
    public let breakBarID: String?; public let frozenSwingID: String?; public let sourceIDs: [String]
    public let entryPrice: Double?; public let stopPrice: Double?; public let targetPrice: Double?
    public let spreadPips: Double?; public let rewardToCost: Double?
    public let selectedQuoteID: String?; public let quoteBid: Double?; public let quoteAsk: Double?
    public let quoteSourceTime: Date?; public let quoteReceivedAt: Date?
    public let quoteSourceAgeSeconds: TimeInterval?; public let quoteReceiptAgeSeconds: TimeInterval?
    public let rawStopPrice: Double?; public let rawTargetPrice: Double?
    public let additionalRoundTripCostPips: Double?
    fileprivate init(state: GBPJPYTrendPullbackState, direction: GBPJPYTrendPullbackDirection,
                     reasons: [String], configDigest: String, inputDigest: String, eventID: String? = nil,
                     start: Date? = nil, end: Date? = nil, htfCutoff: Date? = nil,
                     cursorDigest: String? = nil, firstLowerBarID: String? = nil, lastLowerBarID: String? = nil,
                     snapshotDigest: String? = nil, buildID: String? = nil, codeDigest: String? = nil,
                     quoteConfirmationEnd: Date? = nil,
                     quoteContinuationCursor: GBPJPYTrendPullbackQuoteContinuationCursor? = nil,
                     breakBarID: String? = nil,
                     swingID: String? = nil, sourceIDs: [String] = [], entry: Double? = nil,
                     stop: Double? = nil, target: Double? = nil, spread: Double? = nil, ratio: Double? = nil,
                     selectedQuote: GBPJPYTrendPullbackQuote? = nil, quoteSourceAge: TimeInterval? = nil,
                     quoteReceiptAge: TimeInterval? = nil, rawStop: Double? = nil, rawTarget: Double? = nil,
                     additionalRoundTripCost: Double? = nil,
                     selectedQuoteIDOverride: String? = nil, quoteBidOverride: Double? = nil,
                     quoteAskOverride: Double? = nil, quoteSourceTimeOverride: Date? = nil,
                     quoteReceivedAtOverride: Date? = nil,
                     quoteSourceAgeOverride: TimeInterval? = nil, quoteReceiptAgeOverride: TimeInterval? = nil,
                     disposition: GBPJPYTrendPullbackDisposition? = nil,
                     version: String) {
        strategyID = "STRAT-GBPJPY-TREND-PULLBACK-V1"; strategyVersion = version
        self.state = state; self.direction = direction; reasonCodes = reasons.sorted()
        let mappedReasons = reasons.compactMap(GBPJPYTrendPullbackReasonCode.init(rawValue:))
        precondition(mappedReasons.count == reasons.count,
            "Every emitted trend-pullback reason must have a typed reason-code case")
        self.disposition = disposition ?? Self.defaultDisposition(state: state, reasons: reasons)
        configurationDigest = configDigest; self.inputDigest = inputDigest; self.eventID = eventID
        eventStart = start; eventEnd = end; self.breakBarID = breakBarID; frozenSwingID = swingID
        higherTimeframeContextCutoff = htfCutoff
        self.quoteConfirmationEnd = quoteConfirmationEnd
        self.quoteContinuationCursor = quoteContinuationCursor
        self.cursorDigest = cursorDigest; self.firstLowerBarID = firstLowerBarID
        self.lastLowerBarID = lastLowerBarID
        self.snapshotDigest = snapshotDigest
        self.buildID = buildID; self.codeDigest = codeDigest
        self.sourceIDs = Array(Set(sourceIDs)).sorted(); entryPrice = entry; stopPrice = stop
        targetPrice = target; spreadPips = spread; rewardToCost = ratio
        selectedQuoteID = selectedQuote?.id ?? selectedQuoteIDOverride
        quoteBid = selectedQuote?.bid ?? quoteBidOverride; quoteAsk = selectedQuote?.ask ?? quoteAskOverride
        quoteSourceTime = selectedQuote?.sourceTime ?? quoteSourceTimeOverride
        quoteReceivedAt = selectedQuote?.receivedAt ?? quoteReceivedAtOverride
        quoteSourceAgeSeconds = quoteSourceAge ?? quoteSourceAgeOverride
        quoteReceiptAgeSeconds = quoteReceiptAge ?? quoteReceiptAgeOverride
        rawStopPrice = rawStop; rawTargetPrice = rawTarget
        additionalRoundTripCostPips = additionalRoundTripCost
    }

    private enum CodingKeys: String, CodingKey {
        case strategyID, strategyVersion, state, direction, reasonCodes, configurationDigest, inputDigest
        case disposition, eventID, eventStart, eventEnd, higherTimeframeContextCutoff, cursorDigest
        case quoteConfirmationEnd, quoteContinuationCursor
        case firstLowerBarID, lastLowerBarID, snapshotDigest, buildID, codeDigest, breakBarID
        case frozenSwingID, sourceIDs, entryPrice, stopPrice, targetPrice, spreadPips, rewardToCost
        case selectedQuoteID, quoteBid, quoteAsk, quoteSourceTime, quoteReceivedAt
        case quoteSourceAgeSeconds, quoteReceiptAgeSeconds, rawStopPrice, rawTargetPrice
        case additionalRoundTripCostPips
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let reasons = try values.decode([String].self, forKey: .reasonCodes)
        guard Set(reasons).count == reasons.count,
              reasons == reasons.sorted(),
              reasons.allSatisfy({ GBPJPYTrendPullbackReasonCode(rawValue: $0) != nil }) else {
            throw DecodingError.dataCorruptedError(forKey: .reasonCodes, in: values,
                debugDescription: "Decision reasons must be unique and have typed reason-code cases")
        }
        let state = try values.decode(GBPJPYTrendPullbackState.self, forKey: .state)
        let disposition = try values.decode(GBPJPYTrendPullbackDisposition.self, forKey: .disposition)
        guard disposition == Self.defaultDisposition(state: state, reasons: reasons) else {
            throw DecodingError.dataCorruptedError(forKey: .disposition, in: values,
                debugDescription: "Decision disposition does not match its state and reasons")
        }
        strategyID = try values.decode(String.self, forKey: .strategyID)
        strategyVersion = try values.decode(String.self, forKey: .strategyVersion)
        self.state = state
        direction = try values.decode(GBPJPYTrendPullbackDirection.self, forKey: .direction)
        reasonCodes = reasons
        configurationDigest = try values.decode(String.self, forKey: .configurationDigest)
        inputDigest = try values.decode(String.self, forKey: .inputDigest)
        self.disposition = disposition
        eventID = try values.decodeIfPresent(String.self, forKey: .eventID)
        eventStart = try values.decodeIfPresent(Date.self, forKey: .eventStart)
        eventEnd = try values.decodeIfPresent(Date.self, forKey: .eventEnd)
        higherTimeframeContextCutoff = try values.decodeIfPresent(Date.self, forKey: .higherTimeframeContextCutoff)
        quoteConfirmationEnd = try values.decodeIfPresent(Date.self, forKey: .quoteConfirmationEnd)
        quoteContinuationCursor = try values.decodeIfPresent(GBPJPYTrendPullbackQuoteContinuationCursor.self, forKey: .quoteContinuationCursor)
        cursorDigest = try values.decodeIfPresent(String.self, forKey: .cursorDigest)
        firstLowerBarID = try values.decodeIfPresent(String.self, forKey: .firstLowerBarID)
        lastLowerBarID = try values.decodeIfPresent(String.self, forKey: .lastLowerBarID)
        snapshotDigest = try values.decodeIfPresent(String.self, forKey: .snapshotDigest)
        buildID = try values.decodeIfPresent(String.self, forKey: .buildID)
        codeDigest = try values.decodeIfPresent(String.self, forKey: .codeDigest)
        breakBarID = try values.decodeIfPresent(String.self, forKey: .breakBarID)
        frozenSwingID = try values.decodeIfPresent(String.self, forKey: .frozenSwingID)
        sourceIDs = try values.decode([String].self, forKey: .sourceIDs)
        entryPrice = try values.decodeIfPresent(Double.self, forKey: .entryPrice)
        stopPrice = try values.decodeIfPresent(Double.self, forKey: .stopPrice)
        targetPrice = try values.decodeIfPresent(Double.self, forKey: .targetPrice)
        spreadPips = try values.decodeIfPresent(Double.self, forKey: .spreadPips)
        rewardToCost = try values.decodeIfPresent(Double.self, forKey: .rewardToCost)
        selectedQuoteID = try values.decodeIfPresent(String.self, forKey: .selectedQuoteID)
        quoteBid = try values.decodeIfPresent(Double.self, forKey: .quoteBid)
        quoteAsk = try values.decodeIfPresent(Double.self, forKey: .quoteAsk)
        quoteSourceTime = try values.decodeIfPresent(Date.self, forKey: .quoteSourceTime)
        quoteReceivedAt = try values.decodeIfPresent(Date.self, forKey: .quoteReceivedAt)
        quoteSourceAgeSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .quoteSourceAgeSeconds)
        quoteReceiptAgeSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .quoteReceiptAgeSeconds)
        rawStopPrice = try values.decodeIfPresent(Double.self, forKey: .rawStopPrice)
        rawTargetPrice = try values.decodeIfPresent(Double.self, forKey: .rawTargetPrice)
        additionalRoundTripCostPips = try values.decodeIfPresent(Double.self, forKey: .additionalRoundTripCostPips)
        if let cursor = quoteContinuationCursor, !cursor.isValid {
            throw DecodingError.dataCorruptedError(forKey: .quoteContinuationCursor, in: values,
                debugDescription: "Quote continuation cursor digest is invalid")
        }
    }

    fileprivate func attachingQuoteCursor(_ cursor: GBPJPYTrendPullbackQuoteContinuationCursor) -> Self {
        .init(state: state, direction: direction, reasons: reasonCodes, configDigest: configurationDigest,
            inputDigest: inputDigest, eventID: eventID, start: eventStart, end: eventEnd,
            htfCutoff: higherTimeframeContextCutoff, cursorDigest: cursorDigest,
            firstLowerBarID: firstLowerBarID, lastLowerBarID: lastLowerBarID,
            snapshotDigest: snapshotDigest, buildID: buildID, codeDigest: codeDigest,
            quoteConfirmationEnd: quoteConfirmationEnd, quoteContinuationCursor: cursor,
            breakBarID: breakBarID, swingID: frozenSwingID, sourceIDs: sourceIDs,
            entry: entryPrice, stop: stopPrice, target: targetPrice, spread: spreadPips,
            ratio: rewardToCost, rawStop: rawStopPrice, rawTarget: rawTargetPrice,
            additionalRoundTripCost: additionalRoundTripCostPips,
            selectedQuoteIDOverride: selectedQuoteID, quoteBidOverride: quoteBid,
            quoteAskOverride: quoteAsk, quoteSourceTimeOverride: quoteSourceTime,
            quoteReceivedAtOverride: quoteReceivedAt, quoteSourceAgeOverride: quoteSourceAgeSeconds,
            quoteReceiptAgeOverride: quoteReceiptAgeSeconds,
            disposition: disposition, version: strategyVersion)
    }

    private static func defaultDisposition(state: GBPJPYTrendPullbackState,
                                           reasons: [String]) -> GBPJPYTrendPullbackDisposition {
        if state == .waiting { return .active }
        let first = reasons.first ?? ""
        let integrityReasons: Set<String> = [
            "CONFIGURATION_INCOMPLETE", "CONFIGURATION_INVALID", "provenance_missing", "provenance_invalid",
            "derived_lineage_unverified", "cursor_invalid", "evaluation_window_invalid",
            "candidate_descriptor_mismatch", "candidate_break_unknown", "candidate_break_out_of_window",
            "candidate_break_not_first_eligible_event", "quote_sequence_invalid", "BAR_IDENTITY_MISMATCH",
            "quote_cursor_mismatch", "quote_window_attestation_invalid",
            "QUOTE_IDENTITY_MISMATCH",
            "BAR_ORDER_INVALID", "CONTEXT_IDENTITY_MISMATCH", "evaluation_identity_mismatch"
        ]
        return integrityReasons.contains(first) ? .integrityRejected : .terminal
    }
}

/// Deterministic, configuration-driven research evaluator. No production selector calls this type.
public enum GBPJPYTrendPullbackV1 {
    public static let strategyID = "STRAT-GBPJPY-TREND-PULLBACK-V1"

    public static func discoverBreakEvents(lowerBars: [GBPJPYTrendPullbackBar],
                                            higherBars: [GBPJPYTrendPullbackBar],
                                            contexts: [GBPJPYTrendPullbackContext], asOf: Date,
                                            window: GBPJPYTrendPullbackWindow,
                                            cursor: GBPJPYTrendPullbackEventCursor,
                                            configuration: GBPJPYTrendPullbackConfiguration) -> [GBPJPYTrendPullbackBreakDescriptor] {
        guard configuration.validationIssues().isEmpty, cursor.isValid,
              let bounds = windowBounds(window, in: lowerBars), asOf.timeIntervalSince1970.isFinite,
              bounds.upperBound < lowerBars.count else { return [] }
        let lowerEvidence = Array(lowerBars[0...bounds.upperBound])
        let windowEnd = end(lowerBars[bounds.upperBound], configuration.lowerTimeframeSeconds)
        let higherEvidence = higherBars.filter { end($0, configuration.higherTimeframeSeconds) <= windowEnd }
        guard validBars(lowerEvidence, timeframe: configuration.lowerTimeframeSeconds, c: configuration, asOf: asOf),
              validBars(higherEvidence, timeframe: configuration.higherTimeframeSeconds, c: configuration, asOf: asOf),
              continuousBySession(lowerEvidence, timeframe: configuration.lowerTimeframeSeconds, contexts: contexts, c: configuration),
              continuousBySession(higherEvidence, timeframe: configuration.higherTimeframeSeconds, contexts: contexts, c: configuration) else { return [] }
        let candidates = findBreaks(lower: lowerEvidence, higher: higherEvidence, c: configuration,
                                    contexts: contexts, asOf: asOf, window: bounds, cursor: cursor)
        return candidates.map { eventDescriptor($0, lower: lowerEvidence, higher: higherEvidence,
                                                 contexts: contexts, c: configuration,
                                                 window: window, cursor: cursor) }
    }

    public static func discoverBreakEventBatch(lowerBars: [GBPJPYTrendPullbackBar],
            higherBars: [GBPJPYTrendPullbackBar], contexts: [GBPJPYTrendPullbackContext],
            provenance: GBPJPYTrendPullbackDiscoveryProvenance, asOf: Date,
            window: GBPJPYTrendPullbackWindow, cursor: GBPJPYTrendPullbackEventCursor,
            configuration: GBPJPYTrendPullbackConfiguration) -> GBPJPYTrendPullbackDiscoveryBatch {
        let ids = Array(Set(lowerBars.map(\.id) + higherBars.map(\.id)
            + contexts.flatMap(\.sourceIDs) + provenance.sourceIDs)).sorted()
        let digest = GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            DiscoveryInputIdentity(configurationDigest: configuration.digest(), lowerBars: lowerBars,
                higherBars: higherBars, contexts: contexts, provenance: provenance,
                asOf: asOf, window: window, cursorDigest: cursor.digest)))
        func batch(_ status: GBPJPYTrendPullbackDiscoveryStatus,
                   _ descriptors: [GBPJPYTrendPullbackBreakDescriptor] = [],
                   _ diagnostics: [GBPJPYTrendPullbackReasonCode] = []) -> GBPJPYTrendPullbackDiscoveryBatch {
            GBPJPYTrendPullbackDiscoveryBatch(status: status, descriptors: descriptors,
                strategyVersion: configuration.version, profileDigest: configuration.digest(), inputDigest: digest,
                instrument: configuration.instrument, provider: provenance.provider,
                environment: provenance.environment, window: window, cursorDigest: cursor.digest,
            asOf: asOf, sourceIDs: ids, diagnosticReasonCodes: diagnostics.sorted { $0.rawValue < $1.rawValue })
        }
        guard configuration.validationIssues().isEmpty else { return batch(.integrityRejected(.configurationInvalid)) }
        guard provenance.provider == configuration.provider, !provenance.environment.isEmpty,
              configuration.allowedEnvironments.contains(provenance.environment),
              !provenance.buildID.isEmpty, !provenance.codeDigest.isEmpty,
              !provenance.snapshotDigest.isEmpty, !provenance.sourceIDs.isEmpty else {
            return batch(.integrityRejected(.provenanceInvalid))
        }
        guard provenance.lineageIsProviderNative else { return batch(.integrityRejected(.derivedLineageUnverified)) }
        guard cursor.isValid, let bounds = windowBounds(window, in: lowerBars), asOf.timeIntervalSince1970.isFinite else {
            return batch(.integrityRejected(cursor.isValid ? .evaluationWindowInvalid : .cursorInvalid))
        }
        guard !contexts.isEmpty else { return batch(.retryableDataQuality(.contextDataUnavailable)) }
        let lowerEvidence = Array(lowerBars[0...bounds.upperBound])
        let windowEnd = end(lowerBars[bounds.upperBound], configuration.lowerTimeframeSeconds)
        let higherEvidence = higherBars.filter { end($0, configuration.higherTimeframeSeconds) <= windowEnd }
        for bars in [lowerEvidence, higherEvidence] {
            if bars.contains(where: { $0.instrument != configuration.instrument || $0.provider != configuration.provider
                || $0.id.isEmpty }) {
                return batch(.integrityRejected(.barIdentityMismatch))
            }
            if !zip(bars, bars.dropFirst()).allSatisfy({ $0.startTime < $1.startTime })
                || Set(bars.map(\.id)).count != bars.count
                || Set(bars.map(\.startTime)).count != bars.count {
                return batch(.integrityRejected(.barOrderInvalid))
            }
        }
        guard validBars(lowerEvidence, timeframe: configuration.lowerTimeframeSeconds, c: configuration, asOf: asOf),
              validBars(higherEvidence, timeframe: configuration.higherTimeframeSeconds, c: configuration, asOf: asOf) else {
            return batch(.retryableDataQuality(.barDataInvalid))
        }
        let requiredLowerHistory = max(configuration.atrLookbackBars + 1,
            configuration.lowerLeftBars + configuration.lowerRightBars + 1)
        guard lowerEvidence.count >= requiredLowerHistory else {
            return batch(.retryableDataQuality(.lowerHistoryInsufficient))
        }
        let requiredHigherHistory = configuration.higherLeftBars + configuration.higherRightBars + 4
        guard higherEvidence.count >= requiredHigherHistory else {
            return batch(.retryableDataQuality(.higherHistoryInsufficient))
        }
        guard continuousBySession(lowerEvidence, timeframe: configuration.lowerTimeframeSeconds,
                                  contexts: contexts, c: configuration),
              continuousBySession(higherEvidence, timeframe: configuration.higherTimeframeSeconds,
                                  contexts: contexts, c: configuration) else {
            return batch(.retryableDataQuality(.missingGridInterval))
        }
        guard contexts.allSatisfy({ !$0.digest.isEmpty && !$0.sessionCalendarDigest.isEmpty
            && !$0.sessionID.isEmpty && !$0.timeZoneID.isEmpty && !$0.regimeVersion.isEmpty
            && !$0.sourceIDs.isEmpty && $0.measuredAt.timeIntervalSince1970.isFinite
            && $0.sessionOpen < $0.sessionClose }) else {
            return batch(.retryableDataQuality(.contextDataUnavailable))
        }
        guard lowerEvidence.allSatisfy({ selectedContext(contexts,
            at: end($0, configuration.lowerTimeframeSeconds)) != nil }) else {
            return batch(.retryableDataQuality(.contextDataUnavailable))
        }
        let contextTimes = lowerEvidence.map { end($0, configuration.lowerTimeframeSeconds) }
            + higherEvidence.map { end($0, configuration.higherTimeframeSeconds) }
        if contextTimes.compactMap({ selectedContext(contexts, at: $0) }).contains(where: {
            $0.sessionCalendarDigest != configuration.sessionCalendarDigest
                || $0.timeZoneID != configuration.timeZoneID || $0.regimeVersion != configuration.regimeVersion
        }) {
            return batch(.integrityRejected(.contextIdentityMismatch))
        }
        let descriptors = findBreaks(lower: lowerEvidence, higher: higherEvidence, c: configuration,
            contexts: contexts, asOf: asOf, window: bounds, cursor: cursor).map {
                eventDescriptor($0, lower: lowerEvidence, higher: higherEvidence,
                    contexts: contexts, c: configuration, window: window, cursor: cursor)
            }
        if !descriptors.isEmpty { return batch(.completeWithEvents, descriptors) }
        let measuredDisallowed = contexts.contains { context in
            context.measuredAt <= asOf && (context.regimeVersion != configuration.regimeVersion
                || !configuration.allowedRegimes.contains(context.regime)
                || !configuration.allowedSessions.contains(context.sessionID)
                || context.sessionCalendarDigest != configuration.sessionCalendarDigest
                || context.timeZoneID != configuration.timeZoneID)
        }
        return batch(.completeEmpty, [], measuredDisallowed ? [.contextMeasuredDisallowed] : [])
    }

    public static func evaluateActiveEvent(discovery: GBPJPYTrendPullbackDiscoveryEvidence,
            candidate: GBPJPYTrendPullbackBreakDescriptor,
            evaluationLowerBars: [GBPJPYTrendPullbackBar], evaluationHigherBars: [GBPJPYTrendPullbackBar],
            quotes: [GBPJPYTrendPullbackQuote], evaluationContexts: [GBPJPYTrendPullbackContext],
            quoteCursor: GBPJPYTrendPullbackQuoteContinuationCursor,
            quoteWindowAttestation: GBPJPYTrendPullbackQuoteWindowAttestation?,
            provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
            configuration: GBPJPYTrendPullbackConfiguration) -> GBPJPYTrendPullbackDecision {
        let original = discovery.batch
        func cursorBindingMatches() -> Bool {
            quoteCursor.isValid && quoteCursor.eventID == candidate.id
                && quoteCursor.discoveryDigest == original.inputDigest
                && quoteCursor.profileDigest == configuration.digest()
                && quoteCursor.instrument == configuration.instrument
                && quoteCursor.provider == configuration.provider
                && quoteCursor.environment == original.environment
                && quoteCursor.quoteSamplingPolicy == configuration.quoteSamplingPolicy
                && asOf >= quoteCursor.asOf
        }
        func quotePrefixMatches() -> Bool {
            guard quotes.count >= quoteCursor.evidencePrefix.count else { return false }
            for (index, prior) in quoteCursor.evidencePrefix.enumerated() {
                let current = quotes[index]
                if prior == current { continue }
                let isLockedFirstCorrection = prior.id == quoteCursor.lockedFirstQuoteID
                    && prior.sequence == quoteCursor.lockedFirstQuoteSequence
                    && prior.sourceTime == quoteCursor.lockedFirstQuoteSourceTime
                    && current.id == prior.id && current.sequence == prior.sequence
                    && current.sourceTime == prior.sourceTime
                    && current.receivedAt > quoteCursor.asOf
                    && current.correctionOfDigest == prior.contentDigest
                if !isLockedFirstCorrection { return false }
            }
            let appended = quotes.dropFirst(quoteCursor.evidencePrefix.count)
            if let prior = quoteCursor.evidencePrefix.last {
                guard appended.first.map({ $0.sequence == prior.sequence + 1 }) ?? true else { return false }
            }
            guard appended.allSatisfy({ $0.receivedAt > quoteCursor.asOf }) else { return false }
            return zip(appended, appended.dropFirst()).allSatisfy {
                $0.sequence == $1.sequence - 1 && $0.sourceTime <= $1.sourceTime
            } && appended.allSatisfy({ $0.correctionOfDigest == nil })
        }
        var allowCursorAdvance = true
        func advancedCursor(boundary: Date? = nil) -> GBPJPYTrendPullbackQuoteContinuationCursor? {
            if !allowCursorAdvance { return quoteCursor }
            guard cursorBindingMatches(), quotePrefixMatches(),
                  quotes.allSatisfy({ $0.sourceTime.timeIntervalSince1970.isFinite
                    && $0.receivedAt.timeIntervalSince1970.isFinite
                    && $0.sourceTime <= asOf && $0.receivedAt <= asOf && $0.receivedAt >= $0.sourceTime }) else { return nil }
            let resolvedBoundary = quoteCursor.confirmationEnd ?? boundary
            if let resolvedBoundary {
                guard let provenance else { return nil }
                let observed = quotes.filter { $0.sourceTime > resolvedBoundary && $0.sourceTime <= asOf }
                let validAttestation = provenance.quoteWindowComplete
                    && quoteWindowAttestation?.isValid(observations: observed,
                        expectedStart: resolvedBoundary, asOf: asOf,
                        snapshotDigest: provenance.snapshotDigest) == true
                    && (quoteCursor.attestation == nil
                        ? quoteWindowAttestation?.priorAttestationDigest == nil
                        : quoteWindowAttestation?.priorAttestationDigest == quoteCursor.attestation?.digest)
                guard validAttestation else { return nil }
            } else if quoteWindowAttestation != nil {
                return nil
            }
            return quoteCursor.advancing(quotes: quotes, asOf: asOf,
                confirmationEnd: resolvedBoundary, attestation: quoteWindowAttestation)
        }
        func activeOutcome(_ state: GBPJPYTrendPullbackState,
                _ disposition: GBPJPYTrendPullbackDisposition, _ reason: String,
                candidate: GBPJPYTrendPullbackBreakDescriptor, discovery: GBPJPYTrendPullbackDiscoveryEvidence,
                provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
                config: GBPJPYTrendPullbackConfiguration, extraSourceIDs: [String]) -> GBPJPYTrendPullbackDecision {
            let digest = GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
                ActiveInputIdentity(discoveryDigest: discovery.batch.inputDigest, candidate: candidate,
                    lowerBars: evaluationLowerBars, higherBars: evaluationHigherBars, quotes: quotes,
                    contexts: evaluationContexts, provenance: provenance, asOf: asOf,
                    evidenceIDs: extraSourceIDs.sorted())))
            let decision = continuationDecision(state, disposition, reason, candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: config,
                extraSourceIDs: extraSourceIDs, inputDigestOverride: digest)
            if let cursor = advancedCursor() { return decision.attachingQuoteCursor(cursor) }
            return decision
        }
        let recomputed = discoverBreakEventBatch(lowerBars: discovery.lowerBars,
            higherBars: discovery.higherBars, contexts: discovery.contexts,
            provenance: discovery.provenance, asOf: original.asOf, window: original.window,
            cursor: discovery.cursor, configuration: configuration)
        guard recomputed == original, original.strategyVersion == configuration.version,
              original.profileDigest == configuration.digest(),
              original.instrument == configuration.instrument,
              original.provider == discovery.provenance.provider,
              original.environment == discovery.provenance.environment,
              original.window == discovery.batch.window,
              original.cursorDigest == discovery.cursor.digest,
              original.asOf.timeIntervalSince1970.isFinite else {
            return activeOutcome(.rejected, .integrityRejected, "candidate_descriptor_mismatch",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        guard asOf.timeIntervalSince1970.isFinite, asOf >= original.asOf else {
            return activeOutcome(.rejected, .integrityRejected, "evaluation_time_before_discovery",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        guard cursorBindingMatches(), quotePrefixMatches() else {
            return activeOutcome(.rejected, .integrityRejected, "quote_cursor_mismatch",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: quotes.map(\.id))
        }
        guard quotes.allSatisfy({ $0.sourceTime.timeIntervalSince1970.isFinite
            && $0.receivedAt.timeIntervalSince1970.isFinite
            && $0.sourceTime <= asOf && $0.receivedAt <= asOf && $0.receivedAt >= $0.sourceTime }) else {
            return activeOutcome(.rejected, .integrityRejected, "quote_window_attestation_invalid",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: quotes.map(\.id))
        }
        guard original.descriptors.contains(candidate) else {
            return activeOutcome(.rejected, .integrityRejected, "candidate_descriptor_mismatch",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        switch original.status {
        case .retryableDataQuality(let reason):
            return activeOutcome(.waiting, .active, reason.rawValue, candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id) + quotes.map(\.id)
                    + evaluationContexts.flatMap(\.sourceIDs))
        case .integrityRejected(let reason):
            return activeOutcome(.rejected, .integrityRejected, reason.rawValue, candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: [])
        case .completeEmpty:
            return activeOutcome(.rejected, .integrityRejected, "candidate_break_unknown",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        case .completeWithEvents:
            break
        }
        guard let provenance else {
            return activeOutcome(.waiting, .active, "provenance_missing", candidate: candidate,
                discovery: discovery, provenance: nil, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        guard evaluationIdentityMatches(discovery: discovery, provenance: provenance,
                                        config: configuration) else {
            return activeOutcome(.rejected, .integrityRejected, "provenance_invalid",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        let prefixCount = discovery.lowerBars.count
        let contextPrefixCount = discovery.contexts.count
        guard evaluationLowerBars.count >= prefixCount,
              Array(evaluationLowerBars.prefix(prefixCount)) == discovery.lowerBars,
              evaluationHigherBars.count >= discovery.higherBars.count,
              Array(evaluationHigherBars.prefix(discovery.higherBars.count)) == discovery.higherBars,
              evaluationContexts.count >= contextPrefixCount,
              Array(evaluationContexts.prefix(contextPrefixCount)) == discovery.contexts,
              evaluationContexts.dropFirst(contextPrefixCount).allSatisfy({ $0.measuredAt > original.asOf }) else {
            return activeOutcome(.rejected, .integrityRejected, "evaluation_identity_mismatch",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        guard asOf.timeIntervalSince1970.isFinite, !evaluationLowerBars.isEmpty else {
            return activeOutcome(.waiting, .active, "BAR_DATA_INVALID", candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        if evaluationLowerBars.contains(where: { $0.instrument != configuration.instrument
            || $0.provider != configuration.provider || $0.id.isEmpty }) {
            return activeOutcome(.rejected, .integrityRejected, "BAR_IDENTITY_MISMATCH",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        if !zip(evaluationLowerBars, evaluationLowerBars.dropFirst()).allSatisfy({ $0.startTime < $1.startTime })
            || Set(evaluationLowerBars.map(\.id)).count != evaluationLowerBars.count
            || Set(evaluationLowerBars.map(\.startTime)).count != evaluationLowerBars.count {
            return activeOutcome(.rejected, .integrityRejected, "BAR_ORDER_INVALID",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        guard validBars(evaluationLowerBars, timeframe: configuration.lowerTimeframeSeconds,
                        c: configuration, asOf: asOf) else {
            return activeOutcome(.waiting, .active, "BAR_DATA_INVALID", candidate: candidate,
                discovery: discovery, provenance: provenance,
                asOf: asOf, config: configuration, extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        guard continuousBySession(evaluationLowerBars, timeframe: configuration.lowerTimeframeSeconds,
                                  contexts: evaluationContexts, c: configuration) else {
            return activeOutcome(.waiting, .active, "missing_grid_interval", candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        guard !evaluationContexts.isEmpty else {
            return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE", candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        guard let breakIndex = evaluationLowerBars.firstIndex(where: { $0.id == candidate.breakBarID }) else {
            return activeOutcome(.rejected, .integrityRejected, "candidate_break_unknown",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        for bar in evaluationLowerBars[breakIndex...] {
            let contextTime = end(bar, configuration.lowerTimeframeSeconds)
            guard let context = selectedContext(evaluationContexts, at: contextTime) else {
                return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration, extraSourceIDs: evaluationLowerBars.map(\.id))
            }
            if context.sessionCalendarDigest != configuration.sessionCalendarDigest
                || context.timeZoneID != configuration.timeZoneID
                || context.regimeVersion != configuration.regimeVersion {
                return activeOutcome(.rejected, .integrityRejected, "CONTEXT_IDENTITY_MISMATCH",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration, extraSourceIDs: context.sourceIDs)
            }
            guard !context.digest.isEmpty, !context.sourceIDs.isEmpty,
                  context.measuredAt.timeIntervalSince1970.isFinite else {
                return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration, extraSourceIDs: evaluationLowerBars.map(\.id))
            }
            if contextTime.timeIntervalSince(context.measuredAt) > configuration.maximumContextAgeSeconds {
                return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration, extraSourceIDs: evaluationLowerBars.map(\.id) + context.sourceIDs)
            }
            if !configuration.allowedRegimes.contains(context.regime)
                || !configuration.allowedSessions.contains(context.sessionID) {
            return activeOutcome(.rejected, .terminal, "CONTEXT_MEASURED_DISALLOWED",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: context.sourceIDs)
            }
        }
        if let context = selectedContext(evaluationContexts, at: asOf) {
            if asOf < context.sessionClose && asOf.timeIntervalSince(context.measuredAt) > configuration.maximumContextAgeSeconds {
                return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE", candidate: candidate,
                    discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                    extraSourceIDs: evaluationLowerBars.map(\.id) + context.sourceIDs)
            }
        } else if asOf < (selectedContext(evaluationContexts, at: end(evaluationLowerBars.last!, configuration.lowerTimeframeSeconds))?.sessionClose ?? .distantPast) {
            return activeOutcome(.waiting, .active, "CONTEXT_DATA_UNAVAILABLE", candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                extraSourceIDs: evaluationLowerBars.map(\.id))
        }
        let quoteProvenance = provenance
        if quoteProvenance.quoteSamplingPolicy != configuration.quoteSamplingPolicy {
            return activeOutcome(.rejected, .integrityRejected, "provenance_invalid",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: [])
        }
        guard zip(quotes, quotes.dropFirst()).allSatisfy({
            $0.sequence < $1.sequence && $0.sourceTime <= $1.sourceTime
        }) else {
            return activeOutcome(.rejected, .integrityRejected, "quote_sequence_invalid",
                candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                config: configuration, extraSourceIDs: quotes.map(\.id))
        }
        let result = evaluate(lowerBars: evaluationLowerBars, higherBars: evaluationHigherBars,
            quotes: quotes, contexts: evaluationContexts, provenance: provenance, asOf: asOf,
            configuration: configuration, window: original.window, cursor: discovery.cursor,
            candidate: candidate)
        if let boundary = result.quoteConfirmationEnd {
            let observed = quotes.filter { $0.sourceTime > boundary && $0.sourceTime <= asOf }
            let attestationValid = provenance.quoteWindowComplete
                && quoteWindowAttestation?.isValid(observations: observed, expectedStart: boundary,
                    asOf: asOf, snapshotDigest: provenance.snapshotDigest) == true
                && (quoteCursor.attestation == nil
                    ? quoteWindowAttestation?.priorAttestationDigest == nil
                    : quoteWindowAttestation?.priorAttestationDigest == quoteCursor.attestation?.digest)
            if !attestationValid && observed.isEmpty {
                allowCursorAdvance = false
                let held = reclassifyAsActiveHold(result, reason: "ENTRY_INTERVAL_UNRESOLVED",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration)
                return held.attachingQuoteCursor(quoteCursor)
            }
            if !attestationValid {
                return activeOutcome(.rejected, .integrityRejected, "quote_window_attestation_invalid",
                    candidate: candidate, discovery: discovery, provenance: provenance, asOf: asOf,
                    config: configuration, extraSourceIDs: observed.map(\.id))
            }
        }
        if result.reasonCodes.contains("ENTRY_INTERVAL_UNRESOLVED")
            || result.reasonCodes.contains("PRICE_OFF_TICK")
            || result.reasonCodes.contains("QUOTE_DATA_INVALID") {
            let held = reclassifyAsActiveHold(result, reason: result.reasonCodes[0], candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration)
            if let cursor = advancedCursor(boundary: result.quoteConfirmationEnd) { return held.attachingQuoteCursor(cursor) }
            return held
        }
        if result.reasonCodes.contains("CONTEXT_INELIGIBLE") {
            let context = selectedContext(evaluationContexts, at: asOf)
            let contextUnavailable = context == nil || asOf.timeIntervalSince(context!.measuredAt) > configuration.maximumContextAgeSeconds
            let reason = contextUnavailable ? "CONTEXT_DATA_UNAVAILABLE" : "CONTEXT_MEASURED_DISALLOWED"
            let disposition: GBPJPYTrendPullbackDisposition = contextUnavailable ? .active : .terminal
            let held = reclassifyAsActiveHold(result, reason: reason, candidate: candidate,
                discovery: discovery, provenance: provenance, asOf: asOf, config: configuration,
                disposition: disposition, state: contextUnavailable ? .waiting : .rejected)
            if let cursor = advancedCursor(boundary: result.quoteConfirmationEnd) { return held.attachingQuoteCursor(cursor) }
            return held
        }
        if let cursor = advancedCursor(boundary: result.quoteConfirmationEnd) { return result.attachingQuoteCursor(cursor) }
        return result
    }

    public static func evaluate(lowerBars: [GBPJPYTrendPullbackBar], higherBars: [GBPJPYTrendPullbackBar],
                                quotes: [GBPJPYTrendPullbackQuote], contexts: [GBPJPYTrendPullbackContext],
                                provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
                                configuration: GBPJPYTrendPullbackConfiguration?,
                                window: GBPJPYTrendPullbackWindow,
                                cursor: GBPJPYTrendPullbackEventCursor,
                                candidate: GBPJPYTrendPullbackBreakDescriptor) -> GBPJPYTrendPullbackDecision {
        let configDigest = configuration?.digest() ?? ""
        let baseInputDigest = GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(
            InputIdentity(configDigest: configDigest, lowerBars: lowerBars, higherBars: higherBars,
                          quotes: quotes, contexts: contexts, provenance: provenance, asOf: asOf)))
        guard let c = configuration else { return decision(.waiting, .wait, ["CONFIGURATION_INCOMPLETE"], c: nil, input: baseInputDigest, provenance: provenance) }
        guard c.validationIssues().isEmpty else { return decision(.rejected, .wait, ["CONFIGURATION_INVALID"] + c.validationIssues(), c: c, input: baseInputDigest, provenance: provenance) }
        guard asOf.timeIntervalSince1970.isFinite, let provenance else { return decision(.rejected, .wait, ["provenance_missing"], c: c, input: baseInputDigest, provenance: provenance) }
        guard provenance.lineageIsProviderNative else { return decision(.rejected, .wait, ["derived_lineage_unverified"], c: c, input: baseInputDigest, provenance: provenance) }
        guard provenance.environment.isEmpty == false, c.allowedEnvironments.contains(provenance.environment),
              !provenance.buildID.isEmpty, !provenance.codeDigest.isEmpty, !provenance.snapshotDigest.isEmpty,
              provenance.quoteSamplingPolicy == c.quoteSamplingPolicy else {
            return decision(.rejected, .wait, ["provenance_invalid"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard cursor.isValid else { return decision(.rejected, .wait, ["cursor_invalid"], c: c, input: baseInputDigest, provenance: provenance) }
        let lower = lowerBars
        let higher = higherBars
        guard let bounds = windowBounds(window, in: lower) else {
            return decision(.rejected, .wait, ["evaluation_window_invalid"], c: c, input: baseInputDigest, provenance: provenance)
        }
        let lowerEvidence = Array(lower[0...bounds.upperBound])
        let evaluationUpperBound = lower.count - 1
        let windowEnd = end(lower[bounds.upperBound], c.lowerTimeframeSeconds)
        let higherEvidence = higher.filter { end($0, c.higherTimeframeSeconds) <= windowEnd }
        guard validBars(lower, timeframe: c.lowerTimeframeSeconds, c: c, asOf: asOf),
              validBars(higherEvidence, timeframe: c.higherTimeframeSeconds, c: c, asOf: asOf) else {
            return decision(.rejected, .wait, ["bars_invalid_or_unordered"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard continuousBySession(lower, timeframe: c.lowerTimeframeSeconds, contexts: contexts, c: c),
              continuousBySession(higherEvidence, timeframe: c.higherTimeframeSeconds, contexts: contexts, c: c) else {
            return decision(.rejected, .wait, ["missing_grid_interval"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard candidate.strategyID == strategyID, candidate.strategyVersion == c.version,
              candidate.profileDigest == c.digest(), candidate.cursorDigest == cursor.digest,
              candidate.windowDigest == windowDigest(window) else {
            return decision(.rejected, .wait, ["candidate_descriptor_mismatch"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard let candidateIndex = lower.firstIndex(where: { $0.id == candidate.breakBarID }) else {
            return decision(.rejected, .wait, ["candidate_break_unknown"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard candidateIndex >= bounds.lowerBound && candidateIndex <= bounds.upperBound else {
            return decision(.rejected, .wait, ["candidate_break_out_of_window"], c: c, input: baseInputDigest, provenance: provenance)
        }
        let discovered = findBreaks(lower: lowerEvidence, higher: higherEvidence, c: c, contexts: contexts,
                                    asOf: asOf, window: bounds, cursor: cursor)
        let sameBarEvents = discovered.filter { $0.breakBarID == candidate.breakBarID }
        guard !sameBarEvents.isEmpty else {
            return decision(.rejected, .wait, ["candidate_break_not_first_eligible_event"], c: c, input: baseInputDigest, provenance: provenance)
        }
        guard let breakData = sameBarEvents.first(where: { event in
            let descriptor = eventDescriptor(event, lower: lowerEvidence, higher: higherEvidence, contexts: contexts,
                                             c: c, window: window, cursor: cursor)
            return descriptorMatches(descriptor, candidate)
        }) else {
            return decision(.rejected, .wait, ["candidate_descriptor_mismatch"], c: c, input: baseInputDigest, provenance: provenance)
        }
        let expectedDescriptor = eventDescriptor(breakData, lower: lowerEvidence, higher: higherEvidence,
            contexts: contexts, c: c, window: window, cursor: cursor)
        guard expectedDescriptor == candidate else {
            return decision(.rejected, .wait, ["candidate_descriptor_mismatch"], c: c, input: baseInputDigest, provenance: provenance)
        }
        let (breakIndex, swing, direction, atr, htfIDs, htfCutoff) = (breakData.index, breakData.swing,
            breakData.direction, breakData.atr, breakData.htfPivotIDs, breakData.htfCutoff)
        let b = lower[breakIndex]; let bEnd = end(b, c.lowerTimeframeSeconds)
        guard let breakContext = selectedContext(contexts, at: bEnd), contextAllowed(contexts, at: bEnd, c: c) else {
            return eventFailure(.rejected, "CONTEXT_INELIGIBLE", c: c,
                candidate: candidate, window: window, cursor: cursor, lower: lower, higher: higher,
                provenance: provenance, asOf: asOf)
        }
        var usedQuoteEvidence: [GBPJPYTrendPullbackQuote] = []
        var usedContextTimes: [Date] = [bEnd]
        var auditQuote: GBPJPYTrendPullbackQuote?
        var auditQuoteSourceAge: TimeInterval?
        var auditQuoteReceiptAge: TimeInterval?
        var auditRawStop: Double?
        var auditRoundedStop: Double?
        var auditRawTarget: Double?
        var auditRoundedTarget: Double?
        var auditConfirmationEnd: Date?
        var inputDigest = eventInputDigest(configuration: c, window: window, cursor: cursor,
            candidate: candidate, lower: lower, higher: higher, quotes: [], contexts: [breakContext],
            provenance: provenance, asOf: asOf, lowerThrough: breakData.index,
            higherTimeframeSeconds: c.higherTimeframeSeconds)
        func terminal(_ state: GBPJPYTrendPullbackState, _ reason: String, _ bar: GBPJPYTrendPullbackBar,
                      _ start: Date, _ index: Int, _ bars: [GBPJPYTrendPullbackBar], _ pivot: Pivot,
                      _ eventDirection: GBPJPYTrendPullbackDirection, _ pivotIDs: [String], _ cutoff: Date,
                      _ config: GBPJPYTrendPullbackConfiguration, _ ignoredInput: String,
                      _ evaluationTime: Date) -> GBPJPYTrendPullbackDecision {
            let safeIndex = max(0, min(index, evaluationUpperBound))
            var usedContexts: [GBPJPYTrendPullbackContext] = []
            for time in usedContextTimes {
                if let context = selectedContext(contexts, at: time), !usedContexts.contains(context) { usedContexts.append(context) }
            }
            usedContexts = eventContexts(lower: Array(lower[0...safeIndex]),
                higher: higher.filter { end($0, config.higherTimeframeSeconds) <= cutoff }, c: config,
                baseContexts: usedContexts, allContexts: contexts)
            inputDigest = eventInputDigest(configuration: config, window: window, cursor: cursor,
                candidate: candidate, lower: lower, higher: higher, quotes: usedQuoteEvidence,
                contexts: usedContexts, provenance: provenance, asOf: evaluationTime,
                lowerThrough: safeIndex, higherTimeframeSeconds: config.higherTimeframeSeconds)
            var ids = candidate.sourceIDs
            ids.append(contentsOf: lower[0...safeIndex].map(\.id))
            ids.append(contentsOf: higher.filter { end($0, config.higherTimeframeSeconds) <= cutoff }.map(\.id))
            ids.append(contentsOf: usedQuoteEvidence.map(\.id))
            ids.append(contentsOf: usedContexts.flatMap(\.sourceIDs))
            return GBPJPYTrendPullbackDecision(state: state, direction: eventDirection, reasons: [reason],
                configDigest: config.digest(), inputDigest: inputDigest, eventID: candidate.id,
                start: start, end: evaluationTime, htfCutoff: cutoff, cursorDigest: cursor.digest,
                firstLowerBarID: window.firstLowerBarID, lastLowerBarID: window.lastLowerBarID,
                snapshotDigest: provenance.snapshotDigest, buildID: provenance.buildID,
                codeDigest: provenance.codeDigest, quoteConfirmationEnd: auditConfirmationEnd,
                breakBarID: bar.id,
                swingID: pivot.bar.id, sourceIDs: ids,
                entry: auditQuote.map { eventDirection == .long ? $0.ask : $0.bid },
                stop: auditRoundedStop, target: auditRoundedTarget,
                spread: auditQuote.map { ($0.ask - $0.bid) / config.pipSize },
                selectedQuote: auditQuote, quoteSourceAge: auditQuoteSourceAge,
                quoteReceiptAge: auditQuoteReceiptAge, rawStop: auditRawStop,
                rawTarget: auditRawTarget, additionalRoundTripCost: config.additionalRoundTripCostPips,
                disposition: state == .waiting ? .active : .terminal,
                version: config.version)
        }
        let sign = direction == .long ? 1.0 : -1.0
        let zoneLow = swing.price - c.pullbackToleranceATR * atr
        let zoneHigh = swing.price + c.pullbackToleranceATR * atr
        let invalidation = swing.price - sign * c.invalidationBufferATR * atr
        var touchIndex: Int?; var expired = false
        let firstIndex = breakIndex + 1
        let breakDeadline = breakIndex + c.maximumBarsFromBreak
        let lastAvailableIndex = evaluationUpperBound
        let lastBreakIndex = min(lastAvailableIndex, breakDeadline)
        if firstIndex <= lastBreakIndex {
            for i in firstIndex...lastBreakIndex {
                let bar = lower[i]
                if end(bar, c.lowerTimeframeSeconds) >= breakContext.sessionClose {
                    usedContextTimes.append(end(bar, c.lowerTimeframeSeconds))
                    return terminal(.expired, "SESSION_CLOSED", b, bEnd, i, lower, swing, direction,
                        htfIDs, htfCutoff, c, inputDigest, asOf)
                }
                if direction == .long ? bar.close <= invalidation : bar.close >= invalidation { return terminal(.rejected, "STRUCTURAL_INVALIDATION", b, bEnd, i, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
                if bar.low <= zoneHigh && bar.high >= zoneLow {
                    guard direction == .long ? bar.close > invalidation : bar.close < invalidation else {
                        return terminal(.rejected, "FIRST_TOUCH_INVALIDATED", b, bEnd, i, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
                    }
                    touchIndex = i; break
                }
            }
        }
        guard let touch = touchIndex else {
            expired = lastAvailableIndex >= breakDeadline
            usedContextTimes.append(asOf)
            let sessionClosed = asOf >= breakContext.sessionClose || !sameSession(contexts, at: asOf, reference: breakContext, c: c)
            let state: GBPJPYTrendPullbackState = (expired || sessionClosed) ? .expired : .waiting
            let reason = sessionClosed ? "SESSION_CLOSED" : (expired ? "PULLBACK_WINDOW_EXPIRED" : "AWAITING_FIRST_PULLBACK")
            return terminal(state, reason, b, bEnd, max(breakIndex, lastBreakIndex), lower, swing, direction,
                            htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        usedContextTimes.append(end(lower[touch], c.lowerTimeframeSeconds))
        let triggerDeadline = touch + c.maximumBarsAfterPullback
        let maxTrigger = min(lastAvailableIndex, triggerDeadline)
        var confirmation: Int?
        if touch + 1 <= maxTrigger {
            for i in (touch + 1)...maxTrigger {
                let bar = lower[i], prev = lower[i - 1]
                if end(bar, c.lowerTimeframeSeconds) >= breakContext.sessionClose {
                    usedContextTimes.append(end(bar, c.lowerTimeframeSeconds))
                    return terminal(.expired, "SESSION_CLOSED", b, bEnd, i, lower, swing, direction,
                        htfIDs, htfCutoff, c, inputDigest, asOf)
                }
                if direction == .long ? bar.close <= invalidation : bar.close >= invalidation {
                    return terminal(.rejected, "STRUCTURAL_INVALIDATION", b, bEnd, i, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
                }
                let trigger = direction == .long
                    ? max(swing.price, prev.high) + c.continuationBufferATR * atr
                    : min(swing.price, prev.low) - c.continuationBufferATR * atr
                if direction == .long ? bar.close > trigger : bar.close < trigger { confirmation = i; break }
            }
        }
        guard let confirm = confirmation else {
            let isExpired = lastAvailableIndex >= triggerDeadline
            usedContextTimes.append(asOf)
            let sessionClosed = asOf >= breakContext.sessionClose || !sameSession(contexts, at: asOf, reference: breakContext, c: c)
            let state: GBPJPYTrendPullbackState = (isExpired || sessionClosed) ? .expired : .waiting
            let reason = sessionClosed ? "SESSION_CLOSED" : (isExpired ? "CONFIRMATION_WINDOW_EXPIRED" : "AWAITING_CONTINUATION")
            return terminal(state, reason, b, bEnd, max(touch, maxTrigger), lower, swing, direction,
                            htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let cb = lower[confirm], cbEnd = end(cb, c.lowerTimeframeSeconds)
        auditConfirmationEnd = cbEnd
        usedContextTimes.append(cbEnd)
        if cbEnd >= breakContext.sessionClose {
            return terminal(.expired, "SESSION_CLOSED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let structuralExtreme = lower[touch..<confirm].reduce(direction == .long ? Double.infinity : -Double.infinity) {
            direction == .long ? min($0, $1.low) : max($0, $1.high)
        }
        var rawStop = structuralExtreme - sign * c.stopBufferATR * atr
        guard rawStop.isFinite, (direction == .long ? rawStop < cb.close : rawStop > cb.close) else {
            return terminal(.rejected, "STOP_DIRECTION_INVALID", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        auditRawStop = rawStop
        let tick = c.priceTickSize
        rawStop = direction == .long ? floor(rawStop / tick) * tick : ceil(rawStop / tick) * tick
        auditRoundedStop = rawStop
        if direction == .long ? cb.low <= rawStop : cb.high >= rawStop {
            return terminal(.rejected, "STOP_TOUCHED_BEFORE_ENTRY", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        if end(lower[touch], c.lowerTimeframeSeconds) >= breakContext.sessionClose {
            return terminal(.expired, "SESSION_CLOSED", b, bEnd, touch, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard contextAllowed(contexts, at: end(lower[touch], c.lowerTimeframeSeconds), c: c),
              contextAllowed(contexts, at: cbEnd, c: c) else {
            return terminal(.rejected, "CONTEXT_INELIGIBLE", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard sameSession(contexts, at: end(lower[touch], c.lowerTimeframeSeconds), reference: breakContext, c: c),
              sameSession(contexts, at: cbEnd, reference: breakContext, c: c) else {
            return terminal(.expired, "SESSION_CLOSED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard provenance.quoteWindowComplete else {
            return terminal(.rejected, "ENTRY_INTERVAL_UNRESOLVED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let validQuotes = quotes.filter { $0.sourceTime > cbEnd }
        guard let quote = validQuotes.first else {
            return terminal(.rejected, "ENTRY_INTERVAL_UNRESOLVED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        usedQuoteEvidence = validQuotes.filter { $0.sourceTime <= quote.sourceTime }
        auditQuote = quote
        auditQuoteSourceAge = asOf.timeIntervalSince(quote.sourceTime)
        auditQuoteReceiptAge = asOf.timeIntervalSince(quote.receivedAt)
        guard !usedQuoteEvidence.isEmpty,
              Set(usedQuoteEvidence.map(\.sequence)).count == usedQuoteEvidence.count,
              zip(usedQuoteEvidence, usedQuoteEvidence.dropFirst()).allSatisfy({ pair in
                  pair.0.sequence < pair.1.sequence && pair.0.sourceTime <= pair.1.sourceTime
              }) else {
            return terminal(.rejected, "quote_sequence_invalid", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard usedQuoteEvidence.allSatisfy({ !$0.id.isEmpty && $0.sequence >= 0
            && $0.instrument == c.instrument && $0.provider == c.provider
            && $0.environment == provenance.environment }) else {
            return terminal(.rejected, "QUOTE_IDENTITY_MISMATCH", b, bEnd, confirm, lower, swing, direction,
                htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard usedQuoteEvidence.allSatisfy({ $0.bid.isFinite && $0.ask.isFinite && $0.bid > 0
            && $0.ask >= $0.bid && $0.receivedAt >= $0.sourceTime && $0.receivedAt <= asOf
            && $0.sourceTime.timeIntervalSince1970.isFinite }) else {
            return terminal(.rejected, "QUOTE_DATA_INVALID", b, bEnd, confirm, lower, swing, direction,
                htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard asOf.timeIntervalSince(quote.sourceTime) <= c.maximumSourceQuoteAgeSeconds,
              asOf.timeIntervalSince(quote.receivedAt) <= c.maximumReceiptQuoteAgeSeconds else {
            return terminal(.rejected, "ENTRY_INTERVAL_UNRESOLVED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        if let interveningBar = lower[0...evaluationUpperBound].first(where: {
            $0.startTime >= cbEnd && end($0, c.lowerTimeframeSeconds) <= quote.sourceTime
        }), let interveningIndex = lower.firstIndex(where: { $0.id == interveningBar.id }) {
            return terminal(.rejected, "ENTRY_TOO_LATE", b, bEnd, interveningIndex,
                lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        usedContextTimes.append(quote.sourceTime)
        if quote.sourceTime >= breakContext.sessionClose { return terminal(.expired, "SESSION_CLOSED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        guard contextAllowed(contexts, at: quote.sourceTime, c: c) else { return terminal(.rejected, "CONTEXT_INELIGIBLE", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        guard sameSession(contexts, at: quote.sourceTime, reference: breakContext, c: c) else { return terminal(.expired, "SESSION_CLOSED", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        if usedQuoteEvidence.contains(where: { direction == .long ? $0.bid <= rawStop : $0.ask >= rawStop }) {
            return terminal(.rejected, "STOP_CROSSED_IN_QUOTE_WINDOW", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let entry = direction == .long ? quote.ask : quote.bid
        guard aligned(entry, tick: tick), aligned(quote.bid, tick: tick), aligned(quote.ask, tick: tick) else {
            return terminal(.rejected, "PRICE_OFF_TICK", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let drift = (direction == .long ? max(0, quote.ask - cb.close) : max(0, cb.close - quote.bid)) / c.pipSize
        let spread = (quote.ask - quote.bid) / c.pipSize
        guard drift <= c.maximumAdverseDriftPips, spread <= c.maximumSpreadPips else {
            return terminal(.rejected, drift > c.maximumAdverseDriftPips ? "ADVERSE_DRIFT_LIMIT" : "SPREAD_LIMIT", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        guard direction == .long ? rawStop < entry : rawStop > entry else { return terminal(.rejected, "STOP_DIRECTION_INVALID", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        let risk = abs(entry - rawStop), rawTarget = entry + sign * risk * c.targetR
        auditRawTarget = rawTarget
        let target = direction == .long ? floor(rawTarget / tick) * tick : ceil(rawTarget / tick) * tick
        auditRoundedTarget = target
        guard direction == .long ? rawStop < entry && target > entry : rawStop > entry && target < entry else {
            return terminal(.rejected, "ROUNDED_LEVEL_ORDER_INVALID", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf)
        }
        let rewardPips = direction == .long ? (target - quote.ask) / c.pipSize : (quote.bid - target) / c.pipSize
        let denominator = spread + c.additionalRoundTripCostPips
        guard denominator.isFinite, denominator > 0 else { return terminal(.rejected, "COST_DENOMINATOR_INVALID", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        let ratio = rewardPips / denominator
        guard ratio.isFinite, ratio >= c.minimumRewardToCost else { return terminal(.rejected, "REWARD_TO_COST_BELOW_MINIMUM", b, bEnd, confirm, lower, swing, direction, htfIDs, htfCutoff, c, inputDigest, asOf) }
        let eventID = candidate.id
        let touchContext = selectedContext(contexts, at: end(lower[touch], c.lowerTimeframeSeconds))
        let confirmationContext = selectedContext(contexts, at: cbEnd)
        let quoteContext = selectedContext(contexts, at: quote.sourceTime)
        var usedIDs = lower[0...confirm].map(\.id)
        usedIDs.append(contentsOf: higher.filter { end($0, c.higherTimeframeSeconds) <= htfCutoff }.map(\.id))
        usedIDs.append(contentsOf: htfIDs)
        usedIDs.append(contentsOf: validQuotes.filter { $0.sourceTime <= quote.sourceTime }.map(\.id))
        usedIDs.append(contentsOf: [breakContext, touchContext, confirmationContext, quoteContext].compactMap { $0 }.flatMap(\.sourceIDs))
        let usedContexts = eventContexts(lower: Array(lower[0...confirm]),
            higher: higher.filter { end($0, c.higherTimeframeSeconds) <= htfCutoff }, c: c,
            baseContexts: [breakContext, touchContext, confirmationContext, quoteContext].compactMap { $0 },
            allContexts: contexts)
        inputDigest = eventInputDigest(configuration: c, window: window, cursor: cursor,
            candidate: candidate, lower: lower, higher: higher, quotes: usedQuoteEvidence,
            contexts: usedContexts, provenance: provenance, asOf: asOf,
            lowerThrough: confirm, higherTimeframeSeconds: c.higherTimeframeSeconds)
        return GBPJPYTrendPullbackDecision(state: .signal, direction: direction, reasons: ["RESEARCH_CANDIDATE"], configDigest: configDigest,
            inputDigest: inputDigest, eventID: eventID, start: bEnd, end: asOf, htfCutoff: htfCutoff,
            cursorDigest: cursor.digest, firstLowerBarID: window.firstLowerBarID, lastLowerBarID: window.lastLowerBarID,
            snapshotDigest: provenance.snapshotDigest, buildID: provenance.buildID,
            codeDigest: provenance.codeDigest, quoteConfirmationEnd: cbEnd,
            breakBarID: b.id, swingID: swing.bar.id,
            sourceIDs: usedIDs, entry: entry, stop: rawStop, target: target,
            spread: spread, ratio: ratio, selectedQuote: quote,
            quoteSourceAge: asOf.timeIntervalSince(quote.sourceTime),
            quoteReceiptAge: asOf.timeIntervalSince(quote.receivedAt),
            rawStop: auditRawStop, rawTarget: auditRawTarget,
            additionalRoundTripCost: c.additionalRoundTripCostPips, disposition: .terminal, version: c.version)
    }

    private struct Pivot { let index: Int; let high: Bool; let price: Double; let bar: GBPJPYTrendPullbackBar; let confirmedAt: Date }
    private struct BreakCandidate {
        let index: Int; let swing: Pivot; let direction: GBPJPYTrendPullbackDirection
        let breakBarID: String
        let atr: Double; let htfPivotIDs: [String]; let htfCutoff: Date
    }
    private struct InputIdentity: Encodable {
        let configDigest: String; let lowerBars: [GBPJPYTrendPullbackBar]; let higherBars: [GBPJPYTrendPullbackBar]
        let quotes: [GBPJPYTrendPullbackQuote]; let contexts: [GBPJPYTrendPullbackContext]
        let provenance: GBPJPYTrendPullbackProvenance?; let asOf: Date
    }
    private struct DiscoveryInputIdentity: Encodable {
        let configurationDigest: String
        let lowerBars: [GBPJPYTrendPullbackBar]
        let higherBars: [GBPJPYTrendPullbackBar]
        let contexts: [GBPJPYTrendPullbackContext]
        let provenance: GBPJPYTrendPullbackDiscoveryProvenance
        let asOf: Date
        let window: GBPJPYTrendPullbackWindow
        let cursorDigest: String
    }
    private struct ActiveInputIdentity: Encodable {
        let discoveryDigest: String; let candidate: GBPJPYTrendPullbackBreakDescriptor
        let lowerBars: [GBPJPYTrendPullbackBar]; let higherBars: [GBPJPYTrendPullbackBar]
        let quotes: [GBPJPYTrendPullbackQuote]; let contexts: [GBPJPYTrendPullbackContext]
        let provenance: GBPJPYTrendPullbackProvenance?; let asOf: Date; let evidenceIDs: [String]
    }
    private struct InputProvenance: Encodable {
        let environment: String; let buildID: String; let codeDigest: String
        let lineageIsProviderNative: Bool; let quoteWindowComplete: Bool; let quoteSamplingPolicy: String
        init?(_ value: GBPJPYTrendPullbackProvenance?) {
            guard let value else { return nil }
            environment = value.environment; buildID = value.buildID; codeDigest = value.codeDigest
            lineageIsProviderNative = value.lineageIsProviderNative
            quoteWindowComplete = value.quoteWindowComplete; quoteSamplingPolicy = value.quoteSamplingPolicy
        }
    }
    private struct EventInputIdentity: Encodable {
        let configDigest: String; let instrument: String; let provider: String
        let lowerTimeframeSeconds: Int; let higherTimeframeSeconds: Int
        let environment: String
        let window: GBPJPYTrendPullbackWindow; let cursorDigest: String
        let eventID: String; let swingID: String; let breakBarID: String
        let direction: GBPJPYTrendPullbackDirection
        let lowerBars: [GBPJPYTrendPullbackBar]; let higherBars: [GBPJPYTrendPullbackBar]
        let quotes: [GBPJPYTrendPullbackQuote]; let contexts: [GBPJPYTrendPullbackContext]
        let provenance: InputProvenance?; let asOf: Date
    }
    private static func evaluationIdentityMatches(discovery: GBPJPYTrendPullbackDiscoveryEvidence,
                                                  provenance: GBPJPYTrendPullbackProvenance?,
                                                  config: GBPJPYTrendPullbackConfiguration) -> Bool {
        guard let provenance else { return false }
        return discovery.provenance.provider == config.provider
            && discovery.provenance.environment == provenance.environment
            && discovery.provenance.buildID == provenance.buildID
            && discovery.provenance.codeDigest == provenance.codeDigest
            && discovery.provenance.lineageIsProviderNative && provenance.lineageIsProviderNative
            && provenance.environment == discovery.batch.environment
            && !provenance.snapshotDigest.isEmpty && !provenance.buildID.isEmpty && !provenance.codeDigest.isEmpty
    }
    private static func continuationDecision(_ state: GBPJPYTrendPullbackState,
            _ disposition: GBPJPYTrendPullbackDisposition, _ reason: String,
            candidate: GBPJPYTrendPullbackBreakDescriptor, discovery: GBPJPYTrendPullbackDiscoveryEvidence,
            provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
            config: GBPJPYTrendPullbackConfiguration, extraSourceIDs: [String],
            inputDigestOverride: String) -> GBPJPYTrendPullbackDecision {
        return .init(state: state, direction: candidate.direction, reasons: [reason],
            configDigest: config.digest(), inputDigest: inputDigestOverride, eventID: candidate.id,
            start: candidate.breakBarEnd, end: asOf,
            htfCutoff: candidate.higherTimeframeContextCutoff, cursorDigest: candidate.cursorDigest,
            firstLowerBarID: candidate.firstLowerBarID, lastLowerBarID: candidate.lastLowerBarID,
            snapshotDigest: provenance?.snapshotDigest ?? discovery.provenance.snapshotDigest,
            buildID: discovery.provenance.buildID, codeDigest: discovery.provenance.codeDigest,
            breakBarID: candidate.breakBarID, swingID: candidate.frozenSwingID,
            sourceIDs: candidate.sourceIDs + discovery.provenance.sourceIDs + extraSourceIDs,
            disposition: disposition, version: config.version)
    }
    private static func reclassifyAsActiveHold(_ value: GBPJPYTrendPullbackDecision, reason: String,
            candidate: GBPJPYTrendPullbackBreakDescriptor, discovery: GBPJPYTrendPullbackDiscoveryEvidence,
            provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
            config: GBPJPYTrendPullbackConfiguration,
            disposition: GBPJPYTrendPullbackDisposition = .active,
            state: GBPJPYTrendPullbackState = .waiting) -> GBPJPYTrendPullbackDecision {
        .init(state: state, direction: value.direction, reasons: [reason],
            configDigest: value.configurationDigest, inputDigest: value.inputDigest, eventID: candidate.id,
            start: candidate.breakBarEnd, end: asOf, htfCutoff: candidate.higherTimeframeContextCutoff,
            cursorDigest: candidate.cursorDigest, firstLowerBarID: candidate.firstLowerBarID,
            lastLowerBarID: candidate.lastLowerBarID,
            snapshotDigest: provenance?.snapshotDigest ?? discovery.provenance.snapshotDigest,
            buildID: discovery.provenance.buildID, codeDigest: discovery.provenance.codeDigest,
            quoteConfirmationEnd: value.quoteConfirmationEnd,
            breakBarID: candidate.breakBarID, swingID: candidate.frozenSwingID,
            sourceIDs: value.sourceIDs + candidate.sourceIDs + discovery.provenance.sourceIDs,
            entry: value.entryPrice, stop: value.stopPrice, target: value.targetPrice,
            spread: value.spreadPips, ratio: value.rewardToCost,
            rawStop: value.rawStopPrice, rawTarget: value.rawTargetPrice,
            additionalRoundTripCost: value.additionalRoundTripCostPips,
            selectedQuoteIDOverride: value.selectedQuoteID, quoteBidOverride: value.quoteBid,
            quoteAskOverride: value.quoteAsk, quoteSourceTimeOverride: value.quoteSourceTime,
            quoteReceivedAtOverride: value.quoteReceivedAt,
            quoteSourceAgeOverride: value.quoteSourceAgeSeconds,
            quoteReceiptAgeOverride: value.quoteReceiptAgeSeconds,
            disposition: disposition, version: config.version)
    }
    private static func decision(_ state: GBPJPYTrendPullbackState, _ direction: GBPJPYTrendPullbackDirection,
                                 _ reasons: [String], c: GBPJPYTrendPullbackConfiguration?, input: String,
                                 provenance: GBPJPYTrendPullbackProvenance? = nil) -> GBPJPYTrendPullbackDecision {
        .init(state: state, direction: direction, reasons: reasons, configDigest: c?.digest() ?? "",
              inputDigest: input, snapshotDigest: provenance?.snapshotDigest,
              buildID: provenance?.buildID, codeDigest: provenance?.codeDigest,
              version: c?.version ?? strategyID)
    }
    private static func windowBounds(_ window: GBPJPYTrendPullbackWindow,
                                     in bars: [GBPJPYTrendPullbackBar]) -> ClosedRange<Int>? {
        guard !window.firstLowerBarID.isEmpty, !window.lastLowerBarID.isEmpty,
              let first = bars.firstIndex(where: { $0.id == window.firstLowerBarID }),
              let last = bars.firstIndex(where: { $0.id == window.lastLowerBarID }), first <= last,
              bars.filter({ $0.id == window.firstLowerBarID }).count == 1,
              bars.filter({ $0.id == window.lastLowerBarID }).count == 1 else { return nil }
        return first...last
    }
    private static func eventID(_ event: BreakCandidate, c: GBPJPYTrendPullbackConfiguration) -> String {
        GBPJPYTrendPullbackConfiguration.sha256(Data("\(strategyID)|\(c.version)|\(c.digest())|\(c.instrument)|\(c.lowerTimeframeSeconds)|\(event.swing.bar.id)|\(event.breakBarID)|\(event.direction.rawValue)".utf8))
    }
    private static func eventDescriptor(_ event: BreakCandidate, lower: [GBPJPYTrendPullbackBar],
                                        higher: [GBPJPYTrendPullbackBar], contexts: [GBPJPYTrendPullbackContext],
                                        c: GBPJPYTrendPullbackConfiguration, window: GBPJPYTrendPullbackWindow,
                                        cursor: GBPJPYTrendPullbackEventCursor) -> GBPJPYTrendPullbackBreakDescriptor {
        let context = selectedContext(contexts, at: event.htfCutoff)
        let lowerUsed = Array(lower[0...event.index])
        let higherUsed = higher.filter { end($0, c.higherTimeframeSeconds) <= event.htfCutoff }
        let usedContexts = eventContexts(lower: lowerUsed, higher: higherUsed, c: c,
                                         baseContexts: context.map { [$0] } ?? [], allContexts: contexts)
        var ids = lowerUsed.map(\.id)
        ids.append(contentsOf: higherUsed.map(\.id)); ids.append(contentsOf: event.htfPivotIDs)
        ids.append(contentsOf: usedContexts.flatMap(\.sourceIDs))
        return GBPJPYTrendPullbackBreakDescriptor(id: eventID(event, c: c), strategyID: strategyID,
            strategyVersion: c.version, profileDigest: c.digest(), cursorDigest: cursor.digest,
            windowDigest: windowDigest(window),
            firstLowerBarID: window.firstLowerBarID, lastLowerBarID: window.lastLowerBarID,
            frozenSwingID: event.swing.bar.id, direction: event.direction, breakBarID: event.breakBarID,
            breakBarEnd: end(lower[event.index], c.lowerTimeframeSeconds),
            higherTimeframeContextCutoff: event.htfCutoff, sourceIDs: Array(Set(ids)).sorted())
    }
    private static func windowDigest(_ window: GBPJPYTrendPullbackWindow) -> String {
        GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(window))
    }
    private static func descriptorMatches(_ discovered: GBPJPYTrendPullbackBreakDescriptor,
                                          _ supplied: GBPJPYTrendPullbackBreakDescriptor) -> Bool {
        discovered.id == supplied.id && discovered.breakBarID == supplied.breakBarID
            && discovered.frozenSwingID == supplied.frozenSwingID && discovered.direction == supplied.direction
            && discovered.firstLowerBarID == supplied.firstLowerBarID
            && discovered.lastLowerBarID == supplied.lastLowerBarID
    }
    private static func eventInputDigest(configuration: GBPJPYTrendPullbackConfiguration, window: GBPJPYTrendPullbackWindow,
                                         cursor: GBPJPYTrendPullbackEventCursor,
                                         candidate: GBPJPYTrendPullbackBreakDescriptor,
                                         lower: [GBPJPYTrendPullbackBar], higher: [GBPJPYTrendPullbackBar],
                                         quotes: [GBPJPYTrendPullbackQuote], contexts: [GBPJPYTrendPullbackContext],
                                         provenance: GBPJPYTrendPullbackProvenance?, asOf: Date,
                                         lowerThrough: Int, higherTimeframeSeconds: Int) -> String {
        let usedLower = lower.isEmpty ? [] : Array(lower[0...min(lowerThrough, lower.count - 1)])
        let usedHigher = higher.filter { $0.startTime.addingTimeInterval(TimeInterval(higherTimeframeSeconds)) <= candidate.higherTimeframeContextCutoff }
        let usedContexts = contexts.sorted {
            $0.measuredAt == $1.measuredAt ? $0.digest < $1.digest : $0.measuredAt < $1.measuredAt
        }
        let identity = EventInputIdentity(configDigest: configuration.digest(), instrument: configuration.instrument,
            provider: configuration.provider, lowerTimeframeSeconds: configuration.lowerTimeframeSeconds,
            higherTimeframeSeconds: configuration.higherTimeframeSeconds,
            environment: provenance?.environment ?? "", window: window, cursorDigest: cursor.digest,
            eventID: candidate.id, swingID: candidate.frozenSwingID, breakBarID: candidate.breakBarID,
            direction: candidate.direction, lowerBars: usedLower, higherBars: usedHigher,
            quotes: quotes, contexts: usedContexts, provenance: InputProvenance(provenance), asOf: asOf)
        return GBPJPYTrendPullbackConfiguration.sha256(GBPJPYTrendPullbackConfiguration.canonical(identity))
    }
    private static func eventFailure(_ state: GBPJPYTrendPullbackState, _ reason: String,
                                     c: GBPJPYTrendPullbackConfiguration,
                                     candidate: GBPJPYTrendPullbackBreakDescriptor,
                                     window: GBPJPYTrendPullbackWindow,
                                     cursor: GBPJPYTrendPullbackEventCursor,
                                     lower: [GBPJPYTrendPullbackBar], higher: [GBPJPYTrendPullbackBar],
                                     provenance: GBPJPYTrendPullbackProvenance,
                                     asOf: Date) -> GBPJPYTrendPullbackDecision {
        let breakIndex = lower.firstIndex(where: { $0.id == candidate.breakBarID }) ?? 0
        let input = eventInputDigest(configuration: c, window: window, cursor: cursor,
            candidate: candidate, lower: lower, higher: higher, quotes: [], contexts: [],
            provenance: provenance, asOf: asOf, lowerThrough: breakIndex,
            higherTimeframeSeconds: c.higherTimeframeSeconds)
        return .init(state: state, direction: candidate.direction, reasons: [reason], configDigest: c.digest(),
              inputDigest: input, eventID: candidate.id, start: candidate.breakBarEnd, end: asOf,
              htfCutoff: candidate.higherTimeframeContextCutoff, cursorDigest: cursor.digest,
              firstLowerBarID: window.firstLowerBarID, lastLowerBarID: window.lastLowerBarID,
              snapshotDigest: provenance.snapshotDigest, buildID: provenance.buildID,
              codeDigest: provenance.codeDigest,
              breakBarID: candidate.breakBarID, swingID: candidate.frozenSwingID,
              sourceIDs: candidate.sourceIDs, version: c.version)
    }
    private static func end(_ bar: GBPJPYTrendPullbackBar, _ seconds: Int) -> Date { bar.startTime.addingTimeInterval(TimeInterval(seconds)) }
    private static func aligned(_ value: Double, tick: Double) -> Bool { abs(value / tick - (value / tick).rounded()) < 1e-8 }
    private static func validBars(_ bars: [GBPJPYTrendPullbackBar], timeframe: Int, c: GBPJPYTrendPullbackConfiguration, asOf: Date) -> Bool {
        let complete = bars.filter { $0.complete }
        guard complete.count == bars.count, complete.allSatisfy({ bar in
            bar.isValid() && bar.instrument == c.instrument && bar.provider == c.provider
                && end(bar, timeframe) <= asOf
                && aligned(bar.open, tick: c.priceTickSize) && aligned(bar.high, tick: c.priceTickSize)
                && aligned(bar.low, tick: c.priceTickSize) && aligned(bar.close, tick: c.priceTickSize)
        }) else { return false }
        guard zip(complete, complete.dropFirst()).allSatisfy({ pair in pair.1.startTime > pair.0.startTime }) else { return false }
        guard Set(complete.map(\.id)).count == complete.count, Set(complete.map(\.startTime)).count == complete.count else { return false }
        return complete.allSatisfy { Int($0.startTime.timeIntervalSince1970.rounded()) % timeframe == c.gridOriginUTCSeconds % timeframe }
    }
    private static func continuousBySession(_ bars: [GBPJPYTrendPullbackBar], timeframe: Int,
                                           contexts: [GBPJPYTrendPullbackContext],
                                           c: GBPJPYTrendPullbackConfiguration) -> Bool {
        zip(bars, bars.dropFirst()).allSatisfy { pair in
            let priorEnd = end(pair.0, timeframe)
            if pair.1.startTime == priorEnd { return true }
            guard pair.1.startTime > priorEnd,
                  let before = selectedContext(contexts, at: priorEnd),
                  let after = selectedContext(contexts, at: pair.1.startTime),
                  before.sessionID != after.sessionID,
                  before.sessionCalendarDigest == c.sessionCalendarDigest,
                  after.sessionCalendarDigest == c.sessionCalendarDigest,
                  before.sessionClose <= pair.1.startTime,
                  after.sessionOpen <= pair.1.startTime else { return false }
            return true
        }
    }
    private static func pivots(_ bars: [GBPJPYTrendPullbackBar], left: Int, right: Int, tf: Int) -> [Pivot] {
        guard bars.count >= left + right + 1 else { return [] }
        var result: [Pivot] = []
        for i in left..<(bars.count - right) {
            let around = Array(bars[(i-left)...(i+right)])
            let highs = around.filter { $0.high == bars[i].high }.count
            let lows = around.filter { $0.low == bars[i].low }.count
            let isHigh = highs == 1 && around.allSatisfy { $0.id == bars[i].id || bars[i].high > $0.high }
            let isLow = lows == 1 && around.allSatisfy { $0.id == bars[i].id || bars[i].low < $0.low }
            if isHigh != isLow { result.append(Pivot(index: i, high: isHigh, price: isHigh ? bars[i].high : bars[i].low,
                                                       bar: bars[i], confirmedAt: end(bars[i+right], tf))) }
        }
        return result
    }
    private static func htfDirection(_ bars: [GBPJPYTrendPullbackBar], cutoff: Date, c: GBPJPYTrendPullbackConfiguration) -> (GBPJPYTrendPullbackDirection, [String])? {
        let confirmed = pivots(bars, left: c.higherLeftBars, right: c.higherRightBars, tf: c.higherTimeframeSeconds).filter { $0.confirmedAt <= cutoff }
        guard !confirmed.isEmpty, Set(confirmed.map(\.confirmedAt)).count == confirmed.count,
              let last = confirmed.last, cutoff.timeIntervalSince(last.confirmedAt) <= c.maximumContextAgeSeconds else { return nil }
        let p = Array(confirmed.suffix(4)); guard p.count == 4 else { return nil }
        let bull = !p[0].high && p[1].high && !p[2].high && p[3].high && p[2].price > p[0].price && p[3].price > p[1].price
        let bear = p[0].high && !p[1].high && p[2].high && !p[3].high && p[2].price < p[0].price && p[3].price < p[1].price
        guard bull || bear else { return nil }
        return (bull ? .long : .short, p.map { $0.bar.id })
    }
    private static func atr(_ bars: [GBPJPYTrendPullbackBar], at breakIndex: Int, lookback: Int) -> Double? {
        // Need the completed close immediately preceding the first TR bar.
        guard breakIndex > lookback else { return nil }
        let start = breakIndex - lookback
        let trs = (start..<breakIndex).map { i -> Double in
            let priorClose = bars[i-1].close
            return max(bars[i].high - bars[i].low, abs(bars[i].high - priorClose), abs(bars[i].low - priorClose))
        }
        let value = trs.reduce(0, +) / Double(lookback)
        return value.isFinite && value > 0 ? value : nil
    }
    private static func findBreaks(lower: [GBPJPYTrendPullbackBar], higher: [GBPJPYTrendPullbackBar], c: GBPJPYTrendPullbackConfiguration,
                                   contexts: [GBPJPYTrendPullbackContext], asOf: Date,
                                   window: ClosedRange<Int>, cursor: GBPJPYTrendPullbackEventCursor) -> [BreakCandidate] {
        let lows = pivots(lower, left: c.lowerLeftBars, right: c.lowerRightBars, tf: c.lowerTimeframeSeconds)
        let consumed = Set(cursor.consumedKeys)
        var emitted = Set<GBPJPYTrendPullbackConsumedKey>()
        var events: [BreakCandidate] = []
        for i in window {
            let closeTime = end(lower[i], c.lowerTimeframeSeconds)
            guard closeTime <= asOf, let vol = atr(lower, at: i, lookback: c.atrLookbackBars),
                  let context = htfDirection(higher, cutoff: closeTime, c: c), contextAllowed(contexts, at: closeTime, c: c) else { continue }
            let direction = context.0
            let keyPivots = lows.filter { $0.high == (direction == .long) && $0.confirmedAt <= closeTime && $0.index < i }
            guard let swing = keyPivots.max(by: { $0.confirmedAt == $1.confirmedAt
                ? $0.bar.id > $1.bar.id : $0.confirmedAt < $1.confirmedAt }) else { continue }
            let key = GBPJPYTrendPullbackConsumedKey(frozenSwingID: swing.bar.id, direction: direction)
            guard !consumed.contains(key), !emitted.contains(key) else { continue }
            let qualifies = direction == .long
                ? lower[i].close > swing.price + c.minimumBreakATR * vol
                : lower[i].close < swing.price - c.minimumBreakATR * vol
            guard qualifies else { continue }
            emitted.insert(key)
            events.append(BreakCandidate(index: i, swing: swing, direction: direction, breakBarID: lower[i].id,
                                         atr: vol, htfPivotIDs: context.1, htfCutoff: closeTime))
        }
        return events.sorted { $0.index == $1.index
            ? ($0.swing.bar.id == $1.swing.bar.id ? $0.direction.rawValue < $1.direction.rawValue : $0.swing.bar.id < $1.swing.bar.id)
            : $0.index < $1.index }
    }
    private static func contextAllowed(_ contexts: [GBPJPYTrendPullbackContext], at time: Date, c: GBPJPYTrendPullbackConfiguration) -> Bool {
        guard let x = selectedContext(contexts, at: time) else { return false }
        return !x.digest.isEmpty && !x.sessionCalendarDigest.isEmpty && !x.sessionID.isEmpty
            && x.sessionCalendarDigest == c.sessionCalendarDigest && x.timeZoneID == c.timeZoneID
            && x.regimeVersion == c.regimeVersion && c.allowedRegimes.contains(x.regime)
            && c.allowedSessions.contains(x.sessionID) && time >= x.sessionOpen && time < x.sessionClose
            && x.measuredAt <= time && time.timeIntervalSince(x.measuredAt) <= c.maximumContextAgeSeconds
            && !x.sourceIDs.isEmpty
    }
    private static func selectedContext(_ contexts: [GBPJPYTrendPullbackContext], at time: Date) -> GBPJPYTrendPullbackContext? {
        let eligible = contexts.filter { $0.measuredAt <= time }
        guard let latest = eligible.map(\.measuredAt).max() else { return nil }
        let matches = eligible.filter { $0.measuredAt == latest }
        return matches.count == 1 ? matches[0] : nil
    }
    private static func eventContexts(lower: [GBPJPYTrendPullbackBar], higher: [GBPJPYTrendPullbackBar],
                                      c: GBPJPYTrendPullbackConfiguration,
                                      baseContexts: [GBPJPYTrendPullbackContext],
                                      allContexts: [GBPJPYTrendPullbackContext]) -> [GBPJPYTrendPullbackContext] {
        var used = baseContexts
        func append(_ value: GBPJPYTrendPullbackContext?) {
            if let value, !used.contains(value) { used.append(value) }
        }
        for (bars, timeframe) in [(lower, c.lowerTimeframeSeconds), (higher, c.higherTimeframeSeconds)] {
            for pair in zip(bars, bars.dropFirst()) where end(pair.0, timeframe) != pair.1.startTime {
                append(selectedContext(allContexts, at: end(pair.0, timeframe)))
                append(selectedContext(allContexts, at: pair.1.startTime))
            }
        }
        return used.sorted {
            $0.measuredAt == $1.measuredAt ? $0.digest < $1.digest : $0.measuredAt < $1.measuredAt
        }
    }
    private static func sameSession(_ contexts: [GBPJPYTrendPullbackContext], at time: Date,
                                    reference: GBPJPYTrendPullbackContext,
                                    c: GBPJPYTrendPullbackConfiguration) -> Bool {
        guard contextAllowed(contexts, at: time, c: c), let value = selectedContext(contexts, at: time) else { return false }
        return value.sessionID == reference.sessionID
            && value.sessionCalendarDigest == reference.sessionCalendarDigest
            && value.timeZoneID == reference.timeZoneID
    }
}
