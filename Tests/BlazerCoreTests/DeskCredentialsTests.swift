import Foundation
import BlazerCore
import Testing
@testable import LightningDesk

private func testSession(_ environment: OandaEnvironment) -> OandaSession {
    OandaSession(token: "fixture-only", accountId: "fixture-account", environment: environment)
}

@Test func macCredentialResolutionPrefersCanonicalLiveAndSkipsLegacyRead() {
    var canonicalReads = 0
    var legacyReads = 0

    let result = DeskCredentials.resolveMacCredential(
        canonicalRead: {
            canonicalReads += 1
            return .ready(testSession(.live))
        },
        legacyRead: {
            legacyReads += 1
            return .ready(testSession(.live))
        })

    if case .ready(let session) = result {
        #expect(session.environment == .live)
    } else {
        Issue.record("Expected canonical Live session")
    }
    #expect(canonicalReads == 1)
    #expect(legacyReads == 0)
}

@Test func macCredentialResolutionFallsBackToLegacyOnlyWhenCanonicalIsMissing() {
    var legacyReads = 0
    let result = DeskCredentials.resolveMacCredential(
        canonicalRead: { .missing },
        legacyRead: {
            legacyReads += 1
            return .ready(testSession(.live))
        })

    if case .ready(let session) = result {
        #expect(session.environment == .live)
    } else {
        Issue.record("Expected legacy Live session")
    }
    #expect(legacyReads == 1)
}

@Test func macCredentialResolutionDoesNotTryAnotherServiceWhenCanonicalIsLocked() {
    var legacyReads = 0
    let result = DeskCredentials.resolveMacCredential(
        canonicalRead: { .locked },
        legacyRead: {
            legacyReads += 1
            return .ready(testSession(.live))
        })

    if case .locked = result {} else {
        Issue.record("Expected locked state")
    }
    #expect(legacyReads == 0)
}

@Test func macCredentialResolutionDoesNotMaskCanonicalReadErrorsAsMissing() {
    var legacyReads = 0
    let result = DeskCredentials.resolveMacCredential(
        canonicalRead: { .invalid("keychain_read_failed") },
        legacyRead: {
            legacyReads += 1
            return .ready(testSession(.live))
        })

    if case .invalid(let message) = result {
        #expect(message == "keychain_read_failed")
    } else {
        Issue.record("Expected the canonical Keychain error to remain visible")
    }
    #expect(legacyReads == 0)
}

@Test func macCredentialResolutionRejectsPracticeSessionsFromEitherService() {
    var fallbackReads = 0
    let canonicalPractice = DeskCredentials.resolveMacCredential(
        canonicalRead: { .ready(testSession(.practice)) },
        legacyRead: {
            fallbackReads += 1
            return .ready(testSession(.live))
        })
    if case .missing = canonicalPractice {} else {
        Issue.record("Canonical Practice session must not enter the Live desk")
    }
    #expect(fallbackReads == 0)

    let legacyPractice = DeskCredentials.resolveMacCredential(
        canonicalRead: { .missing },
        legacyRead: { .ready(testSession(.practice)) })
    if case .missing = legacyPractice {} else {
        Issue.record("Legacy Practice session must not enter the Live desk")
    }
}
