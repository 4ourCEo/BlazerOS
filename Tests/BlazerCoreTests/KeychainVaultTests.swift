import Foundation
import Testing
@testable import BlazerCore

// The AI copilot's key vault. Logic is tested through the in-memory implementation; real
// Keychain I/O is not exercised here.

@Test func vaultStoresAndReadsBack() throws {
    let vault = InMemoryKeychainVault()
    try vault.set("sk-abc", for: KeychainKey.deepseekAPIKey)
    #expect(try vault.get(KeychainKey.deepseekAPIKey) == "sk-abc")
    #expect(try vault.get(KeychainKey.geminiAPIKey) == nil)
}

@Test func vaultOverwritesAndRemoves() throws {
    let vault = InMemoryKeychainVault()
    try vault.set("first", for: "K")
    try vault.set("second", for: "K")
    #expect(try vault.get("K") == "second")
    try vault.remove("K")
    #expect(try vault.get("K") == nil)
    // Removing a missing key is not an error.
    try vault.remove("K")
}

@Test func providersMapToDistinctKeySlots() {
    #expect(AIProvider.deepseek.keychainKeyName == KeychainKey.deepseekAPIKey)
    #expect(AIProvider.gemini.keychainKeyName == KeychainKey.geminiAPIKey)
    #expect(AIProvider.deepseek.keychainKeyName != AIProvider.gemini.keychainKeyName)
    // Stored secrets never live under a generic/shared name.
    #expect(KeychainKey.deepseekAPIKey != KeychainKey.geminiAPIKey)
}
