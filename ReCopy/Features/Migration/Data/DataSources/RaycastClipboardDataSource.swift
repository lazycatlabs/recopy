import AppKit
import Foundation

/// The clipboard files Raycast keeps unencrypted: images, and the HTML and plain text of rich copies.
/// Raycast's history database is encrypted, so copy counts, source apps and plain-text copies can't be read.
nonisolated enum RaycastClipboardDataSource {
    /// Built from the real home folder: in the sandboxed App Store build `homeDirectoryForCurrentUser` is the container.
    static let folder = URL(filePath: String(cString: getpwuid(getuid())!.pointee.pw_dir), directoryHint: .isDirectory)
        .appending(path: "Library/Application Support/com.raycast.macos/clipboard", directoryHint: .isDirectory)

    static let imageExtensions: Set<String> = ["png", "tiff", "tif", "jpg", "jpeg", "heic", "gif", "icns"]
    static let textExtensions: Set<String> = ["html", "htm", "txt"]

    /// The files that can become entries, oldest first so the history keeps its order.
    static func importableFiles(in folder: URL = folder) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { imageExtensions.union(textExtensions).contains($0.pathExtension.lowercased()) }
            .sorted { copiedAt($0) < copiedAt($1) }
    }

    /// When Raycast saved the file, used as the entry's copy date.
    static func copiedAt(_ file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    /// Reads one file. Runs on the caller's actor (the main actor: HTML parsing needs it); images decode off it.
    static func capture(of file: URL) async -> CapturedContent? {
        let ext = file.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return await image(at: file) }
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = ext == "txt" ? String(data: data, encoding: .utf8) : plainText(fromHTML: data)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(text)
    }

    @concurrent
    private static func image(at file: URL) async -> CapturedContent? {
        guard let image = NSImage(contentsOf: file), let png = image.pngRepresentation else { return nil }
        let size = image.pixelSize
        return .image(png: png, width: Int(size.width), height: Int(size.height))
    }

    /// The text of a rich copy, without its markup.
    static func plainText(fromHTML data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil))?.string
    }
}
