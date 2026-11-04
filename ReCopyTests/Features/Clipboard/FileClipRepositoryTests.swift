import Foundation
import Testing
@testable import ReCopy

struct FileClipRepositoryTests {
    @Test func savesLoadsAndDeletesWithBlobs() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileClipRepository(root: root)
        var item = ClipItem(kind: .image, hash: "h", firstCopied: .now, lastCopied: .now)
        item.blob = try repository.writeBlob(Data([1, 2, 3]), name: "\(item.id).png")
        try repository.save(item)

        #expect(repository.loadAll().map(\.id) == [item.id])
        #expect(FileManager.default.fileExists(atPath: repository.blobURL(item.blob ?? "").path))

        try repository.delete(item)
        #expect(repository.loadAll().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: repository.blobURL(item.blob ?? "").path))
    }

    /// Reloads reuse decoded entries, but must still pick up a file another Mac changed in the synced vault.
    @Test func reloadPicksUpFilesChangedOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileClipRepository(root: root)
        var item = ClipItem(kind: .text, text: "first", hash: "h", firstCopied: .now, lastCopied: .now)
        try repository.save(item)
        #expect(repository.loadAll().first?.text == "first")

        item.text = "changed elsewhere"
        try FileClipRepository(root: root).save(item)
        #expect(repository.loadAll().first?.text == "changed elsewhere")

        try FileManager.default.removeItem(at: root.appending(path: "\(VaultLayout.items)/\(item.id.uuidString).json"))
        #expect(repository.loadAll().isEmpty)
    }

    @Test func settingsFallBackToDefaultsForMissingKeys() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try JSONFileStore(root: root).writeData(Data(#"{"retention":"week"}"#.utf8), to: VaultLayout.config)
        let settings = FileClipRepository(root: root).loadSettings()
        #expect(settings.retention == .week)
        #expect(settings.textRecognition)
    }

    /// A vault from before the rename keeps its settings, and the old file stays for Macs still on Copaste.
    @Test func adoptsCopasteSettings() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONFileStore(root: root)
        try store.writeData(Data(#"{"retention":"week"}"#.utf8), to: VaultLayout.legacyConfig)

        let repository = FileClipRepository(root: root)
        #expect(repository.loadSettings().retention == .week)
        #expect(store.exists(VaultLayout.config))

        var settings = repository.loadSettings()
        settings.retention = .month
        try repository.saveSettings(settings)
        #expect(repository.loadSettings().retention == .month)
        #expect(store.read(VaultLayout.legacyConfig, default: AppSettings()).retention == .week)
    }
}
