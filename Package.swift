// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlazerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BlazerCore", type: .static, targets: ["BlazerCore"]),
        .library(name: "BlazerCrypto", type: .static, targets: ["BlazerCrypto"]),
        .library(name: "LightningDesk", type: .static, targets: ["LightningDesk"]),
        .executable(name: "BlazerOS", targets: ["BlazerOSMac"]),
        .executable(name: "ForwardTest", targets: ["ForwardTest"]),
    ],
    targets: [
        .executableTarget(name: "EdgeReport", dependencies: ["BlazerCore"]),
        .executableTarget(name: "ScanBenchmark", dependencies: ["BlazerCore"]),
        .executableTarget(name: "CoreAudit", dependencies: ["BlazerCore", "BlazerCrypto"]),
        .executableTarget(name: "StrategyManifestTool", dependencies: ["BlazerCore"], path: "Sources/StrategyManifestTool"),
        .target(
            name: "BlazerCore",
            resources: [
                .copy("scan-engine.js"),
                .copy("Research/scan-engine-control.js"),
            ]
        ),
        .target(
            name: "BlazerCrypto",
            dependencies: ["BlazerCore"]
        ),
        .executableTarget(
            name: "Parity",
            dependencies: ["BlazerCore"]
        ),
        .target(
            name: "LightningDesk",
            dependencies: ["BlazerCore", "BlazerCrypto"],
            resources: [
                .copy("BlazerMark.png"),
            ]
        ),
        .executableTarget(
            name: "BlazerOSMac",
            dependencies: ["LightningDesk"],
            path: "Sources/BlazerOSMac"
        ),
        .executableTarget(
            name: "Persist",
            dependencies: ["BlazerCore"]
        ),
        .executableTarget(
            name: "Soak",
            dependencies: ["BlazerCore", "LightningDesk"]
        ),
        .executableTarget(
            name: "ForwardTest",
            dependencies: ["BlazerCore", "LightningDesk"]
        ),
        .testTarget(
            name: "BlazerCoreTests",
            dependencies: ["BlazerCore", "LightningDesk", "BlazerCrypto"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
