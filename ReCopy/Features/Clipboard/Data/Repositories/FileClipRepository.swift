import Foundation
import Synchronization

/// Clipboard entries as one JSON file each in the vault, with images beside them in `blobs/`.
nonisolated final class FileClipRepository: ClipRepository {
    private let store: JSONFileStore
    /// Entries already decoded, so reopening the clipboard window only reads the files that changed.
    private let cache = Mutex<[URL: CachedFile<ClipItem>]>([:])

    init(root: URL) {
        store = JSONFileStore(root: root)
    }

    func loadAll() -> [ClipItem] {
        cache.withLock { store.readAll(ClipItem.self, in: VaultLayout.items, cache: &$0) }
    }

    func save(_ item: ClipItem) throws {
        try store.write(item, to: path(of: item))
    }

    func delete(_ item: ClipItem) throws {
        for blob in [item.blob, item.link?.favicon, item.link?.image].compactMap({ $0 }) {
            try store.remove(blob)
        }
        try store.remove(path(of: item))
        _ = cache.withLock { $0.removeValue(forKey: store.root.appending(path: path(of: item))) }
    }

    func writeBlob(_ data: Data, name: String) throws -> String {
        let path = "\(VaultLayout.blobs)/\(name)"
        try store.writeData(data, to: path)
        return path
    }

    func blobURL(_ path: String) -> URL {
        store.root.appending(path: path)
    }

    func loadSettings() -> AppSettings {
        store.adoptLegacyConfig()
        // If the copy failed, read Copaste's settings in place rather than losing them.
        let path = store.exists(VaultLayout.config) ? VaultLayout.config : VaultLayout.legacyConfig
        return store.read(path, default: AppSettings())
    }

    func saveSettings(_ settings: AppSettings) throws {
        try store.write(settings, to: VaultLayout.config)
    }

    func size(of items: [ClipItem]) -> Int64 {
        items.reduce(0) { total, item in
            let paths = [path(of: item), item.blob, item.link?.favicon, item.link?.image].compactMap { $0 }
            return total + paths.reduce(0) { $0 + Self.fileSize(store.root.appending(path: $1)) }
        }
    }

    func totalSize() -> Int64 {
        let folders = [VaultLayout.items, VaultLayout.blobs, VaultLayout.marker].map { store.root.appending(path: $0) }
        return folders.reduce(0) { total, folder in
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            return total + (files?.compactMap { $0 as? URL }.reduce(0) { $0 + Self.fileSize($1) } ?? 0)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private func path(of item: ClipItem) -> String {
        "\(VaultLayout.items)/\(item.id.uuidString).json"
    }
}
