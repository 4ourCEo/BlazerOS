import Foundation
import Testing
@testable import BlazerCore

private func shadowPoint(_ identity: ShadowMarketIdentity, _ provider: String, _ t: Double, _ price: Double) -> ShadowMarketDataPoint {
    let date = Date(timeIntervalSince1970: t)
    return ShadowMarketDataPoint(identity: identity, providerID: provider, sourceTime: date,
        receivedAt: date, price: price, provenance: "test", status: .unverified)
}

@Test func disabledProviderAlwaysFailsClosed() async {
    let provider = DisabledShadowMarketDataProvider()
    do {
        _ = try await provider.point(for: ShadowMarketDataFixtures.standardEURUSD,
                                     at: Date(timeIntervalSince1970: 100))
        Issue.record("Disabled provider returned a point")
    } catch let error as ShadowMarketDataError {
        #expect(error == .disabled)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func standardAndOTCEURUSDIdentitiesNeverAlias() {
    let standard = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    #expect(standard != otc)
    #expect(standard.marketKind == .standard)
    #expect(otc.marketKind == .otc)
    #expect(otc.venueSymbol == "EURUSD_otc")
    #expect(otc.session == .weekendSession)
    #expect(otc.settlementBasis == .venueDisplayed)
    let points = ShadowMarketDataFixtures.points()
    #expect(points.map(\.identity) == [standard, otc])
    let comparison = ShadowMarketDataComparison.compare(
        shadowPoint(standard, "standard-feed", 100, 1.1), shadowPoint(otc, "otc-feed", 100, 1.1),
        previousLHS: shadowPoint(standard, "standard-feed", 99, 1.0),
        previousRHS: shadowPoint(otc, "otc-feed", 99, 1.0),
        at: Date(timeIntervalSince1970: 100), maximumTimestampSkew: 1)
    #expect(comparison.status == .comparable)
    #expect(comparison.standardIdentity == standard)
    #expect(comparison.otcIdentity == otc)
    #expect(comparison.standardProviderID == "standard-feed")
    #expect(comparison.otcProviderID == "otc-feed")
    #expect(comparison.researchOnly)
    #expect(!comparison.mayAuthorizeEntry)

    let crossedIdentity = ShadowMarketDataComparison.compare(
        shadowPoint(standard, "standard-feed", 100, 1.1), shadowPoint(otc, "otc-feed", 100, 1.1),
        previousLHS: shadowPoint(otc, "standard-feed", 99, 1.0),
        previousRHS: shadowPoint(otc, "otc-feed", 99, 1.0),
        at: Date(timeIntervalSince1970: 100), maximumTimestampSkew: 1)
    #expect(crossedIdentity.status == .identityMismatch)
}

@Test func comparisonRejectsOfflineMissingAndStaleObservations() {
    let id = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let now = 1_700_000_100.0
    let freshA = shadowPoint(id, "a", now - 1, 1.2)
    let freshPrevA = shadowPoint(id, "a", now - 2, 1.1)
    let freshB = shadowPoint(otc, "b", now - 1, 1.3)
    let freshPrevB = shadowPoint(otc, "b", now - 2, 1.2)
    let absent = ShadowMarketDataComparison.compare(nil, freshB, previousLHS: freshPrevA,
        previousRHS: freshPrevB, at: Date(timeIntervalSince1970: now), maximumTimestampSkew: 1)
    #expect(absent.status == .unavailable)
    let stale = ShadowMarketDataComparison.compare(shadowPoint(id, "a", now - 60, 1.2), freshB,
        previousLHS: freshPrevA, previousRHS: freshPrevB, at: Date(timeIntervalSince1970: now),
        maximumTimestampSkew: 1, maximumAge: 10)
    #expect(stale.status == .invalid)
}

@Test func comparisonHonorsTimestampSkewAndDirectionWithoutSignals() {
    let id = ShadowMarketDataFixtures.standardEURUSD
    let otc = ShadowMarketDataFixtures.pocketOptionEURUSDOTC
    let now = 1_700_000_100.0
    let compared = ShadowMarketDataComparison.compare(
        shadowPoint(id, "a", now - 1, 1.2), shadowPoint(otc, "b", now - 4, 1.3),
        previousLHS: shadowPoint(id, "a", now - 2, 1.1), previousRHS: shadowPoint(otc, "b", now - 5, 1.2),
        at: Date(timeIntervalSince1970: now), maximumTimestampSkew: 1)
    #expect(compared.status == .excessiveTimestampSkew)

    let aligned = ShadowMarketDataComparison.compare(
        shadowPoint(id, "a", now - 1, 1.2), shadowPoint(otc, "b", now - 1.5, 1.3),
        previousLHS: shadowPoint(id, "a", now - 2, 1.1), previousRHS: shadowPoint(otc, "b", now - 2.5, 1.2),
        at: Date(timeIntervalSince1970: now), maximumTimestampSkew: 1)
    #expect(aligned.status == .comparable)
    #expect(aligned.directionAgreement == true)
    #expect(aligned.timestampSkewSeconds == 0.5)
    #expect(abs((aligned.priceDisplacement ?? .infinity) - 0.1) < 1e-12)
    #expect(!aligned.explanation.localizedCaseInsensitiveContains("trade signal"))

    let misalignedPrevious = ShadowMarketDataComparison.compare(
        shadowPoint(id, "a", now - 1, 1.2), shadowPoint(otc, "b", now - 1, 1.3),
        previousLHS: shadowPoint(id, "a", now - 8, 1.1),
        previousRHS: shadowPoint(otc, "b", now - 2, 1.2),
        at: Date(timeIntervalSince1970: now), maximumTimestampSkew: 1)
    #expect(misalignedPrevious.status == .excessiveTimestampSkew)

    let reversed = ShadowMarketDataComparison.compare(
        shadowPoint(id, "a", now - 1, 1.2), shadowPoint(otc, "b", now - 1, 1.3),
        previousLHS: shadowPoint(id, "a", now - 2, 1.1),
        previousRHS: shadowPoint(otc, "b", now - 0.5, 1.2),
        at: Date(timeIntervalSince1970: now), maximumTimestampSkew: 1)
    #expect(reversed.status == .invalid)
}

@Test func syntheticFixturesRemainDocumentationOnly() {
    for point in ShadowMarketDataFixtures.points() {
        #expect(point.status == .syntheticDocumentationOnly)
        #expect(point.provenance.localizedCaseInsensitiveContains("synthetic"))
        #expect(point.status != .verified)
    }
}
