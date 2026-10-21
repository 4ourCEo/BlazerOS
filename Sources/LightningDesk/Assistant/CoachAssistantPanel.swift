import BlazerCore
import SwiftUI

/// Grounded on-device assistant. Every authoritative number shown here comes from the
/// deterministic record; the model only narrates it.
struct CoachAssistantPanel: View {
    @ObservedObject var model: LightningDeskModel
    @State private var question = ""
    @State private var reflection = ""
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            actions
            questionBox
            if let error = model.assistantError {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeskInk.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let answer = model.assistantAnswer { answerCard(answer) }
            if let explanation = model.assistantScanExplanation { explanationCard(explanation) }
            if let debrief = model.assistantDebrief { debriefCard(debrief) }
            if let comparison = model.assistantComparison { comparisonCard(comparison) }
            if !model.assistantResearch.isEmpty { researchCard }
            journalDraftCard
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DeskInk.violet.opacity(0.22), lineWidth: 0.6)
        )
        .task { await model.refreshAssistantAvailability() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("On-device assistant")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: model.assistantAvailability.isReady ? "apple.intelligence" : "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.assistantAvailability.isReady ? DeskInk.emerald : DeskInk.slate)
                Text("On-Device Assistant")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                Text(originLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(originColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(originColor.opacity(0.12), in: Capsule())
            }
            Text(model.assistantAvailability.detail)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.assistantStatus.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DeskInk.slate.opacity(0.85))
        }
    }

    private var actions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                action("Explain latest", "sparkles") { await model.explainLatestScan() }
                action("Debrief", "list.bullet.rectangle") { await model.requestSessionDebrief() }
                action("Compare scans", "rectangle.on.rectangle") { await model.compareLatestScans() }
                action("Research ideas", "flask") { await model.requestResearchSuggestions() }
            }
        }
    }

    private var questionBox: some View {
        HStack(spacing: 8) {
            TextField("Ask about a saved scan…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DeskInk.ink)
                .lineLimit(1...3)
                .padding(10)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.send)
                .onSubmit { ask() }
            Button {
                ask()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(question.trimmingCharacters(in: .whitespaces).isEmpty ? DeskInk.slate : DeskInk.electric)
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Ask the on-device coach")
        }
    }

    private func answerCard(_ answer: CoachAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(answer.answer)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DeskInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !answer.citations.isEmpty {
                Text("Records: \(answer.citations.prefix(4).joined(separator: ", "))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
            }
            Text(answer.limitations)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DeskInk.slate)
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private func explanationCard(_ explanation: ScanExplanation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(explanation.decision) · score \(explanation.score)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
                Spacer()
                if let gate = explanation.blockingGate, !gate.isEmpty {
                    Text(gate.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DeskInk.coral)
                        .lineLimit(1)
                }
            }
            Text(explanation.summary)
                .font(.system(size: 13))
                .foregroundStyle(DeskInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !explanation.evidenceUsed.isEmpty {
                Text("Recorded evidence: \(explanation.evidenceUsed.joined(separator: " · "))")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !explanation.missingEvidence.isEmpty {
                Text("Missing: \(explanation.missingEvidence.joined(separator: " · "))")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskInk.coral.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(explanation.coachNote)
                .font(.system(size: 11))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
            if !explanation.recordID.isEmpty {
                Text("Record \(explanation.recordID)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DeskInk.slate.opacity(0.8))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private func debriefCard(_ debrief: SessionDebrief) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(debrief.summary)
                .font(.system(size: 13))
                .foregroundStyle(DeskInk.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                metric("Confirmed", "\(debrief.sampleSize)")
                metric("Wins", "\(debrief.wins)")
                metric("Losses", "\(debrief.losses)")
                metric("Unresolved", "\(debrief.unresolved)")
            }
            if !debrief.missingConfirmations.isEmpty {
                Text("Missing confirmations: \(debrief.missingConfirmations.prefix(4).joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
            }
            if !debrief.lateEntries.isEmpty {
                Text("Late entries: \(debrief.lateEntries.prefix(4).joined(separator: ", "))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DeskInk.coral)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonCard(_ comparison: ScanComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(comparison.explanation)
                .font(.system(size: 13))
                .foregroundStyle(DeskInk.ink)
            ForEach(Array(comparison.differences.prefix(8).enumerated()), id: \.offset) { _, diff in
                Text("\(diff.field): \(diff.left) → \(diff.right)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(comparison.limitations)
                .font(.system(size: 10))
                .foregroundStyle(DeskInk.slate)
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private var researchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.assistantResearch) { suggestion in
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Text(suggestion.proposedExperiment)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskInk.slate)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Records: \(suggestion.supportingRecordIDs.prefix(3).joined(separator: ", "))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DeskInk.slate.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private var journalDraftCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Journal draft")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeskInk.ink)
            TextEditor(text: $reflection)
                .font(.system(size: 12))
                .frame(minHeight: 64)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Draft annotations") {
                    Task { await model.draftJournalNote(reflection) }
                }
                .buttonStyle(.bordered)
                .disabled(reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if let draft = model.assistantJournalDraft {
                    Button("Save to latest entry") {
                        Task {
                            if let id = model.journal.first?.id {
                                await model.saveAssistantJournalDraft(draft, entryID: id)
                                saveMessage = "Saved as an annotation. The original note was preserved."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let draft = model.assistantJournalDraft {
                Text(draft.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(DeskInk.ink)
                Text("Emotion: \(draft.emotion) · \(draft.discipline)")
                    .font(.system(size: 10))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Lesson: \(draft.lesson)")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskInk.slate)
                    .fixedSize(horizontal: false, vertical: true)
                if !draft.tags.isEmpty {
                    Text("Tags: \(draft.tags.joined(separator: ", "))")
                        .font(.system(size: 10))
                        .foregroundStyle(DeskInk.electric)
                }
            }
            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(DeskInk.emerald)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DeskInk.slate)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(DeskInk.ink)
        }
    }

    private func action(_ title: String, _ icon: String, run: @escaping @MainActor () async -> Void) -> some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DeskInk.electric)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(DeskInk.electric.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private var isGenerating: Bool {
        if case .generating = model.assistantStatus { return true }
        return false
    }

    private func ask() {
        let text = question
        question = ""
        Task { await model.askAssistant(text) }
    }

    private var originLabel: String {
        switch model.assistantOrigin {
        case .appleOnDevice: return "APPLE ON-DEVICE"
        case .deterministicFallback: return "BASIC FALLBACK"
        case nil: return model.assistantAvailability.isReady ? "READY" : "BASIC FALLBACK"
        }
    }

    private var originColor: Color {
        switch model.assistantOrigin {
        case .appleOnDevice: return DeskInk.emerald
        case .deterministicFallback: return DeskInk.violet
        case nil: return model.assistantAvailability.isReady ? DeskInk.slate : DeskInk.violet
        }
    }
}
