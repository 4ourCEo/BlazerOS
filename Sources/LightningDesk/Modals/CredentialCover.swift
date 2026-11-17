import BlazerCore
import SwiftUI

/// Shown when Keychain has no OANDA credentials, or opened via Desk settings.
struct CredentialCover: View {
    @ObservedObject var model: LightningDeskModel
    @State private var unlockRequestInFlight = false

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
                        closeCredentialCover()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DeskInk.slate)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                }

                Text(connectionDescription)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(DeskInk.slate)

                #if os(macOS)
                if model.keychainState == .locked && !model.isEditingCredentials {
                    Button {
                        guard !unlockRequestInFlight else { return }
                        unlockRequestInFlight = true
                        Task {
                            await model.scan()
                            unlockRequestInFlight = false
                        }
                    } label: {
                        Text(unlockRequestInFlight ? "Authorizing OANDA…" : "Unlock Saved Credentials & SCAN")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.scanning || unlockRequestInFlight)
                    .accessibilityIdentifier("mac.unlock-oanda-scan")

                    Button("Enter credentials manually") {
                        model.isEditingCredentials = true
                        model.draftEnvironment = .live
                        model.draftToken = ""
                        model.draftAccount = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DeskInk.electric)
                    .accessibilityIdentifier("mac.replace-oanda-credentials")

                    if let issue = model.candleIssue {
                        Text(issue)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DeskInk.coral)
                    }
                }
                if model.keychainState == .locked && model.isEditingCredentials {
                    Button("Back to saved credentials") {
                        model.draftToken = ""
                        model.draftAccount = ""
                        model.isEditingCredentials = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DeskInk.electric)
                }
                #endif

                if model.keychainState == .ready && !model.isEditingCredentials {
                    Button("Change OANDA account") {
                        model.isEditingCredentials = true
                        model.draftEnvironment = .live
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DeskInk.electric)
                }

                if let error = model.credentialConfigurationError {
                    Text(error)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DeskInk.coral)
                }

                if showCredentialFields {
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
                        #if os(iOS)
                        environmentChoice(.practice, title: "Practice")
                        #endif
                        environmentChoice(.live, title: "Live")
                    }

                    #if os(macOS)
                    Text("Live connects to OANDA fxtrade and requests live account market data.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                    #else
                    Text(model.draftEnvironment == .practice
                        ? "Practice connects to OANDA fxpractice (demo account)."
                        : "Live connects to OANDA fxtrade (real funded account).")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeskInk.slate)
                    #endif
                }

                if model.credentialSaveFailed {
                    Text("Could not save OANDA credentials to this device’s Keychain.")
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
                }

#if os(iOS)
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
#endif

                Spacer()
            }
            .padding(24)
            .padding(.top, 10)
        }
        .accessibilityElement(children: .contain)
        .onChange(of: model.keychainState) { _, state in
            #if os(macOS)
            if state == .ready {
                unlockRequestInFlight = false
                model.showingCredentials = false
            }
            #endif
        }
    }

    private var showCredentialFields: Bool {
        #if os(macOS)
        return model.keychainState == .missing || model.isEditingCredentials
        #else
        return model.keychainState != .ready || model.isEditingCredentials
        #endif
    }

    private func closeCredentialCover() {
        model.draftToken = ""
        model.draftAccount = ""
        model.isEditingCredentials = false
        model.showingCredentials = false
    }

    private var connectionDescription: String {
        if model.keychainState == .ready {
            let environment = model.connectedOandaEnvironment?.rawValue.capitalized ?? "OANDA"
            let marketState: String
            switch model.feed {
            case .live:
                marketState = "A recent market quote was verified."
            case .connecting:
                marketState = "Checking broker market-data access."
            case .stale:
                marketState = "The latest quote is stale; refresh before trading."
            case .error:
                marketState = "OANDA rejected or failed the latest request. Check the token and account ID."
            case .disconnected:
                marketState = "The credential is saved, but the quote feed is disconnected."
            }
            return "OANDA \(environment) credentials are saved in this device’s Keychain. \(marketState)"
        }
        #if os(macOS)
        if model.keychainState == .locked {
            return "Saved OANDA Live credentials are locked. Unlock them to scan, or enter replacement credentials manually."
        }
        return "Connect an OANDA Live account. Credentials are stored in this Mac’s Keychain."
        #else
        return "Connect OANDA credentials stored in this device’s Keychain."
        #endif
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
