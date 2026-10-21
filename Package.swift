// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlazerCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BlazerCore", targets: ["BlazerCore"]),
        .library(name: "BlazerCrypto", targets: ["BlazerCrypto"]),
        .library(name: "LightningDesk", targets: ["LightningDesk"]),
        .executable(name: "BlazerOS", targets: ["BlazerOS"]),
        .executable(name: "ForwardTest", targets: ["ForwardTest"]),
    ],
    targets: [
        .target(
            name: "BlazerCore",
            resources: [
                .copy("scan-engine.js"),
                .copy("Research/scan-engine-control.js"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "BlazerCrypto",
            dependencies: ["BlazerCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Parity",
            dependencies: ["BlazerCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "LightningDesk",
            dependencies: ["BlazerCore", "BlazerCrypto"],
            resources: [
                .copy("BlazerMark.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "BlazerOS",
            dependencies: ["LightningDesk"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Persist",
            dependencies: ["BlazerCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "Soak",
            dependencies: ["BlazerCore", "LightningDesk"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "ForwardTest",
            dependencies: ["BlazerCore", "LightningDesk"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(name: "BlazerCoreTests", dependencies: ["BlazerCore", "LightningDesk", "BlazerCrypto"]),
    ]
)
