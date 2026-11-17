import CryptoKit
import Foundation
import Testing
@testable import BlazerCore

@Suite("Strategy promotion package")
struct StrategyPromotionPackageTests {
    private let signer = String(repeating: "A", count: 40)

    @Test func swiftPMMetadataAllowsXcodeWorkspaceButRejectsBuildConfiguration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("swiftpm-metadata-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let metadata = root.appendingPathComponent(".swiftpm")
        let configuration = metadata.appendingPathComponent("configuration", isDirectory: true)
        let workspace = metadata.appendingPathComponent("xcode/package.xcworkspace", isDirectory: true)
        let xcodeUserData = metadata.appendingPathComponent("xcode/xcuserdata/thagreat.xcuserdatad/xcschemes", isDirectory: true)
        let userData = workspace.appendingPathComponent("xcuserdata/thagreat.xcuserdatad", isDirectory: true)
        try fileManager.createDirectory(at: configuration, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: xcodeUserData, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userData, withIntermediateDirectories: true)
        try Data("scheme state".utf8).write(to: xcodeUserData.appendingPathComponent("xcschememanagement.plist"))
        try Data("<Workspace version=\"1.0\"/>".utf8).write(to: workspace.appendingPathComponent("contents.xcworkspacedata"))
        try Data("ui state".utf8).write(to: userData.appendingPathComponent("UserInterfaceState.xcuserstate"))
        let dsStore = metadata.appendingPathComponent(".DS_Store")
        try Data("finder metadata".utf8).write(to: dsStore)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).isEmpty)
        try fileManager.removeItem(at: dsStore)
        let nestedDSStore = userData.appendingPathComponent(".DS_Store")
        try Data("nested finder metadata".utf8).write(to: nestedDSStore)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_metadata_ds_store_nested"))
        try fileManager.removeItem(at: nestedDSStore)
        try fileManager.createDirectory(at: dsStore, withIntermediateDirectories: false)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_metadata_ds_store_invalid"))
        try fileManager.removeItem(at: dsStore)
        try fileManager.createSymbolicLink(at: dsStore, withDestinationURL: workspace)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_metadata_symlink_unsupported"))
        try fileManager.removeItem(at: dsStore)

        try Data("{}".utf8).write(to: configuration.appendingPathComponent(".hidden-mirrors.json"))
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_configuration_must_be_empty"))
        try fileManager.removeItem(at: configuration.appendingPathComponent(".hidden-mirrors.json"))
        try fileManager.createDirectory(at: metadata.appendingPathComponent("unexpected"), withIntermediateDirectories: true)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_metadata_unknown_entry"))
        try fileManager.removeItem(at: metadata.appendingPathComponent("unexpected"))
        let workspaceState = userData.appendingPathComponent("UserInterfaceState.xcuserstate")
        try fileManager.removeItem(at: workspaceState)
        let schemeState = metadata.appendingPathComponent("xcode/xcuserdata/thagreat.xcuserdatad/xcschemes/xcschememanagement.plist")
        try fileManager.createSymbolicLink(at: workspaceState, withDestinationURL: schemeState)
        #expect(StrategySwiftPMMetadataPolicy.validationErrors(root: root).contains("swiftpm_metadata_symlink_unsupported"))
    }

    @Test func stagedPackagerMetadataPreflightAcceptsWorkspaceAndRejectsUnsafeEntries() throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("swiftpm-preflight-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("repo", isDirectory: true)
        try writeCurrentXcodeMetadataFixture(at: root)
        let metadata = root.appendingPathComponent(".swiftpm", isDirectory: true)
        let workspace = metadata.appendingPathComponent("xcode/package.xcworkspace", isDirectory: true)
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = sourceRoot.appendingPathComponent("scripts/package-mac-app-staged.sh")
        #expect(try runMetadataPreflight(script: script, root: root) == 0)

        let dsStore = metadata.appendingPathComponent(".DS_Store")
        try Data("finder metadata".utf8).write(to: dsStore)
        #expect(try runMetadataPreflight(script: script, root: root) == 0)
        try fileManager.removeItem(at: dsStore)
        let nestedDSStore = workspace.appendingPathComponent("xcuserdata/thagreat.xcuserdatad/.DS_Store")
        try Data("nested finder metadata".utf8).write(to: nestedDSStore)
        #expect(try runMetadataPreflight(script: script, root: root) != 0)
        try fileManager.removeItem(at: nestedDSStore)
        try fileManager.createDirectory(at: dsStore, withIntermediateDirectories: false)
        #expect(try runMetadataPreflight(script: script, root: root) != 0)
        try fileManager.removeItem(at: dsStore)
        try fileManager.createSymbolicLink(at: dsStore, withDestinationURL: workspace)
        #expect(try runMetadataPreflight(script: script, root: root) != 0)
        try fileManager.removeItem(at: dsStore)

        let configuration = metadata.appendingPathComponent("configuration", isDirectory: true)
        try fileManager.createDirectory(at: configuration, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: configuration.appendingPathComponent(".hidden.json"))
        #expect(try runMetadataPreflight(script: script, root: root) != 0)
        try fileManager.removeItem(at: configuration)
        try fileManager.createSymbolicLink(at: metadata.appendingPathComponent(".hidden-unknown"), withDestinationURL: workspace)
        #expect(try runMetadataPreflight(script: script, root: root) != 0)

        let symlinkKinds = ["root", "configuration", "xcode", "workspace", "workspace-file", "workspace-userdata", "xcode-userdata", "scheme-dir"]
        for kind in symlinkKinds {
            let caseRoot = temporary.appendingPathComponent("symlink-\(kind)/repo", isDirectory: true)
            try writeCurrentXcodeMetadataFixture(at: caseRoot)
            let caseMetadata = caseRoot.appendingPathComponent(".swiftpm", isDirectory: true)
            let caseWorkspace = caseMetadata.appendingPathComponent("xcode/package.xcworkspace", isDirectory: true)
            let xcodeUserData = caseMetadata.appendingPathComponent("xcode/xcuserdata", isDirectory: true)
            let schemeDirectory = xcodeUserData.appendingPathComponent("thagreat.xcuserdatad/xcschemes", isDirectory: true)
            let target = schemeDirectory.appendingPathComponent("xcschememanagement.plist")
            switch kind {
            case "root":
                let moved = temporary.appendingPathComponent("symlink-root/metadata-real", isDirectory: true)
                try fileManager.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: caseMetadata, to: moved)
                try fileManager.createSymbolicLink(at: caseMetadata, withDestinationURL: moved)
            case "configuration":
                let link = caseMetadata.appendingPathComponent("configuration", isDirectory: true)
                try fileManager.removeItem(at: link)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: caseWorkspace)
            case "xcode":
                let link = caseMetadata.appendingPathComponent("xcode", isDirectory: true)
                let moved = temporary.appendingPathComponent("symlink-xcode/xcode-real", isDirectory: true)
                try fileManager.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: link, to: moved)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: moved)
            case "workspace":
                let moved = temporary.appendingPathComponent("symlink-workspace/workspace-real", isDirectory: true)
                try fileManager.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: caseWorkspace, to: moved)
                try fileManager.createSymbolicLink(at: caseWorkspace, withDestinationURL: moved)
            case "workspace-file":
                let file = caseWorkspace.appendingPathComponent("contents.xcworkspacedata")
                try fileManager.removeItem(at: file)
                try fileManager.createSymbolicLink(at: file, withDestinationURL: target)
            case "workspace-userdata":
                let link = caseWorkspace.appendingPathComponent("xcuserdata", isDirectory: true)
                try fileManager.removeItem(at: link)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: xcodeUserData)
            case "scheme-dir":
                let link = schemeDirectory
                let targetDirectory = caseWorkspace.appendingPathComponent("xcuserdata/thagreat.xcuserdatad", isDirectory: true)
                try fileManager.removeItem(at: link)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: targetDirectory)
            default:
                let link = xcodeUserData
                let moved = temporary.appendingPathComponent("symlink-xcode-userdata/xcuserdata-real", isDirectory: true)
                try fileManager.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: link, to: moved)
                try fileManager.createSymbolicLink(at: link, withDestinationURL: moved)
            }
            #expect(try runMetadataPreflight(script: script, root: caseRoot) != 0, "accepted symlink layer: \(kind)")
        }
    }

    private func writeCurrentXcodeMetadataFixture(at root: URL) throws {
        let fileManager = FileManager.default
        let metadata = root.appendingPathComponent(".swiftpm", isDirectory: true)
        let configuration = metadata.appendingPathComponent("configuration", isDirectory: true)
        let workspace = metadata.appendingPathComponent("xcode/package.xcworkspace", isDirectory: true)
        let xcodeSchemes = metadata.appendingPathComponent("xcode/xcuserdata/thagreat.xcuserdatad/xcschemes", isDirectory: true)
        let userData = workspace.appendingPathComponent("xcuserdata/thagreat.xcuserdatad", isDirectory: true)
        try fileManager.createDirectory(at: configuration, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: xcodeSchemes, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userData, withIntermediateDirectories: true)
        try Data("<Workspace version=\"1.0\"/>".utf8).write(to: workspace.appendingPathComponent("contents.xcworkspacedata"))
        try Data("scheme".utf8).write(to: xcodeSchemes.appendingPathComponent("xcschememanagement.plist"))
        try Data("window".utf8).write(to: userData.appendingPathComponent("UserInterfaceState.xcuserstate"))
    }

    private func runMetadataPreflight(script: URL, root: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--test-metadata-preflight", root.path]
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func signerTrustRequiresSeparateNonEmptyOwnerPin() {
        let arbitrarySigner = String(repeating: "A", count: 40)
        let differentOwnerPin = String(repeating: "B", count: 40)
        #expect(!StrategySignerTrust.accepts(actualSignerSHA1: arbitrarySigner, ownerPinnedSHA1: ""))
        #expect(!StrategySignerTrust.accepts(actualSignerSHA1: arbitrarySigner,
            ownerPinnedSHA1: differentOwnerPin))
        #expect(StrategySignerTrust.accepts(actualSignerSHA1: arbitrarySigner,
            ownerPinnedSHA1: arbitrarySigner.lowercased()))
    }

    @Test func emptyProductionPackageIsValidAndContainsNoAuthority() {
        let errors = StrategyPromotionPackage.empty.validationErrors(evidenceDataByPath: [:])
        #expect(errors.isEmpty)
        #expect(StrategyResearchRegistry.productionPromotionRecords.isEmpty)
        #expect(StrategyResearchRegistry.profiles.allSatisfy { !$0.mayAuthorizeOrder && $0.decisionRole != .liveSignal })
    }

    @Test func buildManifestRequiresPinnedSignerPackageInputsAndCompleteClosures() {
        let manifest = buildManifest()
        #expect(manifest.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: signer, expectedSignerSHA1: signer).isEmpty)
        let evaluatorPath = "Sources/BlazerCore/Research/Fixture.swift"
        let helperPath = "Sources/BlazerCore/V3DomainContracts.swift"
        #expect(manifest.sourceDigestMatches(digest(evaluatorPath), atPath: evaluatorPath,
            forProfile: "TEST_PROFILE"))
        #expect(!manifest.sourceDigestMatches(digest(evaluatorPath), atPath: helperPath,
            forProfile: "TEST_PROFILE"))
        #expect(!manifest.sourceDigestMatches(digest("not-in-closure"), atPath: evaluatorPath,
            forProfile: "TEST_PROFILE"))
        #expect(!manifest.sourceDigestMatches(digest("anything"), atPath: evaluatorPath,
            forProfile: "MISSING"))
        let changedHelper = StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift 6", buildFlags: ManifestToolFlags.releaseMac,
            packageResolvedPresent: false,
            inputDigests: [input("Package.swift"), input(evaluatorPath),
                           StrategyBuildInputDigest(path: helperPath, sha256: digest("changed helper"))],
            sourceClosurePathsByProfile: ["TEST_PROFILE": [evaluatorPath, helperPath]])
        #expect(manifest.sourceClosureSHA256(forProfile: "TEST_PROFILE") !=
            changedHelper.sourceClosureSHA256(forProfile: "TEST_PROFILE"))
        #expect(manifest.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: String(repeating: "B", count: 40), expectedSignerSHA1: signer)
            .contains("build_manifest_signer_mismatch"))
        let missingPackage = StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift", buildFlags: ManifestToolFlags.releaseMac,
            packageResolvedPresent: false,
            inputDigests: [input("Sources/BlazerCore/Research/A.swift")],
            sourceClosurePathsByProfile: ["TEST": ["Sources/BlazerCore/Research/A.swift"]])
        #expect(missingPackage.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: signer, expectedSignerSHA1: signer).contains("build_manifest_package_missing"))
        let unhashedClosure = StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift", buildFlags: ManifestToolFlags.releaseMac,
            packageResolvedPresent: false,
            inputDigests: [input("Package.swift")],
            sourceClosurePathsByProfile: ["TEST": ["Sources/BlazerCore/Missing.swift"]])
        #expect(unhashedClosure.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: signer, expectedSignerSHA1: signer).contains("build_manifest_source_closure_unhashed"))
    }

    @Test func buildManifestRejectsUnsafePathsDuplicateInputsAndUnsupportedFlags() {
        let unsafe = StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift", buildFlags: ["debug"],
            packageResolvedPresent: false,
            inputDigests: [input("Package.swift"), input("../outside.swift")],
            sourceClosurePathsByProfile: ["TEST": ["../outside.swift"]])
        let errors = unsafe.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: signer, expectedSignerSHA1: signer)
        #expect(errors.contains("build_manifest_release_flags_invalid"))
        #expect(errors.contains("build_manifest_input_path_invalid"))
        let duplicate = StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift", buildFlags: ManifestToolFlags.releaseMac,
            packageResolvedPresent: false,
            inputDigests: [input("Package.swift"), input("Package.swift")],
            sourceClosurePathsByProfile: [:])
        #expect(duplicate.validationErrors(expectedBundleIdentifier: "com.blazer.BlazerOS",
            actualSignerSHA1: signer, expectedSignerSHA1: signer).contains("build_manifest_duplicate_input"))
    }

    @Test func globalBuildEnvelopeBindsCriticalInputsAndRejectsMalformedRoles() throws {
        let manifest = buildManifest()
        let baseline = manifest.promotionInputDigest(forProfile: "TEST_PROFILE")!
        for role in [StrategyBuildInputRole.compilerToolchain, .compilerPath, .xcodeIdentity, .sdkIdentity,
                     .xcodeCodeSignature, .sdkPath, .sdkSettingsDigest, .effectiveBuildFlags, .architecture,
                     .deploymentTarget, .macroPluginInventory, .generatedInputInventory] {
            let changed = manifest.globalBuildInputs.map { item in
                item.role == role
                    ? StrategyGlobalBuildInput(role: item.role, key: item.key, value: (item.value ?? "") + " changed")
                    : item
            }
            let variant = StrategyBuildInputManifest(bundleIdentifier: manifest.bundleIdentifier,
                ownerSignerSHA1: signer, toolchain: manifest.toolchain, buildFlags: manifest.buildFlags,
                packageResolvedPresent: manifest.packageResolvedPresent, inputDigests: manifest.inputDigests,
                sourceClosurePathsByProfile: manifest.sourceClosurePathsByProfile, globalBuildInputs: changed)
            #expect(variant.globalBuildInputDigest() != manifest.globalBuildInputDigest(), "role \(role)")
            #expect(variant.promotionInputDigest(forProfile: "TEST_PROFILE") != baseline)
        }
        let packageRoleMutated = manifest.globalBuildInputs.map { item in
            item.role == .packageManifest
                ? StrategyGlobalBuildInput(role: item.role, key: item.key, path: item.path!, sha256: digest("tampered package"))
                : item
        }
        let invalid = StrategyBuildInputManifest(bundleIdentifier: manifest.bundleIdentifier,
            ownerSignerSHA1: signer, toolchain: manifest.toolchain, buildFlags: manifest.buildFlags,
            packageResolvedPresent: false, inputDigests: manifest.inputDigests,
            sourceClosurePathsByProfile: manifest.sourceClosurePathsByProfile, globalBuildInputs: packageRoleMutated)
        #expect(invalid.globalBuildInputDigest() == nil)
        #expect(invalid.validationErrors(expectedBundleIdentifier: manifest.bundleIdentifier,
            actualSignerSHA1: signer, expectedSignerSHA1: signer).contains("build_manifest_global_file_digest_mismatch"))

        let duplicatePath = manifest.globalBuildInputs + [
            .init(role: .packageManifest, key: "duplicate-package", path: "package.swift", sha256: digest("Package.swift"))
        ]
        let duplicate = StrategyBuildInputManifest(bundleIdentifier: manifest.bundleIdentifier,
            ownerSignerSHA1: signer, toolchain: manifest.toolchain, buildFlags: manifest.buildFlags,
            packageResolvedPresent: false, inputDigests: manifest.inputDigests,
            sourceClosurePathsByProfile: manifest.sourceClosurePathsByProfile, globalBuildInputs: duplicatePath)
        #expect(duplicate.validationErrors(expectedBundleIdentifier: manifest.bundleIdentifier,
            actualSignerSHA1: signer, expectedSignerSHA1: signer).contains("build_manifest_duplicate_global_path"))

        let encoded = try JSONSerialization.data(withJSONObject: ["role": "unknownRole", "key": "x", "value": "x", "sha256": digest("x")])
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StrategyGlobalBuildInput.self, from: encoded) }
    }

    @Test func stagedPackagerDropsCallerToolchainOverridesAndPathShadowing() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/package-mac-app-staged.sh")
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("blazeros-env-probe-\(UUID().uuidString)")
        let poisonBin = temporary.appendingPathComponent("poison-bin")
        try fileManager.createDirectory(at: poisonBin, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }
        let fakeSwift = poisonBin.appendingPathComponent("swift")
        try Data("#!/bin/sh\nprintf poison-swift-ran\n".utf8).write(to: fakeSwift)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSwift.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "--test-env-probe"]
        process.environment = [
            "PATH": poisonBin.path,
            "HOME": "/tmp/poison-home",
            "TMPDIR": "/tmp/poison-tmp",
            "DEVELOPER_DIR": "/poison/Developer",
            "TOOLCHAINS": "poison",
            "SDKROOT": "/poison/SDK",
            "MACOSX_DEPLOYMENT_TARGET": "99.0",
            "SWIFT_EXEC": "/poison/swift",
            "SWIFTFLAGS": "-DPOISON",
            "CFLAGS": "-DPOISON",
            "DYLD_INSERT_LIBRARIES": "/poison/inject.dylib",
            "BASH_ENV": "/dev/null"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        #expect(process.terminationStatus == 0)
        #expect(text.contains("PATH=/usr/bin:/bin:/usr/sbin:/sbin"))
        #expect(text.contains("MACOSX_DEPLOYMENT_TARGET=14.0"))
        #expect(text.contains("resolved-swift=/usr/bin/swift"))
        #expect(!text.contains("poison"))
        #expect(!text.contains("DYLD_INSERT_LIBRARIES"))
        #expect(!text.contains("SWIFT_EXEC"))
    }

    @Test func promotionMustBindActualEvidenceBytesAndProfile() throws {
        let profile = promotedProfile()
        let manifest = buildManifest()
        let promotionDigest = manifest.promotionInputDigest(forProfile: "TEST_PROFILE")!
        let heldOutData = Data("holdout".utf8)
        let costData = Data("costs".utf8)
        let campaignData = try encoded(StrategyPromotionCampaignEvidence(
            profileID: "TEST_PROFILE", profileVersion: "v1", campaignID: "campaign-1",
            promotionInputDigest: promotionDigest, heldOutArtifactSHA256: sha256(heldOutData),
            costModelSHA256: sha256(costData), campaignCompletion: .completed,
            campaignVerdict: .passed, preregistered: true, protectedHoldout: true))
        let campaignDigest = sha256(campaignData)
        let approvalData = try encoded(StrategyPromotionOwnerApprovalEvidence(
            approvalID: "approval-1", profileID: "TEST_PROFILE", profileVersion: "v1",
            campaignID: "campaign-1", campaignManifestSHA256: campaignDigest,
            promotionInputDigest: promotionDigest, approved: true))
        let files = [
            "evidence/campaign.json": campaignData,
            "evidence/holdout.json": heldOutData,
            "evidence/costs.json": costData,
            "evidence/approval.json": approvalData
        ]
        let refs = files.map { StrategyPromotionEvidenceFile(path: $0.key, sha256: sha256($0.value)) }
        let digests = Dictionary(uniqueKeysWithValues: refs.map { ($0.path, $0.sha256) })
        let record = promotion(digests: digests)
        let package = StrategyPromotionPackage(profiles: [profile],
            promotions: [StrategyPromotionRecordBinding(record: record, promotionInputDigest: promotionDigest)],
            evidenceFiles: refs)
        let closureMap = ["TEST_PROFILE": promotionDigest]
        #expect(package.validationErrors(evidenceDataByPath: files,
            promotionInputDigestByProfile: closureMap).isEmpty)
        #expect(package.validationErrors(evidenceDataByPath: files,
            promotionInputDigestByProfile: ["TEST_PROFILE": digest("changed shared helper")])
            .contains("promotion_package_promotion_input_digest_mismatch"))

        let changedHelper = "Sources/BlazerCore/V3DomainContracts.swift"
        let changedInputs = manifest.inputDigests.map { item in
            item.path == changedHelper ? StrategyBuildInputDigest(path: changedHelper, sha256: digest("changed helper")) : item
        }
        let changedManifest = StrategyBuildInputManifest(bundleIdentifier: manifest.bundleIdentifier,
            ownerSignerSHA1: signer, toolchain: manifest.toolchain, buildFlags: manifest.buildFlags,
            packageResolvedPresent: manifest.packageResolvedPresent, inputDigests: changedInputs,
            sourceClosurePathsByProfile: manifest.sourceClosurePathsByProfile,
            globalBuildInputs: manifest.globalBuildInputs)
        let changedClosureDigest = changedManifest.promotionInputDigest(forProfile: "TEST_PROFILE")!
        let staleCampaignPackage = StrategyPromotionPackage(profiles: [profile],
            promotions: [StrategyPromotionRecordBinding(record: record,
                promotionInputDigest: changedClosureDigest)], evidenceFiles: refs)
        let staleEvidenceErrors = staleCampaignPackage.validationErrors(evidenceDataByPath: files,
            promotionInputDigestByProfile: ["TEST_PROFILE": changedClosureDigest])
        #expect(staleEvidenceErrors.contains("promotion_package_campaign_evidence_mismatch"))
        #expect(staleEvidenceErrors.contains("promotion_package_owner_approval_mismatch"))

        var tampered = files
        tampered["evidence/campaign.json"] = Data("changed".utf8)
        #expect(package.validationErrors(evidenceDataByPath: tampered,
            promotionInputDigestByProfile: closureMap)
            .contains("promotion_package_evidence_digest_mismatch"))
        #expect(package.validationErrors(evidenceDataByPath: [:],
            promotionInputDigestByProfile: closureMap)
            .contains("promotion_package_evidence_missing_or_digest_invalid"))
    }

    @Test func promotedProfileMustMatchInstrumentConfigurationAndHaveNoOrderAuthority() {
        let noInstrument = StrategyResearchProfile(id: "TEST_PROFILE", version: "v1", family: "Test",
            status: .researchCandidate, sourceReferences: ["test"], mayAuthorizeOrder: false,
            decisionRole: .liveSignal, configurationSHA256ByInstrument: ["EUR/USD": digest("config")],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: digest("evaluator"), adapterCodeSHA256: digest("adapter"),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
        let invalid = StrategyPromotionRecord(id: "p", profileID: "TEST_PROFILE", profileVersion: "v1",
            hypothesisID: "h", configurationSHA256: digest("config"), instrument: "USD/JPY",
            evaluatorCodeSHA256: digest("evaluator"), adapterCodeSHA256: digest("adapter"),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256,
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            campaignID: "c", campaignManifestSHA256: digest("campaign"),
            heldOutArtifactSHA256: digest("holdout"), campaignCompletion: .completed,
            campaignVerdict: .passed, preregistered: true, protectedHoldout: true,
            costModelSHA256: digest("cost"), ownerApprovalID: "a", ownerApprovalSHA256: digest("approval"))
        #expect(invalid.validationErrors(for: noInstrument).contains("profile_instrument_configuration_missing"))
        let authority = StrategyResearchProfile(id: "TEST_PROFILE", version: "v1", family: "Test",
            status: .researchCandidate, sourceReferences: ["test"], mayAuthorizeOrder: true,
            decisionRole: .liveSignal, configurationSHA256ByInstrument: ["USD/JPY": digest("config")],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: digest("evaluator"), adapterCodeSHA256: digest("adapter"),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
        #expect(invalid.validationErrors(for: authority).contains("profile_has_order_authority"))
    }

    private func buildManifest() -> StrategyBuildInputManifest {
        let source = "Sources/BlazerCore/Research/Fixture.swift"
        let sharedHelper = "Sources/BlazerCore/V3DomainContracts.swift"
        return StrategyBuildInputManifest(bundleIdentifier: "com.blazer.BlazerOS",
            ownerSignerSHA1: signer, toolchain: "Swift 6", buildFlags: ManifestToolFlags.releaseMac,
            packageResolvedPresent: false,
            inputDigests: [input("Package.swift"), input("scripts/package-mac-app-staged.sh"), input("Sources/StrategyManifestTool/main.swift"), input(source), input(sharedHelper)],
            sourceClosurePathsByProfile: ["TEST_PROFILE": [source, sharedHelper]],
            globalBuildInputs: testGlobalInputs())
    }

    private func testGlobalInputs() -> [StrategyGlobalBuildInput] {
        [
            .init(role: .packageManifest, key: "swift-package-manifest", path: "Package.swift", sha256: digest("Package.swift")),
            .init(role: .packageResolutionAbsent, key: "swift-package-resolution", value: "absent"),
            .init(role: .trustedPackager, key: "staged-mac-packager", path: "scripts/package-mac-app-staged.sh", sha256: digest("scripts/package-mac-app-staged.sh")),
            .init(role: .manifestGenerator, key: "manifest-generator", path: "Sources/StrategyManifestTool/main.swift", sha256: digest("Sources/StrategyManifestTool/main.swift")),
            .init(role: .macroPluginInventory, key: "declared-generators", value: "[]"),
            .init(role: .generatedInputInventory, key: "generated-inputs", value: "[]"),
            .init(role: .compilerToolchain, key: "swift-compiler-identity", value: "Swift 6"),
            .init(role: .compilerPath, key: "resolved-swift-compiler-path", value: "/Xcode/Toolchains/Swift.xctoolchain/usr/bin/swift"),
            .init(role: .xcodeIdentity, key: "selected-xcode-identity", value: "/Xcode|Xcode 27.2"),
            .init(role: .xcodeCodeSignature, key: "selected-xcode-signature", value: "TeamIdentifier=59GAB85EFG|Apple Mac OS Application Signing|Apple Root CA"),
            .init(role: .sdkIdentity, key: "macos-sdk-identity", value: "SDK test"),
            .init(role: .sdkPath, key: "resolved-macos-sdk-path", value: "/Xcode/SDKs/MacOSX.sdk"),
            .init(role: .sdkSettingsDigest, key: "macos-sdk-settings-sha256", value: digest("sdk settings")),
            .init(role: .bundleIdentifier, key: "application-bundle-identifier", value: "com.blazer.BlazerOS"),
            .init(role: .target, key: "swift-package-target", value: "BlazerOSMac"),
            .init(role: .configuration, key: "build-configuration", value: "release"),
            .init(role: .architecture, key: "build-architecture", value: "arm64"),
            .init(role: .deploymentTarget, key: "macos-deployment-target", value: "macOS 14.0"),
            .init(role: .effectiveBuildFlags, key: "ordered-release-build-argv", value: "[\"/usr/bin/swift\",\"build\",\"-c\",\"release\",\"--scratch-path\",\"<isolated-swiftpm-scratch>\",\"--triple\",\"arm64-apple-macosx14.0\",\"--target\",\"BlazerOSMac\"]")
        ]
    }

    private func input(_ path: String) -> StrategyBuildInputDigest {
        StrategyBuildInputDigest(path: path, sha256: digest(path))
    }

    private func promotedProfile() -> StrategyResearchProfile {
        StrategyResearchProfile(id: "TEST_PROFILE", version: "v1", family: "Test",
            status: .researchCandidate, sourceReferences: ["test"], mayAuthorizeOrder: false,
            decisionRole: .liveSignal,
            configurationSHA256ByInstrument: ["USD/JPY": digest("config")],
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            evaluatorCodeSHA256: digest("evaluator"), adapterCodeSHA256: digest("adapter"),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256)
    }

    private func promotion(digests: [String: String]) -> StrategyPromotionRecord {
        StrategyPromotionRecord(id: "promotion-1", profileID: "TEST_PROFILE", profileVersion: "v1",
            hypothesisID: "hypothesis-1", configurationSHA256: digest("config"), instrument: "USD/JPY",
            evaluatorCodeSHA256: digest("evaluator"), adapterCodeSHA256: digest("adapter"),
            selectorCodeSHA256: StrategyImplementationDigests.selectorCodeSHA256,
            selectorPolicySHA256: LiveStrategySelectorPolicy.sha256,
            campaignID: "campaign-1", campaignManifestSHA256: digests["evidence/campaign.json"]!,
            heldOutArtifactSHA256: digests["evidence/holdout.json"]!, campaignCompletion: .completed,
            campaignVerdict: .passed, preregistered: true, protectedHoldout: true,
            costModelSHA256: digests["evidence/costs.json"]!, ownerApprovalID: "approval-1",
            ownerApprovalSHA256: digests["evidence/approval.json"]!)
    }

    private func digest(_ value: String) -> String { sha256(Data(value.utf8)) }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

private enum ManifestToolFlags {
    static let releaseMac = ["/usr/bin/swift", "build", "-c", "release", "--scratch-path",
                            "<isolated-swiftpm-scratch>", "--triple", "arm64-apple-macosx14.0", "--target", "BlazerOSMac"]
}
