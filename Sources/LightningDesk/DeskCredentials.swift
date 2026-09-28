import Foundation
import LocalAuthentication
import Security
import BlazerCore

/// Result of a keychain read. `locked` means the item exists and needs an Allow click.
public enum CredentialGate: Sendable {
    case ready(OandaSession)
    case locked
    case missing
}

/// Device Keychain only. The token is never written into the desk model or a synced record.
public enum DeskCredentials {
    private static let phoneService = "com.blazer.os.oanda"
    private static let macService = "com.blazer.mac.oanda"

    /// `allowPrompt` false returns immediately when macOS would otherwise wait on an Allow dialog.
    public static func session(allowPrompt: Bool) -> CredentialGate {
        switch read(service: phoneService, allowPrompt: allowPrompt) {
        case .ready(let session):
            return .ready(session)
        case .locked:
            return .locked
        case .missing:
            break
        }
        #if os(macOS)
        switch read(service: macService, allowPrompt: allowPrompt) {
        case .ready(let session):
            return .ready(session)
        case .locked:
            return .locked
        case .missing:
            break
        }
        if let token = ProcessInfo.processInfo.environment["OANDA_API_TOKEN"],
            let accountId = ProcessInfo.processInfo.environment["OANDA_ACCOUNT_ID"],
            !token.isEmpty, !accountId.isEmpty
        {
            let env = ProcessInfo.processInfo.environment["OANDA_ENV"]?.lowercased()
            let environment: OandaEnvironment = env == "live" ? .live : .practice
            return .ready(OandaSession(token: token, accountId: accountId, environment: environment))
        }
        #endif
        return .missing
    }

    private static func read(service: String, allowPrompt: Bool) -> CredentialGate {
        let token = item(service: service, account: "token", allowPrompt: allowPrompt)
        let accountId = item(service: service, account: "accountId", allowPrompt: allowPrompt)
        switch (token, accountId) {
        case (.value(let token), .value(let accountId)) where !token.isEmpty && !accountId.isEmpty:
            let env = item(service: service, account: "env", allowPrompt: allowPrompt)
            let name: String?
            if case .value(let raw) = env {
                name = raw.lowercased()
            } else {
                name = nil
            }
            let environment: OandaEnvironment = name == "live" ? .live : .practice
            return .ready(OandaSession(token: token, accountId: accountId, environment: environment))
        case (.locked, _), (_, .locked):
            return .locked
        default:
            return .missing
        }
    }

    private enum ItemRead {
        case value(String)
        case missing
        case locked
    }

    private static func item(service: String, account: String, allowPrompt: Bool) -> ItemRead {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        query[kSecUseAuthenticationContext as String] = context
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) {
            return .value(text)
        }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return .locked
        }
        return .missing
    }

    /// Writes the phone Keychain items. The token is not returned and not logged.
    static func store(token: String, accountId: String, environment: OandaEnvironment) -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedAccount.isEmpty else { return false }
        let tokenSaved = write(service: phoneService, account: "token", value: trimmedToken)
        let accountSaved = write(service: phoneService, account: "accountId", value: trimmedAccount)
        let envSaved = write(service: phoneService, account: "env", value: environment.rawValue)
        return tokenSaved && accountSaved && envSaved
    }

    private static func write(service: String, account: String, value: String) -> Bool {
        let delete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delete as CFDictionary)
        var add = delete
        add[kSecValueData as String] = Data(value.utf8)
        #if os(iOS)
        add[kSecUseDataProtectionKeychain as String] = true
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
