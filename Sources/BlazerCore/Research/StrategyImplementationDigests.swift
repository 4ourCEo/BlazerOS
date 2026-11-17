import Foundation

/// Source digests live outside the files they identify so they can bind to the
/// exact evaluator/adapter/selector bytes without self-referential hashes.
public enum StrategyImplementationDigests {
    public static let adapterVersion = "ADAPTIVE_ADAPTERS_V3"
    public static let adapterCodeSHA256 = "bb7bae9148a6a5b43d88e6ae01c8493e1852effe82ac65094c88ae243d7117b4"
    public static let selectorCodeSHA256 = "77ccab807a3741d3848067fbc7e414e088a6da1f558d2e512799f4dbf5115598"
    public static let evaluatorCodeSHA256: [String: String] = [
        "ORB_BREAK_RETEST": "7199de9171fe9d9e390bf934b0658fec600ded75d4abeb86adf54225c503f304",
        "CHOCH_FVG_FIB": "2cc3dd123c59584d41a42be7a69cd0a0b24ed50a5dddc4fddc2775c01c667236",
        "AUCTION_FAILURE": "3c525e42aa82e09673b9e284b2904b6deb02e022f3ea3f3b44401366d4bc368a",
        "LEGACY_V1": "d463994c3d604f038f97f33f79dbc28afc2eba4a2490f5074f0a283349c8bae3"
    ]
}
