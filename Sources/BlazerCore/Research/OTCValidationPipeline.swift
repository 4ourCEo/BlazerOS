import Foundation

public enum OTCObservationOrigin: String, Codable, Sendable, Equatable {
    case directBrokerData
    case independentAPI
    case manualChartObservation
    case syntheticTestFixture
}

public struct OTCValidationSample: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let capturedAt: Date
    public let standard: ShadowMarketObservation?
    public let otc: ShadowMarketObservation?
    public let standardOrigin: OTCObservationOrigin?
    public let otcOrigin: OTCObservationOrigin?
    public let note: String?

    public init(id: String = UUID().uuidString, capturedAt: Date,
                standard: ShadowMarketObservation?, otc: ShadowMarketObservation?,
                standardOrigin: OTCObservationOrigin?, otcOrigin: OTCObservationOrigin?,
                note: String? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.standard = standard
        self.otc = otc
        self.standardOrigin = standardOrigin
        self.otcOrigin = otcOrigin
        self.note = note
    }

    public var isValid: Bool {
        !id.isEmpty && capturedAt <= Date()
            && standard.map { $0.identity.marketKind == .standard && $0.isValid }.unwrap(or: true)
            && otc.map { $0.identity.marketKind == .otc && $0.isValid }.unwrap(or: true)
            && ((standard == nil) == (standardOrigin == nil))
            && ((otc == nil) == (otcOrigin == nil))
    }
}

/// Descriptive research statistics only. No field carries settlement or entry authority.
public struct OTCValidationReport: Codable, Sendable, Equatable {
    public let totalSamples: Int
    /// Non-overlapping 60-second bucket transitions with a valid standard and OTC leg.
    public let sixtySecondComparableTransitions: Int
    public let sixtySecondDirectionAgreements: Int
    public let meanTimestampSkewSeconds: Double?
    public let meanAbsolutePriceDisplacement: Double?
    public let missingStandardObservations: Int
    public let missingOTCObservations: Int
    /// Observations whose declared identity is the OTC session.
    public let otcSessionSamples: Int
    /// Observations captured on a Saturday or Sunday in the local calendar.
    public let calendarWeekendSamples: Int
    public let staleWeekendReferencesExcluded: Int
    public let syntheticSampleCount: Int
    public let containsSyntheticData: Bool
    /// True when the retained archive contains a non-synthetic-flagged OTC observation from a
    /// configured provider source. This is provider data, never broker or settlement verification.
    public let hasProviderOTCObservation: Bool
    /// Coverage of the retained archive after retention pruning.
    public let oldestCapturedAt: Date?
    public let newestCapturedAt: Date?
    public let retentionLimit: Int
    public let status: String
}

public actor OTCValidationPipeline {
    private let root: URL
    /// Bounds on-disk growth for this research-only archive.
    private let maximumSamples: Int
    private let pruneEvery: Int
    private var writesSincePrune = 0

    public init(root: URL, maximumSamples: Int = 5_000, pruneEvery: Int = 256) {
        self.root = root
        self.maximumSamples = max(1, maximumSamples)
        self.pruneEvery = max(1, pruneEvery)
    }

    public func record(_ sample: OTCValidationSample) throws {
        guard sample.isValid,
              sample.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw ShadowMarketDataError.invalidPoint
        }
        let directory = root.appendingPathComponent("paired-observations", isDirectory: true)
        // A timestamp prefix keeps filenames chronologically sortable for retention pruning.
        let name = String(format: "%015.3f", sample.capturedAt.timeIntervalSince1970)
            + "-" + sample.id + ".json"
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try AtomicFile.write(encoder.encode(sample), to: url)
        writesSincePrune += 1
        if writesSincePrune >= pruneEvery {
            writesSincePrune = 0
            prune(in: directory)
        }
    }

    public func samples() throws -> [OTCValidationSample] {
        let directory = root.appendingPathComponent("paired-observations", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(OTCValidationSample.self, from: Data(contentsOf: $0)) }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    public func report(maximumTimestampSkew: TimeInterval = 3,
                       maximumStandardAge: TimeInterval = 10) throws -> OTCValidationReport {
        let values = try samples()
        var skews: [Double] = []
        var displacements: [Double] = []
        var missingStandard = 0
        var missingOTC = 0
        var otcSession = 0
        var calendarWeekend = 0
        var excludedWeekend = 0
        var syntheticSamples = 0
        var paired: [(capturedAt: Date, standard: ShadowMarketObservation, otc: ShadowMarketObservation)] = []

        for sample in values {
            if sample.otc != nil { otcSession += 1 }
            if sample.otc != nil, Calendar.current.isDateInWeekend(sample.capturedAt) {
                calendarWeekend += 1
            }
            if sample.standard == nil { missingStandard += 1 }
            if sample.otc == nil { missingOTC += 1 }
            if sample.standardOrigin == .syntheticTestFixture
                || sample.otcOrigin == .syntheticTestFixture
                || sample.standard?.verification == .syntheticTestFixture
                || sample.otc?.verification == .syntheticTestFixture {
                syntheticSamples += 1
            }
            guard let standard = sample.standard, let otc = sample.otc else { continue }
            let standardAge = sample.capturedAt.timeIntervalSince(standard.providerTimestamp.normalized)
            let otcAge = sample.capturedAt.timeIntervalSince(otc.providerTimestamp.normalized)
            // A stale or future-dated leg is excluded from every derived metric.
            guard otcAge >= -maximumTimestampSkew, otcAge <= maximumStandardAge else { continue }
            // An OANDA print that stopped updating at the Friday close is not a valid
            // comparison for an active weekend OTC market.
            if otc.identity.session == .weekendSession && standardAge > maximumStandardAge {
                excludedWeekend += 1
                continue
            }
            guard standardAge >= -maximumTimestampSkew, standardAge <= maximumStandardAge else { continue }
            let skew = abs(standard.providerTimestamp.normalized.timeIntervalSince(otc.providerTimestamp.normalized))
            if skew <= maximumTimestampSkew {
                skews.append(skew)
                displacements.append(abs(otc.quote.price - standard.quote.price))
            }
            paired.append((sample.capturedAt, standard, otc))
        }

        // A dense tick archive would make adjacent-sample deltas overlap and overstate the
        // sample size. Direction is measured open-to-open once per aligned 60-second bucket,
        // keyed on the OTC provider's own timestamp. The compared prints must actually span
        // roughly a minute and share the same 3-second skew gate as the descriptive metrics.
        var previousByBucket: (key: Int, standard: ShadowMarketObservation, otc: ShadowMarketObservation)?
        var sixtyComparable = 0
        var sixtyAgreements = 0
        for entry in paired {
            let key = Int(floor(entry.otc.providerTimestamp.normalized.timeIntervalSince1970 / 60))
            if let previous = previousByBucket {
                if previous.key == key {
                    // Keep the first print in the bucket; do not let a later tick replace it.
                    continue
                }
                guard previous.key + 1 == key,
                      previous.standard.identity == entry.standard.identity,
                      previous.otc.identity == entry.otc.identity else {
                    previousByBucket = (key, entry.standard, entry.otc)
                    continue
                }
                let spacing = entry.otc.providerTimestamp.normalized
                    .timeIntervalSince(previous.otc.providerTimestamp.normalized)
                let skew = abs(entry.standard.providerTimestamp.normalized
                    .timeIntervalSince(entry.otc.providerTimestamp.normalized))
                guard (40...80).contains(spacing), skew <= maximumTimestampSkew else {
                    previousByBucket = (key, entry.standard, entry.otc)
                    continue
                }
                let standardDelta = entry.standard.quote.price - previous.standard.quote.price
                let otcDelta = entry.otc.quote.price - previous.otc.quote.price
                // A flat bucket carries no directional information and is not agreement.
                if standardDelta != 0, otcDelta != 0 {
                    sixtyComparable += 1
                    if direction(standardDelta) == direction(otcDelta) { sixtyAgreements += 1 }
                }
            }
            previousByBucket = (key, entry.standard, entry.otc)
        }

        let synthetic = syntheticSamples > 0
        let providerOrigins: Set<OTCObservationOrigin> =
            [.directBrokerData, .independentAPI, .manualChartObservation]
        // Provider data requires at least one real OTC observation and no synthetic sample in
        // the retained window. It never means independently verified or settlement-equivalent.
        let hasProviderOTC = values.contains { sample in
            guard let otc = sample.otc, let origin = sample.otcOrigin,
                  providerOrigins.contains(origin),
                  otc.verification != .syntheticTestFixture else { return false }
            return otc.identity.marketKind == .otc
        }
        let status: String
        if !hasProviderOTC {
            status = "UNVERIFIED"
        } else if sixtyComparable > 0 {
            status = "PROVIDER DATA — INDEPENDENT VALIDATION REQUIRED"
        } else {
            status = "PROVIDER DATA — NO PAIRED COMPARISON"
        }
        return OTCValidationReport(totalSamples: values.count,
            sixtySecondComparableTransitions: sixtyComparable,
            sixtySecondDirectionAgreements: sixtyAgreements,
            meanTimestampSkewSeconds: mean(skews),
            meanAbsolutePriceDisplacement: mean(displacements),
            missingStandardObservations: missingStandard,
            missingOTCObservations: missingOTC,
            otcSessionSamples: otcSession,
            calendarWeekendSamples: calendarWeekend,
            staleWeekendReferencesExcluded: excludedWeekend,
            syntheticSampleCount: syntheticSamples,
            containsSyntheticData: synthetic,
            hasProviderOTCObservation: hasProviderOTC,
            oldestCapturedAt: values.first?.capturedAt,
            newestCapturedAt: values.last?.capturedAt,
            retentionLimit: maximumSamples,
            status: status)
    }

    private func prune(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        let samples = files.filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        guard samples.count > maximumSamples else { return }
        for file in samples.prefix(samples.count - maximumSamples) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func direction(_ value: Double) -> ShadowDirection {
        value > 0 ? .up : (value < 0 ? .down : .unchanged)
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

private extension Optional where Wrapped == Bool {
    func unwrap(or fallback: Bool) -> Bool { self ?? fallback }
}
