import SwiftUI
import BlazerCore

enum V3ReviewArchiveSource: CaseIterable, Identifiable, Equatable {
    case liveOanda
    case proxyResearch

    var id: Self { self }

    var title: String {
        switch self {
        case .liveOanda: "Live OANDA decision archive"
        case .proxyResearch: "OANDA proxy research archive"
        }
    }

    var directoryName: String {
        switch self {
        case .liveOanda: "live-oanda"
        case .proxyResearch: "oanda-proxy"
        }
    }

    func archiveRoot(under researchRoot: URL) -> URL {
        researchRoot.appendingPathComponent(directoryName, isDirectory: true)
    }
}

struct V3ReviewTimelineItem: Identifiable, Equatable {
    let id: String
    let date: Date
    let kind: String
    let title: String
    let detail: String

    var stableSortKey: String { "\(kind)|\(id)" }
}

struct V3ReviewInsight: Identifiable, Equatable {
    let id: String
    let source: V3ReviewArchiveSource
    let planID: String
    let closeID: String
    let openingRecordID: String
    let missingFields: [String]
    let recordedAt: Date
    let openingWasSuperseded: Bool
    /// Exact close and immutable opening rows from this same archive snapshot.
    let evidenceRows: [V3ReviewTimelineItem]

    /// Rendered visibly inside the expanded insight alongside its cited rows.
    var visibleCitationText: String {
        "Plan \(planID) · close record \(closeID) · opening record \(openingRecordID)"
    }

    var accessibilityLabel: String {
        "\(source.title) insight. User-reported manual close; unverified, not broker-confirmed. "
            + "Missing \(missingFields.joined(separator: " and ")). Plan \(planID), close record \(closeID), "
            + "opening record \(openingRecordID)."
            + (openingWasSuperseded ? " Referenced opening revision was later superseded." : "")
    }
}

private struct V3ReviewInsightRoute: Identifiable {
    let id = UUID()
    let original: V3ReviewInsight
    var state: V3ReviewInsightRouteValidation = .loading
}

enum V3ReviewInsightRouteValidation: Equatable {
    case loading
    case unavailable
    case empty
    case stale
    case ready(V3ReviewInsight)

    var insight: V3ReviewInsight? {
        guard case .ready(let insight) = self else { return nil }
        return insight
    }

    static func project(selectedSource: V3ReviewArchiveSource,
                        original: V3ReviewInsight,
                        archive: V3ReviewArchiveState) -> Self {
        guard selectedSource == original.source else { return .stale }
        switch archive {
        case .loading:
            return .loading
        case .unavailable:
            return .unavailable
        case .empty:
            return .empty
        case .populated(let snapshot):
            guard let current = snapshot.closeCompletenessInsight(source: selectedSource, id: original.id),
                  current == original else { return .stale }
            return .ready(current)
        }
    }
}

enum V3ReviewInsightQuestion: String, CaseIterable, Identifiable {
    case missingDetails = "What is missing?"
    case establishes = "What does this record establish?"
    case brokerConfirmation = "Is this broker-confirmed?"
    case linkedRecords = "Which records are linked?"
    case openingSupersession = "Was the opening superseded?"
    case unsupported = "Unsupported question"

    static var supported: [Self] { allCases.filter { $0 != .unsupported } }
    var id: String { rawValue }
}

struct V3ReviewInsightQuestionAnswer: Equatable {
    let question: V3ReviewInsightQuestion
    let text: String
    /// Archive-qualified durable record references that support this fixed answer.
    let citations: [String]

    static func make(question: V3ReviewInsightQuestion,
                     route: V3ReviewInsightRouteValidation) -> Self? {
        guard let insight = route.insight else { return nil }
        let closeCitation = "v3:\(insight.source.directoryName):user-close:\(insight.closeID)"
        let openingCitation = "v3:\(insight.source.directoryName):user-position:\(insight.openingRecordID)"

        switch question {
        case .missingDetails:
            return Self(question: question,
                text: "Missing: \(insight.missingFields.joined(separator: " and ")). These values are not recorded and remain unavailable; none are inferred.",
                citations: [closeCitation])
        case .establishes:
            return Self(question: question,
                text: "This record establishes only that a manual close report was recorded by the user. It does not establish an actual close, execution, or fill.",
                citations: [closeCitation])
        case .brokerConfirmation:
            return Self(question: question,
                text: "No. This is a user-reported manual record. It is unverified and not broker-confirmed.",
                citations: [closeCitation])
        case .linkedRecords:
            return Self(question: question,
                text: "Archive: \(insight.source.title). Plan \(insight.planID) is a binding reference. Linked evidence: close \(insight.closeID) and opening \(insight.openingRecordID).",
                citations: [closeCitation, openingCitation])
        case .openingSupersession:
            let text = insight.openingWasSuperseded
                ? "The cited opening revision \(insight.openingRecordID) was later superseded. It is historical evidence, not the current opening."
                : "The selected evidence does not mark opening revision \(insight.openingRecordID) as superseded."
            return Self(question: question, text: text, citations: [closeCitation, openingCitation])
        case .unsupported:
            return Self(question: question,
                text: "This question is not supported by this record. No other evidence or archive was consulted.",
                citations: [closeCitation])
        }
    }
}

enum V3ReviewInsightsState: Equatable {
    case loading
    case unavailable
    case emptyArchive
    case noMatchingInsights
    case insights([V3ReviewInsight])

    static func project(archive: V3ReviewArchiveState, source: V3ReviewArchiveSource) -> Self {
        switch archive {
        case .loading: return .loading
        case .unavailable: return .unavailable
        case .empty: return .emptyArchive
        case .populated(let snapshot):
            let values = snapshot.closeCompletenessInsights(source: source)
            return values.isEmpty ? .noMatchingInsights : .insights(values)
        }
    }
}

struct V3ReviewPlanDetail: Equatable {
    let plan: V3TradePlan
    let timeline: [V3ReviewTimelineItem]
    let integrity: [V3ReviewTimelineItem]
    let emptyCategories: [String]
    let currentUserReportedPosition: V3PositionRecord?
    let hasLegacyUserReportedPosition: Bool
    let terminalSourceTime: Date?
}

struct V3ReviewArchiveSnapshot: Equatable {
    let plans: [V3TradePlan]
    let setupLifecycleEvents: [V3SetupLifecycleEvent]
    let planEntryEvidence: [V3PlanEntryEvidence]
    let positions: [V3PositionRecord]
    let positionCloses: [V3UserReportedPositionClose]
    let spotOutcomes: [V3DurableSpotOutcome]
    let structuralOutcomes: [V3StructuralOutcome]

    var planCount: Int { plans.count }
    var setupLifecycleEventCount: Int { setupLifecycleEvents.count }
    var planEntryEvidenceEventCount: Int { planEntryEvidence.count }
    var positionEventCount: Int { positions.count }
    var positionCloseCount: Int { positionCloses.count }
    var spotOutcomeCount: Int { spotOutcomes.count }
    var structuralOutcomeCount: Int { structuralOutcomes.count }

    var totalRecordCount: Int {
        planCount + setupLifecycleEventCount + planEntryEvidenceEventCount
            + positionEventCount + positionCloseCount + spotOutcomeCount + structuralOutcomeCount
    }

    init(plans: [V3TradePlan] = [], setupLifecycleEvents: [V3SetupLifecycleEvent] = [],
         planEntryEvidence: [V3PlanEntryEvidence] = [], positions: [V3PositionRecord] = [],
         positionCloses: [V3UserReportedPositionClose] = [],
         spotOutcomes: [V3DurableSpotOutcome] = [], structuralOutcomes: [V3StructuralOutcome] = []) {
        self.plans = plans
        self.setupLifecycleEvents = setupLifecycleEvents
        self.planEntryEvidence = planEntryEvidence
        self.positions = positions
        self.positionCloses = positionCloses
        self.spotOutcomes = spotOutcomes
        self.structuralOutcomes = structuralOutcomes
    }

    func detail(for planID: String) -> V3ReviewPlanDetail? {
        guard let plan = plans.first(where: { $0.id == planID }) else { return nil }
        var linked: [V3ReviewTimelineItem] = [planItem(plan)]
        var integrity: [V3ReviewTimelineItem] = []
        let directlyLinkedLifecycle = setupLifecycleEvents.filter { $0.planID == plan.id }
        let linkedSetupIDs = Set(directlyLinkedLifecycle.map(\.setupID))
        // The confirmed ORB event carries the plan ID; preceding/terminal events in
        // that same validated setup stream may correctly have no plan ID.
        let lifecycle = setupLifecycleEvents.filter {
            $0.planID == plan.id || (linkedSetupIDs.contains($0.setupID) && $0.planID == nil)
        }
        let entries = planEntryEvidence.filter { $0.planID == plan.id }
        let positionEvents = positions.filter { $0.planID == plan.id }
        let closeEvents = positionCloses.filter { $0.planID == plan.id }
        let spot = spotOutcomes.filter { $0.planID == plan.id }
        let structural = structuralOutcomes.filter { $0.planID == plan.id }

        for event in lifecycle {
            let item = lifecycleItem(event)
            if event.instrument != plan.instrument || event.strategyID != plan.strategyID
                || event.strategyVersion != plan.strategyVersion
                || (event.engineVersion.map { $0 != plan.engineVersion } ?? false) { integrity.append(item) }
            else { linked.append(item) }
        }
        for entry in entries {
            let item = entryItem(entry)
            if entry.observation.instrument != plan.instrument { integrity.append(item) }
            else { linked.append(item) }
        }
        let supersededPositionIDs = Set(positionEvents.compactMap(\.supersedesRecordID))
        for position in positionEvents {
            let item = positionItem(position, isSuperseded: supersededPositionIDs.contains(position.id),
                                    terminalSourceTime: Self.terminalSourceTime(for: plan, events: lifecycle))
            if position.instrument != plan.instrument || position.side != plan.side { integrity.append(item) }
            else { linked.append(item) }
        }
        let supersededCloseIDs = Set(closeEvents.compactMap(\.supersedesCloseID))
        let supersededPositionIDsForCloses = Set(positionEvents.compactMap(\.supersedesRecordID))
        for close in closeEvents {
            let currentOpening = positionEvents.first { $0.positionID == close.positionID
                && !supersededPositionIDsForCloses.contains($0.id) }
            let item = positionCloseItem(close, isSuperseded: supersededCloseIDs.contains(close.id),
                                         openingWasSuperseded: currentOpening?.id != close.openingRecordID)
            if !positionEvents.contains(where: {
                $0.id == close.openingRecordID && $0.positionID == close.positionID
            }) { integrity.append(item) }
            else { linked.append(item) }
        }
        for outcome in spot {
            let item = spotItem(outcome)
            if outcome.instrument != plan.instrument || outcome.strategyVersion != plan.strategyVersion
                || outcome.engineVersion != plan.engineVersion {
                integrity.append(item)
            } else { linked.append(item) }
        }
        for outcome in structural {
            let item = structuralItem(outcome)
            if outcome.instrument != plan.instrument || outcome.strategyVersion != plan.strategyVersion
                || outcome.engineVersion != plan.engineVersion {
                integrity.append(item)
            } else { linked.append(item) }
        }

        let categories: [(String, Bool)] = [
            ("setup lifecycle event", !lifecycle.isEmpty),
            ("entry evidence record", !entries.isEmpty),
            ("position evidence record", !positionEvents.isEmpty),
            ("user-reported close", !closeEvents.isEmpty),
            ("spot outcome", !spot.isEmpty),
            ("structural outcome", !structural.isEmpty),
        ]
        let currentPosition = positionEvents.first {
            $0.positionID != nil && $0.state == .userReported
                && $0.provenance == .manualTradeReport && !supersededPositionIDs.contains($0.id)
        }
        let hasLegacyPosition = positionEvents.contains {
            $0.positionID == nil && $0.state == .userReported && $0.provenance == .manualTradeReport
        }
        return V3ReviewPlanDetail(plan: plan, timeline: Self.sorted(linked), integrity: Self.sorted(integrity),
                                  emptyCategories: categories.filter { !$0.1 }.map { "No \($0.0) is stored." },
                                  currentUserReportedPosition: currentPosition,
                                  hasLegacyUserReportedPosition: hasLegacyPosition,
                                  terminalSourceTime: Self.terminalSourceTime(for: plan, events: lifecycle))
    }

    /// Projects only validated, linked, unsuperseded manual close leaves whose
    /// user-reported effective close time or exit price is unavailable.
    func closeCompletenessInsights(source: V3ReviewArchiveSource) -> [V3ReviewInsight] {
        Array(allCloseCompletenessInsights(source: source).prefix(6))
    }

    /// Looks up one selected record without applying the six-card Review display cap.
    func closeCompletenessInsight(source: V3ReviewArchiveSource, id: String) -> V3ReviewInsight? {
        allCloseCompletenessInsights(source: source).first { $0.id == id }
    }

    private func allCloseCompletenessInsights(source: V3ReviewArchiveSource) -> [V3ReviewInsight] {
        var projected: [V3ReviewInsight] = []
        let positionGroups = Dictionary(grouping: positions.filter { $0.positionID != nil },
                                        by: { $0.positionID! })
        let closeGroups = Dictionary(grouping: positionCloses, by: \.positionID)

        for (positionID, closeChain) in closeGroups {
            guard Self.validCloseChain(closeChain, positionID: positionID),
                  let leaf = Self.leaf(of: closeChain),
                  leaf.provenance == .manualTradeCloseReport,
                  leaf.validation().isEmpty,
                  plans.filter({ $0.id == leaf.planID }).count == 1,
                  let plan = plans.first(where: { $0.id == leaf.planID }),
                  let positionChain = positionGroups[positionID],
                  Self.validOpeningChain(positionChain, positionID: positionID),
                  positionChain.filter({ $0.id == leaf.openingRecordID }).count == 1,
                  let opening = positionChain.first(where: { $0.id == leaf.openingRecordID }),
                  opening.planID == plan.id, opening.instrument == plan.instrument,
                  opening.side == plan.side, opening.state == .userReported,
                  opening.provenance == .manualTradeReport, opening.validation().isEmpty,
                  let detail = detail(for: plan.id),
                  let closeRow = detail.timeline.first(where: { $0.id == "position-close|\(leaf.id)" }),
                  let openingRow = detail.timeline.first(where: { $0.id == "position|\(opening.id)" }) else {
                continue
            }

            var missing: [String] = []
            if leaf.closedAt == nil { missing.append("close time") }
            if leaf.exitPrice == nil { missing.append("exit price") }
            guard !missing.isEmpty else { continue }
            let latestOpeningID = Self.leaf(of: positionChain)?.id
            let insightID = "\(source.directoryName)|user-close|\(leaf.id)"
            projected.append(V3ReviewInsight(id: insightID, source: source,
                planID: plan.id, closeID: leaf.id, openingRecordID: leaf.openingRecordID,
                missingFields: missing, recordedAt: leaf.recordedAt,
                openingWasSuperseded: latestOpeningID != leaf.openingRecordID,
                evidenceRows: [closeRow, openingRow]))
        }

        return projected.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt > $1.recordedAt }
            return $0.id < $1.id
        }
    }

    private static func leaf(of chain: [V3UserReportedPositionClose]) -> V3UserReportedPositionClose? {
        let supersededIDs = Set(chain.compactMap(\.supersedesCloseID))
        let leaves = chain.filter { !supersededIDs.contains($0.id) }
        return leaves.count == 1 ? leaves[0] : nil
    }

    private static func leaf(of chain: [V3PositionRecord]) -> V3PositionRecord? {
        let supersededIDs = Set(chain.compactMap(\.supersedesRecordID))
        let leaves = chain.filter { !supersededIDs.contains($0.id) }
        return leaves.count == 1 ? leaves[0] : nil
    }

    private static func validCloseChain(_ chain: [V3UserReportedPositionClose],
                                        positionID: String) -> Bool {
        guard !chain.isEmpty, Set(chain.map(\.id)).count == chain.count,
              Set(chain.map(\.planID)).count == 1,
              Set(chain.map(\.openingRecordID)).count == 1,
              chain.allSatisfy({ $0.positionID == positionID && $0.validation().isEmpty }),
              let root = chain.first(where: { $0.supersedesCloseID == nil }),
              chain.filter({ $0.supersedesCloseID == nil }).count == 1 else { return false }
        var successors: [String: [V3UserReportedPositionClose]] = [:]
        for record in chain {
            guard let predecessorID = record.supersedesCloseID else { continue }
            guard let predecessor = chain.first(where: { $0.id == predecessorID }),
                  predecessor.positionID == record.positionID,
                  predecessor.planID == record.planID,
                  predecessor.openingRecordID == record.openingRecordID,
                  predecessor.recordedAt <= record.recordedAt else { return false }
            successors[predecessorID, default: []].append(record)
        }
        guard successors.values.allSatisfy({ $0.count == 1 }) else { return false }
        var visited: Set<String> = []
        var current: V3UserReportedPositionClose? = root
        while let record = current, visited.insert(record.id).inserted {
            current = successors[record.id]?.first
        }
        return visited.count == chain.count
    }

    private static func validOpeningChain(_ chain: [V3PositionRecord], positionID: String) -> Bool {
        guard !chain.isEmpty, Set(chain.map(\.id)).count == chain.count,
              Set(chain.compactMap(\.planID)).count == 1,
              chain.allSatisfy({ $0.positionID == positionID && $0.validation().isEmpty }),
              let root = chain.first(where: { $0.supersedesRecordID == nil }),
              chain.filter({ $0.supersedesRecordID == nil }).count == 1 else { return false }
        var successors: [String: [V3PositionRecord]] = [:]
        for record in chain {
            guard let predecessorID = record.supersedesRecordID else { continue }
            guard let predecessor = chain.first(where: { $0.id == predecessorID }),
                  predecessor.positionID == record.positionID,
                  predecessor.planID == record.planID,
                  predecessor.instrument == record.instrument,
                  predecessor.side == record.side,
                  predecessor.updatedAt <= record.updatedAt else { return false }
            successors[predecessorID, default: []].append(record)
        }
        guard successors.values.allSatisfy({ $0.count == 1 }) else { return false }
        var visited: Set<String> = []
        var current: V3PositionRecord? = root
        while let record = current, visited.insert(record.id).inserted {
            current = successors[record.id]?.first
        }
        return visited.count == chain.count
    }

    var unlinkedEvidence: [V3ReviewTimelineItem] {
        let planIDs = Set(plans.map(\.id))
        var items: [V3ReviewTimelineItem] = []
        items += setupLifecycleEvents.filter { $0.planID.map { !planIDs.contains($0) } ?? true }
            .map(lifecycleItem)
        items += planEntryEvidence.filter { !planIDs.contains($0.planID) }.map(entryItem)
        items += positions.filter { $0.planID.map { !planIDs.contains($0) } ?? true }
            .map { positionItem($0, isSuperseded: false, terminalSourceTime: nil) }
        items += positionCloses.filter { !planIDs.contains($0.planID) }
            .map { positionCloseItem($0, isSuperseded: false, openingWasSuperseded: false) }
        items += spotOutcomes.filter { !planIDs.contains($0.planID) }.map(spotItem)
        items += structuralOutcomes.filter { !planIDs.contains($0.planID) }.map(structuralItem)
        return Self.sorted(items)
    }

    private func planItem(_ plan: V3TradePlan) -> V3ReviewTimelineItem {
        V3ReviewTimelineItem(id: "plan|\(plan.id)", date: plan.createdAt, kind: "plan",
            title: "Research plan · \(plan.instrument) · \(plan.side.rawValue)",
            detail: "Plan ID \(plan.id) · strategy \(plan.strategyID) \(plan.strategyVersion) · engine \(plan.engineVersion) · quality unavailable for plans · provider/environment unavailable · a plan is not an entry or fill.")
    }

    private func lifecycleItem(_ event: V3SetupLifecycleEvent) -> V3ReviewTimelineItem {
        let sourceTime = event.sourceTime.map(Self.dateText) ?? "unavailable"
        let engine = event.engineVersion ?? "unavailable"
        return V3ReviewTimelineItem(id: "lifecycle|\(event.id)", date: event.recordedAt,
            kind: "setup lifecycle", title: "Setup lifecycle · \(event.state.rawValue)",
            detail: "Recorded \(Self.dateText(event.recordedAt)) · source time \(sourceTime) · received \(Self.dateText(event.receivedAt)) · \(event.provider) / \(event.environment.rawValue) · engine \(engine) · quality unavailable for lifecycle events · \(event.reason)")
    }

    private func entryItem(_ entry: V3PlanEntryEvidence) -> V3ReviewTimelineItem {
        let observation = entry.observation
        return V3ReviewTimelineItem(id: "entry|\(entry.id)", date: entry.recordedAt,
            kind: "entry evidence", title: "Entry evidence · \(observation.instrument)",
            detail: "Plan \(entry.planID) · bid \(observation.bid) / ask \(observation.ask) · recorded \(Self.dateText(entry.recordedAt)) · source time \(Self.dateText(observation.sourceTime)) · received \(Self.dateText(observation.receivedAt)) · \(observation.provider) / \(observation.environment.rawValue) · quality \(entry.quality.rawValue). Hypothetical market entry reference; not an order, fill, or position.")
    }

    private func positionItem(_ position: V3PositionRecord, isSuperseded: Bool,
                              terminalSourceTime: Date?) -> V3ReviewTimelineItem {
        let entered = position.userReportedEnteredAt.map(Self.dateText) ?? "unavailable"
        let price = position.entryPrice.map(String.init(describing:)) ?? "unavailable"
        let timing: String
        if let terminalSourceTime, let enteredAt = position.userReportedEnteredAt {
            timing = enteredAt > terminalSourceTime ? "outside plan window" : "before terminal source time (unverified)"
        } else if terminalSourceTime != nil {
            timing = "entry timing unavailable relative to terminal setup"
        } else {
            timing = "no terminal setup time available"
        }
        let supersession = isSuperseded ? " · superseded by a later user correction" : " · current report in this correction chain"
        let assurance = position.state == .userReported
            ? "User-reported; not independently verified and not a broker fill."
            : "Position evidence is not a validated current-position stream."
        return V3ReviewTimelineItem(id: "position|\(position.id)", date: position.updatedAt,
            kind: "position evidence", title: "User-reported position · \(position.instrument)",
            detail: "Reported \(Self.dateText(position.updatedAt)) · entered at \(entered) · actual entry price \(price) · actual total units \(position.units) · side \(position.side.rawValue) · quality/provenance \(position.provenance.rawValue) · \(timing)\(supersession). \(assurance)")
    }

    private func positionCloseItem(_ close: V3UserReportedPositionClose, isSuperseded: Bool,
                                   openingWasSuperseded: Bool) -> V3ReviewTimelineItem {
        let closeTime = close.closedAt.map(Self.dateText) ?? "unavailable"
        let price = close.exitPrice.map(String.init(describing:)) ?? "unavailable"
        let correction = isSuperseded ? "superseded by a later close correction" : "current close report"
        let openingStatus = openingWasSuperseded
            ? "referenced opening revision was later superseded"
            : "referenced opening revision remains current"
        return V3ReviewTimelineItem(id: "position-close|\(close.id)", date: close.recordedAt,
            kind: "user-reported close", title: "User-reported manual close · \(close.positionID)",
            detail: "Reported at \(Self.dateText(close.recordedAt)) · close time \(closeTime) · exit price \(price) · opening revision \(close.openingRecordID) (\(openingStatus)) · \(correction). User-reported/manual, unverified, not broker-confirmed.")
    }

    private func spotItem(_ outcome: V3DurableSpotOutcome) -> V3ReviewTimelineItem {
        let entryProvenance = observationDetail("entry", outcome.entryObservation)
        let exitProvenance = observationDetail("exit", outcome.exitObservation)
        return V3ReviewTimelineItem(id: "spot|\(outcome.id)", date: outcome.recordedAt,
            kind: "spot outcome", title: "Spot outcome · \(outcome.evaluation.status.rawValue)",
            detail: "Recorded \(Self.dateText(outcome.recordedAt)) · envelope \(outcome.provider) / \(outcome.environment.rawValue) · \(entryProvenance) · \(exitProvenance) · strategy \(outcome.strategyVersion) · engine \(outcome.engineVersion) · quality unavailable for durable spot outcomes · P&L \(outcome.evaluation.notionalPnl.map(String.init(describing:)) ?? "unavailable") · cost fields unavailable (not recorded; no estimates).")
    }

    private func structuralItem(_ outcome: V3StructuralOutcome) -> V3ReviewTimelineItem {
        let entryProvenance = observationDetail("entry", outcome.entryObservation)
        let exitProvenance = observationDetail("exit", outcome.exitObservation)
        return V3ReviewTimelineItem(id: "structural|\(outcome.id)", date: outcome.recordedAt,
            kind: "structural outcome", title: "Structural outcome · \(outcome.status.rawValue)",
            detail: "First sampled stop/target trigger · simulated structural outcome · Recorded \(Self.dateText(outcome.recordedAt)) · \(entryProvenance) · \(exitProvenance) · strategy \(outcome.strategyVersion) · engine \(outcome.engineVersion) · quality \(outcome.quality.rawValue) · net P&L \(value(outcome.netPnl)) · spread cost \(value(outcome.spreadCost)) · additional costs \(value(outcome.additionalCosts)) · persisted values as stored; units are not normalized. This is a sampled market path, not a user or broker close.")
    }

    private func observationDetail(_ label: String, _ observation: V3MarketObservation?) -> String {
        guard let observation else { return "\(label) observation unavailable" }
        return "\(label) \(observation.provider) / \(observation.environment.rawValue) · source \(Self.dateText(observation.sourceTime)) · received \(Self.dateText(observation.receivedAt)) · observation \(observation.id)"
    }

    private func value(_ number: Double?) -> String { number.map(String.init(describing:)) ?? "unavailable" }
    private static func sorted(_ items: [V3ReviewTimelineItem]) -> [V3ReviewTimelineItem] {
        items.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.stableSortKey < $1.stableSortKey
        }
    }
    private static func terminalSourceTime(for plan: V3TradePlan,
                                           events: [V3SetupLifecycleEvent]) -> Date? {
        guard let confirmed = events.first(where: { $0.planID == plan.id }) else { return nil }
        return events.filter {
            $0.setupID == confirmed.setupID && [.invalidated, .setupExpired].contains($0.state)
        }.compactMap(\.sourceTime).max()
    }
    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .standard)
    }
}

enum V3ReviewArchiveState: Equatable {
    case loading
    case empty(V3ReviewArchiveSnapshot)
    case populated(V3ReviewArchiveSnapshot)
    case unavailable

    var snapshot: V3ReviewArchiveSnapshot? {
        switch self {
        case .empty(let snapshot), .populated(let snapshot): snapshot
        case .loading, .unavailable: nil
        }
    }

    static func load(root: URL) async -> Self {
        let store = ResearchStore(root: root)
        do {
            let plans = try await store.v3TradePlans()
            let lifecycle = try await store.v3SetupLifecycleEvents()
            let entries = try await store.v3PlanEntryEvidence()
            let positions = try await store.v3PositionRecords()
            let positionCloses = try await store.v3UserReportedPositionCloses()
            let spotOutcomes = try await store.v3SpotOutcomes()
            let structuralOutcomes = try await store.v3StructuralOutcomes()
            let snapshot = V3ReviewArchiveSnapshot(plans: plans, setupLifecycleEvents: lifecycle,
                planEntryEvidence: entries, positions: positions, positionCloses: positionCloses,
                spotOutcomes: spotOutcomes,
                structuralOutcomes: structuralOutcomes)
            return snapshot.totalRecordCount == 0 ? .empty(snapshot) : .populated(snapshot)
        } catch {
            return .unavailable
        }
    }
}

/// V3's Review destination keeps legacy research and journal views available.
struct ReviewScreen: View {
    @ObservedObject var model: LightningDeskModel
    @State private var section: Section = .trades
    @State private var showingCoach = false
    @State private var insightRoute: V3ReviewInsightRoute?
    @State private var reportingPlan: V3TradePlan?
    @State private var liveArchiveState: V3ReviewArchiveState = .loading
    @State private var proxyArchiveState: V3ReviewArchiveState = .loading
    private let liveArchiveRoot: URL
    private let proxyArchiveRoot: URL

    private enum Section: String, CaseIterable, Identifiable {
        case trades = "Trades"
        case research = "Research"
        var id: String { rawValue }
    }

    init(model: LightningDeskModel, researchRoot: URL? = nil) {
        self.model = model
        let root = researchRoot ?? FileLocations.applicationSupport()
            .appendingPathComponent("Research", isDirectory: true)
        liveArchiveRoot = V3ReviewArchiveSource.liveOanda.archiveRoot(under: root)
        proxyArchiveRoot = V3ReviewArchiveSource.proxyResearch.archiveRoot(under: root)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review").font(.system(size: 28, weight: .semibold)).foregroundStyle(DeskInk.ink)
                Spacer()
                Button { showingCoach = true } label: {
                    Label("Coach", systemImage: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskInk.electric)
                }
                .accessibilityLabel("Open contextual Coach")
            }
            .padding(.horizontal, 20).padding(.top, 14)

            Picker("Review section", selection: $section) {
                ForEach(Section.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 12)

            switch section {
            case .trades:
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            V3ReviewArchiveCard(source: .liveOanda, state: liveArchiveState,
                                onReportPosition: { plan in reportingPlan = plan },
                                onExplainInsight: openInsightBrief)
                            V3ReviewArchiveCard(source: .proxyResearch, state: proxyArchiveState,
                                onReportPosition: { _ in }, onExplainInsight: openInsightBrief)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 8)
                    }
                    .frame(maxHeight: 350)
                    JournalScreen(model: model)
                }
            case .research:
                IntelScreen(model: model)
            }
        }
        .task { await loadV3ReviewArchives() }
        .sheet(isPresented: $showingCoach) { CoachScreen(model: model) }
        .sheet(item: $insightRoute, onDismiss: { insightRoute = nil }) { route in
            V3CoachInsightBriefSheet(route: route, onRetry: {
                Task { await validateInsightRoute(route.id) }
            })
        }
        .sheet(item: $reportingPlan) { plan in
            V3UserReportedPositionForm(plan: plan, model: model) { _ in
                reportingPlan = nil
                Task { await loadV3ReviewArchives() }
            }
        }
    }

    private func loadV3ReviewArchives() async {
        liveArchiveState = await V3ReviewArchiveState.load(root: liveArchiveRoot)
        proxyArchiveState = await V3ReviewArchiveState.load(root: proxyArchiveRoot)
    }

    private func openInsightBrief(_ insight: V3ReviewInsight) {
        insightRoute = V3ReviewInsightRoute(original: insight)
        guard let routeID = insightRoute?.id else { return }
        Task { await validateInsightRoute(routeID) }
    }

    @MainActor
    private func validateInsightRoute(_ routeID: UUID) async {
        guard let route = insightRoute, route.id == routeID else { return }
        insightRoute?.state = .loading
        let researchRoot = liveArchiveRoot.deletingLastPathComponent()
        let current = await V3ReviewArchiveState.load(root: route.original.source.archiveRoot(under: researchRoot))
        guard let activeRoute = insightRoute, activeRoute.id == routeID else { return }
        switch route.original.source {
        case .liveOanda: liveArchiveState = current
        case .proxyResearch: proxyArchiveState = current
        }
        switch current {
        case .loading, .unavailable, .empty, .populated:
            insightRoute?.state = V3ReviewInsightRouteValidation.project(
                selectedSource: route.original.source, original: route.original, archive: current)
        }
    }
}

private struct V3ReviewArchiveCard: View {
    let source: V3ReviewArchiveSource
    let state: V3ReviewArchiveState
    let onReportPosition: (V3TradePlan) -> Void
    let onExplainInsight: (V3ReviewInsight) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskInk.ink)
                .accessibilityAddTraits(.isHeader)
            switch state {
            case .loading:
                status("Loading archive", symbol: "clock", color: DeskInk.slate)
            case .unavailable:
                status("Archive unavailable", symbol: "exclamationmark.triangle", color: DeskInk.coral)
            case .empty(let snapshot):
                status("No V3 records", symbol: "tray", color: DeskInk.slate)
                metrics(snapshot)
            case .populated(let snapshot):
                status("\(snapshot.totalRecordCount) V3 records", symbol: "checkmark.circle", color: DeskInk.emerald)
                metrics(snapshot)
                ForEach(snapshot.plans, id: \.id) { plan in
                    if let detail = snapshot.detail(for: plan.id) { planDetail(detail) }
                }
                let unlinked = snapshot.unlinkedEvidence
                if !unlinked.isEmpty {
                    DisclosureGroup("Unlinked / unresolved evidence (\(unlinked.count))") {
                        ForEach(unlinked) { timelineRow($0) }
                    }
                    .accessibilityLabel("Unlinked or unresolved evidence")
                }
            }
            insightsSection
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private func status(_ label: String, symbol: String, color: Color) -> some View {
        Label(label, systemImage: symbol).font(.system(size: 10, weight: .medium))
            .foregroundStyle(color).accessibilityLabel("\(source.title): \(label)")
    }

    private func metrics(_ snapshot: V3ReviewArchiveSnapshot) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            metric("V3 trade plans", snapshot.planCount)
            metric("Setup lifecycle events", snapshot.setupLifecycleEventCount)
            metric("Plan entry-evidence events", snapshot.planEntryEvidenceEventCount)
            metric("Position evidence records", snapshot.positionEventCount)
            metric("Executable spot outcomes", snapshot.spotOutcomeCount)
            metric("Structural outcomes", snapshot.structuralOutcomeCount)
        }
    }

    private var insightsSection: some View {
        let insightState = V3ReviewInsightsState.project(archive: self.state, source: source)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Insights")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(DeskInk.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("v3.review.insights.title.\(source.directoryName)")
            switch insightState {
            case .loading:
                insightStatus("Loading insights · \(source.title)")
            case .unavailable:
                insightStatus("Insights unavailable · \(source.title) archive could not be read")
            case .emptyArchive:
                insightStatus("No V3 records · no insights for \(source.title)")
            case .noMatchingInsights:
                insightStatus("No matching close-completeness insights · \(source.title)")
            case .insights(let values):
                insightStatus("\(values.count) close-completeness insights · \(source.title)")
                ForEach(values) { insight in
                    DisclosureGroup {
                        Text("Source archive: \(insight.source.title)")
                            .font(.caption2)
                        Text(insight.visibleCitationText)
                            .font(.caption2.monospaced())
                            .accessibilityIdentifier("v3.review.insight.citations.\(insight.id)")
                        Text("Missing: \(insight.missingFields.joined(separator: " and ")). These values remain unavailable; none are inferred.")
                            .font(.caption2)
                        Text("User-reported/manual, unverified, not broker-confirmed.")
                            .font(.caption2)
                        if insight.openingWasSuperseded {
                            Text("Referenced opening revision \(insight.openingRecordID) was later superseded.")
                                .font(.caption2)
                        }
                        ForEach(insight.evidenceRows) { timelineRow($0) }
                    } label: {
                        Text("Close report \(insight.closeID) · missing \(insight.missingFields.joined(separator: " and "))")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel(insight.accessibilityLabel)
                    .accessibilityIdentifier("v3.review.insight.\(insight.id)")
                    Button {
                        onExplainInsight(insight)
                    } label: {
                        Label("Explain in Coach", systemImage: "text.magnifyingglass")
                    }
                    .accessibilityLabel("Explain close report \(insight.closeID) from \(insight.source.title) in Coach")
                    .accessibilityIdentifier("v3.review.insight.explain.\(insight.source.directoryName).\(insight.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("v3.review.insights.\(source.directoryName)")
    }

    private func insightStatus(_ value: String) -> some View {
        Text(value).font(.caption2).foregroundStyle(DeskInk.slate)
            .accessibilityIdentifier("v3.review.insights.status.\(source.directoryName)")
    }

    private func metric(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(DeskInk.slate)
            Spacer(minLength: 2)
            Text("\(count)").font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(DeskInk.ink)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue("\(count)")
    }

    private func planDetail(_ detail: V3ReviewPlanDetail) -> some View {
        DisclosureGroup("\(detail.plan.instrument) · \(detail.plan.side.rawValue) · \(detail.plan.id)") {
            Text("Created \(detail.plan.createdAt.formatted(date: .numeric, time: .standard)) · state \(detail.plan.state.rawValue)")
                .font(.caption2)
            Text("Plan only; it does not imply entry, fill, or outcome.")
                .font(.caption2).foregroundStyle(DeskInk.slate)
            if source == .liveOanda {
                if detail.hasLegacyUserReportedPosition {
                    Text("An older user-reported position exists and needs review before another report can be added.")
                        .font(.caption2).foregroundStyle(.orange)
                        .accessibilityIdentifier("v3.position.legacy-review-required")
                } else {
                    Button(detail.currentUserReportedPosition == nil
                        ? "Record position I opened" : "Correct user-reported position") {
                        onReportPosition(detail.plan)
                    }
                    .accessibilityIdentifier("v3.position.report-action")
                }
            }
            ForEach(Array(detail.emptyCategories.enumerated()), id: \.offset) { index, category in
                Text(category).font(.caption2).foregroundStyle(DeskInk.slate)
                    .accessibilityIdentifier(category == "No position evidence record is stored."
                        ? "v3.review.no-position-evidence.\(detail.plan.id)"
                        : "v3.review.empty-category.\(detail.plan.id).\(index)")
            }
            ForEach(detail.timeline.filter { $0.kind != "plan" }) { timelineRow($0) }
            if !detail.integrity.isEmpty {
                DisclosureGroup("Integrity conflicts (\(detail.integrity.count))") {
                    ForEach(detail.integrity) { timelineRow($0) }
                }
                .accessibilityLabel("Integrity conflicts for plan \(detail.plan.id)")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .accessibilityLabel("Review details for plan \(detail.plan.id), \(detail.plan.instrument)")
        .accessibilityIdentifier("v3.review.plan-detail.\(detail.plan.id)")
        .accessibilityValue(detail.emptyCategories.contains("No position evidence record is stored.")
            ? "No position evidence is linked for plan \(detail.plan.id)"
            : "Position evidence is linked for plan \(detail.plan.id)")
    }

    private func timelineRow(_ item: V3ReviewTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.date.formatted(date: .numeric, time: .standard)) · \(item.title)")
                .font(.caption2.weight(.semibold))
            Text(item.detail).font(.caption2).foregroundStyle(DeskInk.slate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.detail)")
        .accessibilityValue(item.date.formatted(date: .numeric, time: .standard))
        .padding(.vertical, 3)
    }
}

private struct V3CoachInsightBriefSheet: View {
    let route: V3ReviewInsightRoute
    let onRetry: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: V3ReviewInsightQuestion?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Insight explanation")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Deterministic record brief · local archive snapshot")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DeskInk.slate)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Coach")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Return to Review") { dismiss() }
                        .accessibilityIdentifier("v3.coach.insight.return")
                }
            }
        }
        .accessibilityIdentifier("v3.coach.insight.brief")
        .onChange(of: route.state) { _, state in
            if state.insight == nil { selectedQuestion = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route.state {
        case .loading:
            ProgressView("Rechecking selected archive…")
                .accessibilityIdentifier("v3.coach.insight.loading")
        case .unavailable:
            unavailable("This source archive could not be read. No insight details are shown.")
        case .empty:
            unavailable("This source archive is now empty. No insight details are shown.")
        case .stale:
            VStack(alignment: .leading, spacing: 10) {
                Text("This insight changed or is no longer available in its source archive. No saved details are shown.")
                    .accessibilityIdentifier("v3.coach.insight.stale")
                Button("Reload this archive", action: onRetry)
                    .accessibilityIdentifier("v3.coach.insight.retry")
            }
        case .ready(let insight):
            VStack(alignment: .leading, spacing: 10) {
                Text("Source archive: \(insight.source.title)")
                    .font(.headline)
                Text(insight.visibleCitationText)
                    .font(.caption.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("v3.coach.insight.citations")
                Text("Missing: \(insight.missingFields.joined(separator: " and ")). These values are not recorded and remain unavailable; none are inferred.")
                Text("User-reported/manual. Unverified and not broker-confirmed.")
                if insight.openingWasSuperseded {
                    Text("The cited opening revision \(insight.openingRecordID) was later superseded. It is historical evidence, not the current opening.")
                }
                Text("Evidence rows from this local archive snapshot")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(insight.evidenceRows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(row.date.formatted(date: .numeric, time: .standard)) · \(row.title)")
                            .font(.caption.weight(.semibold))
                        Text("\(row.id) · \(row.detail)")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Supported questions")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(V3ReviewInsightQuestion.supported) { question in
                        Button(question.rawValue) {
                            selectedQuestion = question
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("v3.coach.insight.intent.\(question.id.stableIntentID)")
                    }
                    if let selectedQuestion,
                       let answer = V3ReviewInsightQuestionAnswer.make(
                        question: selectedQuestion, route: route.state) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(answer.question.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(answer.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("v3.coach.insight.intent.answer")
                            Text("Citations: \(answer.citations.joined(separator: " · "))")
                                .font(.caption.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("v3.coach.insight.intent.citations")
                        }
                        .padding(10)
                        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .contain)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("v3.coach.insight.ready")
        }
    }

    private func unavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).accessibilityIdentifier("v3.coach.insight.unavailable")
            Button("Retry", action: onRetry)
                .accessibilityIdentifier("v3.coach.insight.retry")
        }
    }
}

private extension String {
    var stableIntentID: String {
        lowercased().replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }
}
