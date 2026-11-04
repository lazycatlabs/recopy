import OSLog
import Foundation

/// Fixed paths inside a vault folder.
nonisolated enum VaultLayout {
    static let marker = ".recopy"
    static let config = ".recopy/config.json"
    /// Where Copaste kept the settings. Read, never written: Macs still on Copaste keep using it.
    static let legacyConfig = ".copaste/config.json"
    /// One JSON file per clipboard entry.
    static let items = "items"
    /// Image data, favicons and link previews, referenced from the entries by relative path.
    static let blobs = "blobs"
}

/// When a file last changed, to tell whether it needs reading again.
nonisolated struct FileStamp: Equatable, Sendable {
    let modified: Date?
    let size: Int?
    /// Changes when a sync replaces the file, even if the date and size come out the same.
    let id: UInt64?
}

/// A decoded file and the stamp it had when it was read.
nonisolated struct CachedFile<T> {
    let stamp: FileStamp
    let value: T
}

extension CachedFile: Sendable where T: Sendable {}

/// Reads and writes Codable values as pretty-printed JSON files inside a vault.
/// One file per entity keeps cloud-sync conflicts (iCloud Drive, Google Drive, OneDrive) small and readable.
nonisolated struct JSONFileStore: Sendable {
    let root: URL

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Every `.json` file in `directory`. Unreadable files are moved aside, never overwritten.
    /// Files a cloud provider hasn't downloaded yet (`.name.json.icloud`) are asked for and picked up on the next read.
    /// A file whose modification date and size match `cache` isn't read or decoded again; `cache` is left holding
    /// exactly the files found this time.
    func readAll<T: Decodable>(_ type: T.Type, in directory: String, cache: inout [URL: CachedFile<T>]) -> [T] {
        let dir = root.appending(path: directory, directoryHint: .isDirectory)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .fileIdentifierKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys)) else {
            cache = [:]
            return []
        }
        let decoder = Self.decoder()
        for placeholder in files where placeholder.pathExtension == "icloud" {
            try? FileManager.default.startDownloadingUbiquitousItem(at: placeholder)
        }
        var fresh: [URL: CachedFile<T>] = [:]
        for file in files where file.pathExtension == "json" {
            let values = try? file.resourceValues(forKeys: keys)
            let stamp = FileStamp(modified: values?.contentModificationDate, size: values?.fileSize, id: values?.fileIdentifier)
            if let cached = cache[file], cached.stamp == stamp {
                fresh[file] = cached
            } else if let value = read(T.self, at: file, decoder: decoder) {
                fresh[file] = CachedFile(stamp: stamp, value: value)
            }
        }
        cache = fresh
        return fresh.values.map(\.value)
    }

    // ponytail: shallow merge, nested settings objects need a recursive merge once they exist.
    /// Decodes `path`, filling keys missing from the file (e.g. settings added in a newer version) from `defaults`.
    func read<T: Codable>(_ path: String, default defaults: T) -> T {
        guard let data = try? Data(contentsOf: root.appending(path: path)),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var merged = try? JSONSerialization.jsonObject(with: Self.encoder().encode(defaults)) as? [String: Any]
        else { return defaults }
        merged.merge(stored) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return defaults }
        return (try? Self.decoder().decode(T.self, from: mergedData)) ?? defaults
    }

    func write<T: Encodable>(_ value: T, to path: String) throws {
        try writeData(Self.encoder().encode(value), to: path)
    }

    func writeData(_ data: Data, to path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path)
    }

    /// Copies Copaste's settings into `.recopy/` the first time a vault from before the rename opens.
    /// The old folder stays, so a Mac still on Copaste that shares the vault keeps working.
    func adoptLegacyConfig() {
        guard !exists(VaultLayout.config), exists(VaultLayout.legacyConfig) else { return }
        do {
            try writeData(Data(contentsOf: root.appending(path: VaultLayout.legacyConfig)), to: VaultLayout.config)
        } catch {
            Log.storage.error("Couldn't copy the Copaste settings: \(String(describing: error), privacy: .public)")
        }
    }

    func remove(_ path: String) throws {
        let url = root.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL, decoder: JSONDecoder) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Never overwrite user data: move the broken file aside so it can be inspected or recovered.
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable"))
            Log.storage.error("Moved unreadable file aside \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
