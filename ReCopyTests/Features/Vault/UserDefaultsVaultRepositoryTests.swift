import Foundation
import Testing
@testable import ReCopy

struct UserDefaultsVaultRepositoryTests {
    @Test func keepsUnreadableCopasteSettingsInsteadOfWritingDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "UserDefaultsVaultRepositoryTests-\(UUID().uuidString)"
        let legacy = root.appending(path: VaultLayout.legacyConfig)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacy.path)
            try? FileManager.default.removeItem(at: root)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        let store = JSONFileStore(root: root)
        try store.writeData(Data(#"{"retention":"week"}"#.utf8), to: VaultLayout.legacyConfig)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: legacy.path)

        try UserDefaultsVaultRepository(defaults: try #require(UserDefaults(suiteName: suite))).prepare(root)

        #expect(!store.exists(VaultLayout.config))
    }
}
