import Foundation
import UniformTypeIdentifiers

/// What a clipboard entry holds. Raw pasteboard data becomes one of these in `ClipClassifier`, so views compare enums.
nonisolated enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, email, color, image, file

    var symbolName: String {
        switch self {
        case .text: "doc.plaintext"
        case .link: "link"
        case .email: "envelope"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var title: String {
        switch self {
        case .text: L(.kindText)
        case .link: L(.kindLink)
        case .email: L(.kindEmail)
        case .color: L(.kindColor)
        case .image: L(.kindImage)
        case .file: L(.kindFile)
        }
    }
}

/// A file copied in Finder. Only the reference is kept, not the file's contents.
nonisolated struct ClipFile: Codable, Hashable, Sendable {
    var path: String
    var name: String
    var size: Int64?
}

/// A web page's title and pictures, fetched once after a link is copied. Paths point into the vault's blobs.
nonisolated struct LinkMetadata: Codable, Hashable, Sendable {
    var title: String?
    var favicon: String?
    var image: String?
}

/// One clipboard entry, stored as `items/<id>.json` in the vault.
nonisolated struct ClipItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: ClipKind
    /// The text for text, link, email and colour entries.
    var text: String?
    var files: [ClipFile]?
    /// Vault-relative path of the image (image entries).
    var blob: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    /// Identifies the same content copied again, so it's counted instead of stored twice.
    var hash: String
    var sourceName: String?
    var sourceBundleID: String?
    /// The device it was first copied on.
    var device: String?
    var pinned = false
    var copyCount = 1
    var pasteCount = 0
    var firstCopied: Date
    var lastCopied: Date
    var firstPasted: Date?
    var lastPasted: Date?
    var link: LinkMetadata?
    /// Text found in an image, so images can be searched.
    var recognizedText: String?
    /// The group the user put the entry in (`AppSettings.groups`), if any.
    var groupID: UUID?
    /// The user's own note about the entry.
    var note: String?

    /// One line for the list.
    var title: String {
        switch kind {
        case .image:
            L(.imageTitle(pixelWidth ?? 0, pixelHeight ?? 0))
        case .file:
            (files ?? []).map(\.name).joined(separator: ", ")
        case .link:
            text ?? ""
        default:
            (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }
    }

    /// The link this entry points at, for opening it.
    var url: URL? {
        switch kind {
        case .link: text.flatMap(ClipClassifier.linkURL)
        case .email: text.flatMap(ClipClassifier.mailURL)
        case .file: files?.first.map { URL(filePath: $0.path) }
        default: nil
        }
    }

    /// Whether Paste Special can convert it: an image, or a single image file.
    var isConvertibleImage: Bool {
        switch kind {
        case .image: true
        case .file:
            files?.count == 1 && files?.first
                .flatMap { UTType(filenameExtension: URL(filePath: $0.path).pathExtension) }?.conforms(to: .image) == true
        default: false
        }
    }

    /// Video or audio, for a file entry whose first file is one. Paste Special converts it when it's the only file.
    var mediaKind: MediaKind? {
        guard kind == .file, let path = files?.first?.path else { return nil }
        return MediaKind(fileExtension: URL(filePath: path).pathExtension)
    }

    /// The single video or audio file Paste Special can convert.
    var convertibleMedia: (url: URL, kind: MediaKind)? {
        guard files?.count == 1, let kind = mediaKind, let path = files?.first?.path else { return nil }
        return (URL(filePath: path), kind)
    }

    var color: ColorValue? { kind == .color ? text.flatMap(ColorValue.init(parsing:)) : nil }

    /// Everything a search should look at.
    var searchableText: String {
        [text, note, link?.title, recognizedText, sourceName, files?.map(\.name).joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }
}

/// Content read from the system clipboard, before it becomes a `ClipItem`.
nonisolated enum CapturedContent: Sendable, Equatable {
    case text(String)
    case image(png: Data, width: Int, height: Int)
    case files([ClipFile])
}

nonisolated struct Capture: Sendable, Equatable {
    var content: CapturedContent
    var sourceName: String?
    var sourceBundleID: String?
}
