import Foundation

/// The activity module. The shared attributes type is the model. The island UI is not in this target.
public enum BlazerActivityModule {
    public static let name = "BlazerActivity"
}

/// Shared model for Dynamic Island and Live Activity preparation.
public struct ArmedActivityState: Codable, Sendable, Equatable {
    public var pair: String
    public var score: Int
    public var side: String
    public var strike: Double
    public var remainingTime: Double
    public var veto: String?

    public init(
        pair: String,
        score: Int,
        side: String,
        strike: Double,
        remainingTime: Double,
        veto: String? = nil
    ) {
        self.pair = pair
        self.score = score
        self.side = side
        self.strike = strike
        self.remainingTime = remainingTime
        self.veto = veto
    }
}

