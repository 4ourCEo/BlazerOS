import Foundation

public enum AdaptiveNotificationKind: String, Codable, Sendable, Equatable {
    case setupForming = "SETUP_FORMING"
    case entryReady = "ENTRY_READY"
    case setupInvalidated = "SETUP_INVALIDATED"
    case opportunityExpired = "OPPORTUNITY_EXPIRED"
    case providerUnavailable = "PROVIDER_UNAVAILABLE"
}

/// Provider-neutral publication contract. It contains no broker or order
/// authority; MarketNotificationService owns local delivery.
public struct AdaptiveNotification: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: AdaptiveNotificationKind
    public let instrument: String
    public let strategyID: String?
    public let sourceTime: Date
    public let expiresAt: Date
    public let deepLink: String

    public init(kind: AdaptiveNotificationKind, instrument: String,
                strategyID: String?, sourceTime: Date, expiresAt: Date) {
        self.kind = kind
        self.instrument = instrument
        self.strategyID = strategyID
        self.sourceTime = sourceTime
        self.expiresAt = expiresAt
        let strategy = strategyID ?? "adaptive"
        id = "adaptive-\(instrument)-\(strategy)-\(kind.rawValue)-\(sourceTime.timeIntervalSince1970)"
        var components = URLComponents()
        components.scheme = "blazer"
        components.host = "opportunity"
        components.queryItems = [
            URLQueryItem(name: "instrument", value: instrument),
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "strategy", value: strategyID)
        ]
        deepLink = components.url?.absoluteString ?? "blazer://opportunity"
    }

    public func isFresh(at now: Date) -> Bool {
        sourceTime <= now && now < expiresAt
    }
}

public enum AdaptiveNotificationPlanner {
    public static func plan(state: AdaptiveMarketDecisionState,
                            selectedCandidate: AdaptiveOpportunityCandidate?,
                            instrument: String, sourceTime: Date, now: Date,
                            previouslyDelivered: Set<String> = [],
                            lifetime: TimeInterval = 30) -> AdaptiveNotification? {
        let kind: AdaptiveNotificationKind
        switch state {
        case .opportunityForming: kind = .setupForming
        case .actionableOpportunity: kind = .entryReady
        case .unavailable: kind = .providerUnavailable
        case .noOpportunity: return nil
        }
        let notification = AdaptiveNotification(kind: kind, instrument: instrument,
            strategyID: selectedCandidate?.strategyID, sourceTime: sourceTime,
            expiresAt: sourceTime.addingTimeInterval(lifetime))
        guard notification.isFresh(at: now), !previouslyDelivered.contains(notification.id) else {
            return nil
        }
        return notification
    }

    public static func planExpiration(for candidate: AdaptiveOpportunityCandidate,
                                      now: Date,
                                      previouslyDelivered: Set<String> = []) -> AdaptiveNotification? {
        guard let observedAt = candidate.observedAt,
              now >= observedAt,
              candidate.direction != .wait else { return nil }
        let notification = AdaptiveNotification(kind: .opportunityExpired,
            instrument: candidate.instrument, strategyID: candidate.strategyID,
            sourceTime: observedAt, expiresAt: now.addingTimeInterval(30))
        return previouslyDelivered.contains(notification.id) ? nil : notification
    }
}
