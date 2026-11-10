import OSLog
import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

/// The open vault's clipboard history: what every screen reads, and the one place entries change.
@Observable
final class ClipboardSession {
    let root: URL
    private(set) var items: [ClipItem] = []
    var settings: AppSettings {
        didSet { if settings != oldValue { persist { try repository.saveSettings(settings) } } }
    }
    /// macOS: stop recording for a while, e.g. while handling secrets.
    var isPaused = false
    /// Shown as an alert. A failed save must never be silent.
    var errorMessage: String?
    /// Receives "“…” copied" / "“…” pasted" confirmations when toasts are on; the app decides where to show them.
    @ObservationIgnored var onToast: ((String) -> Void)?
    /// The code language of text entries, by content hash, so each text is looked at once.
    @ObservationIgnored private var languages: [String: CodeLanguage?] = [:]
    @ObservationIgnored private var languageNames: [String: String] = [:]

    @ObservationIgnored let repository: ClipRepository
    @ObservationIgnored let pasteboard: SystemPasteboard

    init(root: URL, repository: ClipRepository? = nil, pasteboard: SystemPasteboard = SystemPasteboard()) {
        self.pasteboard = pasteboard
        self.root = root
        let repository = repository ?? FileClipRepository(root: root)
        self.repository = repository
        settings = repository.loadSettings()
        items = repository.loadAll()
        pruneExpired()
        pasteboard.onCapture = { [weak self] capture in self?.handle(capture) }
        pasteboard.savesUniversalClipboard = { [weak self] in self?.settings.saveUniversalClipboard ?? false }
        pasteboard.startMonitoring()
    }

    /// Picks up entries other devices added to the synced vault.
    func reload() async {
        let repository = repository
        let loaded = await Task.detached { repository.loadAll() }.value
        // Assigning redraws every row, so only when something changed.
        if Set(loaded) != Set(items) { items = loaded }
        pruneExpired()
    }

    func blobURL(_ path: String?) -> URL? {
        path.map(repository.blobURL)
    }

    // MARK: Recording

    /// A copy made in another app: recorded unless recording is paused or the app is ignored.
    func handle(_ capture: Capture) {
        guard !isPaused else { return }
        if let bundleID = capture.sourceBundleID, settings.ignoredApps.contains(where: { $0.bundleID == bundleID }) { return }
        guard let item = record(capture) else { return }
        SoundPlayer.play(settings.copySound)
        announce(L(.toastCopied(toastTitle(item))))
    }

    /// Adds an entry from another clipboard manager, dated when it was first copied there.
    /// Content already in the history is left alone, so an import can be run again safely.
    /// - Returns: whether a new entry was added.
    @discardableResult
    func importClip(_ content: CapturedContent, source: String, copiedAt date: Date) -> Bool {
        let hash = ClipUseCases.hash(of: content)
        guard !items.contains(where: { $0.hash == hash }) else { return false }
        return record(Capture(content: content, sourceName: source), at: date, enrichNow: false) != nil
    }

    /// Reads text in imported images one at a time, so a large import doesn't load every core at once.
    func recognizeTextInImages() async {
        guard settings.textRecognition else { return }
        for item in items where item.kind == .image && item.recognizedText == nil {
            guard let url = blobURL(item.blob), let data = try? Data(contentsOf: url),
                  let text = await TextRecognitionDataSource.recognize(data, accurate: settings.accurateRecognition) else { continue }
            update(item.id) { $0.recognizedText = text }
        }
    }

    @discardableResult
    private func record(_ capture: Capture, at date: Date = .now, enrichNow: Bool = true) -> ClipItem? {
        var (item, isNew) = ClipUseCases.record(capture, in: items, device: DeviceInfo.name, now: date)
        if isNew, case let .image(png, _, _) = capture.content {
            guard let path = persist({ try repository.writeBlob(png, name: "\(item.id.uuidString).png") }) else { return nil }
            item.blob = path
        }
        save(item)
        if isNew, enrichNow { enrich(item, capture: capture) }
        return item
    }

    /// Fetches a link's preview and reads text in images, after the entry is already saved.
    private func enrich(_ item: ClipItem, capture: Capture) {
        let settings = settings
        Task {
            if item.kind == .link, settings.fetchLinkPreviews, let url = item.url { await addPreview(to: item.id, from: url) }
            if case let .image(png, _, _) = capture.content, settings.textRecognition,
               let text = await TextRecognitionDataSource.recognize(png, accurate: settings.accurateRecognition) {
                update(item.id) { $0.recognizedText = text }
            }
        }
    }

    private func addPreview(to id: UUID, from url: URL) async {
        guard let metadata = await LinkMetadataDataSource.fetch(url) else { return }
        let favicon = metadata.favicon.flatMap { data in persist { try repository.writeBlob(data, name: "\(id.uuidString)-icon") } }
        let image = metadata.image.flatMap { data in persist { try repository.writeBlob(data, name: "\(id.uuidString)-preview") } }
        update(id) { $0.link = LinkMetadata(title: metadata.title, favicon: favicon, image: image) }
    }

    /// Adds an image made in ReCopy (an annotated copy) as a new entry, and puts it on the clipboard.
    /// Works while recording is paused: the user asked for this entry.
    @discardableResult
    func addImage(_ png: Data, width: Int, height: Int) -> ClipItem? {
        guard let item = record(Capture(content: .image(png: png, width: width, height: height), sourceName: "ReCopy")) else { return nil }
        write(item)
        SoundPlayer.play(settings.copySound)
        return item
    }

    /// Puts an image made in ReCopy (an annotated copy) on the clipboard without keeping it as an entry.
    func copyImage(_ png: Data) {
        pasteboard.write(.png(png))
        SoundPlayer.play(settings.copySound)
        announce(L(.toastImageCopied))
    }

    // MARK: Using entries

    /// Puts the entry on the clipboard. `text` overrides what is written, e.g. a colour in another format.
    func copy(_ item: ClipItem, as text: String? = nil) {
        write(item, as: text)
        save(ClipUseCases.markCopied(item))
        SoundPlayer.play(settings.copySound)
        announce(L(.toastCopied(toastTitle(item))))
    }

    /// Puts the entry on the clipboard and counts a paste; the platform layer sends the keystroke.
    func preparePaste(_ item: ClipItem) {
        write(item)
        save(ClipUseCases.markPasted(item))
        SoundPlayer.play(settings.pasteSound)
        announce(L(.toastPasted(toastTitle(item))))
    }

    /// Several entries at once, as one text when they're all text; otherwise each one is its own clipboard item.
    /// An image whose file is gone is left out, and not counted as copied.
    func copy(_ items: [ClipItem]) {
        let items = items.filter { payload($0) != nil }
        guard !items.isEmpty else { return }
        if let text = ClipUseCases.joinedText(items) {
            pasteboard.write(.text(text))
        } else {
            // Apps paste only the first image on the clipboard but every file, so images go as their files.
            pasteboard.write(.many(items.compactMap { item in
                item.kind == .image ? blobURL(item.blob).map { .files([$0]) } : payload(item)
            }))
        }
        for item in items { save(ClipUseCases.markCopied(item)) }
        SoundPlayer.play(settings.copySound)
        announce(L(.toastCopiedMany(items.count)))
    }

    /// Puts several entries on the clipboard as one text and counts a paste for each.
    func preparePaste(_ items: [ClipItem], text: String) {
        pasteboard.write(.text(text))
        for item in items { save(ClipUseCases.markPasted(item)) }
        SoundPlayer.play(settings.pasteSound)
        announce(L(.toastPastedMany(items.count)))
    }

    /// The language of a text entry that is code, or nil for prose and other kinds. Worked out once per text.
    func codeLanguage(of item: ClipItem) -> CodeLanguage? {
        guard item.kind == .text, let text = item.text else { return nil }
        if let cached = languages[item.hash] { return cached }
        let language = TextFormatter.language(of: text)
        languages[item.hash] = language
        return language
    }

    /// The language name the list shows for a code entry (e.g. a code block's own YAML tag), or nil for other entries.
    func codeName(of item: ClipItem) -> String? {
        guard let language = codeLanguage(of: item), let text = item.text else { return nil }
        if let cached = languageNames[item.hash] { return cached }
        let name = TextFormatter.languageName(language, of: text)
        languageNames[item.hash] = name
        return name
    }

    /// The image file Paste Special reads: the entry's image, or the image file it points at.
    func imageURL(of item: ClipItem) -> URL? {
        guard item.isConvertibleImage else { return nil }
        return item.kind == .image ? blobURL(item.blob) : item.files?.first.map { URL(filePath: $0.path) }
    }

    /// Puts converted copies of entries on the clipboard as files (one ⌘V pastes them all), so apps receive them in
    /// the chosen format. The files go in a temporary folder that's emptied each time. `pasting` counts a paste
    /// instead of a copy.
    /// - Returns: whether they're on the clipboard; a failed write is reported to the user.
    @discardableResult
    func writeConverted(_ images: [ConvertedImage], format: ImageFormat, for items: [ClipItem], pasting: Bool) -> Bool {
        guard !images.isEmpty, images.count == items.count else { return false }
        let names = ClipUseCases.uniqueNames(items.map { item in
            let name = (item.kind == .file ? item.files?.first?.name : nil) ?? L(.imageFileName)
            return (name as NSString).deletingPathExtension
        })
        do {
            let folder = try emptyPasteSpecialFolder()
            let urls = names.map { folder.appending(path: $0).appendingPathExtension(for: format.type) }
            for (image, url) in zip(images, urls) { try image.data.write(to: url, options: .atomic) }
            writeFiles(urls, for: items, pasting: pasting)
            return true
        } catch {
            Log.storage.error("Paste Special write failed: \(error.localizedDescription, privacy: .public)")
            NSApp.presentError(error)
            return false
        }
    }

    /// The temporary folder Paste Special writes its files to, emptied of the previous ones.
    func emptyPasteSpecialFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PasteSpecial")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Puts files Paste Special made on the clipboard and counts a paste or a copy of the entries they came from.
    func writeFiles(_ urls: [URL], for items: [ClipItem], pasting: Bool) {
        pasteboard.write(.files(urls))
        countUse(of: items, pasting: pasting)
    }

    /// Puts text rewritten by Paste Special on the clipboard, in a monospaced font if asked, and adds it to the history
    /// as its own entry: it's what was copied, so it's what the list should offer next. `pasting` also counts a paste.
    func writeFormatted(_ text: String, monospaced: Bool, for items: [ClipItem], pasting: Bool) {
        pasteboard.write(monospaced ? .monospaced(text) : .text(text))
        let source = items.first
        let capture = Capture(content: .text(text), sourceName: source?.sourceName, sourceBundleID: source?.sourceBundleID)
        guard var entry = record(capture) else { return }
        if pasting {
            entry = ClipUseCases.markPasted(entry, countsCopy: false)
            save(entry)
        }
        announceUse(of: [entry], pasting: pasting)
    }

    /// Counts a paste or a copy of each entry, with its sound and toast.
    private func countUse(of items: [ClipItem], pasting: Bool) {
        for item in items { save(pasting ? ClipUseCases.markPasted(item) : ClipUseCases.markCopied(item)) }
        announceUse(of: items, pasting: pasting)
    }

    private func announceUse(of items: [ClipItem], pasting: Bool) {
        SoundPlayer.play(pasting ? settings.pasteSound : settings.copySound)
        if let item = items.first, items.count == 1 {
            announce(pasting ? L(.toastPasted(toastTitle(item))) : L(.toastCopied(toastTitle(item))))
        } else {
            announce(pasting ? L(.toastPastedMany(items.count)) : L(.toastCopiedMany(items.count)))
        }
    }

    /// The entry's title, cut short for a toast.
    func toastTitle(_ item: ClipItem) -> String {
        let title = item.title.isEmpty ? item.kind.title : item.title
        return title.count > Metrics.Panel.toastTitleLength ? title.prefix(Metrics.Panel.toastTitleLength) + "…" : title
    }

    private func announce(_ message: String) {
        if settings.showToasts { onToast?(message) }
    }

    private func write(_ item: ClipItem, as text: String? = nil) {
        if let payload = payload(item, as: text) { pasteboard.write(payload) }
    }

    private func payload(_ item: ClipItem, as text: String? = nil) -> PasteboardPayload? {
        switch item.kind {
        case .image: blobURL(item.blob).flatMap { FileManager.default.fileExists(atPath: $0.path) ? .image($0) : nil }
        case .file: .files((item.files ?? []).map { URL(filePath: $0.path) })
        default: .text(text ?? item.text ?? "")
        }
    }

    /// Sets or, with an empty text, removes the entry's note.
    func setNote(_ note: String, for item: ClipItem) {
        update(item.id) { $0.note = ClipUseCases.cleanNote(note) }
    }

    /// Puts the entry in a group, or takes it out with nil.
    func setGroup(_ group: UUID?, for item: ClipItem) {
        update(item.id) { $0.groupID = group }
    }

    func group(of item: ClipItem) -> ClipGroup? {
        settings.groups.first { $0.id == item.groupID }
    }

    /// Adds a group, named "New Group" (or "New Group 2", …) until the user renames it.
    @discardableResult
    func addGroup(named name: String? = nil) -> ClipGroup {
        let base = name ?? L(.groupNewName)
        var title = base
        var number = 2
        while settings.groups.contains(where: { $0.name == title }) {
            title = "\(base) \(number)"
            number += 1
        }
        let group = ClipGroup(name: title)
        settings.groups.append(group)
        return group
    }

    /// Deletes the group; its entries stay in the history, outside any group.
    func deleteGroup(_ group: ClipGroup) {
        for item in items where item.groupID == group.id { setGroup(nil, for: item) }
        settings.groups.removeAll { $0.id == group.id }
    }

    func togglePin(_ item: ClipItem) {
        update(item.id) { $0.pinned.toggle() }
    }

    func delete(_ item: ClipItem) {
        guard persist({ try repository.delete(item) }) != nil else { return }
        items.removeAll { $0.id == item.id }
    }

    /// Deletes the entries the criteria pick (Settings › History › Delete Entries).
    func delete(matching criteria: CleanupCriteria) {
        for item in ClipUseCases.matching(items, criteria) { delete(item) }
    }

    /// Bytes on disk for these entries and their images, worked out off the main actor.
    func storageSize(of items: [ClipItem]) async -> Int64 {
        let repository = repository
        return await Task.detached { repository.size(of: items) }.value
    }

    /// Bytes on disk for the whole history, worked out off the main actor.
    func totalStorageSize() async -> Int64 {
        let repository = repository
        return await Task.detached { repository.totalSize() }.value
    }

    // MARK: Helpers

    private func pruneExpired() {
        for item in ClipUseCases.expired(items, retention: settings.retention) { delete(item) }
    }

    private func update(_ id: UUID, _ change: (inout ClipItem) -> Void) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        change(&item)
        save(item)
    }

    private func save(_ item: ClipItem) {
        guard persist({ try repository.save(item) }) != nil else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    /// Runs a vault write, reporting a failure to the user instead of throwing.
    @discardableResult
    private func persist<T>(_ write: () throws -> T) -> T? {
        do {
            return try write()
        } catch {
            Log.storage.error("Vault write failed: \(error.localizedDescription, privacy: .public)")
            NSApp.presentError(error)
            return nil
        }
    }
}
