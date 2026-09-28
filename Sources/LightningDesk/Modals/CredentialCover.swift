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
                    if model.keychainState != .missing {
                        Button("Close") {
                            model.showingCredentials = false
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DeskInk.slate)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                    }
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

                HStack(spacing: 10) {
                    environmentChoice(.practice, title: "Practice")
                    environmentChoice(.live, title: "Live")
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
                    Text("Continue")
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
                .padding(.top, 8)

                Spacer()
            }
            .padding(24)
            .padding(.top, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private func environmentChoice(_ choice: OandaEnvironment, title: String) -> some View {
        Button {
            model.draftEnvironment = choice
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.draftEnvironment == choice ? DeskInk.ink : DeskInk.slate)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    (model.draftEnvironment == choice ? DeskInk.indigo.opacity(0.45) : DeskInk.surface),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
