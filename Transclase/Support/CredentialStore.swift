import Foundation

/// API keys for a locally-built app cannot live in the Keychain without pain:
/// the app is ad-hoc signed, so every rebuild changes the code identity and
/// macOS asks the user to approve access again. They live in the sandbox
/// container instead, readable only by this app and the user.
enum CredentialStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Transclase", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func read() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func write(_ dict: [String: String]) {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONEncoder().encode(dict) else { return }
        fm.createFile(
            atPath: fileURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    static func save(_ value: String, for account: String) {
        var dict = read()
        if value.isEmpty {
            dict.removeValue(forKey: account)
        } else {
            dict[account] = value
        }
        write(dict)
    }

    static func load(_ account: String) -> String? {
        let value = read()[account]
        return (value?.isEmpty ?? true) ? nil : value
    }

    static func delete(_ account: String) {
        var dict = read()
        dict.removeValue(forKey: account)
        write(dict)
    }
}
