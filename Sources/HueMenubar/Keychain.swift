import Foundation
import Security

/// Bridge secrets live in the login Keychain, keyed by the bridge ID so an IP change keeps the pairing.
enum KeychainItem: String {
    case appKey = "local.HueMenubar"
    case certificate = "local.HueMenubar.Certificate"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: rawValue, kSecAttrAccount as String: account.lowercased()]
    }
    func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func save(_ value: String, account: String) throws {
        let q = query(account), data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = q
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw HueError.message(t("Keychain refused to save the item (%d).", Int(added))) }
        } else if status != errSecSuccess {
            throw HueError.message(t("Keychain refused to save the item (%d).", Int(status)))
        }
    }
    func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw HueError.message(t("Keychain refused to remove the item (%d).", Int(status))) }
    }
}
