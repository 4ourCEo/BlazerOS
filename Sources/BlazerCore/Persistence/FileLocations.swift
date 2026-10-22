import Foundation

/// On-disk locations for documents the desk is allowed to keep. No Keychain material belongs here.
public enum FileLocations {
    public static let ledgerFileName = "scan_ledger.csv"
    public static let snapshotFileName = "scan_snapshots.jsonl"
    public static let journalFileName = "journal.jsonl"

    public static func applicationSupport() -> URL {
        #if os(iOS)
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PhoneTarget.appGroup
        ) {
            return applicationSupport(inGroup: group)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("BlazerOS", isDirectory: true)
    }

    /// Standard App Group location, with a read-only fallback to the legacy root layout for the
    /// widget before the app performs its one-time move.
    public static func applicationSupport(
        inGroup group: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let modern = modernRoot(inGroup: group)
        let legacy = group.appendingPathComponent("BlazerOS", isDirectory: true)
        if fileManager.fileExists(atPath: modern.path) { return modern }
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        return modern
    }

    /// Moves pre-standard-layout App Group data under `Library/Application Support`.
    /// The App Group root is not reachable by `devicectl`, which made ledger and diagnostics
    /// export impossible. Migration is best-effort and never deletes a legacy directory if the
    /// move fails.
    public static func migrateLegacyGroupStorageIfNeeded() {
        #if os(iOS)
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: PhoneTarget.appGroup
        ) else { return }
        migrateLegacyStorage(inGroup: group)
        #endif
    }

    public static func migrateLegacyStorage(
        inGroup group: URL,
        fileManager: FileManager = .default
    ) {
        let modern = modernRoot(inGroup: group)
        let legacy = group.appendingPathComponent("BlazerOS", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: modern.path)
        else { return }
        do {
            try fileManager.createDirectory(
                at: modern.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: modern)
        } catch {
            // Keep the legacy data in place; applicationSupport() continues to read it.
        }
    }

    private static func modernRoot(inGroup group: URL) -> URL {
        group
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("BlazerOS", isDirectory: true)
    }

    public static func ledgerCSV(in root: URL) -> URL {
        root.appendingPathComponent(ledgerFileName)
    }

    public static func snapshots(in root: URL) -> URL {
        root.appendingPathComponent(snapshotFileName)
    }

    public static func journal(in root: URL) -> URL {
        root.appendingPathComponent(journalFileName)
    }

    public static let activePositionFileName = "active_position.json"
    public static let pendingSettlementsFileName = "pending_settlements.jsonl"

    public static func activePosition(in root: URL) -> URL {
        root.appendingPathComponent(activePositionFileName)
    }

    public static func pendingSettlements(in root: URL) -> URL {
        root.appendingPathComponent(pendingSettlementsFileName)
    }
}

enum AtomicFile {
    /// Replaces `url` with a completed file. A crash mid-write leaves the previous file intact.
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: temp.path
        )
        #endif
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
