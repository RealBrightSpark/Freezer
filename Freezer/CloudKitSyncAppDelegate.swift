import UIKit
import CloudKit

extension Notification.Name {
    static let cloudKitRemoteChangeReceived = Notification.Name("cloudKitRemoteChangeReceived")
}

final class CloudKitSyncAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            NotificationCenter.default.post(name: .cloudKitRemoteChangeReceived, object: nil)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
}
