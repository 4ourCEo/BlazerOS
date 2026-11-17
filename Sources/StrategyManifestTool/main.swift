import BlazerCore
import CryptoKit
import Foundation

private enum ManifestToolError: Error, CustomStringConvertible {
    case usage
    case invalid(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: StrategyManifestTool generate <repo> <resource-dir> <bundle-id> <signer-sha1> | verify <repo> <manifest-path> <bundle-id> <signer-sha1>"
        case .invalid(let message): return message
        }
    }
}

private enum ManifestTool {
    static let controlledPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    static func buildFlags(triple: String) -> [String] {
        ["/usr/bin/swift", "build", "-c", "release", "--scratch-path",
         "<isolated-swiftpm-scratch>", "--triple", triple, "--target", "BlazerOSMac"]
    }
    static let generatedResourceName = "StrategyBuildInputManifest.json"
    static let promotionResourceName = "StrategyPromotions.json"
    static let bundleID = "com.blazer.BlazerOS"

    static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 5 else { throw ManifestToolError.usage }
        let command = arguments[0]
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let metadataErrors = StrategySwiftPMMetadataPolicy.validationErrors(root: root)
        guard metadataErrors.isEmpty else {
            throw ManifestToolError.invalid("Unsupported SwiftPM metadata: \(metadataErrors.joined(separator: ", ")).")
        }
        switch command {
        case "generate":
            let resourceDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let requestedBundleID = arguments[3]
            let signer = arguments[4].uppercased()
            guard requestedBundleID == bundleID else { throw ManifestToolError.invalid("Unsupported application bundle identifier.") }
            guard StrategyBuildInputManifest.isSHA1(signer) else { throw ManifestToolError.invalid("Owner signer fingerprint is missing or malformed.") }
            try generate(root: root, resourceDirectory: resourceDirectory, signer: signer)
        case "verify":
            let manifestURL = URL(fileURLWithPath: arguments[2])
            let requestedBundleID = arguments[3]
            let signer = arguments[4].uppercased()
            guard requestedBundleID == bundleID, StrategyBuildInputManifest.isSHA1(signer) else {
                throw ManifestToolError.invalid("Bundle or signer identity is invalid.")
            }
            try verify(root: root, manifestURL: manifestURL, signer: signer)
        default:
            throw ManifestToolError.usage
        }
    }

    private static func generate(root: URL, resourceDirectory: URL, signer: String) throws {
        let inputPaths = try buildInputPaths(root: root)
        let digests = try inputPaths.map { path -> StrategyBuildInputDigest in
            let fileURL = root.appendingPathComponent(path)
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            return StrategyBuildInputDigest(path: path, sha256: sha256(data))
        }
        let sourcePaths = inputPaths.filter { $0.hasPrefix("Sources/") }
        guard !sourcePaths.isEmpty else { throw ManifestToolError.invalid("No package source inputs were found.") }
        let inputByPath = Dictionary(uniqueKeysWithValues: digests.map { ($0.path, $0.sha256) })
        let profileClosures = Dictionary(uniqueKeysWithValues:
            StrategyResearchRegistry.profiles.map { ($0.id, sourcePaths) })
        let resolvedPresent = inputPaths.contains { URL(fileURLWithPath: $0).lastPathComponent == "Package.resolved" }
        let toolchain = try toolchainIdentity()
        let flags = buildFlags(triple: toolchain.triple)
        let packageSource = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        guard !packageSource.contains(".macro("), !packageSource.contains(".plugin(") else {
            throw ManifestToolError.invalid("Package-declared macro/plugin generators need an explicit v2 provenance adapter.")
        }
        guard !sourcePaths.contains(where: isGeneratedInputPath) else {
            throw ManifestToolError.invalid("Generated source inputs need an explicit v2 generator provenance adapter.")
        }
        let flagsEncoder = JSONEncoder()
        flagsEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let orderedFlags = try? flagsEncoder.encode(flags),
              let orderedFlagsString = String(data: orderedFlags, encoding: .utf8) else {
            throw ManifestToolError.invalid("Could not canonicalize effective build flags.")
        }
        var globalInputs: [StrategyGlobalBuildInput] = [
            fileInput(.packageManifest, key: "swift-package-manifest", path: "Package.swift", hashes: inputByPath),
            fileInput(.trustedPackager, key: "staged-mac-packager", path: "scripts/package-mac-app-staged.sh", hashes: inputByPath),
            fileInput(.manifestGenerator, key: "manifest-generator", path: "Sources/StrategyManifestTool/main.swift", hashes: inputByPath),
            .init(role: .macroPluginInventory, key: "declared-package-macro-plugin-generators", value: "[]"),
            .init(role: .generatedInputInventory, key: "declared-generated-inputs", value: "[]"),
            .init(role: .compilerToolchain, key: "swift-compiler-identity", value: toolchain.swiftVersion),
            .init(role: .compilerPath, key: "resolved-swift-compiler-path", value: toolchain.compilerPath),
            .init(role: .xcodeIdentity, key: "selected-xcode-identity", value: toolchain.xcodeIdentity),
            .init(role: .xcodeCodeSignature, key: "selected-xcode-signature", value: toolchain.xcodeCodeSignature),
            .init(role: .sdkIdentity, key: "macos-sdk-identity", value: toolchain.sdkVersion),
            .init(role: .sdkPath, key: "resolved-macos-sdk-path", value: toolchain.sdkPath),
            .init(role: .sdkSettingsDigest, key: "macos-sdk-settings-sha256", value: toolchain.sdkSettingsSHA256),
            .init(role: .bundleIdentifier, key: "application-bundle-identifier", value: bundleID),
            .init(role: .target, key: "swift-package-target", value: "BlazerOSMac"),
            .init(role: .configuration, key: "build-configuration", value: "release"),
            .init(role: .architecture, key: "build-architecture", value: toolchain.architecture),
            .init(role: .deploymentTarget, key: "macos-deployment-target", value: toolchain.deploymentTarget),
            .init(role: .effectiveBuildFlags, key: "ordered-release-build-argv", value: orderedFlagsString)
        ]
        if resolvedPresent {
            globalInputs.append(fileInput(.packageResolution, key: "swift-package-resolution",
                path: "Package.resolved", hashes: inputByPath))
        } else {
            globalInputs.append(.init(role: .packageResolutionAbsent,
                key: "swift-package-resolution", value: "absent"))
        }
        let manifest = StrategyBuildInputManifest(
            bundleIdentifier: bundleID,
            ownerSignerSHA1: signer,
            toolchain: toolchain.swiftVersion,
            buildFlags: flags,
            packageResolvedPresent: resolvedPresent,
            inputDigests: digests,
            sourceClosurePathsByProfile: profileClosures,
            globalBuildInputs: globalInputs
        )
        let errors = manifest.validationErrors(expectedBundleIdentifier: bundleID,
            actualSignerSHA1: signer, expectedSignerSHA1: signer)
        guard errors.isEmpty else { throw ManifestToolError.invalid("Generated build manifest failed validation: \(errors.joined(separator: ", "))") }

        let promotionPackage = try loadPromotionPackage(root: root)
        let evidenceData = try loadEvidence(root: root, package: promotionPackage)
        let promotionInputDigests = Dictionary(profileClosures.keys.compactMap { profileID in
            manifest.promotionInputDigest(forProfile: profileID).map { (profileID, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let promotionErrors = promotionPackage.validationErrors(evidenceDataByPath: evidenceData,
            promotionInputDigestByProfile: promotionInputDigests)
        guard promotionErrors.isEmpty else {
            throw ManifestToolError.invalid("Promotion package failed validation: \(promotionErrors.joined(separator: ", "))")
        }
        for profile in promotionPackage.profiles where profile.decisionRole != .liveSignal || profile.mayAuthorizeOrder {
            throw ManifestToolError.invalid("Promotion profiles must be liveSignal profiles without order authority.")
        }
        for profile in promotionPackage.profiles where profileClosures[profile.id] == nil {
            throw ManifestToolError.invalid("Promotion profile has no source closure: \(profile.id)")
        }

        try FileManager.default.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)
        try write(manifest, to: resourceDirectory.appendingPathComponent(generatedResourceName))
        try write(promotionPackage, to: resourceDirectory.appendingPathComponent(promotionResourceName))
        let evidenceRoot = resourceDirectory.appendingPathComponent("evidence", isDirectory: true)
        for (path, data) in evidenceData {
            let destination = evidenceRoot.appendingPathComponent(String(path.dropFirst("evidence/".count)))
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    private static func verify(root: URL, manifestURL: URL, signer: String) throws {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(StrategyBuildInputManifest.self, from: data)
        let errors = manifest.validationErrors(expectedBundleIdentifier: bundleID,
            actualSignerSHA1: signer, expectedSignerSHA1: signer)
        guard errors.isEmpty else { throw ManifestToolError.invalid("Build manifest validation failed: \(errors.joined(separator: ", "))") }
        let currentEnvironment = try toolchainIdentity()
        let expectedEnvironmentValues: [StrategyBuildInputRole: String] = [
            .compilerToolchain: currentEnvironment.swiftVersion,
            .compilerPath: currentEnvironment.compilerPath,
            .xcodeIdentity: currentEnvironment.xcodeIdentity,
            .xcodeCodeSignature: currentEnvironment.xcodeCodeSignature,
            .sdkIdentity: currentEnvironment.sdkVersion,
            .sdkPath: currentEnvironment.sdkPath,
            .sdkSettingsDigest: currentEnvironment.sdkSettingsSHA256,
            .architecture: currentEnvironment.architecture,
            .deploymentTarget: currentEnvironment.deploymentTarget
        ]
        for (role, expectedValue) in expectedEnvironmentValues {
            guard manifest.globalBuildInputs.first(where: { $0.role == role })?.value == expectedValue else {
                throw ManifestToolError.invalid("Resolved build environment changed before signing: \(role.rawValue).")
            }
        }
        let currentPaths = try buildInputPaths(root: root)
        let expected = Set(manifest.inputDigests.map(\.path))
        guard Set(currentPaths) == expected else {
            throw ManifestToolError.invalid("Build input file set changed between manifest generation and signing.")
        }
        for input in manifest.inputDigests {
            let current = try Data(contentsOf: root.appendingPathComponent(input.path), options: [.mappedIfSafe])
            guard sha256(current) == input.sha256 else {
                throw ManifestToolError.invalid("Build input changed before signing: \(input.path)")
            }
        }
    }

    private static func buildInputPaths(root: URL) throws -> [String] {
        let fileManager = FileManager.default
        let enumerationRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let sourceRoot = root.appendingPathComponent("Sources", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceRoot.path) else {
            throw ManifestToolError.invalid("Sources directory is missing.")
        }
        var paths = Set<String>(["Package.swift", "scripts/package-mac-app-staged.sh"])
        let excludedTopDirectories: Set<String> = [".git", ".build", ".codex", ".agents", "dist", "DerivedData"]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(at: enumerationRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else {
            throw ManifestToolError.invalid("Could not enumerate package build inputs.")
        }
        for case let fileURL as URL in enumerator {
            let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard canonicalFile.path.hasPrefix(enumerationRoot.path + "/") else {
                throw ManifestToolError.invalid("Build input resolves outside the package root: \(fileURL.path)")
            }
            let relative = String(canonicalFile.path.dropFirst(enumerationRoot.path.count + 1))
            let first = relative.split(separator: "/").first.map(String.init) ?? ""
            if excludedTopDirectories.contains(first) {
                enumerator.skipDescendants()
                continue
            }
            if relative.hasPrefix("Sources/Sources/") || relative.hasPrefix("Tests/") || relative.hasPrefix("reports/") {
                if relative.hasPrefix("Sources/Sources/") { enumerator.skipDescendants() }
                continue
            }
            if URL(fileURLWithPath: relative).lastPathComponent == "Package.resolved" {
                paths.insert(relative)
                continue
            }
            guard relative.hasPrefix("Sources/") else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw ManifestToolError.invalid("Symlink in source build inputs is not allowed: \(relative)")
            }
            if values.isRegularFile == true { paths.insert(relative) }
        }
        if let enumerationError {
            throw ManifestToolError.invalid("Could not enumerate all build inputs: \(enumerationError.localizedDescription)")
        }
        for path in ["Package.swift", "scripts/package-mac-app-staged.sh"] {
            guard fileManager.fileExists(atPath: root.appendingPathComponent(path).path) else {
                throw ManifestToolError.invalid("Required build input is missing: \(path)")
            }
        }
        return paths.sorted()
    }

    private static func loadPromotionPackage(root: URL) throws -> StrategyPromotionPackage {
        let url = root.appendingPathComponent("reports/strategy-promotions/StrategyPromotions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        return try JSONDecoder().decode(StrategyPromotionPackage.self, from: Data(contentsOf: url))
    }

    private static func loadEvidence(root: URL,
                                     package: StrategyPromotionPackage) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let evidenceRoot = root.appendingPathComponent("reports/strategy-promotions", isDirectory: true)
        for evidence in package.evidenceFiles {
            guard StrategyBuildInputManifest.isSafeRelativePath(evidence.path),
                  evidence.path.hasPrefix("evidence/") else {
                throw ManifestToolError.invalid("Unsafe promotion evidence path.")
            }
            let relativePath = String(evidence.path.dropFirst("evidence/".count))
            let fileURL = evidenceRoot.appendingPathComponent("evidence", isDirectory: true)
                .appendingPathComponent(relativePath).standardizedFileURL
            guard fileURL.path.hasPrefix(evidenceRoot.appendingPathComponent("evidence", isDirectory: true).standardizedFileURL.path + "/") else {
                throw ManifestToolError.invalid("Promotion evidence escaped its source root.")
            }
            result[evidence.path] = try Data(contentsOf: fileURL)
        }
        return result
    }

    private struct ToolchainIdentity {
        let swiftVersion: String
        let compilerPath: String
        let xcodeIdentity: String
        let xcodeCodeSignature: String
        let sdkVersion: String
        let sdkPath: String
        let sdkSettingsSHA256: String
        let architecture: String
        let deploymentTarget: String
        let triple: String
    }

    private static func toolchainIdentity() throws -> ToolchainIdentity {
        let environment = ProcessInfo.processInfo.environment
        guard let developerDir = environment["DEVELOPER_DIR"], developerDir.hasPrefix("/"),
              let home = environment["HOME"], home.hasSuffix("/home"),
              let temp = environment["TMPDIR"], temp.hasSuffix("/tmp"),
              URL(fileURLWithPath: home).deletingLastPathComponent()
                == URL(fileURLWithPath: temp).deletingLastPathComponent(),
              environment["PATH"] == controlledPath,
              environment["LANG"] == "C", environment["LC_ALL"] == "C",
              environment["MACOSX_DEPLOYMENT_TARGET"] == "14.0" else {
            throw ManifestToolError.invalid("Controlled SwiftPM environment is incomplete.")
        }
        let selectedDeveloperDir = try capture("/usr/bin/xcode-select", ["-p"])
        guard selectedDeveloperDir == developerDir,
              developerDir.hasSuffix("/Contents/Developer") else {
            throw ManifestToolError.invalid("Build must use the selected full Xcode developer directory.")
        }
        let swift = try capture("/usr/bin/swift", ["--version"])
        let compilerPath = try capture("/usr/bin/xcrun", ["--find", "swiftc"])
        guard compilerPath.hasPrefix(developerDir + "/") else {
            throw ManifestToolError.invalid("Resolved Swift compiler is outside the selected Xcode developer directory.")
        }
        let xcodeIdentity = try capture("/usr/bin/xcodebuild", ["-version"])
        let xcodeAppPath = String(developerDir.dropLast("/Contents/Developer".count))
        _ = try capture("/usr/bin/codesign", ["--verify", "--deep", "--strict", xcodeAppPath])
        let signatureDetails = try capture("/usr/bin/codesign", ["-dv", "--verbose=4", xcodeAppPath])
        guard signatureDetails.contains("TeamIdentifier=59GAB85EFG"),
              signatureDetails.contains("Authority=Apple Mac OS Application Signing"),
              signatureDetails.contains("Authority=Apple Root CA") else {
            throw ManifestToolError.invalid("Selected Xcode is not a valid Apple-signed installation.")
        }
        let sdkPath = try capture("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-path"])
        guard sdkPath.hasPrefix(developerDir + "/") else {
            throw ManifestToolError.invalid("Resolved macOS SDK is outside the selected Xcode developer directory.")
        }
        let sdkSettings = URL(fileURLWithPath: sdkPath).appendingPathComponent("SDKSettings.plist")
        let sdkData = try Data(contentsOf: sdkSettings)
        let sdkPropertyList = try PropertyListSerialization.propertyList(from: sdkData, format: nil)
        guard let sdkVersion = (sdkPropertyList as? [String: Any])?["Version"] as? String,
              !sdkVersion.isEmpty else {
            throw ManifestToolError.invalid("Could not read the selected macOS SDK version.")
        }
        let architecture = try capture("/usr/bin/uname", ["-m"])
        let deploymentTarget = "macOS 14.0"
        return ToolchainIdentity(swiftVersion: swift, compilerPath: compilerPath,
            xcodeIdentity: "\(developerDir)|\(xcodeIdentity)",
            xcodeCodeSignature: "TeamIdentifier=59GAB85EFG|Apple Mac OS Application Signing|Apple Root CA",
            sdkVersion: sdkVersion,
            sdkPath: sdkPath, sdkSettingsSHA256: sha256(sdkData), architecture: architecture,
            deploymentTarget: deploymentTarget,
            triple: "\(architecture)-apple-macosx14.0")
    }

    private static func fileInput(_ role: StrategyBuildInputRole, key: String,
                                  path: String, hashes: [String: String]) -> StrategyGlobalBuildInput {
        .init(role: role, key: key, path: path, sha256: hashes[path] ?? "")
    }

    private static func isGeneratedInputPath(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).pathComponents.map { $0.lowercased() }
        return components.contains("generated") || components.contains("generatedsources")
            || URL(fileURLWithPath: path).lastPathComponent.lowercased().contains(".generated.")
    }

    private static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let value = String(data: data, encoding: .utf8) else {
            throw ManifestToolError.invalid("Could not capture build toolchain identity from \(executable).")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

do {
    try ManifestTool.run()
} catch {
    fputs("Strategy manifest tool: \(error)\n", stderr)
    exit(1)
}
