#if DEBUG
import AppKit
import OSLog
import SwiftUI

/// Sets ReCopy up for the E2E tests (`-e2e`): a fresh vault in a temporary folder with sample entries, a private
/// clipboard, no global shortcut, and commands the tests send as distributed notifications
/// ("panel", "panel:image", "settings", "welcome", "annotate", "hide", "pasteSpecial", "copy:imageFile",
/// "recordPaste").
enum E2EFixtures {
    private static var observer: Any?

    static func makeContainer() -> AppContainer {
        let root = FileManager.default.temporaryDirectory.appending(path: "recopy-e2e-\(UUID().uuidString)")
        let vaults = UserDefaultsVaultRepository()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(E2EMode.defaultsSuite))
        let container = AppContainer(vaults: vaults) { SystemPasteboard(pasteboard: pasteboard) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        container.open(root)
        if let session = container.session { seed(session) }
        if E2EMode.startsFresh { seedPasteStats() }
        return container
    }

    static func start(_ delegate: MacAppDelegate) {
        delegate.panel.showSettings = { [weak delegate] in delegate?.showSettings() }
        observer = DistributedNotificationCenter.default().addObserver(forName: E2EMode.notification, object: nil, queue: .main) { note in
            let command = note.object as? String
            MainActor.assumeIsolated { if let command { run(command, delegate) } }
        }
        if let command = E2EMode.openCommand { run(command, delegate) }
    }

    private static func run(_ command: String, _ delegate: MacAppDelegate) {
        let session = delegate.container.session
        let image = session?.items.first { $0.kind == .image }
        switch command {
        case "panel": delegate.panel.show()
        case "panel:image": delegate.panel.show(selecting: image?.id)
        case "settings": delegate.showSettings()
        case "welcome": delegate.showWelcome()
        case "annotate": if let image { delegate.panel.perform(.annotate, on: image) }
        case "hide": delegate.panel.hide()
        // The global Paste Special shortcut (global shortcuts are off in E2E runs).
        case "pasteSpecial": delegate.panel.pasteSpecialLatest()
        // An image file copied in Finder. Written by the app: the test runner's own files are in its sandbox.
        case "copy:imageFile": copyImageFile()
        // A paste counted, without sending ⌘V anywhere.
        case "recordPaste": PasteStats.shared.record()
        // ⌘ pressed or released, through the app's own event queue (the test runner can't press keys system-wide).
        case "command:down", "command:up":
            let flags: NSEvent.ModifierFlags = command == "command:down" ? .command : []
            let window = NSApp.keyWindow?.windowNumber ?? 0
            if let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: 0,
                                            windowNumber: window, context: nil, characters: "", charactersIgnoringModifiers: "",
                                            isARepeat: false, keyCode: 55) {
                NSApp.postEvent(event, atStart: false)
            }
        default: Log.clipboard.error("Unknown E2E command \(command, privacy: .public)")
        }
    }

    /// Paste Count reads 2 today and this month, 3 in all: two pastes now and one 40 days ago.
    private static func seedPasteStats() {
        let stats = PasteStats.shared
        stats.record()
        stats.record()
        if let earlier = Calendar.current.date(byAdding: .day, value: -40, to: .now) { stats.record(at: earlier) }
    }

    /// The entries in the README screenshot: a pinned command, links, colors, an image, an email and some text.
    private static func seed(_ session: ClipboardSession) {
        session.settings.fetchLinkPreviews = false
        let now = Date.now
        let yesterday = now.addingTimeInterval(-86_400)
        let entries: [(String, Date)] = [
            ("Terima kasih sudah mencoba ReCopy!", yesterday.addingTimeInterval(-300)),
            ("hsl(211, 100%, 50%)", yesterday.addingTimeInterval(-200)),
            ("Meeting moved to Thursday 3 pm", yesterday),
            ("admin@lazycatlabs.com", now.addingTimeInterval(-400)),
            ("#FF8C3C", now.addingTimeInterval(-200)),
            ("https://github.com/lazycatlabs/recopy", now.addingTimeInterval(-100)),
            ("brew install --cask lazycatlabs/tap/recopy", now.addingTimeInterval(-600)),
            ("struct ContentView: View {\n    var body: some View {\n        Text(\"Hello, ReCopy!\")\n    }\n}",
             now.addingTimeInterval(-700)),
            (#"{"name": "ReCopy", "platform": "macOS", "tags": ["clipboard", "productivity"]}"#, yesterday.addingTimeInterval(-100)),
        ]
        for (text, date) in entries { session.importClip(.text(text), source: "Safari", copiedAt: date) }
        if let png = chartPNG() {
            session.importClip(.image(png: png, width: Int(chartSize.width), height: Int(chartSize.height)),
                               source: "Screenshot", copiedAt: now.addingTimeInterval(-300))
        }
        if let brew = session.items.first(where: { $0.text?.hasPrefix("brew") == true }) { session.togglePin(brew) }
        let work = session.addGroup(named: "Work")
        session.addGroup(named: "Design")
        for item in session.items where item.text?.hasPrefix("Meeting") == true || item.kind == .email {
            session.setGroup(work.id, for: item)
        }
        Task { await session.recognizeTextInImages() }
    }

    /// Saves the sample chart as Sample.png and puts the file on the private clipboard, where the app records it.
    private static func copyImageFile() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "recopy-e2e-files-\(UUID().uuidString)")
        let url = folder.appending(path: "Sample.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try chartPNG()?.write(to: url)
        } catch {
            return Log.clipboard.error("E2E sample file: \(error.localizedDescription, privacy: .public)")
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(E2EMode.defaultsSuite))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    private static let chartSize = CGSize(width: 1440, height: 900)

    private static func chartPNG() -> Data? {
        let renderer = ImageRenderer(content: SampleChart().frame(width: chartSize.width, height: chartSize.height))
        renderer.scale = 1
        return renderer.nsImage?.pngRepresentation
    }
}

/// A dashboard screenshot to annotate.
private struct SampleChart: View {
    private let bars: [CGFloat] = [0.35, 0.55, 0.42, 0.66, 0.5, 0.8, 0.72]

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            HStack(spacing: 40) {
                stat("Revenue Q3", "+24%")
                stat("Active users", "18.2k")
            }
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 30) {
                    ForEach(bars.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                            .frame(height: proxy.size.height * bars[index])
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(60)
        .background(Color(red: 0.06, green: 0.09, blue: 0.16))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 20))
    }
}
#endif
