import CryptoKit
import Foundation

/// Immutable metadata for a historical OANDA Live candle batch. It contains
/// market data and request provenance only; credentials and account identity
/// are deliberately absent.
public struct LiveHistoricalResearchArchiveRecord: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let provider: String
    public let environment: String
    public let endpoint: String
    public let instrument: String
    public let granularity: String
    public let priceComponent: String
    public let smooth: Bool
    public let includeFirst: Bool
    public let requestedFrom: Date
    public let requestedTo: Date
    public let retrievedAt: Date
    public let payloadSHA256: String
    public let gapCount: Int
    public let batch: OandaHistoricalBidAskBatch

    fileprivate init(batch: OandaHistoricalBidAskBatch, includeFirst: Bool,
                     retrievedAt: Date, payloadSHA256: String, gapCount: Int) {
        schemaVersion = 1
        provider = "OANDA_V20"
        environment = "LIVE"
        endpoint = "/v3/instruments/{instrument}/candles"
        instrument = batch.instrument
        granularity = batch.granularity
        priceComponent = "BA"
        smooth = false
        self.includeFirst = includeFirst
        requestedFrom = batch.requestedFrom
        requestedTo = batch.requestedTo
        self.retrievedAt = retrievedAt
        self.payloadSHA256 = payloadSHA256
        self.gapCount = gapCount
        self.batch = batch
    }
}

public struct LiveHistoricalArchiveWrite: Sendable, Equatable {
    public let url: URL
    public let payloadSHA256: String
    public let candleCount: Int
    public let gapCount: Int
    public let skippedExisting: Bool
}

/// Canonical content covered by the archive digest. The digest field itself is
/// intentionally excluded, while every provider, request, retrieval, and gap
/// claim is bound to the candle payload.
private struct LiveHistoricalArchiveIntegrityPayload: Codable {
    let schemaVersion: Int
    let provider: String
    let environment: String
    let endpoint: String
    let instrument: String
    let granularity: String
    let priceComponent: String
    let smooth: Bool
    let includeFirst: Bool
    let requestedFrom: Date
    let requestedTo: Date
    let retrievedAt: Date
    let gapCount: Int
    let batch: OandaHistoricalBidAskBatch

    init(record: LiveHistoricalResearchArchiveRecord) {
        schemaVersion = record.schemaVersion
        provider = record.provider
        environment = record.environment
        endpoint = record.endpoint
        instrument = record.instrument
        granularity = record.granularity
        priceComponent = record.priceComponent
        smooth = record.smooth
        includeFirst = record.includeFirst
        requestedFrom = record.requestedFrom
        requestedTo = record.requestedTo
        retrievedAt = record.retrievedAt
        gapCount = record.gapCount
        batch = record.batch
    }
}

/// Separate, append-only storage for explicitly collected OANDA Live history.
/// Practice history and current streaming quotes have different directories and
/// must not be combined implicitly.
public enum LiveHistoricalResearchArchive {
    public enum ArchiveError: Error, Sendable, Equatable {
        case invalidBatch([String])
        case liveCaptureReceiptRequired
        case existingArchiveInvalid
        case immutableConflict
        case writeFailed
    }

    public struct DayWindow: Sendable, Equatable {
        public let start: Date
        public let end: Date
        public let includeFirst: Bool
    }

    /// UTC day slices keep M1 requests bounded. `endExclusive` must be aligned to
    /// UTC midnight so resumed runs have deterministic chunk identities.
    public static func utcDayWindows(dayCount: Int, endExclusive: Date) -> [DayWindow]? {
        guard (1...3_650).contains(dayCount), endExclusive.timeIntervalSince1970.isFinite else { return nil }
        let seconds = endExclusive.timeIntervalSince1970
        let aligned = floor(seconds / 86_400) * 86_400
        guard aligned == seconds else { return nil }
        let start = aligned - Double(dayCount) * 86_400
        return (0..<dayCount).map { index in
            let windowStart = Date(timeIntervalSince1970: start + Double(index) * 86_400)
            return DayWindow(start: windowStart,
                end: Date(timeIntervalSince1970: start + Double(index + 1) * 86_400),
                // Each bounded historical request begins at a new interval.
                // OANDA's false setting omits the candle covered by `from`,
                // which would drop the first M1 candle of every later day.
                includeFirst: true)
        }
    }

    public static func validationIssues(for batch: OandaHistoricalBidAskBatch,
                                        expectedInstrument: String,
                                        expectedGranularity: String,
                                        expectedFrom: Date, expectedTo: Date) -> [String] {
        var issues: [String] = []
        if batch.transport != .ok || batch.httpStatus != 200 {
            issues.append("transport_not_successful")
        }
        if batch.liveOnlyRejected != false || batch.practiceOnlyRejected {
            issues.append("environment_rejected")
        }
        if batch.instrument != expectedInstrument || batch.granularity != expectedGranularity {
            issues.append("identity_mismatch")
        }
        if batch.requestedFrom != expectedFrom || batch.requestedTo != expectedTo || !(expectedTo > expectedFrom) {
            issues.append("requested_interval_mismatch")
        }
        var previousTime: Date?
        for candle in batch.candles {
            if candle.instrument != expectedInstrument || candle.granularity != expectedGranularity {
                issues.append("candle_identity_mismatch")
            }
            if candle.sourceTime < expectedFrom || candle.sourceTime >= expectedTo {
                issues.append("candle_outside_requested_interval")
            }
            if !candle.complete { issues.append("incomplete_candle") }
            if !candle.validation.isEmpty { issues.append("candle_invalid") }
            if let previousTime, candle.sourceTime <= previousTime {
                issues.append("candles_not_strictly_ordered")
            }
            previousTime = candle.sourceTime
        }
        return Array(Set(issues)).sorted()
    }

    /// Writes or verifies one immutable day file. A duplicate run never silently
    /// replaces existing data; corrupted or conflicting files fail closed.
    public static func append(capture: OandaLiveHistoricalCapture, includeFirst: Bool,
                              root: URL,
                              fileManager: FileManager = .default) throws -> LiveHistoricalArchiveWrite {
        guard let receipt = capture.sourceReceipt else { throw ArchiveError.liveCaptureReceiptRequired }
        guard receipt.includeFirst == includeFirst else {
            throw ArchiveError.invalidBatch(["include_first_mismatch"])
        }
        let retrievedAt = receipt.retrievedAt
        let batch = capture.batch
        let issues = validationIssues(for: batch, expectedInstrument: batch.instrument,
            expectedGranularity: "M1", expectedFrom: batch.requestedFrom, expectedTo: batch.requestedTo)
        guard issues.isEmpty, retrievedAt.timeIntervalSince1970.isFinite,
              floor(batch.requestedFrom.timeIntervalSince1970 / 86_400)
                == batch.requestedFrom.timeIntervalSince1970 / 86_400,
              floor(batch.requestedTo.timeIntervalSince1970 / 86_400)
                == batch.requestedTo.timeIntervalSince1970 / 86_400 else {
            throw ArchiveError.invalidBatch(issues.isEmpty ? ["utc_day_window_invalid"] : issues)
        }
        let gaps = missingMinuteCount(batch.candles)
        let record = LiveHistoricalResearchArchiveRecord(batch: batch, includeFirst: includeFirst,
            retrievedAt: retrievedAt, payloadSHA256: "", gapCount: gaps)
        let digest = try integrityDigest(record)
        let sealedRecord = LiveHistoricalResearchArchiveRecord(batch: batch, includeFirst: includeFirst,
            retrievedAt: retrievedAt, payloadSHA256: digest, gapCount: gaps)
        let directory = root.appendingPathComponent("historical-live-bid-ask", isDirectory: true)
            .appendingPathComponent(batch.instrument, isDirectory: true)
            .appendingPathComponent(batch.granularity, isDirectory: true)
        try createPrivateDirectory(directory, fileManager: fileManager)
        let start = Int64(batch.requestedFrom.timeIntervalSince1970)
        let end = Int64(batch.requestedTo.timeIntervalSince1970)
        let destination = directory.appendingPathComponent("oanda-live-\(batch.instrument)-M1-\(start)-\(end).json")

        if fileManager.fileExists(atPath: destination.path) {
            let existing = try readAndVerify(destination, fileManager: fileManager)
            guard existing.instrument == batch.instrument,
                  existing.granularity == batch.granularity,
                  existing.requestedFrom == batch.requestedFrom,
                  existing.requestedTo == batch.requestedTo,
                  existing.payloadSHA256 == digest else {
                throw ArchiveError.immutableConflict
            }
            return LiveHistoricalArchiveWrite(url: destination,
                payloadSHA256: existing.payloadSHA256, candleCount: existing.batch.candles.count,
                gapCount: existing.gapCount, skippedExisting: true)
        }

        guard let encoded = try? canonicalRecordData(sealedRecord) else { throw ArchiveError.writeFailed }
        let temporary = directory.appendingPathComponent(".capture-\(UUID().uuidString).tmp")
        do {
            try encoded.write(to: temporary, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            try fileManager.moveItem(at: temporary, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? fileManager.removeItem(at: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                let existing = try readAndVerify(destination, fileManager: fileManager)
                guard existing.payloadSHA256 == digest else { throw ArchiveError.immutableConflict }
                return LiveHistoricalArchiveWrite(url: destination, payloadSHA256: digest,
                    candleCount: existing.batch.candles.count, gapCount: existing.gapCount,
                    skippedExisting: true)
            }
            throw ArchiveError.writeFailed
        }
        return LiveHistoricalArchiveWrite(url: destination, payloadSHA256: digest,
            candleCount: batch.candles.count, gapCount: gaps, skippedExisting: false)
    }

    private static func readAndVerify(_ url: URL, fileManager: FileManager) throws -> LiveHistoricalResearchArchiveRecord {
        guard let data = try? Data(contentsOf: url),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0,
              let record = try? JSONDecoder.liveHistoricalArchive.decode(LiveHistoricalResearchArchiveRecord.self, from: data),
              record.schemaVersion == 1, record.provider == "OANDA_V20", record.environment == "LIVE",
              record.endpoint == "/v3/instruments/{instrument}/candles", record.priceComponent == "BA",
              !record.smooth, record.granularity == "M1",
              record.requestedFrom == record.batch.requestedFrom,
              record.requestedTo == record.batch.requestedTo,
              record.gapCount == missingMinuteCount(record.batch.candles),
              record.retrievedAt.timeIntervalSince1970.isFinite,
              try integrityDigest(record) == record.payloadSHA256,
              validationIssues(for: record.batch, expectedInstrument: record.instrument,
                expectedGranularity: record.granularity, expectedFrom: record.requestedFrom,
                expectedTo: record.requestedTo).isEmpty,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ArchiveError.existingArchiveInvalid
        }
        return record
    }

    private static func integrityDigest(_ record: LiveHistoricalResearchArchiveRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return sha256(try encoder.encode(LiveHistoricalArchiveIntegrityPayload(record: record)))
    }

    private static func canonicalRecordData(_ record: LiveHistoricalResearchArchiveRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(record)
    }

    private static func createPrivateDirectory(_ directory: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ArchiveError.writeFailed
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func missingMinuteCount(_ candles: [OandaBidAskCandle]) -> Int {
        guard candles.count > 1 else { return 0 }
        return zip(candles, candles.dropFirst()).reduce(0) { count, pair in
            count + max(0, Int(pair.1.sourceTime.timeIntervalSince(pair.0.sourceTime) / 60) - 1)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONDecoder {
    static var liveHistoricalArchive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
