import Foundation

/// Source digests live outside the files they identify so they can bind to the
/// exact evaluator/adapter/selector bytes without self-referential hashes.
public enum StrategyImplementationDigests {
    public static let adapterVersion = "ADAPTIVE_ADAPTERS_V3"
    public static let adapterCodeSHA256 = "af116791196d95f575f8903bf08d6d64fa187b2402df62066e32a4431c8248c9"
    public static let selectorCodeSHA256 = "d127d7fc5160213d28df23a6c546401437ccecd7bd7f58fc39b6efaa7419fe08"
    public static let evaluatorCodeSHA256: [String: String] = [
        "ORB_BREAK_RETEST": "7199de9171fe9d9e390bf934b0658fec600ded75d4abeb86adf54225c503f304",
        "CHOCH_FVG_FIB": "2cc3dd123c59584d41a42be7a69cd0a0b24ed50a5dddc4fddc2775c01c667236",
        "AUCTION_FAILURE": "3c525e42aa82e09673b9e284b2904b6deb02e022f3ea3f3b44401366d4bc368a",
        "LONDON_BREAK_RETEST": "a883b28bdebd3c672413fb0b0dc79935f1067398c2a68598c9b1d0d32784eb2c",
        "LEGACY_V1": "d463994c3d604f038f97f33f79dbc28afc2eba4a2490f5074f0a283349c8bae3"
    ]
}
