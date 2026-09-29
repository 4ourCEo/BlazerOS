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
            return group.appendingPathComponent("BlazerOS", isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("BlazerOS", isDirectory: true)
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
