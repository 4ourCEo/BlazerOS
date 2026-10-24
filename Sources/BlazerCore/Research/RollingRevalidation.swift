import CryptoKit
import Foundation

/// Candidate revalidation checkpoints are observational research only.
public enum RollingRevalidationWindow: Int, Codable, Sendable, CaseIterable {
    case seconds8 = 8
    case seconds12 = 12
    case seconds16 = 16
    case seconds20 = 20
}

public struct RollingRevalidationBaseline: Codable, Sendable, Equatable {
    public let parentFullFingerprint: String
    public let originalScanAt: Date
    public let marketAsset: String
    public let side: String
    public let entryReference: Double
    public let maximumAbsoluteDisplacement: Double
    public let expirySeconds: Int
    public let engineVersion: String
    public let policyVersion: String
    public let sourceID: String
    public let venueID: String
    public let instrumentID: String

    public init(parentFullFingerprint: String, originalScanAt: Date, marketAsset: String, side: String,
                entryReference: Double, maximumAbsoluteDisplacement: Double, expirySeconds: Int,
                engineVersion: String, policyVersion: String, sourceID: String,
                venueID: String, instrumentID: String) {
        self.parentFullFingerprint = parentFullFingerprint
        self.originalScanAt = originalScanAt
        self.marketAsset = marketAsset
        self.side = side
        self.entryReference = entryReference
        self.maximumAbsoluteDisplacement = maximumAbsoluteDisplacement
        self.expirySeconds = expirySeconds
        self.engineVersion = engineVersion
        self.policyVersion = policyVersion
        self.sourceID = sourceID
        self.venueID = venueID
        self.instrumentID = instrumentID
    }
}

public struct RollingRevalidationLocks: Codable, Sendable, Equatable {
    public let entry: Bool
    public let settlement: Bool
    public let activePosition: Bool
    public let awaitingOutcome: Bool

    public init(entry: Bool, settlement: Bool, activePosition: Bool, awaitingOutcome: Bool) {
        self.entry = entry
        self.settlement = settlement
        self.activePosition = activePosition
        self.awaitingOutcome = awaitingOutcome
    }

    public var allClear: Bool { !entry && !settlement && !activePosition && !awaitingOutcome }
}

public struct RollingRevalidationInput: Codable, Sendable, Equatable {
    public let marketAsset: String
    public let quotePrice: Double
    public let quoteTimestamp: Date
    public let receivedAt: Date
    public let evaluatedAt: Date
    public let side: String
    public let qualified: Bool
    public let updatedInputDigest: String
    public let sourceID: String
    public let venueID: String
    public let instrumentID: String
    public let expirySeconds: Int
    public let locks: RollingRevalidationLocks
    public let marketDataValid: Bool

    public init(marketAsset: String, quotePrice: Double, quoteTimestamp: Date, receivedAt: Date, evaluatedAt: Date,
                side: String, qualified: Bool, updatedInputDigest: String, sourceID: String,
                venueID: String, instrumentID: String, expirySeconds: Int, locks: RollingRevalidationLocks,
                marketDataValid: Bool = true) {
        self.marketAsset = marketAsset
        self.quotePrice = quotePrice
        self.quoteTimestamp = quoteTimestamp
        self.receivedAt = receivedAt
        self.evaluatedAt = evaluatedAt
        self.side = side
        self.qualified = qualified
        self.updatedInputDigest = updatedInputDigest
        self.sourceID = sourceID
        self.venueID = venueID
        self.instrumentID = instrumentID
        self.expirySeconds = expirySeconds
        self.locks = locks
        self.marketDataValid = marketDataValid
    }
}

public enum RollingRevalidationRejection: String, Codable, Sendable, CaseIterable {
    case invalidBaseline, invalidWindow, originalScanTooOld, originalScanInFuture
    case invalidQuote, invalidTimeline, quoteTimestampInFuture, staleQuote, sideMismatch, notQualified
    case priceOutsideEnvelope, sourceMismatch, venueMismatch, instrumentMismatch
    case assetMismatch, engineMismatch, policyMismatch, expiryMismatch, invalidMarketData
    case entryLocked, settlementLocked, activePositionLocked, awaitingOutcomeLocked
}

public struct RollingRevalidationResult: Codable, Sendable, Equatable {
    public let identity: String
    public let parentFullFingerprint: String
    public let windowSeconds: Int
    public let evaluatedAt: Date
    public let quoteTimestamp: Date
    public let sourceID: String
    public let venueID: String
    public let instrumentID: String
    public let engineVersion: String
    public let policyVersion: String
    public let acceptedForResearch: Bool
    public let rejectionReasons: [RollingRevalidationRejection]
    public let researchOnly: Bool
    public let mayAuthorizeEntry: Bool
    public let status: String
}

public enum RollingRevalidation {
    static func evaluate(baseline: RollingRevalidationBaseline,
                         window: RollingRevalidationWindow,
                         input: RollingRevalidationInput,
                         engineVersion: String,
                         policyVersion: String,
                         maximumQuoteAge: TimeInterval = 2) -> RollingRevalidationResult {
        var reasons: [RollingRevalidationRejection] = []
        let age = input.evaluatedAt.timeIntervalSince(baseline.originalScanAt)
        if baseline.parentFullFingerprint.isEmpty || !baseline.entryReference.isFinite || baseline.entryReference <= 0 ||
            !baseline.maximumAbsoluteDisplacement.isFinite || baseline.maximumAbsoluteDisplacement < 0 ||
            !["HIGH", "LOW"].contains(baseline.side) || ![60, 180, 300].contains(baseline.expirySeconds) ||
            baseline.marketAsset.isEmpty || !baseline.originalScanAt.timeIntervalSince1970.isFinite ||
            baseline.engineVersion.isEmpty || baseline.policyVersion.isEmpty || baseline.sourceID.isEmpty ||
            baseline.venueID.isEmpty || baseline.instrumentID.isEmpty {
            reasons.append(.invalidBaseline)
        }
        if !maximumQuoteAge.isFinite || maximumQuoteAge < 0 { reasons.append(.invalidWindow) }
        if age < 0 { reasons.append(.originalScanInFuture) }
        else if age > Double(window.rawValue) { reasons.append(.originalScanTooOld) }
        if !input.quotePrice.isFinite || input.quotePrice <= 0 || !input.quoteTimestamp.timeIntervalSince1970.isFinite ||
            !input.receivedAt.timeIntervalSince1970.isFinite || !input.evaluatedAt.timeIntervalSince1970.isFinite {
            reasons.append(.invalidQuote)
        } else {
            let quoteAge = input.evaluatedAt.timeIntervalSince(input.quoteTimestamp)
            if quoteAge < 0 { reasons.append(.quoteTimestampInFuture) }
            else if input.receivedAt > input.evaluatedAt || input.quoteTimestamp > input.receivedAt {
                reasons.append(.invalidTimeline)
            } else if maximumQuoteAge.isFinite && maximumQuoteAge >= 0 && quoteAge > maximumQuoteAge {
                reasons.append(.staleQuote)
            }
        }
        if input.side != baseline.side || !["HIGH", "LOW"].contains(input.side) { reasons.append(.sideMismatch) }
        if !input.qualified { reasons.append(.notQualified) }
        if input.quotePrice.isFinite && baseline.entryReference.isFinite && baseline.maximumAbsoluteDisplacement.isFinite &&
            abs(input.quotePrice - baseline.entryReference) > baseline.maximumAbsoluteDisplacement {
            reasons.append(.priceOutsideEnvelope)
        }
        if input.sourceID != baseline.sourceID { reasons.append(.sourceMismatch) }
        if input.venueID != baseline.venueID { reasons.append(.venueMismatch) }
        if input.instrumentID != baseline.instrumentID { reasons.append(.instrumentMismatch) }
        if input.marketAsset != baseline.marketAsset { reasons.append(.assetMismatch) }
        if engineVersion != baseline.engineVersion { reasons.append(.engineMismatch) }
        if policyVersion != baseline.policyVersion { reasons.append(.policyMismatch) }
        if input.updatedInputDigest.isEmpty || input.marketAsset.isEmpty { reasons.append(.invalidQuote) }
        if !input.marketDataValid { reasons.append(.invalidMarketData) }
        if input.expirySeconds != baseline.expirySeconds { reasons.append(.expiryMismatch) }
        if input.locks.entry { reasons.append(.entryLocked) }
        if input.locks.settlement { reasons.append(.settlementLocked) }
        if input.locks.activePosition { reasons.append(.activePositionLocked) }
        if input.locks.awaitingOutcome { reasons.append(.awaitingOutcomeLocked) }
        let uniqueReasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        let accepted = uniqueReasons.isEmpty
        let identityPayload = IdentityPayload(
            baseline: baseline,
            window: window.rawValue,
            input: input,
            maximumQuoteAge: maximumQuoteAge,
            engine: engineVersion,
            policy: policyVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        let bytes = (try? encoder.encode(identityPayload)) ?? Data()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return RollingRevalidationResult(identity: digest, parentFullFingerprint: baseline.parentFullFingerprint,
            windowSeconds: window.rawValue, evaluatedAt: input.evaluatedAt, quoteTimestamp: input.quoteTimestamp,
            sourceID: input.sourceID, venueID: input.venueID, instrumentID: input.instrumentID,
            engineVersion: engineVersion,
            policyVersion: policyVersion,
            acceptedForResearch: accepted, rejectionReasons: uniqueReasons, researchOnly: true,
            mayAuthorizeEntry: false, status: accepted ? "RESEARCH CANDIDATE" : "REJECTED")
    }

    private struct IdentityPayload: Codable {
        let baseline: RollingRevalidationBaseline
        let window: Int
        let input: RollingRevalidationInput
        let maximumQuoteAge: TimeInterval
        let engine: String
        let policy: String
    }

    /// Re-evaluates a newly acquired input with the authoritative deterministic engine.
    /// Its evaluation time is new; the original scan time and fingerprint remain in `baseline`.
    public static func revalidate(
        baseline: RollingRevalidationBaseline,
        window: RollingRevalidationWindow,
        marketInput: StrategyEngine.MarketInput,
        sourceID: String,
        venueID: String,
        instrumentID: String,
        receivedAt: Date,
        evaluatedAt: Date,
        locks: RollingRevalidationLocks,
        maximumQuoteAge: TimeInterval = 2
    ) async throws -> RollingRevalidationResult {
        var updated = marketInput
        updated.evaluatedAtMs = evaluatedAt.timeIntervalSince1970 * 1_000
        let evaluationMs = evaluatedAt.timeIntervalSince1970 * 1_000
        let marketDataValid = evaluationMs.isFinite
            && updated.candles1m.allSatisfy { $0.time.isFinite && $0.time <= evaluationMs - 60_000 }
            && updated.candles5m.allSatisfy { $0.time.isFinite && $0.time <= evaluationMs - 300_000 }
        if !marketDataValid {
            let invalidInput = RollingRevalidationInput(
                marketAsset: updated.asset,
                quotePrice: updated.lastPrice,
                quoteTimestamp: Date(timeIntervalSince1970: (updated.quoteAsOfMs ?? .nan) / 1_000),
                receivedAt: receivedAt,
                evaluatedAt: evaluatedAt,
                side: baseline.side,
                qualified: false,
                updatedInputDigest: try ResearchEvent.digest(of: updated),
                sourceID: updated.source == sourceID ? sourceID : "",
                venueID: venueID,
                instrumentID: instrumentID,
                expirySeconds: updated.expirySeconds,
                locks: locks,
                marketDataValid: false
            )
            return evaluate(
                baseline: baseline,
                window: window,
                input: invalidInput,
                engineVersion: EngineIdentity.loadedSHA1() ?? "unverified",
                policyVersion: updated.policy?.rawValue ?? "baseline",
                maximumQuoteAge: maximumQuoteAge
            )
        }
        let evaluated = try await StrategyEngine.evaluate(input: updated)
        let signal = evaluated.signal
        let quote = LiveQuote(
            asset: updated.asset,
            bid: updated.bid,
            ask: updated.ask,
            mid: updated.lastPrice,
            asOfMs: updated.quoteAsOfMs ?? .nan,
            source: updated.source
        )
        let gateVeto = EntryQuality.veto(signal: signal, quote: quote, at: evaluatedAt)
        let qualified = signal.cabinetSide == baseline.side
            && ["HIGH", "LOW"].contains(signal.cabinetSide)
            && (signal.vetoes?.isEmpty ?? true)
            && gateVeto == nil
        let digest = try ResearchEvent.digest(of: updated)
        let input = RollingRevalidationInput(
            marketAsset: updated.asset,
            quotePrice: updated.lastPrice,
            quoteTimestamp: Date(timeIntervalSince1970: (updated.quoteAsOfMs ?? .nan) / 1_000),
            receivedAt: receivedAt,
            evaluatedAt: evaluatedAt,
            side: signal.cabinetSide,
            qualified: qualified,
            updatedInputDigest: digest,
            sourceID: updated.source == sourceID ? sourceID : "",
            venueID: venueID,
            instrumentID: instrumentID,
            expirySeconds: updated.expirySeconds,
            locks: locks,
            marketDataValid: marketDataValid
        )
        return evaluate(
            baseline: baseline,
            window: window,
            input: input,
            engineVersion: EngineIdentity.loadedSHA1() ?? "unverified",
            policyVersion: updated.policy?.rawValue ?? "baseline",
            maximumQuoteAge: maximumQuoteAge
        )
    }
}
