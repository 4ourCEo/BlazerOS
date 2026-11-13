import BlazerCore
import SwiftUI

/// Shown when Keychain has no OANDA credentials, or opened via Desk settings.
struct CredentialCover: View {
    @ObservedObject var model: LightningDeskModel
    var practiceOnly = false

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Quote source")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(primaryText)
                    Spacer()
                    Button("Close") {
                        model.showingCredentials = false
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(secondaryText)
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
                    .background(fieldSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(primaryText)

                TextField("Account", text: $model.draftAccount)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(fieldSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(primaryText)

                VStack(alignment: .leading, spacing: 6) {
                    if practiceOnly {
                        Label("OANDA Practice", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(practiceOnly ? Color(red: 0.16, green: 0.42, blue: 0.78) : DeskInk.electric)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(practiceOnly ? Color(red: 0.91, green: 0.95, blue: 0.99) : DeskInk.indigo.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        HStack(spacing: 10) {
                            environmentChoice(.practice, title: "Practice")
                            environmentChoice(.live, title: "Live")
                        }
                    }

                    Text(practiceOnly || model.draftEnvironment == .practice
                        ? "Practice connects to OANDA fxpractice (demo account)."
                        : "Live connects to OANDA fxtrade (real funded account).")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(secondaryText)
                }

                if practiceOnly && model.keychainState == .locked {
                    Text("Keychain access was not authorized. This app uses its Mac-only OANDA service. If macOS asks, authorize the signed BlazerOS app once; repeated prompts usually indicate a signing-identity mismatch.")
                        .font(.system(size: 12)).foregroundStyle(Color.orange)
                } else if practiceOnly && model.keychainState == .missing {
                    Text("No Practice credential is stored for this Mac app yet.")
                        .font(.system(size: 12)).foregroundStyle(secondaryText)
                }

                if model.credentialSaveFailed {
                    Text("Could not save to the Keychain.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(practiceOnly ? Color.red : DeskInk.coral)
                }

                Button {
                    let success = model.storeCredentials(
                        token: model.draftToken,
                        accountId: model.draftAccount,
                        environment: practiceOnly ? .practice : model.draftEnvironment
                    )
                    model.credentialSaveFailed = !success
                    if success {
                        model.showingCredentials = false
                    }
                } label: {
                    Text("Connect Account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            practiceOnly ? AnyShapeStyle(Color(red: 0.16, green: 0.42, blue: 0.78))
                                : AnyShapeStyle(LinearGradient(colors: [DeskInk.indigo, DeskInk.electric], startPoint: .leading, endPoint: .trailing)),
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
                        .foregroundStyle(practiceOnly ? Color(red: 0.16, green: 0.42, blue: 0.78) : DeskInk.electric)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    .background(fieldSurface, in: Capsule())
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

    private var backgroundColor: Color { practiceOnly ? Color(red: 0.965, green: 0.977, blue: 0.99) : DeskInk.background }
    private var fieldSurface: Color { practiceOnly ? .white : DeskInk.surface }
    private var primaryText: Color { practiceOnly ? Color(red: 0.12, green: 0.19, blue: 0.29) : DeskInk.ink }
    private var secondaryText: Color { practiceOnly ? Color(red: 0.39, green: 0.48, blue: 0.59) : DeskInk.slate }
}
