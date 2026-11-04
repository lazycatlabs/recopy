import Foundation

/// The vault location is device-specific (each Mac sees the synced folder at its own path), so it lives in
/// UserDefaults as a bookmark, which keeps pointing at the folder if it is moved or renamed.
final class UserDefaultsVaultRepository: VaultRepository {
    private static let bookmarkKey = "vaultBookmark"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
    }

    func resolveVault() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        // The App Store build is sandboxed and can only reopen the folder through a security-scoped bookmark.
        // Bookmarks saved before 0.11 have no scope: they still resolve, and are saved again with one.
        let scoped = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
        guard let url = scoped ?? (try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if isStale || scoped == nil, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    func prepare(_ url: URL) throws {
        let store = JSONFileStore(root: url)
        if !FileManager.default.fileExists(atPath: url.appending(path: VaultLayout.config).path) {
            try store.write(AppSettings(), to: VaultLayout.config)
        }
        defaults.set(try url.bookmarkData(options: .withSecurityScope), forKey: Self.bookmarkKey)
    }

    func forget() {
        defaults.removeObject(forKey: Self.bookmarkKey)
    }
}
