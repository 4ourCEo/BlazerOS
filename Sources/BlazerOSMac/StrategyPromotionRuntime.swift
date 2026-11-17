import BlazerCore
import CryptoKit
import Foundation
import Security

struct VerifiedStrategyPromotionConfiguration {
    let profiles: [StrategyResearchProfile]
    let promotions: [StrategyPromotionRecord]
    /// True only after the signed bundle, source manifest, and profile package pass validation.
    let sourceAttestationVerified: Bool

    static let empty = Self(profiles: StrategyResearchRegistry.profiles, promotions: [],
                            sourceAttestationVerified: false)
}

/// Loads promotion records only from the signed app bundle. Missing files,
/// ad-hoc signatures, signer drift, malformed evidence, and stale source maps
/// all fall back to the compiled shadow/control registry with no promotions.
enum StrategyPromotionRuntime {
    static let bundleIdentifier = "com.blazer.BlazerOS"
    static let signerInfoKey = "BLAZER_OWNER_SIGNER_SHA1"
    static let manifestName = "StrategyBuildInputManifest"
    static let promotionsName = "StrategyPromotions"
    static let resourceDirectory = "StrategyPromotions"
    private static let evaluatorSourcePathByProfileID: [String: String] = [
        "LEGACY_V1": "Sources/BlazerCore/Research/scan-engine-control.js",
        "ORB_BREAK_RETEST": "Sources/BlazerCore/Research/ORBBreakRetestV1.swift",
        "CHOCH_FVG_FIB": "Sources/BlazerCore/Research/Candidate001.swift",
        "AUCTION_FAILURE": "Sources/BlazerCore/Research/Candidate002.swift"
    ]
    private static let adapterSourcePath = "Sources/BlazerCore/Research/AdaptiveOpportunityAdapters.swift"
    private static let selectorSourcePath = "Sources/BlazerCore/Research/LiveStrategyDecision.swift"

    static func load(from bundle: Bundle = .main) -> VerifiedStrategyPromotionConfiguration {
        let expectedSigner = OwnerSignerPin.certificateSHA1.uppercased()
        guard bundle.bundleIdentifier == bundleIdentifier,
              StrategyBuildInputManifest.isSHA1(expectedSigner),
              bundle.object(forInfoDictionaryKey: signerInfoKey) as? String == expectedSigner,
              let actualSigner = verifiedSignerSHA1(at: bundle.bundleURL),
              StrategySignerTrust.accepts(actualSignerSHA1: actualSigner,
                                          ownerPinnedSHA1: expectedSigner),
              let manifestURL = bundle.url(forResource: manifestName, withExtension: "json",
                                           subdirectory: resourceDirectory),
              let promotionURL = bundle.url(forResource: promotionsName, withExtension: "json",
                                             subdirectory: resourceDirectory),
              let manifestData = try? Data(contentsOf: manifestURL),
              let promotionData = try? Data(contentsOf: promotionURL),
              let manifest = try? JSONDecoder().decode(StrategyBuildInputManifest.self, from: manifestData),
              let package = try? JSONDecoder().decode(StrategyPromotionPackage.self, from: promotionData) else {
            return .empty
        }

        let manifestErrors = manifest.validationErrors(expectedBundleIdentifier: bundleIdentifier,
            actualSignerSHA1: actualSigner, expectedSignerSHA1: expectedSigner)
        guard manifestErrors.isEmpty else { return .empty }

        let evidenceRoot = bundle.resourceURL?.appendingPathComponent(resourceDirectory, isDirectory: true)
        guard let evidenceRoot else { return .empty }
        var evidenceData: [String: Data] = [:]
        for evidence in package.evidenceFiles {
            guard StrategyBuildInputManifest.isSafeRelativePath(evidence.path),
                  evidence.path.hasPrefix("evidence/") else { return .empty }
            let fileURL = evidenceRoot.appendingPathComponent(evidence.path).standardizedFileURL
            guard fileURL.path.hasPrefix(evidenceRoot.standardizedFileURL.path + "/"),
                  let data = try? Data(contentsOf: fileURL) else { return .empty }
            evidenceData[evidence.path] = data
        }
        let promotionInputDigests = Dictionary(package.profiles.compactMap { profile in
            manifest.promotionInputDigest(forProfile: profile.id).map { (profile.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        guard package.validationErrors(evidenceDataByPath: evidenceData,
            promotionInputDigestByProfile: promotionInputDigests).isEmpty else { return .empty }

        let registeredProfiles = StrategyResearchRegistry.profiles
        let promotedIDs = Set(package.profiles.map(\.id))
        guard promotedIDs.count == package.profiles.count else { return .empty }
        for profile in package.profiles {
            guard let registered = registeredProfiles.first(where: {
                $0.id == profile.id && $0.version == profile.version
            }),
            registered.acceptedCandidateIdentities == profile.acceptedCandidateIdentities,
            registered.family == profile.family,
            registered.sourceReferences == profile.sourceReferences,
            registered.status == .researchCandidate,
            profile.status == .researchCandidate,
            let expectedEvaluator = StrategyImplementationDigests.evaluatorCodeSHA256[profile.id],
            let evaluatorPath = evaluatorSourcePathByProfileID[profile.id],
            profile.evaluatorCodeSHA256 == expectedEvaluator,
            profile.adapterCodeSHA256 == StrategyImplementationDigests.adapterCodeSHA256,
            profile.selectorCodeSHA256 == StrategyImplementationDigests.selectorCodeSHA256,
            manifest.sourceDigestMatches(expectedEvaluator, atPath: evaluatorPath,
                                         forProfile: profile.id),
            manifest.sourceDigestMatches(StrategyImplementationDigests.adapterCodeSHA256,
                                         atPath: adapterSourcePath, forProfile: profile.id),
            manifest.sourceDigestMatches(StrategyImplementationDigests.selectorCodeSHA256,
                                         atPath: selectorSourcePath, forProfile: profile.id),
            profile.decisionRole == .liveSignal,
            !profile.mayAuthorizeOrder else {
                return .empty
            }
        }
        var mergedProfiles = registeredProfiles.filter { !promotedIDs.contains($0.id) }
        mergedProfiles.append(contentsOf: package.profiles)
        guard StrategyResearchRegistry.duplicateIdentityErrors(in: mergedProfiles).isEmpty else { return .empty }
        guard package.promotions.allSatisfy({ binding in
            package.profiles.contains { $0.id == binding.record.profileID && $0.version == binding.record.profileVersion }
        }) else { return .empty }

        return VerifiedStrategyPromotionConfiguration(profiles: mergedProfiles,
            promotions: package.promotions.map(\.record), sourceAttestationVerified: true)
    }

    private static func verifiedSignerSHA1(at bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }
        let verifyStatus = SecStaticCodeCheckValidity(staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), nil)
        guard verifyStatus == errSecSuccess else { return nil }
        var information: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard informationStatus == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == bundleIdentifier,
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leafCertificate = certificates.first else {
            return nil
        }
        let certificateData = SecCertificateCopyData(leafCertificate) as Data
        return Insecure.SHA1.hash(data: certificateData)
            .map { String(format: "%02x", $0) }.joined().uppercased()
    }
}
