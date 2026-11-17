import CryptoKit
import Foundation

public enum StrategySwiftPMMetadataPolicy {
    /// The staged package invokes the SwiftPM CLI directly. Xcode workspace
    /// metadata does not configure that command; SwiftPM's configuration folder
    /// can, so it must remain empty and the accepted tree is deliberately narrow.
    public static func validationErrors(root: URL) -> [String] {
        let fileManager = FileManager.default
        let metadata = root.appendingPathComponent(".swiftpm", isDirectory: true)
        if isSymbolicLink(metadata) { return ["swiftpm_metadata_symlink_unsupported"] }
        guard fileManager.fileExists(atPath: metadata.path) else { return [] }
        guard isRealDirectory(metadata) else { return ["swiftpm_metadata_root_invalid"] }
        guard let children = try? fileManager.contentsOfDirectory(at: metadata,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: []) else {
            return ["swiftpm_metadata_unreadable"]
        }
        var errors: [String] = []
        if let enumerator = fileManager.enumerator(at: metadata, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
            for case let entry as URL in enumerator {
                if isSymbolicLink(entry) { errors.append("swiftpm_metadata_symlink_unsupported") }
                if entry.lastPathComponent == ".DS_Store",
                   entry.deletingLastPathComponent().standardizedFileURL != metadata.standardizedFileURL {
                    errors.append("swiftpm_metadata_ds_store_nested")
                }
            }
        }
        for child in children {
            guard !isSymbolicLink(child) else {
                errors.append("swiftpm_metadata_symlink_unsupported")
                continue
            }
            switch child.lastPathComponent {
            case ".DS_Store":
                guard isRealRegularFile(child) else {
                    errors.append("swiftpm_metadata_ds_store_invalid")
                    continue
                }
            case "configuration":
                guard isRealDirectory(child) else {
                    errors.append("swiftpm_configuration_root_invalid")
                    continue
                }
                let entries = (try? fileManager.contentsOfDirectory(at: child,
                    includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])) ?? []
                if !entries.isEmpty { errors.append("swiftpm_configuration_must_be_empty") }
            case "xcode":
                guard isRealDirectory(child), let xcodeChildren = try? fileManager.contentsOfDirectory(at: child,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: []) else {
                    errors.append("swiftpm_xcode_metadata_invalid")
                    continue
                }
                for xcodeChild in xcodeChildren {
                    guard !isSymbolicLink(xcodeChild), isRealDirectory(xcodeChild) else {
                        errors.append("swiftpm_xcode_metadata_unknown_entry")
                        continue
                    }
                    if xcodeChild.lastPathComponent == "xcuserdata" { continue }
                    guard xcodeChild.lastPathComponent == "package.xcworkspace" else {
                        errors.append("swiftpm_xcode_metadata_unknown_entry")
                        continue
                    }
                    guard let workspaceChildren = try? fileManager.contentsOfDirectory(at: xcodeChild,
                        includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: []) else {
                        errors.append("swiftpm_xcode_workspace_unreadable")
                        continue
                    }
                    for workspaceChild in workspaceChildren {
                        let name = workspaceChild.lastPathComponent
                        let accepted = name == "contents.xcworkspacedata" && !isSymbolicLink(workspaceChild)
                            || name == "xcuserdata" && !isSymbolicLink(workspaceChild) && isRealDirectory(workspaceChild)
                        if !accepted { errors.append("swiftpm_xcode_workspace_unknown_entry") }
                    }
                }
            default:
                errors.append("swiftpm_metadata_unknown_entry")
            }
        }
        return Array(Set(errors)).sorted()
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        !isSymbolicLink(url) && ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
    }

    private static func isRealRegularFile(_ url: URL) -> Bool {
        guard !isSymbolicLink(url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { return false }
        return values.isRegularFile == true && values.isDirectory != true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

public struct StrategyBuildInputDigest: Codable, Sendable, Equatable, Hashable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256.lowercased()
    }
}

public enum StrategySignerTrust {
    /// A bundle or manifest never supplies the trust anchor. An empty or
    /// malformed owner pin cannot accept any signer.
    public static func accepts(actualSignerSHA1: String, ownerPinnedSHA1: String) -> Bool {
        StrategyBuildInputManifest.isSHA1(ownerPinnedSHA1)
            && actualSignerSHA1.uppercased() == ownerPinnedSHA1.uppercased()
    }
}

/// Required, typed classes for the shared build context. Unknown classes fail
/// decoding, while missing classes fail manifest validation.
public enum StrategyBuildInputRole: String, Codable, CaseIterable, Sendable, Equatable {
    case packageManifest
    case packageResolution
    case packageResolutionAbsent
    case trustedPackager
    case manifestGenerator
    case macroPluginInventory
    case generatedInputInventory
    case compilerToolchain
    case compilerPath
    case xcodeIdentity
    case xcodeCodeSignature
    case sdkIdentity
    case sdkPath
    case sdkSettingsDigest
    case bundleIdentifier
    case target
    case configuration
    case architecture
    case deploymentTarget
    case effectiveBuildFlags
}

public struct StrategyGlobalBuildInput: Codable, Sendable, Equatable, Hashable {
    public let role: StrategyBuildInputRole
    public let key: String
    public let path: String?
    public let value: String?
    public let sha256: String

    public init(role: StrategyBuildInputRole, key: String, path: String, sha256: String) {
        self.role = role; self.key = key; self.path = path; self.value = nil
        self.sha256 = sha256.lowercased()
    }

    public init(role: StrategyBuildInputRole, key: String, value: String) {
        self.role = role; self.key = key; self.path = nil; self.value = value
        self.sha256 = StrategyBuildInputManifest.sha256(Data(value.utf8))
    }
}

/// Embedded before code signing. It deliberately has no self-referential binary
/// digest; the complete app signature seals the executable and this manifest.
public struct StrategyBuildInputManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let bundleIdentifier: String
    public let ownerSignerSHA1: String
    public let toolchain: String
    public let buildFlags: [String]
    public let packageResolvedPresent: Bool
    public let inputDigests: [StrategyBuildInputDigest]
    public let sourceClosurePathsByProfile: [String: [String]]
    public let globalBuildInputs: [StrategyGlobalBuildInput]

    public init(schemaVersion: Int = 2, bundleIdentifier: String,
                ownerSignerSHA1: String, toolchain: String,
                buildFlags: [String], packageResolvedPresent: Bool,
                inputDigests: [StrategyBuildInputDigest],
                sourceClosurePathsByProfile: [String: [String]],
                globalBuildInputs: [StrategyGlobalBuildInput] = []) {
        self.schemaVersion = schemaVersion
        self.bundleIdentifier = bundleIdentifier
        self.ownerSignerSHA1 = ownerSignerSHA1.uppercased()
        self.toolchain = toolchain
        self.buildFlags = buildFlags
        self.packageResolvedPresent = packageResolvedPresent
        self.inputDigests = inputDigests.sorted { $0.path < $1.path }
        self.sourceClosurePathsByProfile = sourceClosurePathsByProfile.mapValues { $0.sorted() }
        self.globalBuildInputs = globalBuildInputs
    }

    public func validationErrors(expectedBundleIdentifier: String,
                                 actualSignerSHA1: String,
                                 expectedSignerSHA1: String) -> [String] {
        var errors: [String] = []
        if schemaVersion != 2 { errors.append("build_manifest_schema_unsupported") }
        if bundleIdentifier != expectedBundleIdentifier { errors.append("build_manifest_bundle_mismatch") }
        let signer = ownerSignerSHA1.uppercased()
        if !Self.isSHA1(signer) || signer != actualSignerSHA1.uppercased()
            || signer != expectedSignerSHA1.uppercased() {
            errors.append("build_manifest_signer_mismatch")
        }
        if toolchain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("build_manifest_toolchain_missing")
        }
        if !buildFlags.contains("-c") || !buildFlags.contains("release")
            || !buildFlags.contains("--target") || !buildFlags.contains("BlazerOSMac")
            || !buildFlags.contains("--triple") {
            errors.append("build_manifest_release_flags_invalid")
        }
        let paths = inputDigests.map(\.path)
        if Set(paths).count != paths.count { errors.append("build_manifest_duplicate_input") }
        if !paths.contains("Package.swift") { errors.append("build_manifest_package_missing") }
        for input in inputDigests {
            if !Self.isSafeRelativePath(input.path) { errors.append("build_manifest_input_path_invalid") }
            if !Self.isSHA256(input.sha256) { errors.append("build_manifest_input_digest_invalid") }
        }
        let inputPaths = Set(paths)
        for (profileID, closure) in sourceClosurePathsByProfile {
            if profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("build_manifest_profile_id_missing")
            }
            if closure.isEmpty || Set(closure).count != closure.count {
                errors.append("build_manifest_source_closure_invalid")
            }
            for path in closure where !inputPaths.contains(path) {
                errors.append("build_manifest_source_closure_unhashed")
            }
        }
        errors.append(contentsOf: globalInputValidationErrors())
        return errors
    }

    public func globalBuildInputDigest() -> String? {
        guard globalInputValidationErrors().isEmpty else { return nil }
        let canonicalItems = globalBuildInputs.sorted {
            if $0.role.rawValue != $1.role.rawValue { return $0.role.rawValue < $1.role.rawValue }
            if $0.key != $1.key { return $0.key < $1.key }
            if ($0.path ?? "") != ($1.path ?? "") { return ($0.path ?? "") < ($1.path ?? "") }
            return ($0.value ?? "") < ($1.value ?? "")
        }.map {
            CanonicalGlobalBuildInput(role: $0.role.rawValue, key: $0.key,
                path: $0.path, value: $0.value, sha256: $0.sha256.lowercased())
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let encoded = try? encoder.encode(canonicalItems) else { return nil }
        var bytes = Data("BLAZEROS_GLOBAL_BUILD_INPUT_ENVELOPE_V2\0".utf8)
        bytes.append(encoded)
        return Self.sha256(bytes)
    }

    public func promotionInputDigest(forProfile profileID: String) -> String? {
        guard let sourceDigest = sourceClosureSHA256(forProfile: profileID),
              let globalDigest = globalBuildInputDigest() else { return nil }
        var bytes = Data("BLAZEROS_PROMOTION_INPUT_V2\0".utf8)
        bytes.append(Data(profileID.utf8)); bytes.append(0)
        bytes.append(Data(sourceDigest.utf8)); bytes.append(0)
        bytes.append(Data(globalDigest.utf8))
        return Self.sha256(bytes)
    }

    private func globalInputValidationErrors() -> [String] {
        var errors: [String] = []
        let inputByNormalizedPath = Dictionary(inputDigests.compactMap { input -> (String, StrategyBuildInputDigest)? in
            guard let normalized = Self.normalizedRelativePath(input.path) else { return nil }
            return (normalized, input)
        }, uniquingKeysWith: { first, _ in first })
        let inputPaths = inputDigests.compactMap { Self.normalizedRelativePath($0.path) }
        if Set(inputPaths).count != inputPaths.count { errors.append("build_manifest_duplicate_normalized_input") }

        let keys = globalBuildInputs.map { "\($0.role.rawValue)\0\($0.key)" }
        if Set(keys).count != keys.count { errors.append("build_manifest_duplicate_global_role_key") }
        let globalPaths = globalBuildInputs.compactMap { input in input.path.flatMap(Self.normalizedRelativePath) }
        if Set(globalPaths).count != globalPaths.count { errors.append("build_manifest_duplicate_global_path") }

        for input in globalBuildInputs {
            guard Self.isSafeKey(input.key) else { errors.append("build_manifest_global_key_invalid"); continue }
            guard Self.isSHA256(input.sha256) else { errors.append("build_manifest_global_digest_invalid"); continue }
            switch (input.path, input.value) {
            case (.some(let path), .none):
                guard let normalized = Self.normalizedRelativePath(path) else {
                    errors.append("build_manifest_global_path_invalid"); continue
                }
                guard let fileInput = inputByNormalizedPath[normalized],
                      fileInput.sha256.lowercased() == input.sha256.lowercased() else {
                    errors.append("build_manifest_global_file_digest_mismatch")
                    continue
                }
            case (.none, .some(let value)):
                if Self.sha256(Data(value.utf8)) != input.sha256.lowercased() {
                    errors.append("build_manifest_global_value_digest_mismatch")
                }
            default:
                errors.append("build_manifest_global_input_shape_invalid")
            }
        }

        let counts = Dictionary(grouping: globalBuildInputs, by: \.role).mapValues(\.count)
        let required: [StrategyBuildInputRole] = [
            .packageManifest, .trustedPackager, .manifestGenerator, .macroPluginInventory,
            .generatedInputInventory, .compilerToolchain, .sdkIdentity, .bundleIdentifier,
            .compilerPath, .xcodeIdentity, .xcodeCodeSignature, .sdkPath, .sdkSettingsDigest,
            .target, .configuration, .architecture, .deploymentTarget, .effectiveBuildFlags
        ]
        for role in required where counts[role] != 1 { errors.append("build_manifest_required_global_role_missing_or_duplicate") }
        let resolutionCount = (counts[.packageResolution] ?? 0) + (counts[.packageResolutionAbsent] ?? 0)
        if resolutionCount != 1 { errors.append("build_manifest_package_resolution_state_invalid") }
        if (counts[.packageResolution] ?? 0) > 1 || (counts[.packageResolutionAbsent] ?? 0) > 1 {
            errors.append("build_manifest_package_resolution_state_invalid")
        }

        func single(_ role: StrategyBuildInputRole) -> StrategyGlobalBuildInput? {
            let values = globalBuildInputs.filter { $0.role == role }
            return values.count == 1 ? values[0] : nil
        }
        if single(.packageManifest)?.path != "Package.swift" { errors.append("build_manifest_package_manifest_role_invalid") }
        if single(.trustedPackager)?.path != "scripts/package-mac-app-staged.sh" {
            errors.append("build_manifest_packager_role_invalid")
        }
        if single(.manifestGenerator)?.path != "Sources/StrategyManifestTool/main.swift" {
            errors.append("build_manifest_generator_role_invalid")
        }
        if let absent = single(.packageResolutionAbsent), absent.value != "absent" {
            errors.append("build_manifest_package_resolution_absence_invalid")
        }
        if let resolved = single(.packageResolution), resolved.path != "Package.resolved" {
            errors.append("build_manifest_package_resolution_path_invalid")
        }
        if packageResolvedPresent != (counts[.packageResolution] == 1) {
            errors.append("build_manifest_package_resolution_presence_mismatch")
        }
        if let bundle = single(.bundleIdentifier), bundle.value != bundleIdentifier {
            errors.append("build_manifest_bundle_input_mismatch")
        }
        if let target = single(.target), target.value != "BlazerOSMac" {
            errors.append("build_manifest_target_input_mismatch")
        }
        if let configuration = single(.configuration), configuration.value != "release" {
            errors.append("build_manifest_configuration_input_mismatch")
        }
        if let compiler = single(.compilerToolchain), compiler.value != toolchain {
            errors.append("build_manifest_toolchain_input_mismatch")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expectedFlags = (try? encoder.encode(buildFlags)).flatMap { String(data: $0, encoding: .utf8) }
        if single(.effectiveBuildFlags)?.value != expectedFlags {
            errors.append("build_manifest_effective_flags_mismatch")
        }
        for role in [StrategyBuildInputRole.compilerPath, .xcodeIdentity, .xcodeCodeSignature, .sdkIdentity, .sdkPath,
                     .sdkSettingsDigest, .architecture, .deploymentTarget,
                     .macroPluginInventory, .generatedInputInventory] {
            guard let input = single(role), let value = input.value, !value.isEmpty else {
                errors.append("build_manifest_required_global_value_missing")
                continue
            }
        }
        return errors.sorted()
    }

    private struct CanonicalGlobalBuildInput: Codable {
        let role: String
        let key: String
        let path: String?
        let value: String?
        let sha256: String
    }

    /// Confirms an implementation digest belongs to its exact source path and
    /// that path is part of this profile's declared dependency closure.
    public func sourceDigestMatches(_ expectedDigest: String, atPath path: String,
                                    forProfile profileID: String) -> Bool {
        guard Self.isSHA256(expectedDigest),
              let closure = sourceClosurePathsByProfile[profileID],
              closure.contains(path),
              let input = inputDigests.first(where: { $0.path == path }) else { return false }
        return input.sha256.lowercased() == expectedDigest.lowercased()
    }

    /// Domain-separated digest over every ordered path and file digest in one
    /// profile closure. Shared-helper edits therefore invalidate old evidence.
    public func sourceClosureSHA256(forProfile profileID: String) -> String? {
        guard let closure = sourceClosurePathsByProfile[profileID], !closure.isEmpty else { return nil }
        let digestByPath = Dictionary(inputDigests.map { ($0.path, $0.sha256.lowercased()) },
                                      uniquingKeysWith: { first, _ in first })
        let paths = closure.sorted()
        guard paths.allSatisfy({ Self.isSafeRelativePath($0) && Self.isSHA256(digestByPath[$0] ?? "") }) else {
            return nil
        }
        var canonical = Data("BLAZEROS_STRATEGY_SOURCE_CLOSURE_V1\0".utf8)
        for path in paths {
            canonical.append(Data(path.utf8))
            canonical.append(0)
            canonical.append(Data(digestByPath[path]!.utf8))
            canonical.append(10)
        }
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    public static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    public static func isSHA1(_ value: String) -> Bool {
        value.count == 40 && value.allSatisfy(\.isHexDigit)
    }

    public static func isSafeRelativePath(_ value: String) -> Bool {
        guard normalizedRelativePath(value) != nil else { return false }
        return true
    }

    private static func normalizedRelativePath(_ value: String) -> String? {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              value.precomposedStringWithCanonicalMapping == value,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ $0 != ".." && $0 != "." && !$0.isEmpty }) else { return nil }
        return components.joined(separator: "/").lowercased()
    }

    private static func isSafeKey(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    fileprivate static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct StrategyPromotionEvidenceFile: Codable, Sendable, Equatable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256.lowercased()
    }
}

/// Package-level binding from a campaign-approved record to the exact source
/// dependency closure used by the build that embeds it.
public struct StrategyPromotionRecordBinding: Codable, Sendable, Equatable {
    public let record: StrategyPromotionRecord
    public let promotionInputDigest: String

    public init(record: StrategyPromotionRecord, promotionInputDigest: String) {
        self.record = record
        self.promotionInputDigest = promotionInputDigest.lowercased()
    }
}

/// The campaign artifact itself carries the closure it measured. Rewrapping an
/// old campaign under new source hashes therefore cannot make it current.
public struct StrategyPromotionCampaignEvidence: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let profileID: String
    public let profileVersion: String
    public let campaignID: String
    public let promotionInputDigest: String
    public let heldOutArtifactSHA256: String
    public let costModelSHA256: String
    public let campaignCompletion: StrategyCampaignCompletion
    public let campaignVerdict: StrategyCampaignVerdict
    public let preregistered: Bool
    public let protectedHoldout: Bool

    public init(profileID: String, profileVersion: String, campaignID: String,
                promotionInputDigest: String, heldOutArtifactSHA256: String,
                costModelSHA256: String, campaignCompletion: StrategyCampaignCompletion,
                campaignVerdict: StrategyCampaignVerdict, preregistered: Bool,
                protectedHoldout: Bool) {
        schemaVersion = 2
        self.profileID = profileID; self.profileVersion = profileVersion
        self.campaignID = campaignID; self.promotionInputDigest = promotionInputDigest.lowercased()
        self.heldOutArtifactSHA256 = heldOutArtifactSHA256.lowercased()
        self.costModelSHA256 = costModelSHA256.lowercased()
        self.campaignCompletion = campaignCompletion; self.campaignVerdict = campaignVerdict
        self.preregistered = preregistered; self.protectedHoldout = protectedHoldout
    }
}

/// Separate approval artifact repeats the closure and campaign identity. Its
/// digest must change when either the closure or campaign changes.
public struct StrategyPromotionOwnerApprovalEvidence: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let approvalID: String
    public let profileID: String
    public let profileVersion: String
    public let campaignID: String
    public let campaignManifestSHA256: String
    public let promotionInputDigest: String
    public let approved: Bool

    public init(approvalID: String, profileID: String, profileVersion: String,
                campaignID: String, campaignManifestSHA256: String,
                promotionInputDigest: String, approved: Bool) {
        schemaVersion = 2
        self.approvalID = approvalID; self.profileID = profileID
        self.profileVersion = profileVersion; self.campaignID = campaignID
        self.campaignManifestSHA256 = campaignManifestSHA256.lowercased()
        self.promotionInputDigest = promotionInputDigest.lowercased(); self.approved = approved
    }
}

/// Compact, code-signed runtime payload. Evidence bytes are stored as separate
/// resources and checked against these references before any record is returned.
public struct StrategyPromotionPackage: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let profiles: [StrategyResearchProfile]
    public let promotions: [StrategyPromotionRecordBinding]
    public let evidenceFiles: [StrategyPromotionEvidenceFile]

    public init(schemaVersion: Int = 2, profiles: [StrategyResearchProfile],
                promotions: [StrategyPromotionRecordBinding],
                evidenceFiles: [StrategyPromotionEvidenceFile]) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.promotions = promotions
        self.evidenceFiles = evidenceFiles.sorted { $0.path < $1.path }
    }

    public static let empty = StrategyPromotionPackage(profiles: [], promotions: [], evidenceFiles: [])

    public func validationErrors(evidenceDataByPath: [String: Data],
                                 promotionInputDigestByProfile: [String: String] = [:]) -> [String] {
        var errors: [String] = []
        if schemaVersion != 2 { errors.append("promotion_package_schema_unsupported") }
        if StrategyResearchRegistry.duplicateIdentityErrors(in: profiles).isEmpty == false {
            errors.append("promotion_package_duplicate_identity")
        }
        let evidencePaths = evidenceFiles.map(\.path)
        let normalizedEvidencePaths = evidencePaths.map { $0.lowercased() }
        if Set(normalizedEvidencePaths).count != normalizedEvidencePaths.count {
            errors.append("promotion_package_duplicate_evidence_path")
        }
        var evidenceDigests = Set<String>()
        for evidence in evidenceFiles {
            guard StrategyBuildInputManifest.isSafeRelativePath(evidence.path),
                  evidence.path.hasPrefix("evidence/") else {
                errors.append("promotion_package_evidence_path_invalid")
                continue
            }
            guard StrategyBuildInputManifest.isSHA256(evidence.sha256),
                  let data = evidenceDataByPath[evidence.path] else {
                errors.append("promotion_package_evidence_missing_or_digest_invalid")
                continue
            }
            let actual = Self.sha256(data)
            guard actual == evidence.sha256 else {
                errors.append("promotion_package_evidence_digest_mismatch")
                continue
            }
            evidenceDigests.insert(actual)
        }
        if promotions.isEmpty {
            if !profiles.isEmpty || !evidenceFiles.isEmpty || !evidenceDataByPath.isEmpty {
                errors.append("promotion_package_orphaned_data")
            }
            return errors.sorted()
        }
        if profiles.isEmpty { errors.append("promotion_package_profiles_missing") }
        if !evidenceDataByPath.keys.allSatisfy({ evidencePaths.contains($0) }) {
            errors.append("promotion_package_unreferenced_evidence_bytes")
        }
        for binding in promotions {
            let record = binding.record
            let matches = profiles.filter { $0.id == record.profileID && $0.version == record.profileVersion }
            guard matches.count == 1, let profile = matches.first else {
                errors.append("promotion_package_profile_missing_or_ambiguous")
                continue
            }
            errors.append(contentsOf: record.validationErrors(for: profile))
            let expectedInputDigest = promotionInputDigestByProfile[profile.id]?.lowercased()
            if !StrategyBuildInputManifest.isSHA256(binding.promotionInputDigest)
                || expectedInputDigest == nil || binding.promotionInputDigest != expectedInputDigest {
                errors.append("promotion_package_promotion_input_digest_mismatch")
            }
            let campaignValid: Bool
            if let campaignData = evidenceData(matching: record.campaignManifestSHA256,
                evidenceFiles: evidenceFiles, evidenceDataByPath: evidenceDataByPath),
                  let campaign = try? JSONDecoder().decode(StrategyPromotionCampaignEvidence.self,
                                                           from: campaignData),
                  campaign.schemaVersion == 2,
                  campaign.profileID == record.profileID,
                  campaign.profileVersion == record.profileVersion,
                  campaign.campaignID == record.campaignID,
                  campaign.promotionInputDigest == binding.promotionInputDigest,
                  campaign.heldOutArtifactSHA256 == record.heldOutArtifactSHA256,
                  campaign.costModelSHA256 == record.costModelSHA256,
                  campaign.campaignCompletion == record.campaignCompletion,
                  campaign.campaignVerdict == record.campaignVerdict,
                  campaign.preregistered == record.preregistered,
                  campaign.protectedHoldout == record.protectedHoldout {
                campaignValid = true
            } else {
                campaignValid = false
            }
            if !campaignValid { errors.append("promotion_package_campaign_evidence_mismatch") }

            let approvalValid: Bool
            if let approvalData = evidenceData(matching: record.ownerApprovalSHA256,
                evidenceFiles: evidenceFiles, evidenceDataByPath: evidenceDataByPath),
                  let approval = try? JSONDecoder().decode(StrategyPromotionOwnerApprovalEvidence.self,
                                                           from: approvalData),
                  approval.schemaVersion == 2,
                  approval.approvalID == record.ownerApprovalID,
                  approval.profileID == record.profileID,
                  approval.profileVersion == record.profileVersion,
                  approval.campaignID == record.campaignID,
                  approval.campaignManifestSHA256 == record.campaignManifestSHA256,
                  approval.promotionInputDigest == binding.promotionInputDigest,
                  approval.approved {
                approvalValid = true
            } else {
                approvalValid = false
            }
            if !approvalValid { errors.append("promotion_package_owner_approval_mismatch") }
            for digest in [record.campaignManifestSHA256, record.heldOutArtifactSHA256,
                           record.costModelSHA256, record.ownerApprovalSHA256]
                where !evidenceDigests.contains(digest.lowercased()) {
                errors.append("promotion_package_record_evidence_unverified")
            }
        }
        return errors.sorted()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func evidenceData(matching digest: String,
                              evidenceFiles: [StrategyPromotionEvidenceFile],
                              evidenceDataByPath: [String: Data]) -> Data? {
        let matches = evidenceFiles.filter { $0.sha256 == digest.lowercased() }
        guard matches.count == 1, let path = matches.first?.path else { return nil }
        return evidenceDataByPath[path]
    }
}
