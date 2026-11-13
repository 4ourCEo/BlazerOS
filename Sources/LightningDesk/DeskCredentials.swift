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
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedSession: OandaSession?

    /// Non-interactive CLI source. This deliberately does not touch Keychain:
    /// macOS Security may block a command-line process while decrypting an
    /// access-controlled item, and that synchronous API cannot be cancelled.
    /// The desktop app continues to use `session(allowPrompt:)` below.
    public static func environmentSession() -> OandaSession? {
        guard let token = ProcessInfo.processInfo.environment["OANDA_API_TOKEN"],
              let accountId = ProcessInfo.processInfo.environment["OANDA_ACCOUNT_ID"],
              !token.isEmpty, !accountId.isEmpty else { return nil }
        let env = ProcessInfo.processInfo.environment["OANDA_ENV"]?.lowercased()
        return OandaSession(token: token, accountId: accountId,
                            environment: env == "live" ? .live : .practice)
    }

    /// `allowPrompt` false returns immediately when macOS would otherwise wait on an Allow dialog.
    public static func session(allowPrompt: Bool) -> CredentialGate {
        if let cached = cached() {
            return .ready(cached)
        }
        // Environment injection is for explicitly authorized research collector commands, not
        // the native Mac app. The app reads only its own device-Keychain service.
#if os(iOS)
        if let environment = environmentSession() {
            _ = store(token: environment.token, accountId: environment.accountId, environment: environment.environment)
            cache(environment)
            return .ready(environment)
        }
#endif
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
#if os(iOS)
        switch read(service: phoneService, context: context) {
        case .ready(let session):
            cache(session)
            return .ready(session)
        case .locked:
            return .locked
        case .missing:
            break
        }
#elseif os(macOS)
        switch read(service: macService, context: context) {
        case .ready(let session):
            cache(session)
            return .ready(session)
        case .locked:
            return .locked
        case .missing:
            break
        }
#endif
        return .missing
    }

    private static func cache(_ session: OandaSession) {
        cacheLock.lock()
        cachedSession = session
        cacheLock.unlock()
    }

    private static func cached() -> OandaSession? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedSession
    }

    /// Loads Clear Street session from environment or Keychain.
    public static func clearStreetSession() -> ClearStreetSession? {
        if let key = ProcessInfo.processInfo.environment["CLEARSTREET_API_KEY"], !key.isEmpty {
            let accountId = ProcessInfo.processInfo.environment["CLEARSTREET_ACCOUNT_ID"]
            let envStr = ProcessInfo.processInfo.environment["CLEARSTREET_ENV"]?.lowercased()
            let env: ClearStreetEnvironment = envStr == "production" ? .production : .demo
            return ClearStreetSession(apiKey: key, accountId: accountId, environment: env)
        }
        return nil
    }

    private static func read(service: String, context: LAContext) -> CredentialGate {
        let token = item(service: service, account: "token", context: context)
        let accountId = item(service: service, account: "accountId", context: context)
        switch (token, accountId) {
        case (.value(let token), .value(let accountId)) where !token.isEmpty && !accountId.isEmpty:
            let env = item(service: service, account: "env", context: context)
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

    private static func item(service: String, account: String, context: LAContext) -> ItemRead {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
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
#if os(macOS)
        let service = macService
#else
        let service = phoneService
#endif
        let tokenSaved = write(service: service, account: "token", value: trimmedToken)
        let accountSaved = write(service: service, account: "accountId", value: trimmedAccount)
        let envSaved = write(service: service, account: "env", value: environment.rawValue)
        return tokenSaved && accountSaved && envSaved
    }

    private static func write(service: String, account: String, value: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        let updateAttributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = Data(value.utf8)
            #if os(iOS)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }

        return false
    }
}
