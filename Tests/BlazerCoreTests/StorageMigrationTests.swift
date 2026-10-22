import Foundation
import Testing
@testable import BlazerCore

private func temporaryGroup() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("blazer-group-\(UUID().uuidString)", isDirectory: true)
}

@Test func legacyGroupStorageMigratesUnderLibrary() throws {
    let group = temporaryGroup()
    defer { try? FileManager.default.removeItem(at: group) }
    let legacy = group.appendingPathComponent("BlazerOS", isDirectory: true)
    let modern = group
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("BlazerOS", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let ledger = legacy.appendingPathComponent("scan_ledger.csv")
    try "row\n".write(to: ledger, atomically: true, encoding: .utf8)

    FileLocations.migrateLegacyStorage(inGroup: group)

    #expect(FileManager.default.fileExists(atPath: modern.path))
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(try String(contentsOf: modern.appendingPathComponent("scan_ledger.csv"), encoding: .utf8) == "row\n")
    #expect(FileLocations.applicationSupport(inGroup: group) == modern)
}

@Test func applicationSupportFallsBackToLegacyUntilMigration() throws {
    let group = temporaryGroup()
    defer { try? FileManager.default.removeItem(at: group) }
    let legacy = group.appendingPathComponent("BlazerOS", isDirectory: true)
    let modern = group
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("BlazerOS", isDirectory: true)

    #expect(FileLocations.applicationSupport(inGroup: group) == modern)

    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    #expect(FileLocations.applicationSupport(inGroup: group) == legacy)

    try FileManager.default.createDirectory(at: modern, withIntermediateDirectories: true)
    #expect(FileLocations.applicationSupport(inGroup: group) == modern)
}
