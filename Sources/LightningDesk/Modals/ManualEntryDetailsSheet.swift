import BlazerCore
import SwiftUI

/// Optional broker details after the user manually places the Pocket Option trade.
/// Nothing here changes the engine, score, strike, deadline, or confirmed outcome.
struct ManualEntryDetailsSheet: View {
    @ObservedObject var model: LightningDeskModel
    @Environment(\.dismiss) private var dismiss

    @State private var entryPrice = ""
    @State private var stake = ""
    @State private var payout = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Optional broker details") {
                    TextField("Broker entry price", text: $entryPrice)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    TextField("Stake", text: $stake)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                    TextField("Net payout ratio (0.88 = 88%)", text: $payout)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
                }
                Section {
                    Text("Leave a field blank if you do not know it. BlazerOS never infers a broker price, stake, or payout. These values are saved locally only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("I placed this trade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.updateActiveEntryDetails(
                                brokerEntryPrice: Double(entryPrice),
                                stake: Double(stake),
                                payout: Double(payout)
                            )
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                entryPrice = model.activeTrade?.brokerEntryPrice.map { String($0) } ?? ""
                stake = model.activeTrade?.stake.map { String($0) } ?? ""
                payout = model.activeTrade?.payout.map { String($0) } ?? ""
            }
        }
    }
}
