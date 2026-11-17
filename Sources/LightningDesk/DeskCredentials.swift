import Foundation
import LocalAuthentication
import Security
import Darwin
import BlazerCore

public struct CredentialFileError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Result of a keychain read. `locked` means the item exists and needs an Allow click.
public enum CredentialGate: Sendable {
    case ready(OandaSession)
    case locked
    case missing
    case invalid(String)
}

private struct StoredOandaCredential: Codable, Sendable {
    let token: String
    let accountId: String
    let environment: OandaEnvironment
}

/// Device Keychain only. The token is never written into the desk model or a synced record.
public enum DeskCredentials {
    private static let phoneService = "com.blazer.os.oanda"
    private static let macService = "com.blazer.mac.oanda"
    #if os(macOS)
    private static let practiceFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BlazerOS/credentials/practice.json")
    #endif
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
        #if os(macOS)
        // The canonical Mac item is checked first. Older native releases stored
        // device credentials under phoneService, so that service remains a bounded
        // fallback and is migrated without deleting the legacy source items.
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        let result = resolveMacCredential(
            canonicalRead: { read(service: macService, context: context) },
            legacyRead: {
                read(service: phoneService, context: context, migrationService: macService)
            })
        switch result {
        case .ready(let session):
            cache(session)
            return .ready(session)
        case .locked:
            return .locked
        case .invalid(let message):
            return .invalid(message)
        case .missing:
            return .missing
        }
        #endif
        #if os(iOS)
        // iPhone retains its existing device-only Keychain contract.
        // Resolve it first so a CLI never probes an access-controlled item before
        // honoring its approved credential provider.
        if let environment = environmentSession() {
            _ = store(token: environment.token, accountId: environment.accountId, environment: environment.environment)
            cache(environment)
            return .ready(environment)
        }
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        switch read(service: phoneService, context: context) {
        case .ready(let session):
            cache(session)
            return .ready(session)
        case .locked:
            return .locked
        case .invalid(let message):
            return .invalid(message)
        case .missing:
            break
        }
        return .missing
        #endif
    }

    /// Resolves Mac credential service migration without permitting an old Practice
    /// session to enter the Live workstation. Exposed internally for call-order tests.
    static func resolveMacCredential(canonicalRead: () -> CredentialGate,
                                     legacyRead: () -> CredentialGate) -> CredentialGate {
        switch canonicalRead() {
        case .ready(let session) where session.environment == .live:
            return .ready(session)
        case .ready:
            return .missing
        case .locked:
            return .locked
        case .invalid(let message):
            return .invalid(message)
        case .missing:
            break
        }
        switch legacyRead() {
        case .ready(let session) where session.environment == .live:
            return .ready(session)
        case .ready:
            return .missing
        case .locked:
            return .locked
        case .invalid(let message):
            return .invalid(message)
        case .missing:
            return .missing
        }
    }

    /// Owner-controlled, local-only OANDA Practice source for the explicitly
    /// authorized ForwardTest collector. The Mac trading desk never reads it.
    /// Never logs credential values.
    public static func localPracticeFileSession() -> Result<OandaSession?, CredentialFileError> {
        #if os(macOS)
        let authorizedProcesses: Set<String> = ["ForwardTest"]
        guard authorizedProcesses.contains(ProcessInfo.processInfo.processName) else {
            return .failure(CredentialFileError("OANDA credentials are available only to BlazerOS and the authorized ForwardTest collector"))
        }
        let fm = FileManager.default
        let path = practiceFile.path
        let directory = practiceFile.deletingLastPathComponent()
        do {
            for component in [directory.deletingLastPathComponent(), directory] {
                let values = try component.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                let attrs = try fm.attributesOfItem(atPath: component.path)
                guard values.isSymbolicLink != true, values.isDirectory == true,
                      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
                    return .failure(CredentialFileError("OANDA Practice credential directory is unsafe; owner-only mode 700 is required"))
                }
            }
            guard fm.fileExists(atPath: path) else { return .success(nil) }
            let values = try practiceFile.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            let attrs = try fm.attributesOfItem(atPath: path)
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  (attrs[.referenceCount] as? NSNumber)?.intValue == 1 else {
                return .failure(CredentialFileError("OANDA Practice credential file is unsafe; owner-owned regular file mode 600 is required"))
            }
            let data = try Data(contentsOf: practiceFile, options: .mappedIfSafe)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = object["OANDA_API_TOKEN"] as? String, !token.isEmpty,
                  let accountId = object["OANDA_ACCOUNT_ID"] as? String,
                  !accountId.isEmpty, accountId.range(of: #"^[0-9-]+$"#, options: .regularExpression) != nil,
                  let environment = object["OANDA_ENV"] as? String,
                  environment.lowercased() == "practice",
                  Set(object.keys) == ["OANDA_API_TOKEN", "OANDA_ACCOUNT_ID", "OANDA_ENV"] else {
                return .failure(CredentialFileError("OANDA Practice credential file is malformed or is not explicitly Practice"))
            }
            return .success(OandaSession(token: token, accountId: accountId, environment: .practice))
        } catch {
            return .failure(CredentialFileError("Unable to safely read OANDA Practice credential file"))
        }
        #else
        return .success(nil)
        #endif
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

    private static func read(service: String, context: LAContext,
                             migrationService: String? = nil) -> CredentialGate {
        #if os(macOS)
        // The Mac record is a single Keychain item so a credential update cannot leave
        // a new token paired with an old account ID if a later write fails.
        switch item(service: service, account: "session", context: context) {
        case .value(let raw):
            guard let data = raw.data(using: .utf8),
                  let saved = try? JSONDecoder().decode(StoredOandaCredential.self, from: data),
                  !saved.token.isEmpty, !saved.accountId.isEmpty else {
                return .invalid("Saved OANDA credentials are malformed; replace them in settings")
            }
            let session = OandaSession(token: saved.token, accountId: saved.accountId,
                                       environment: saved.environment)
            if session.environment == .live, let migrationService, migrationService != service {
                _ = write(service: migrationService, account: "session", value: raw)
            }
            return .ready(session)
        case .locked:
            return .locked
        case .missing:
            break
        case .invalid:
            return .invalid("Could not read the saved OANDA Keychain item; check Keychain access or replace credentials in Settings")
        }
        #endif
        #if os(macOS)
        switch legacyValues(service: service, context: context) {
        case .locked:
            return .locked
        case .invalid:
            return .invalid("Could not read legacy OANDA credentials from Keychain; check Keychain access or replace credentials in Settings")
        case .missing:
            return .missing
        case .values(let values):
            guard let token = values["token"], !token.isEmpty,
                  let accountId = values["accountId"], !accountId.isEmpty else {
                return .missing
            }
            let environment: OandaEnvironment = values["env"]?.lowercased() == "live" ? .live : .practice
            let session = OandaSession(token: token, accountId: accountId, environment: environment)
            // Migrate a legacy multi-item Mac record into one item after its one
            // authenticated read. Keep the old entries intact as a recovery path.
            if environment == .live,
               let data = try? JSONEncoder().encode(StoredOandaCredential(
                   token: token, accountId: accountId, environment: environment)),
               let encoded = String(data: data, encoding: .utf8) {
                _ = write(service: migrationService ?? service, account: "session", value: encoded)
            }
            return .ready(session)
        }
        #else
        let token = item(service: service, account: "token", context: context)
        let accountId = item(service: service, account: "accountId", context: context)
        switch (token, accountId) {
        case (.value(let token), .value(let accountId)) where !token.isEmpty && !accountId.isEmpty:
            let env = item(service: service, account: "env", context: context)
            let name: String?
            if case .value(let raw) = env { name = raw.lowercased() } else { name = nil }
            let environment: OandaEnvironment = name == "live" ? .live : .practice
            return .ready(OandaSession(token: token, accountId: accountId, environment: environment))
        case (.locked, _), (_, .locked):
            return .locked
        case (.invalid, _), (_, .invalid):
            return .invalid("Could not read saved OANDA credentials from Keychain; check Keychain access or replace credentials in Settings")
        default:
            return .missing
        }
        #endif
    }

    private enum ItemRead {
        case value(String)
        case missing
        case locked
        case invalid
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
        if status == errSecItemNotFound { return .missing }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return .locked
        }
        guard status == errSecSuccess, let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return .invalid }
        return .value(text)
    }

    #if os(macOS)
    private enum LegacyItemsRead {
        case values([String: String])
        case missing
        case locked
        case invalid
    }

    /// Reads the old token/account/environment entries in one Keychain request,
    /// so an access-controlled legacy record raises at most one authorization UI.
    private static func legacyValues(service: String, context: LAContext) -> LegacyItemsRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return .locked
        }
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            return .invalid
        }
        var values: [String: String] = [:]
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  ["token", "accountId", "env"].contains(account) else { continue }
            guard let data = row[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8), values[account] == nil else {
                return .invalid
            }
            values[account] = value
        }
        if values.isEmpty {
            return .missing
        }
        return .values(values)
    }
    #endif

    /// Writes device Keychain items. The token is not returned and not logged.
    static func store(token: String, accountId: String, environment: OandaEnvironment) -> Bool {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty, !trimmedAccount.isEmpty else { return false }
        #if os(macOS)
        guard environment == .live else { return false }
        let service = macService
        let payload = StoredOandaCredential(
            token: trimmedToken,
            accountId: trimmedAccount,
            environment: environment
        )
        guard let data = try? JSONEncoder().encode(payload),
              let value = String(data: data, encoding: .utf8),
              write(service: service, account: "session", value: value) else {
            return false
        }
        #else
        let service = phoneService
        let tokenSaved = write(service: service, account: "token", value: trimmedToken)
        let accountSaved = write(service: service, account: "accountId", value: trimmedAccount)
        let envSaved = write(service: service, account: "env", value: environment.rawValue)
        guard tokenSaved, accountSaved, envSaved else { return false }
        #endif
        cache(OandaSession(token: trimmedToken, accountId: trimmedAccount, environment: environment))
        return true
    }

    #if os(macOS)
    private static func createPracticeFile(token: String, accountId: String) -> Bool {
        let fm = FileManager.default
        let directory = practiceFile.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            for component in [directory.deletingLastPathComponent(), directory] {
                let values = try component.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                let attrs = try fm.attributesOfItem(atPath: component.path)
                guard values.isSymbolicLink != true, values.isDirectory == true,
                      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { return false }
            }
            guard !fm.fileExists(atPath: practiceFile.path) else { return false }
            let object = ["OANDA_API_TOKEN": token, "OANDA_ACCOUNT_ID": accountId,
                          "OANDA_ENV": "practice"]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let fd = open(practiceFile.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard fd >= 0 else { return false }
            defer { _ = close(fd) }
            let ok = data.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    if count <= 0 { return false }
                    offset += count
                }
                return fsync(fd) == 0
            }
            if !ok { _ = unlink(practiceFile.path) }
            return ok
        } catch {
            return false
        }
    }
    #endif

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
