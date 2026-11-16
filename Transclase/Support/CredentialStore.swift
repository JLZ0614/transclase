import Foundation
import Security

/// API keys live in the Keychain. The app used a plain JSON file while it was
/// ad-hoc signed (every rebuild changed the code identity and triggered a
/// Keychain prompt); with a stable signing identity the Keychain is the right
/// place, so the old file is imported once and then removed.
enum CredentialStore {
    private static let service = "com.transclase.credentials"

    // MARK: - Keychain

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ value: String, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty else { return }

        var attributes = query(account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(_ account: String) -> String? {
        if let value = keychainValue(account) { return value }
        return migrateLegacyFile(account)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    private static func keychainValue(_ account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    // MARK: - Legacy migration

    private static var legacyFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Transclase", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func migrateLegacyFile(_ account: String) -> String? {
        let file = legacyFileURL
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let value = dict[account], !value.isEmpty
        else { return nil }

        save(value, for: account)

        // Drop the plaintext copy once every key has been imported.
        if dict.count == 1 {
            try? FileManager.default.removeItem(at: file)
        }
        return value
    }
}
