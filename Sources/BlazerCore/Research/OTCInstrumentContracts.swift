import Foundation

/// First-class research instrument identity. The `instrumentID` is the canonical, stable key;
/// the embedded `ShadowMarketIdentity` is the venue-facing contract. Two instruments may share a
/// display ticker (EUR/USD) and still remain distinct here: OANDA spot, Pocket Option standard,
/// and Pocket Option OTC are never aliases of one another.
public struct OTCInstrumentIdentity: Codable, Sendable, Equatable, Identifiable {
    public let instrumentID: String
    public let identity: ShadowMarketIdentity

    public init(instrumentID: String, identity: ShadowMarketIdentity) {
        self.instrumentID = instrumentID
        self.identity = identity
    }

    public var id: String { instrumentID }
    public var displaySymbol: String { identity.displaySymbol }
    public var venue: String { identity.venue }
    public var venueSymbol: String { identity.venueSymbol }
    public var isOTC: Bool { identity.marketKind == .otc }
    /// Every OTC instrument is research-only in this build. The flag is intentionally not
    /// configurable: an OTC signal can never claim production execution eligibility.
    public var isResearchOnly: Bool { isOTC }
    public var mayAuthorizeEntry: Bool { false }

    /// Canonical identity validation. A malformed contract is rejected rather than coerced.
    public var isValid: Bool {
        !instrumentID.isEmpty
            && instrumentID.contains(":")
            && !identity.venue.isEmpty
            && !identity.venueSymbol.isEmpty
            && !identity.displaySymbol.isEmpty
            && (identity.marketKind == .otc
                ? (identity.venueSymbol.hasSuffix("_otc") && identity.session == .weekendSession)
                : true)
    }
}

/// The canonical catalogue. Provider discovery expands the OTC watchlist through
/// `otcWatchlist(from:)`; it never renames or substitutes these contracts.
public enum OTCInstrumentCatalog {
    /// OANDA spot reference for EUR/USD. Standard session, spot settlement.
    public static let oandaEURUSD = OTCInstrumentIdentity(
        instrumentID: "oanda:EUR/USD",
        identity: ShadowMarketIdentity(
            marketKind: .standard, venue: "OANDA", venueSymbol: "EUR/USD",
            displaySymbol: "EUR/USD", session: .regularSession,
            settlementBasis: .spotReference))

    /// Pocket Option's standard EUR/USD book. Same ticker as OANDA, different venue and basis.
    public static let pocketOptionEURUSD = OTCInstrumentIdentity(
        instrumentID: "pocketoption:EURUSD",
        identity: ShadowMarketIdentity(
            marketKind: .standard, venue: "Pocket Option", venueSymbol: "EURUSD",
            displaySymbol: "EUR/USD", session: .regularSession,
            settlementBasis: .venueDisplayed))

    /// Pocket Option's weekend OTC book. This is the only instrument the research engine
    /// nominally targets in V2.4, and it is distinct from both standard contracts above.
    public static let pocketOptionEURUSDOTC = OTCInstrumentIdentity(
        instrumentID: "pocketoption:EURUSD_otc",
        identity: ShadowMarketDataFixtures.pocketOptionEURUSDOTC)

    public static let canonical: [OTCInstrumentIdentity] = [
        oandaEURUSD, pocketOptionEURUSD, pocketOptionEURUSDOTC
    ]

    /// Resolves only an exact catalogue entry. Unknown or near-match tickers are rejected so a
    /// provider cannot silently stand in for a different venue's instrument.
    public static func exact(venue: String, venueSymbol: String) -> OTCInstrumentIdentity? {
        canonical.first {
            $0.identity.venue == venue && $0.identity.venueSymbol == venueSymbol
        }
    }

    public static func exact(instrumentID: String) -> OTCInstrumentIdentity? {
        canonical.first { $0.instrumentID == instrumentID }
    }

    /// Converts one provider-verified OTC availability into a first-class instrument. The
    /// provider must already declare the OTC market kind, the weekend session, venue-displayed
    /// settlement, and a `_otc` symbol; otherwise the row is ignored rather than reinterpreted.
    public static func otcIdentity(from availability: ShadowInstrumentAvailability) -> OTCInstrumentIdentity? {
        let identity = availability.identity
        guard identity.marketKind == .otc,
              identity.session == .weekendSession,
              identity.settlementBasis == .venueDisplayed,
              identity.venue == "Pocket Option",
              identity.venueSymbol.hasSuffix("_otc"),
              identity.venueSymbol.count > "_otc".count,
              !identity.displaySymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !identity.venueSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let instrument = OTCInstrumentIdentity(
            instrumentID: "pocketoption:\(identity.venueSymbol)",
            identity: identity)
        return instrument.isValid ? instrument : nil
    }

    /// Expands the OTC watchlist from the provider's verified catalogue. Duplicate rows keep the
    /// first exact contract; the result is stable and sorted by instrument ID.
    public static func otcWatchlist(from availabilities: [ShadowInstrumentAvailability]) -> [OTCInstrumentIdentity] {
        var seen = Set<String>()
        return availabilities.compactMap(otcIdentity(from:))
            .filter { seen.insert($0.instrumentID).inserted }
            .sorted { $0.instrumentID < $1.instrumentID }
    }
}
