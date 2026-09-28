import ActivityKit
import Foundation

/// What the Dynamic Island is allowed to show. The desk pushes this. The island does not score.
public struct DeskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var verb: String
        public var endsAt: Date
        public var startedAt: Date
        public var veto: String?
        public var currentPrice: Double?

        public init(
            verb: String,
            endsAt: Date,
            startedAt: Date = Date(),
            veto: String? = nil,
            currentPrice: Double? = nil
        ) {
            self.verb = verb
            self.endsAt = endsAt
            self.startedAt = startedAt
            self.veto = veto
            self.currentPrice = currentPrice
        }
    }

    public var pair: String
    public var score: Int
    public var strike: Double
    public var fingerprint: String

    public init(pair: String, score: Int, strike: Double, fingerprint: String) {
        self.pair = pair
        self.score = score
        self.strike = strike
        self.fingerprint = fingerprint
    }
}
