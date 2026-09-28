import BlazerCore
import SwiftUI

/// Shown when Keychain has no OANDA credentials, or opened via Desk settings.
struct CredentialCover: View {
    @ObservedObject var model: LightningDeskModel

    var body: some View {
        ZStack {
            DeskInk.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Quote source")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                    Spacer()
                    Button("Close") {
                        model.showingCredentials = false
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }

                Text("Saved in the Keychain on this device only.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DeskInk.slate)

                SecureField("Token", text: $model.draftToken)
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(DeskInk.ink)

                TextField("Account", text: $model.draftAccount)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(DeskInk.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(DeskInk.ink)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        environmentChoice(.practice, title: "Practice")
                        environmentChoice(.live, title: "Live")
                    }

                    Text(model.draftEnvironment == .practice
                        ? "Practice connects to OANDA fxpractice (demo account)."
                        : "Live connects to OANDA fxtrade (real funded account).")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                }

                if model.credentialSaveFailed {
                    Text("Could not save to the Keychain.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DeskInk.coral)
                }

                Button {
                    let success = model.storeCredentials(
                        token: model.draftToken,
                        accountId: model.draftAccount,
                        environment: model.draftEnvironment
                    )
                    model.credentialSaveFailed = !success
                    if success {
                        model.showingCredentials = false
                    }
                } label: {
                    Text("Connect Account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DeskInk.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(colors: [DeskInk.indigo, DeskInk.electric], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.draftToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.draftAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.top, 4)

                Button {
                    model.loadDemoDesk()
                    model.showingCredentials = false
                } label: {
                    Text("Explore Demo Desk (Simulated)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DeskInk.electric)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DeskInk.surface, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(24)
            .padding(.top, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private func environmentChoice(_ choice: OandaEnvironment, title: String) -> some View {
        let isSelected = model.draftEnvironment == choice
        return Button {
            DeskHaptics.tabSwitch()
            model.draftEnvironment = choice
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? DeskInk.electric : DeskInk.slate.opacity(0.6))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? DeskInk.ink : DeskInk.slate)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                (isSelected ? DeskInk.indigo.opacity(0.4) : DeskInk.surface),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? DeskInk.electric.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
