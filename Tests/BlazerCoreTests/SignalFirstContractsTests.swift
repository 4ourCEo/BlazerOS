import Foundation
import Testing
@testable import BlazerCore

struct SignalFirstContractsTests {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)

    private func code(_ value: String) throws -> SignalFirstReasonCode {
        try SignalFirstReasonCode(validating: value)
    }

    private func context(scanID: String, generation: UInt64,
                         environment: SignalFirstEnvironment = .practice,
                         provider: String = "OANDA",
                         instrument: String = "GBP_JPY",
                         sourceID: String = String(repeating: "C", count: 40)) throws -> SignalFirstScanContext {
        try SignalFirstScanContext(environment: environment, providerIdentity: provider,
            requestedInstrument: instrument, scanID: scanID, generation: generation,
            quoteAsOf: Date(timeIntervalSince1970: 1_000), candleAsOf: Date(timeIntervalSince1970: 999),
            sourceInputIdentity: sourceID)
    }

    private func identity(timeframe: String = "M5", digest: String? = nil,
                         setupKey: String = "breakout:2026-11-18T09:30Z") throws -> SignalFirstSetupIdentity {
        try SignalFirstSetupIdentity(strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            instrument: "GBP_JPY", direction: .long, timeframe: timeframe,
            configurationSHA256: digest ?? digestA, setupKey: setupKey)
    }

    private func candidateReference(evaluatorID: String = "ORB", strategyID: String = "GBPJPY_ORB",
                                    version: String = "v1",
                                    timeframe: String = "M5",
                                    setupKey: String = "breakout:2026-11-18T09:30Z") throws -> SignalFirstCandidateReference {
        try SignalFirstCandidateReference(signalID: try identity(timeframe: timeframe, setupKey: setupKey).signalID,
            evaluatorID: evaluatorID, strategyID: strategyID, strategyVersion: version, timeframe: timeframe)
    }

    @Test func signalIdentityStableAcrossScanObservations() throws {
        let setup = try identity()
        let first = try SignalFirstObservation(context: context(scanID: "scan-1", generation: 4),
            observedAt: Date(timeIntervalSince1970: 1_000))
        let second = try SignalFirstObservation(context: context(scanID: "scan-2", generation: 5),
            observedAt: Date(timeIntervalSince1970: 1_005))
        let a = try SignalFirstObservationRecord(identity: setup, observation: first,
            lifecycle: .forming)
        let b = try SignalFirstObservationRecord(identity: setup, observation: second,
            lifecycle: .confirmed)

        #expect(a.signalID == b.signalID)
        #expect(a.storageKey == b.storageKey)
        #expect(a.id == a.storageKey)
        #expect(a.scanID != b.scanID)
        #expect(a.generation != b.generation)
        #expect(a.observation.context.environment == .practice)
        #expect(a.observation.context.requestedInstrument == "GBP/JPY")
        #expect(a.observation.context.providerIdentity == "oanda")
        #expect(a.observation.context.sourceInputIdentity == String(repeating: "c", count: 40))
    }

    @Test func storageKeyIsNamespacedByEnvironmentAndProvider() throws {
        let setup = try identity()
        func record(environment: SignalFirstEnvironment, provider: String) throws -> SignalFirstObservationRecord {
            try SignalFirstObservationRecord(identity: setup,
                observation: SignalFirstObservation(context: context(scanID: "same-scan", generation: 1,
                    environment: environment, provider: provider), observedAt: Date(timeIntervalSince1970: 1_001)),
                lifecycle: .actionable)
        }
        let practice = try record(environment: .practice, provider: "OANDA")
        let live = try record(environment: .live, provider: "OANDA")
        let otherProvider = try record(environment: .practice, provider: "other-feed")
        #expect(practice.signalID == live.signalID)
        #expect(practice.signalID == otherProvider.signalID)
        #expect(practice.storageKey != live.storageKey)
        #expect(practice.storageKey != otherProvider.storageKey)
    }

    @Test func identityChangesWithSetupConfigurationOrTimeframe() throws {
        let baseline = try identity()
        #expect(try identity(setupKey: "breakout:2026-11-18T09:35Z").signalID != baseline.signalID)
        #expect(try identity(digest: digestB).signalID != baseline.signalID)
        #expect(try identity(timeframe: "M15").signalID != baseline.signalID)
    }

    @Test func snapshotContainsNoAuthorizationOrExecutionClaims() throws {
        let setup = try identity()
        let observation = try SignalFirstObservation(context: context(scanID: "scan", generation: 1),
            observedAt: Date(timeIntervalSince1970: 1_000))
        let record = try SignalFirstObservationRecord(identity: setup, observation: observation,
            lifecycle: .actionable)

        #expect(record.lifecycle == .actionable)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        #expect(encoded?["authorization"] == nil)
        #expect(encoded?["execution"] == nil)
        #expect(encoded?["brokerEvidenceIdentity"] == nil)
    }

    @Test func snapshotStillRejectsInstrumentMismatch() throws {
        let setup = try identity()
        #expect(throws: SignalFirstContractError.instrumentMismatch) {
            try SignalFirstObservationRecord(identity: setup, observation: SignalFirstObservation(
                context: context(scanID: "other", generation: 1, instrument: "EUR_USD"),
                observedAt: Date(timeIntervalSince1970: 1_000)), lifecycle: .actionable)
        }
    }

    @Test func decodingObservationRecordRevalidatesCrossFieldConstraints() throws {
        let validRecord = try SignalFirstObservationRecord(identity: identity(),
            observation: SignalFirstObservation(context: context(scanID: "scan", generation: 1),
                observedAt: Date(timeIntervalSince1970: 1_000)),
            lifecycle: .actionable)
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(validRecord)
        let originalRoot = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var root = originalRoot
        var observation = try #require(root["observation"] as? [String: Any])
        var contextObject = try #require(observation["context"] as? [String: Any])
        contextObject["requestedInstrument"] = "EUR/USD"
        observation["context"] = contextObject
        root["observation"] = observation
        let mismatchedInstrument = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: SignalFirstContractError.instrumentMismatch) {
            try JSONDecoder().decode(SignalFirstObservationRecord.self, from: mismatchedInstrument)
        }

        root = originalRoot
        var decodedContext = try #require((root["observation"] as? [String: Any])?["context"] as? [String: Any])
        decodedContext["environment"] = SignalFirstEnvironment.live.rawValue
        var decodedObservation = try #require(root["observation"] as? [String: Any])
        decodedObservation["context"] = decodedContext
        root["observation"] = decodedObservation
        let relabeledEnvironment = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(SignalFirstObservationRecord.self, from: relabeledEnvironment)
        #expect(decoded.observation.context.environment == .live)
        #expect(decoded.storageKey != validRecord.storageKey)
    }

    @Test func freshnessRejectsFutureAndOverAgeSourceTimes() throws {
        let scan = try context(scanID: "scan", generation: 1)
        #expect(scan.isFresh(asOf: Date(timeIntervalSince1970: 1_002), maxQuoteAge: 5, maxCandleAge: 120))
        #expect(!scan.isFresh(asOf: Date(timeIntervalSince1970: 999), maxQuoteAge: 5, maxCandleAge: 120))
        #expect(!scan.isFresh(asOf: Date(timeIntervalSince1970: 2_000), maxQuoteAge: 5, maxCandleAge: 120))
        #expect(!scan.isFresh(asOf: Date(timeIntervalSince1970: 1_002), maxQuoteAge: .nan, maxCandleAge: 120))
    }

    @Test func acceptsExistingSha1ScanIdentityAndSha256ArchiveDigest() throws {
        let existingScanIdentity = try context(scanID: "scan-sha1", generation: 1,
            sourceID: String(repeating: "A", count: 40))
        let archiveDigest = try context(scanID: "archive-sha256", generation: 1,
            sourceID: String(repeating: "B", count: 64))
        #expect(existingScanIdentity.sourceInputIdentity == String(repeating: "a", count: 40))
        #expect(archiveDigest.sourceInputIdentity == String(repeating: "b", count: 64))
    }

    @Test func terminalLifecycleCannotReactivate() throws {
        try SignalFirstLifecycleTransition.validate(from: .forming, to: .confirmed)
        try SignalFirstLifecycleTransition.validate(from: .confirmed, to: .actionable)
        try SignalFirstLifecycleTransition.validate(from: .actionable, to: .expired)
        #expect(throws: SignalFirstContractError.invalidLifecycleTransition) {
            try SignalFirstLifecycleTransition.validate(from: .expired, to: .forming)
        }
        #expect(throws: SignalFirstContractError.invalidLifecycleTransition) {
            try SignalFirstLifecycleTransition.validate(from: .invalidated, to: .actionable)
        }
    }

    @Test func evaluatorCompletionMakesEmptyDifferentFromFailure() throws {
        let empty = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "m5", completion: .completed(candidates: []))
        let failed = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "M5", completion: .failed(reason: try code("evaluator_exception")))
        let unavailable = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "M5", completion: .dataUnavailable(reason: try code("history_incomplete")))
        let notConfigured = try SignalFirstEvaluatorOutcome(evaluatorID: "LondonBreak", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "M5", completion: .notConfigured(reason: try code("profile_not_frozen")))
        let unsupported = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "H2", completion: .unsupported(reason: try code("timeframe_not_supported")))

        #expect(empty.completion == .completed(candidates: []))
        #expect(failed.completion == .failed(reason: try code("evaluator_exception")))
        #expect(unavailable.completion == .dataUnavailable(reason: try code("history_incomplete")))
        #expect(notConfigured.completion == .notConfigured(reason: try code("profile_not_frozen")))
        #expect(unsupported.completion == .unsupported(reason: try code("timeframe_not_supported")))
        #expect(throws: SignalFirstContractError.invalidCandidateIdentities) {
            let candidate = try candidateReference()
            let duplicate = try candidateReference()
            _ = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .completed(candidates: [candidate, duplicate]))
        }
        #expect(throws: SignalFirstContractError.invalidSignalID) {
            try SignalFirstCandidateReference(signalID: "bad", evaluatorID: "ORB", strategyID: "GBPJPY_ORB",
                strategyVersion: "v1", timeframe: "M5")
        }
        let positiveCandidate = try candidateReference()
        let positive = try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1",
            timeframe: "m5", completion: .completed(candidates: [positiveCandidate]))
        #expect(positive.completion == .completed(candidates: [positiveCandidate]))
        let positiveData = try JSONEncoder().encode(positive)
        #expect(try JSONDecoder().decode(SignalFirstEvaluatorOutcome.self, from: positiveData) == positive)
        #expect(throws: SignalFirstContractError.candidateReferenceMismatch) {
            try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .completed(candidates: [candidateReference(strategyID: "OTHER_STRATEGY")]))
        }
        #expect(throws: SignalFirstContractError.candidateReferenceMismatch) {
            try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .completed(candidates: [candidateReference(evaluatorID: "OTHER_EVALUATOR")]))
        }
        #expect(throws: SignalFirstContractError.candidateReferenceMismatch) {
            try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .completed(candidates: [candidateReference(version: "v2")]))
        }
        #expect(throws: SignalFirstContractError.candidateReferenceMismatch) {
            try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .completed(candidates: [candidateReference(timeframe: "M15")]))
        }
    }

    @Test func rejectsInvalidIdentityObservationAndCompletionInputs() throws {
        #expect(throws: SignalFirstContractError.requiredIdentityFieldMissing) {
            try SignalFirstSetupIdentity(strategyID: "", strategyVersion: "v1", instrument: "GBP/JPY",
                direction: .long, timeframe: "M5", configurationSHA256: digestA, setupKey: "setup")
        }
        #expect(throws: SignalFirstContractError.invalidConfigurationDigest) {
            try identity(digest: "not-a-digest")
        }
        #expect(throws: SignalFirstContractError.scanIDMissing) {
            try SignalFirstScanContext(environment: .practice, providerIdentity: "OANDA",
                requestedInstrument: "GBP/JPY", scanID: "  ", generation: 1,
                quoteAsOf: Date(timeIntervalSince1970: 1_000))
        }
        #expect(throws: SignalFirstContractError.invalidObservationTime) {
            try SignalFirstScanContext(environment: .practice, providerIdentity: "OANDA",
                requestedInstrument: "GBP/JPY", scanID: "scan", generation: 1,
                quoteAsOf: Date(timeIntervalSince1970: .infinity))
        }
        #expect(throws: SignalFirstContractError.invalidReasonCode) {
            _ = try code("raw exception text")
        }
        #expect(throws: SignalFirstContractError.invalidReasonCode) {
            try SignalFirstEvaluatorOutcome(evaluatorID: "ORB", strategyID: "GBPJPY_ORB", strategyVersion: "v1", timeframe: "M5",
                completion: .failed(reason: try code("Exception: stack trace")))
        }
        #expect(throws: SignalFirstContractError.invalidSourceIdentity) {
            try SignalFirstScanContext(environment: .replay, providerIdentity: "fixture",
                requestedInstrument: "GBP/JPY", scanID: "scan", generation: 1,
                quoteAsOf: Date(timeIntervalSince1970: 1_000), sourceInputIdentity: "fixture-snapshot")
        }
        #expect(throws: SignalFirstContractError.sourceTimestampMissing) {
            try SignalFirstScanContext(environment: .replay, providerIdentity: "fixture",
                requestedInstrument: "GBP/JPY", scanID: "scan", generation: 1,
                sourceInputIdentity: String(repeating: "d", count: 64))
        }
        let malformedIdentity = Data(#"{"strategyID":"ORB","strategyVersion":"v1","instrument":"GBP/JPY","direction":"LONG","timeframe":"M5","configurationSHA256":"bad","setupKey":"setup"}"#.utf8)
        #expect(throws: SignalFirstContractError.invalidConfigurationDigest) {
            try JSONDecoder().decode(SignalFirstSetupIdentity.self, from: malformedIdentity)
        }
    }

    @Test func identityAndObservationRoundTripCodable() throws {
        let original = try SignalFirstObservationRecord(identity: identity(),
            observation: try SignalFirstObservation(context: context(scanID: "scan-1", generation: 2),
                observedAt: Date(timeIntervalSince1970: 1_000)),
            lifecycle: .confirmed)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SignalFirstObservationRecord.self, from: data)
        #expect(decoded == original)
    }

}
