import Foundation
#if canImport(Security)
import Security
#endif

// MARK: - Keychain vault
//
// Secure storage for the OPTIONAL AI copilot's API keys (DeepSeek / Gemini). This is NOT
// execution credential plumbing — retail Strike has no order API, and the plan forbids
// execution keys. Advisory keys are read-only, user-supplied, and revocable.

public enum KeychainError: Error, Equatable {
    case failure(Int32)
    case unavailable
}

/// Minimal secure string store. Injectable so logic is testable without the real Keychain.
public protocol KeychainVault: Sendable {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String) throws
}

/// Canonical key names. Never hardcoded secrets — only storage identifiers.
public enum KeychainKey {
    public static let deepseekAPIKey = "DEEPSEEK_API_KEY"
    public static let geminiAPIKey = "GEMINI_API_KEY"
    public static let otchartsAPIKey = "OTCHARTS_API_KEY"
    public static let pocketOptionReadOnlySession = "POCKET_OPTION_READ_ONLY_SESSION"
}

extension AIProvider {
    /// Which vault slot holds this provider's key.
    public var keychainKeyName: String {
        switch self {
        case .deepseek: return KeychainKey.deepseekAPIKey
        case .gemini: return KeychainKey.geminiAPIKey
        }
    }
}

/// In-memory vault for tests and previews. Never for production secrets.
public final class InMemoryKeychainVault: KeychainVault, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func set(_ value: String, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    public func get(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

#if canImport(Security)
/// Real macOS/iOS Keychain-backed vault. Generic-password items under a service identifier.
public struct SystemKeychainVault: KeychainVault {
    public let service: String

    public init(service: String = "com.blazer.strike") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func set(_ value: String, for key: String) throws {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.failure(status) }
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.failure(status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failure(status)
        }
    }
}
#endif
