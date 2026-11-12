import SwiftUI
import BlazerCore

/// V3's Review destination keeps legacy research and journal views available
/// without giving each one a separate primary-navigation slot.
struct ReviewScreen: View {
    @ObservedObject var model: LightningDeskModel
    @State private var section: Section = .trades
    @State private var showingCoach = false
    @State private var v3Plans = 0
    @State private var v3Positions = 0
    @State private var v3Outcomes = 0
    @State private var v3StructuralOutcomes = 0

    private enum Section: String, CaseIterable, Identifiable {
        case trades = "Trades"
        case research = "Research"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Button { showingCoach = true } label: {
                    Label("Coach", systemImage: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DeskInk.electric)
                }
                .accessibilityLabel("Open contextual Coach")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Picker("Review section", selection: $section) {
                ForEach(Section.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            switch section {
            case .trades:
                VStack(spacing: 0) {
                    V3ReviewSummary(plans: v3Plans, positions: v3Positions, outcomes: v3Outcomes,
                                    structuralOutcomes: v3StructuralOutcomes)
                    JournalScreen(model: model)
                }
            case .research:
                IntelScreen(model: model)
            }
        }
        .task { await loadV3ReviewRecords() }
        .sheet(isPresented: $showingCoach) {
            CoachScreen(model: model)
        }
    }

    private func loadV3ReviewRecords() async {
        let store = ResearchStore(root: ResearchStore.defaultRoot())
        do {
            let plans = try await store.v3TradePlans()
            let positions = try await store.v3PositionRecords()
            let outcomes = try await store.v3SpotOutcomes()
            let structuralOutcomes = try await store.v3StructuralOutcomes()
            v3Plans = plans.count
            v3Positions = positions.count
            v3Outcomes = outcomes.count
            v3StructuralOutcomes = structuralOutcomes.count
        } catch {
            // Corrupt or incomplete evidence stays out of the summary; it remains quarantined
            // in the research archive and is never presented as a valid outcome.
        }
    }
}

private struct V3ReviewSummary: View {
    let plans: Int
    let positions: Int
    let outcomes: Int
    let structuralOutcomes: Int

    var body: some View {
        HStack(spacing: 8) {
            metric("V3 plans", plans)
            metric("position events", positions)
            metric("outcomes", outcomes)
            metric("ORB outcomes", structuralOutcomes)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("V3 Review records: \(plans) plans, \(positions) position events, \(outcomes) spot outcomes, \(structuralOutcomes) ORB outcomes")
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 16, weight: .bold))
            Text(title).font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(DeskInk.slate)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(DeskInk.card, in: RoundedRectangle(cornerRadius: 8))
    }
}
