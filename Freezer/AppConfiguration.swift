import Foundation

enum AppConfiguration {
    static var cloudSharingEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FREEZER_CLOUD_SHARING_ENABLED") as? Bool) ?? false
    }

    static func sharingService() -> any FreezerSharingService {
        if cloudSharingEnabled {
            return CloudKitFreezerSharingService()
        }
        return DisabledFreezerSharingService()
    }

    static func repository() -> any FreezerRepository {
        if cloudSharingEnabled {
            return CloudKitFreezerRepository()
        }
        return LocalJSONFreezerRepository()
    }
}
