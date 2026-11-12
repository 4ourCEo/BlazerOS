import SwiftUI

/// Captures the actual broker execution time for a trade recorded after the live beam.
/// Recording time is never substituted for an unknown execution time.
struct LateEntrySheet: View {
    @ObservedObject var model: LightningDeskModel
    @Environment(\.dismiss) private var dismiss
    @State private var enteredAt = Date().addingTimeInterval(-30)
    @State private var entrySecond = Calendar.current.component(.second, from: Date().addingTimeInterval(-30))
    @State private var saving = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual broker execution") {
                    DatePicker(
                        "Entry time",
                        selection: $enteredAt,
                        in: Date().addingTimeInterval(-10 * 60)...Date(),
                        displayedComponents: [.hourAndMinute]
                    )
                    Stepper("Seconds: \(entrySecond)", value: $entrySecond, in: 0...59)
                        Text("Use the precise time shown by the broker. This records late evidence and never claims the entry was within the eight-second window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Record without execution time") {
                        guard !saving else { return }
                        saving = true
                        Task {
                            await model.recordUnknownLateEntryTime()
                            await MainActor.run {
                                saving = false
                                if model.entryIssue == "Recorded as incomplete evidence; no expiry was inferred" {
                                    statusMessage = model.entryIssue
                                } else {
                                    statusMessage = model.entryIssue ?? "Could not save incomplete evidence"
                                }
                            }
                        }
                    }
                    .disabled(saving)
                    Text("Unknown time is saved only as an incomplete research observation. It does not create a trade or guessed outcome.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: statusMessage.hasPrefix("Recorded") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(statusMessage.hasPrefix("Recorded") ? .green : .orange)
                    }
                }
            }
            .navigationTitle("Log Late Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving else { return }
                        saving = true
                        Task {
                            await model.lockInTrade(late: true, actualEntryTime: preciseEnteredAt)
                            await MainActor.run {
                                saving = false
                                if model.activeTrade != nil {
                                    dismiss()
                                } else {
                                    statusMessage = model.entryIssue ?? "Entry was not recorded"
                                }
                            }
                        }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Record Late Entry")
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private var preciseEnteredAt: Date {
        Calendar.current.date(bySetting: .second, value: entrySecond, of: enteredAt) ?? enteredAt
    }
}
