import AppKit
import Foundation
import Testing
@testable import ReCopy

@MainActor
struct ClipboardSessionTests {
    @Test func copiesAreCountedButPastesAreNot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let copies = UsageStats(key: "copies", store: defaults)
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: NSPasteboard(name: .init(UUID().uuidString))),
                                       copies: copies)
        session.handle(Capture(content: .text("copied in another app")))
        let item = try #require(session.items.first)
        session.copy(item)
        session.preparePaste(item)
        #expect(copies.total == 2)
    }

    @Test func annotatedImageBecomesANewEntry() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: NSPasteboard(name: .init(UUID().uuidString))))
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let png = try #require(image.pngRepresentation)
        session.addImage(png, width: 4, height: 4)
        let item = try #require(session.items.first)
        #expect(item.kind == .image)
        #expect(item.sourceName == "ReCopy")
        #expect(session.blobURL(item.blob).map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func formattedTextIsCopiedAndBecomesTheLatestEntry() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let clipboard = NSPasteboard(name: .init(UUID().uuidString))
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: clipboard))
        session.importClip(.text("a: 1"), source: "Xcode", copiedAt: .distantPast)
        let original = try #require(session.items.first)

        session.writeFormatted("```yaml\na: 1\n```", monospaced: false, for: [original], pasting: false)
        #expect(clipboard.string(forType: .string) == "```yaml\na: 1\n```")
        let latest = try #require(ClipUseCases.latest(session.items))
        #expect(latest.text == "```yaml\na: 1\n```" && latest.sourceName == "Xcode" && latest.copyCount == 1)
        #expect(session.items.first { $0.id == original.id }?.copyCount == 1, "The original isn't counted again")

        session.writeFormatted("```yaml\na: 1\n```", monospaced: true, for: [original], pasting: true)
        let pasted = try #require(ClipUseCases.latest(session.items))
        #expect(pasted.id == latest.id && pasted.copyCount == 2 && pasted.pasteCount == 1, "The same text is counted, not added again")
        #expect(session.items.count == 2)
    }
}

@MainActor
struct ClipboardToastTests {
    @Test func copyAndPasteAnnounceUnlessToastsAreOff() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: NSPasteboard(name: .init(UUID().uuidString))))
        var messages: [String] = []
        session.onToast = { messages.append($0) }

        session.handle(Capture(content: .text("hello")))
        let item = try #require(session.items.first)
        session.preparePaste(item)
        #expect(messages == [L(.toastCopied("hello")), L(.toastPasted("hello"))])

        session.settings.showToasts = false
        session.copy(item)
        #expect(messages.count == 2)
    }
}

@MainActor
struct UniversalClipboardTests {
    @Test func savesItemsFromOtherDevicesUnlessTurnedOff() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        let session = ClipboardSession(root: root, pasteboard: SystemPasteboard(pasteboard: pasteboard))
        func copyFromPhone(_ text: String) {
            pasteboard.declareTypes([.string, SystemPasteboard.universalClipboardType], owner: nil)
            pasteboard.setString(text, forType: .string)
            pasteboard.setData(Data(), forType: SystemPasteboard.universalClipboardType)
        }

        copyFromPhone("from iPhone")
        // The clipboard is polled; a busy CI machine can take a few polls to record it.
        for _ in 0..<50 where session.items.first?.text != "from iPhone" {
            try await Task.sleep(for: .seconds(0.2))
        }
        #expect(session.items.first?.text == "from iPhone")
        #expect(session.items.first?.sourceName == L(.universalClipboardSource))

        session.settings.saveUniversalClipboard = false
        copyFromPhone("not saved")
        try await Task.sleep(for: .seconds(1.5))
        #expect(!session.items.contains { $0.text == "not saved" })
    }
}

@MainActor
struct ClipGroupTests {
    @Test func groupsAreSavedAndDeletingOneKeepsItsEntries() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = SystemPasteboard(pasteboard: NSPasteboard(name: .init(UUID().uuidString)))
        let session = ClipboardSession(root: root, pasteboard: pasteboard)
        session.importClip(.text("hello"), source: "Test", copiedAt: .now)
        let item = try #require(session.items.first)

        let work = session.addGroup(named: "Work")
        #expect(session.addGroup(named: "Work").name == "Work 2")
        session.setGroup(work.id, for: item)

        let reopened = ClipboardSession(root: root, pasteboard: pasteboard)
        #expect(reopened.settings.groups.map(\.name) == ["Work", "Work 2"])
        #expect(reopened.items.first?.groupID == work.id)

        session.deleteGroup(work)
        #expect(session.settings.groups.map(\.name) == ["Work 2"])
        #expect(session.items.count == 1)
        #expect(session.items.first?.groupID == nil)
    }
}
