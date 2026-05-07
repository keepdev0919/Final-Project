import Foundation

final class DeviceIdentity {
    static let shared = DeviceIdentity()
    private init() {}

    private let key = "jeju_device_uuid"

    var id: String {
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
