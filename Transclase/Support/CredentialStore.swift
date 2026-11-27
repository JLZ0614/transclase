import Foundation
import Security

/// API keys live in a 0600 file inside the App's own sandbox container.
///
/// The Keychain would be the canonical place, but this build is ad-hoc signed:
/// every rebuild produces a new code identity, so macOS treats each version as a
/// different app and asks the user to allow Keychain access again. A sandboxed
/// file with owner-only permissions avoids that without exposing the keys to
/// other apps. Revisit the Keychain once the app is signed with a stable
/// developer identity.
enum CredentialStore {
    private static var cache: [String: String] = [:]
    private static var loaded = false
    private static let lock = NSLock()

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base
            .appendingPathComponent("Transclase", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    // MARK: - Public API

    static func save(_ value: String, for account: String) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        if value.isEmpty {
            cache.removeValue(forKey: account)
        } else {
            cache[account] = value
        }
        persist()
    }

    static func load(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return cache[account]
    }

    static func delete(_ account: String) {
        save("", for: account)
    }

    // MARK: - Storage

    private static func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
            return
        }

        // One-off rescue of keys written to the Keychain by 1.6.x.
        if let migrated = migrateFromKeychain(), !migrated.isEmpty {
            cache = migrated
            persist()
        }
    }

    private static func persist() {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        if cache.isEmpty {
            try? fm.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(cache) else { return }
        // `createFile` fails when the file already exists, which silently lost
        // every key written after the first one. Write atomically instead.
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Keep the in-memory cache; the next save will retry.
        }
    }

    // MARK: - Keychain migration

    private static let keychainService = "com.transclase.credentials"
    private static let knownAccounts = ["cloudAPIKey"]

    /// Reads any keys the previous version stored in the Keychain, then removes
    /// them so the prompt never appears again.
    private static func migrateFromKeychain() -> [String: String]? {
        var found: [String: String] = [:]

        for account in knownAccounts + providerAccountsFromDefaults() {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty
            else { continue }

            found[account] = text
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account,
            ] as CFDictionary)
        }
        return found.isEmpty ? nil : found
    }

    /// Provider keys are stored as `provider.<uuid>`; collect the UUIDs from the
    /// saved settings so they can be migrated too.
    private static func providerAccountsFromDefaults() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: "transclase.settings.v1"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = json["providers"] as? [[String: Any]]
        else { return [] }
        return providers.compactMap { provider in
            (provider["id"] as? String).map { "provider.\($0)" }
        }
    }
}
