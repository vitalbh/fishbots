import CryptoKit
import Foundation
import Security

/// The key that opens the Mac's notifications (PushSeal), kept where the app and its notification extension both
/// read it: a Keychain group of the two ("<team>.io.vitalbh.fishbots.shared", named in each one's Info.plist). It's
/// derived from the pairing key and opens notifications only: the extension never holds the key that talks to the Mac.
enum PushKey {
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "FishbotsKeychainGroup") as? String }

    private static func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "fishbots.push",
                                kSecAttrAccount as String: "mac"]
        // without a team (the simulator, signed ad hoc) the prefix is empty: the app's own Keychain then
        if let group, !group.hasPrefix("."), !group.contains("$") { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    /// Kept when pairing.
    @discardableResult
    static func keep(pairing: Data) -> OSStatus {
        let raw = PushSeal.key(pairing: pairing).withUnsafeBytes { Data($0) }
        SecItemDelete(query() as CFDictionary)
        var q = query()
        q[kSecValueData as String] = raw
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil)
    }

    static func forget() { SecItemDelete(query() as CFDictionary) }

    static func load() -> SymmetricKey? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return SymmetricKey(data: d)
    }
}
