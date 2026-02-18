import Foundation
import CloudKit

enum FreezerShareError: LocalizedError {
    case missingShareURL
    case sharingUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingShareURL:
            return "Could not create a share URL."
        case .sharingUnavailable(let reason):
            return reason
        }
    }
}

protocol FreezerSharingService {
    func createOrFetchShareURL(householdID: UUID, householdName: String) async throws -> URL
    func acceptShare(from url: URL) async throws -> FreezerShareAcceptanceResult
}

struct FreezerShareAcceptanceResult: Sendable {
    let rootRecordName: String
}

struct CloudKitFreezerSharingService: FreezerSharingService {
    init() {}

    func createOrFetchShareURL(householdID: UUID, householdName: String) async throws -> URL {
        let privateDB = CKContainer.default().privateCloudDatabase
        let rootRecordID = CKRecord.ID(recordName: "freezer-\(householdID.uuidString.lowercased())")

        let existingRoot: CKRecord? = try await fetchRecord(id: rootRecordID, in: privateDB)
        let rootRecord = existingRoot ?? CKRecord(recordType: "FreezerRoot", recordID: rootRecordID)
        rootRecord["householdName"] = householdName as CKRecordValue
        rootRecord["updatedAt"] = Date() as CKRecordValue

        if let existingShare = try await fetchShare(for: rootRecord, in: privateDB), let url = existingShare.url {
            return url
        }

        let share = CKShare(rootRecord: rootRecord)
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = householdName as CKRecordValue

        let (_, savedShare) = try await save(rootRecord: rootRecord, share: share, in: privateDB)
        guard let url = savedShare.url else {
            throw FreezerShareError.missingShareURL
        }
        return url
    }

    func acceptShare(from url: URL) async throws -> FreezerShareAcceptanceResult {
        let container = CKContainer.default()
        let metadata = try await fetchShareMetadata(for: url, using: container)
        try await accept(metadata: metadata, using: container)
        return FreezerShareAcceptanceResult(rootRecordName: metadata.rootRecordID.recordName)
    }

    private func fetchRecord(id: CKRecord.ID, in database: CKDatabase) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func fetchShare(for rootRecord: CKRecord, in database: CKDatabase) async throws -> CKShare? {
        guard let shareReference = rootRecord.share else { return nil }
        do {
            return try await database.record(for: shareReference.recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func save(rootRecord: CKRecord, share: CKShare, in database: CKDatabase) async throws -> (CKRecord, CKShare) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(CKRecord, CKShare), Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume(returning: (rootRecord, share))
                }
            }
            database.add(operation)
        }
    }

    private func fetchShareMetadata(for url: URL, using container: CKContainer) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            container.fetchShareMetadata(with: url) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let metadata else {
                    continuation.resume(throwing: FreezerShareError.missingShareURL)
                    return
                }
                continuation.resume(returning: metadata)
            }
        }
    }

    private func accept(metadata: CKShare.Metadata, using container: CKContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var perShareError: Error?

            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.perShareCompletionBlock = { _, _, error in
                if let error {
                    perShareError = error
                }
            }
            operation.acceptSharesCompletionBlock = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let perShareError {
                    continuation.resume(throwing: perShareError)
                } else {
                    continuation.resume(returning: ())
                }
            }
            container.add(operation)
        }
    }
}

struct DisabledFreezerSharingService: FreezerSharingService {
    let reason: String

    init(reason: String = "Cloud sharing is not configured for this build.") {
        self.reason = reason
    }

    func createOrFetchShareURL(householdID: UUID, householdName: String) async throws -> URL {
        throw FreezerShareError.sharingUnavailable(reason)
    }

    func acceptShare(from url: URL) async throws -> FreezerShareAcceptanceResult {
        throw FreezerShareError.sharingUnavailable(reason)
    }
}
