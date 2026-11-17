import Foundation

/// Build provenance shown to the operator and diagnostics. A dirty suffix is intentional:
/// it prevents a working-tree build from being mistaken for a reproducible commit artifact.
enum BuildIdentity {
    static var value: String {
        Bundle.main.object(forInfoDictionaryKey: "BLAZER_BUILD_ID") as? String ?? "unidentified"
    }

    static var display: String {
        value == "unidentified" ? "BUILD UNIDENTIFIED" : "BUILD \(value)"
    }
}
