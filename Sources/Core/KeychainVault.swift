import Foundation
import Security

/// Small Keychain wrapper for opaque authentication-session data.
///
/// Never use this store for an Apple ID password. The future authentication
/// adapter should store only the minimum session material required by its
/// protocol and should delete it on sign-out.
enum KeychainVault {
    enum VaultError: Error {
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    private static let service = "com.kemi579.PurpleKit.auth-session"

    static func save(_ data: Data, account: String = "apple-session") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultError.unexpectedStatus(status) }

        var insert = query
        update.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw VaultError.unexpectedStatus(insertStatus) }
    }

    static func load(account: String = "apple-session") throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw VaultError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw VaultError.invalidData }
        return data
    }

    static func delete(account: String = "apple-session") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.unexpectedStatus(status)
        }
    }
}
