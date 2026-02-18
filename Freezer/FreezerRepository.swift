import Foundation
import CloudKit

enum FreezerStorageBackend: String {
    case local
    case cloudKit
}

protocol FreezerRepository {
    var backend: FreezerStorageBackend { get }
    func load() throws -> FreezerData?
    func save(_ data: FreezerData) throws
    func loadSnapshot() -> FreezerData?
    func syncFromRemote() throws
    func ensureSubscriptions() throws
}

extension FreezerRepository {
    func syncFromRemote() throws {}
    func ensureSubscriptions() throws {}
}

enum FreezerRepositoryFactory {
    static func makeDefault() -> any FreezerRepository {
        // Phase 1: keep local JSON as runtime default while cloud backend is scaffolded.
        LocalJSONFreezerRepository()
    }
}

struct LocalJSONFreezerRepository: FreezerRepository {
    let backend: FreezerStorageBackend = .local
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> FreezerData? {
        guard let raw = try? Data(contentsOf: fileURL) else { return nil }
        return try JSONDecoder().decode(FreezerData.self, from: raw)
    }

    func save(_ data: FreezerData) throws {
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: [.atomic])
    }

    func loadSnapshot() -> FreezerData? {
        try? load()
    }

    static var defaultFileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent("freezer-data.json")
    }
}

struct CloudKitFreezerRepository: FreezerRepository {
    let backend: FreezerStorageBackend = .cloudKit
    private let cache: LocalJSONFreezerRepository
    private let container: CKContainer
    private let recordType = "FreezerRoot"
    private let privateSubscriptionID = "freezer.private.database.subscription"
    private let sharedSubscriptionID = "freezer.shared.database.subscription"

    init(
        cacheURL: URL = LocalJSONFreezerRepository.defaultFileURL,
        container: CKContainer = .default()
    ) {
        self.cache = LocalJSONFreezerRepository(fileURL: cacheURL)
        self.container = container
    }

    func load() throws -> FreezerData? {
        // Phase 1 scaffold: local cache is the source of truth until CloudKit sync is implemented.
        try cache.load()
    }

    func save(_ data: FreezerData) throws {
        try cache.save(data)
        pushToCloud(data)
    }

    func loadSnapshot() -> FreezerData? {
        cache.loadSnapshot()
    }

    func syncFromRemote() throws {
        guard let remote = try fetchFromCloud(timeout: 2.0) else { return }
        try cache.save(remote)
    }

    func ensureSubscriptions() throws {
        try ensureDatabaseSubscription(
            id: privateSubscriptionID,
            database: container.privateCloudDatabase
        )
        try ensureDatabaseSubscription(
            id: sharedSubscriptionID,
            database: container.sharedCloudDatabase
        )
    }

    private func fetchFromCloud(timeout: TimeInterval) throws -> FreezerData? {
        let recordID = CKRecord.ID(recordName: activeRecordName())
        let database = activeDatabase()
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()

        var fetchedData: FreezerData?
        var thrownError: Error?

        database.fetch(withRecordID: recordID) { record, error in
            defer { semaphore.signal() }

            lock.lock()
            defer { lock.unlock() }

            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return
            }

            if let error {
                thrownError = error
                return
            }

            guard let payload = record?["payload"] as? Data else {
                return
            }

            do {
                fetchedData = try JSONDecoder().decode(FreezerData.self, from: payload)
            } catch {
                thrownError = error
            }
        }

        let didFinish = semaphore.wait(timeout: .now() + timeout) == .success
        guard didFinish else { return nil }
        if let thrownError { throw thrownError }
        return fetchedData
    }

    private func pushToCloud(_ data: FreezerData) {
        guard let payload = try? JSONEncoder().encode(data) else { return }

        let recordID = CKRecord.ID(recordName: activeRecordName(fallbackData: data))
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["payload"] = payload as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        record["householdID"] = data.household.id.uuidString as CKRecordValue
        record["householdName"] = data.household.name as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.modifyRecordsResultBlock = { _ in }
        activeDatabase().add(operation)
    }

    private func activeDatabase() -> CKDatabase {
        if CloudKitShareContext.acceptedRootRecordName != nil {
            return container.sharedCloudDatabase
        }
        return container.privateCloudDatabase
    }

    private func activeRecordName(fallbackData: FreezerData? = nil) -> String {
        if let sharedName = CloudKitShareContext.acceptedRootRecordName {
            return sharedName
        }

        if let householdID = fallbackData?.household.id ?? cache.loadSnapshot()?.household.id {
            return "freezer-\(householdID.uuidString.lowercased())"
        }

        return "freezer-default"
    }

    private func ensureDatabaseSubscription(id: String, database: CKDatabase) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var thrownError: Error?
        var existingSubscription: CKSubscription?

        database.fetch(withSubscriptionID: id) { subscription, error in
            defer { semaphore.signal() }
            lock.lock()
            defer { lock.unlock() }

            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return
            }
            if let error {
                thrownError = error
                return
            }
            existingSubscription = subscription
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        if let thrownError { throw thrownError }
        if existingSubscription != nil { return }

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true

        let subscription = CKDatabaseSubscription(subscriptionID: id)
        subscription.notificationInfo = notificationInfo

        let saveSemaphore = DispatchSemaphore(value: 0)
        var saveError: Error?
        database.save(subscription) { _, error in
            defer { saveSemaphore.signal() }
            if let error { saveError = error }
        }

        _ = saveSemaphore.wait(timeout: .now() + 2.0)
        if let saveError { throw saveError }
    }
}
