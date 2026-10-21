import BlazerCore
import SwiftUI

/// Compact "Track Trade" sheet for an external Crypto.com Strike contract.
///
/// Deterministic card (moneyness, breakeven, decay gate, basis) comes from `StrikeMath`.
/// The optional AI card is ADVISORY ONLY and labeled as such. No order is ever placed from here.
struct StrikeTradeSheet: View {
    @ObservedObject var model: LightningDeskModel
    @Environment(\.dismiss) private var dismiss

    @State private var strikeText = ""
    @State private var askText = "0.50"
    @State private var minutesText = "5"
    @State private var contractsText = "1"
    @State private var side: StrikeSide = .yes

    private let posix = Locale(identifier: "en_US_POSIX")

    // MARK: Derived inputs

    private var strike: Double? {
        Double(strikeText.trimmingCharacters(in: .whitespaces))
    }

    private var entryPrice: Decimal? {
        Decimal(string: askText.trimmingCharacters(in: .whitespaces), locale: posix)
    }

    private var secondsRemaining: Int? {
        Double(minutesText.trimmingCharacters(in: .whitespaces)).map { Int($0 * 60) }
    }

    private var quantity: Int? {
        Int(contractsText.trimmingCharacters(in: .whitespaces))
    }

    private var expiryDate: Date? {
        Double(minutesText.trimmingCharacters(in: .whitespaces)).map { Date().addingTimeInterval($0 * 60) }
    }

    private var assessment: StrikeAssessment? {
        guard let spot = model.currentPrice, let strike, let entryPrice, let secondsRemaining else {
            return nil
        }
        return StrikeAssessment.evaluate(
            spot: spot, strike: strike, entryPrice: entryPrice, secondsRemaining: secondsRemaining,
            basisWarningBuffer: StrikeMath.basisBuffer(
                spot: spot,
                pipScale: Assets.pipScale(for: model.pair)
            )
        )
    }

    private var direction: String {
        model.side(for: model.pair) == "LOW" ? "BEARISH" : "BULLISH"
    }

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inputs
                    if let assessment {
                        deterministicCard(assessment)
                    } else {
                        Text("Enter a strike and contract ask to see local risk math.")
                            .font(.system(size: 12))
                            .foregroundStyle(DeskInk.slate)
                    }
                    auditSection
                    trackedSection
                    buttons
                }
                .padding(20)
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TRACK EXTERNAL CONTRACT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DeskInk.electric)
                Text("Crypto.com Strike Options")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DeskInk.ink)
                Text("Local tracking only — no order is placed from Blazer.")
                    .font(.system(size: 11))
                    .foregroundStyle(DeskInk.slate)
            }
            Spacer()
            Button {
                DeskHaptics.tabSwitch()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DeskInk.slate.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Listed strike", text: $strikeText, placeholder: "e.g. 68400")
            HStack(spacing: 10) {
                field("Contract ask", text: $askText, placeholder: "0.50")
                field("Contracts", text: $contractsText, placeholder: "1")
            }
            field("Minutes to expiry", text: $minutesText, placeholder: "5")
            HStack(spacing: 8) {
                Text("Side")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskInk.slate)
                ForEach(StrikeSide.allCases, id: \.self) { option in
                    Button {
                        DeskHaptics.tabSwitch()
                        side = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(side == option
                                    ? (option == .yes ? DeskInk.emerald : DeskInk.coral).opacity(0.22)
                                    : Color.white.opacity(0.05))
                            )
                            .foregroundStyle(side == option ? DeskInk.ink : DeskInk.slate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(DeskInk.surface))
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeskInk.slate)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))
        }
    }

    private func deterministicCard(_ a: StrikeAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOCAL RISK MATH")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(DeskInk.slate)
                Spacer()
                Text("breakeven \(pct(a.breakevenWinRate))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
            }
            HStack(spacing: 10) {
                tag(a.moneyness.rawValue, tint: moneynessTint(a.moneyness))
                tag(a.decayGate.rawValue, tint: decayTint(a.decayGate))
                if a.basisWarning {
                    tag("NEAR STRIKE", tint: DeskInk.coral)
                }
            }
            HStack(spacing: 16) {
                stat("Net if win", money(a.netProfitIfWin), tint: DeskInk.emerald)
                stat("Risk if lose", money(a.lossIfLose), tint: DeskInk.coral)
            }
            if a.basisWarning {
                Text("Reference price is close to the strike — settlement-index drift could flip the outcome.")
                    .font(.system(size: 10))
                    .foregroundStyle(DeskInk.slate)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(DeskInk.surface))
    }

    private var auditSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ON-DEVICE ASSISTANT")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(DeskInk.slate)
            Text("Grounded explanations are available in Coach using Apple’s on-device model. Remote AI providers and API keys are disabled in this release.")
                .font(.system(size: 12))
                .foregroundStyle(DeskInk.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(DeskInk.surface))
    }

    private func adviceCard(_ advice: StrikeAuditAdvice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(advisoryLabel(advice.advisoryLabel))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(advisoryTint(advice.advisoryLabel))
                Spacer()
                Text("ASSISTANT OPINION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(DeskInk.slate)
            }
            if !advice.regimeSummary.isEmpty {
                Text(advice.regimeSummary).font(.system(size: 12)).foregroundStyle(DeskInk.ink)
            }
            if !advice.riskWarning.isEmpty {
                Text("⚠︎ " + advice.riskWarning)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskInk.coral)
            }
            ForEach(Array(advice.checklist.enumerated()), id: \.offset) { _, item in
                Text("• " + item).font(.system(size: 11)).foregroundStyle(DeskInk.slate)
            }
            if !advice.coachNote.isEmpty {
                Text(advice.coachNote)
                    .font(.system(size: 10))
                    .foregroundStyle(DeskInk.slate.opacity(0.8))
            }
        }
    }

    private var trackedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRACKED POSITIONS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(DeskInk.slate)
                Spacer()
                Button {
                    DeskHaptics.tabSwitch()
                    model.refreshTrackedStrikePositions()
                } label: {
                    Text("Refresh").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DeskInk.electric)
            }
            if model.trackedStrikePositions.isEmpty {
                Text("No tracked contracts yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(DeskInk.slate)
            } else {
                ForEach(model.trackedStrikePositions) { position in
                    StrikePositionRow(model: model, position: position)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(DeskInk.surface))
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button {
                DeskHaptics.tradeLocked()
                guard let strike, let entryPrice, let expiryDate, let quantity, quantity > 0 else { return }
                model.trackStrikeContract(
                    symbol: model.pair,
                    side: side,
                    strike: strike,
                    expiry: expiryDate,
                    entryPrice: entryPrice,
                    quantity: quantity
                )
                dismiss()
            } label: {
                Text("Track Local")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(assessment == nil || quantity == nil)
        }
    }

    // MARK: Small helpers

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.8))
            .foregroundStyle(tint)
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(DeskInk.slate)
            Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(tint)
        }
    }

    private func money(_ d: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: d).doubleValue)
    }

    private func pct(_ d: Decimal) -> String {
        String(format: "%.0f%%", NSDecimalNumber(decimal: d).doubleValue * 100)
    }

    private func moneynessTint(_ m: StrikeMoneyness) -> Color {
        switch m {
        case .inTheMoney: return DeskInk.emerald
        case .atTheMoney: return DeskInk.slate
        case .outOfTheMoney: return DeskInk.coral
        }
    }

    private func decayTint(_ g: StrikeDecayGate) -> Color {
        switch g {
        case .open: return DeskInk.emerald
        case .lateWindow: return DeskInk.electric
        case .blocked: return DeskInk.coral
        case .expired: return DeskInk.slate
        }
    }

    private func advisoryLabel(_ g: AdvisoryGate) -> String {
        switch g {
        case .proceed: return "PROCEED (opinion)"
        case .caution: return "CAUTION (opinion)"
        case .pass: return "PASS (opinion)"
        }
    }

    private func advisoryTint(_ g: AdvisoryGate) -> Color {
        switch g {
        case .proceed: return DeskInk.emerald
        case .caution: return DeskInk.violet
        case .pass: return DeskInk.coral
        }
    }
}

/// One tracked position: status, quantities, net cash flow, and settle / exit controls.
/// Exit only ever reduces owned quantity (enforced by the ledger).
private struct StrikePositionRow: View {
    @ObservedObject var model: LightningDeskModel
    let position: StrikePosition

    @State private var exitQuantityText = ""
    @State private var exitPriceText = ""

    private let posix = Locale(identifier: "en_US_POSIX")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(position.side.rawValue) \(position.symbol)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeskInk.ink)
                Text("@ \(String(format: "%.2f", position.strike))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DeskInk.slate)
                Spacer()
                statusBadge
            }
            HStack(spacing: 14) {
                meta("Open", "\(position.openQuantity)")
                meta("Entered", "\(position.enteredQuantity)")
                meta("Net", pnlText)
            }
            if position.openQuantity > 0 {
                exitControls
            }
            if position.isPending {
                HStack(spacing: 8) {
                    settleButton("Settle ITM", .inTheMoney, tint: DeskInk.emerald)
                    settleButton("Settle OTM", .outOfTheMoney, tint: DeskInk.coral)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    private var exitControls: some View {
        HStack(spacing: 8) {
            TextField("qty", text: $exitQuantityText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 56)
            TextField("exit price", text: $exitPriceText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 110)
            Button {
                let qty = Int(exitQuantityText.trimmingCharacters(in: .whitespaces)) ?? position.openQuantity
                let price = Decimal(string: exitPriceText.trimmingCharacters(in: .whitespaces), locale: posix)
                model.exitStrikePosition(id: position.id, quantity: qty, pricePerContract: price)
                exitQuantityText = ""
                exitPriceText = ""
            } label: {
                Text("Exit").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
    }

    private func settleButton(_ label: String, _ result: StrikeResult, tint: Color) -> some View {
        Button {
            model.settleStrikePosition(id: position.id, result: result)
        } label: {
            Text(label).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private var statusBadge: some View {
        let (text, tint) = statusStyle
        return Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }

    private var statusStyle: (String, Color) {
        if let s = position.settlement {
            let base = s.result == .inTheMoney ? "ITM" : "OTM"
            let suffix = s.provenance == .venueVerified ? "V" : "U"
            let tint = s.result == .inTheMoney ? DeskInk.emerald : DeskInk.coral
            return ("\(base)·\(suffix)", tint)
        }
        return ("PENDING", DeskInk.violet)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(DeskInk.slate)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DeskInk.ink)
        }
    }

    private var pnlText: String {
        switch position.netCashFlow() {
        case .known(let d): return String(format: "$%.2f", NSDecimalNumber(decimal: d).doubleValue)
        case .unknown: return "unknown"
        }
    }
}
