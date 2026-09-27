import CloudKit
import Foundation

/// Errors encountered during CloudKit synchronization.
public enum CloudSyncError: LocalizedError, Equatable {
    case securityGateViolation(String)
    case unauthenticated
    case recordMalformed(String)
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .securityGateViolation(let msg):
            return "Security gate refused sync: \(msg)"
        case .unauthenticated:
            return "iCloud account not signed in or restricted."
        case .recordMalformed(let msg):
            return "Malformed record: \(msg)"
        case .networkUnavailable:
            return "Network unavailable for CloudKit sync."
        }
    }
}

/// Abstract transport layer for CloudKit database operations.
public protocol CloudSyncTransport: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func queryRecords(recordType: String) async throws -> [CKRecord]
    func modifyRecords(toSave: [CKRecord], toDelete: [CKRecord.ID]) async throws -> (saved: [CKRecord], deleted: [CKRecord.ID])
}

/// In-memory actor transport for deterministic testing and zero-network CLI environments.
public actor MockCloudSyncTransport: CloudSyncTransport {
    private var records: [CKRecord.ID: CKRecord] = [:]
    public var status: CKAccountStatus = .available
    public var simulateOffline = false

    public init(status: CKAccountStatus = .available) {
        self.status = status
    }

    public func setStatus(_ status: CKAccountStatus) {
        self.status = status
    }

    public func setSimulateOffline(_ offline: Bool) {
        self.simulateOffline = offline
    }

    public func accountStatus() async throws -> CKAccountStatus {
        if simulateOffline { throw CloudSyncError.networkUnavailable }
        return status
    }

    public func queryRecords(recordType: String) async throws -> [CKRecord] {
        if simulateOffline { throw CloudSyncError.networkUnavailable }
        guard status == .available else { throw CloudSyncError.unauthenticated }
        return records.values.filter { $0.recordType == recordType }
    }

    public func modifyRecords(toSave: [CKRecord], toDelete: [CKRecord.ID]) async throws -> (saved: [CKRecord], deleted: [CKRecord.ID]) {
        if simulateOffline { throw CloudSyncError.networkUnavailable }
        guard status == .available else { throw CloudSyncError.unauthenticated }

        var saved: [CKRecord] = []
        for record in toSave {
            guard CloudSecurityGate.validate(record: record) else {
                throw CloudSyncError.securityGateViolation(record.recordID.recordName)
            }
            records[record.recordID] = record
            saved.append(record)
        }

        var deleted: [CKRecord.ID] = []
        for id in toDelete {
            if records.removeValue(forKey: id) != nil {
                deleted.append(id)
            }
        }

        return (saved, deleted)
    }

    public func allRecords() -> [CKRecord] {
        Array(records.values)
    }
}

/// Production CloudKit transport using Apple's CloudKit private database.
public actor NativeCloudKitTransport: CloudSyncTransport {
    private let database: CKDatabase
    private let container: CKContainer

    public init(containerIdentifier: String = "iCloud.com.blazer.os") {
        let cnt = CKContainer(identifier: containerIdentifier)
        self.container = cnt
        self.database = cnt.privateCloudDatabase
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    public func queryRecords(recordType: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let (matchResults, _) = try await database.records(matching: query)
        var records: [CKRecord] = []
        for (_, result) in matchResults {
            if let record = try? result.get() {
                records.append(record)
            }
        }
        return records
    }

    public func modifyRecords(toSave: [CKRecord], toDelete: [CKRecord.ID]) async throws -> (saved: [CKRecord], deleted: [CKRecord.ID]) {
        for record in toSave {
            guard CloudSecurityGate.validate(record: record) else {
                throw CloudSyncError.securityGateViolation(record.recordID.recordName)
            }
        }
        let result = try await database.modifyRecords(saving: toSave, deleting: toDelete)
        var saved: [CKRecord] = []
        for (_, res) in result.saveResults {
            if let record = try? res.get() {
                saved.append(record)
            }
        }
        var deleted: [CKRecord.ID] = []
        for (id, res) in result.deleteResults {
            if (try? res.get()) != nil {
                deleted.append(id)
            }
        }
        return (saved, deleted)
    }
}
