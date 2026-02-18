import Foundation

enum CloudKitShareContext {
    private static let recordNameKey = "cloudkit.acceptedShareRootRecordName"

    static var acceptedRootRecordName: String? {
        get { UserDefaults.standard.string(forKey: recordNameKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: recordNameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: recordNameKey)
            }
        }
    }
}
