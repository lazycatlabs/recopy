import SwiftUI

/// Settings › Import: brings Raycast's clipboard images and rich-text copies into the vault.
struct ImportSettingsPage: View {
    let session: ClipboardSession
    @State private var files: [URL] = []
    @State private var confirms = false
    @State private var progress: (done: Int, total: Int)?
    @State private var result: String?

    var body: some View {
        SettingsGroup(L(.importTitle), footer: L(.importFooter)) {
            SettingsRow("Raycast", symbol: "square.and.arrow.down.on.square", subtitle: result) {
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                        Text(.importProgress(progress.done, progress.total)).font(.scaled(.caption))
                    }
                    .frame(width: Metrics.Settings.groupNameWidth)
                } else {
                    Button(L(.importFromRaycast), action: prepare)
                        .disabled(!Distribution.isAppStore
                            && !FileManager.default.fileExists(atPath: RaycastClipboardDataSource.folder.path))
                        .accessibilityIdentifier("settings.importRaycast")
                }
            }
        }
        .confirmationDialog(L(.importConfirm(files.count)), isPresented: $confirms) {
            Button(L(.importAction), action: start)
        } message: {
            Text(.importConfirmMessage)
        }
    }

    /// Lists the files first, so the confirmation can say how many there are. Files older than the
    /// "Keep history for" setting are left out: they would be deleted again straight away.
    private func prepare() {
        guard let folder = raycastFolder() else { return }
        let cutoff = session.settings.retention.cutoff(from: .now) ?? .distantPast
        files = RaycastClipboardDataSource.importableFiles(in: folder).filter { RaycastClipboardDataSource.copiedAt($0) >= cutoff }
        result = nil
        if files.isEmpty { result = L(.importNothing) } else { confirms = true }
    }

    /// Raycast's clipboard folder. The sandboxed App Store build can't read it until the user picks it.
    private func raycastFolder() -> URL? {
        guard Distribution.isAppStore else { return RaycastClipboardDataSource.folder }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = RaycastClipboardDataSource.folder
        panel.prompt = L(.importAction)
        panel.message = L(.importPickFolder)
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func start() {
        let files = files
        Task {
            var added = 0
            progress = (0, files.count)
            for (index, file) in files.enumerated() {
                if let content = await RaycastClipboardDataSource.capture(of: file),
                   session.importClip(content, source: "Raycast", copiedAt: RaycastClipboardDataSource.copiedAt(file)) {
                    added += 1
                }
                progress = (index + 1, files.count)
            }
            progress = nil
            result = L(.importDone(added, files.count - added))
            await session.recognizeTextInImages()
        }
    }
}
