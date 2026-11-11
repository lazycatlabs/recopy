import AppKit
import Carbon.HIToolbox
import SwiftUI

/// ReCopy lives in the menu bar: a global shortcut (⇧⌘V unless changed in Settings) opens the floating clipboard window,
/// another (⌃⌘V) opens Paste Special for the latest copy. ⌥↩ in the window opens it for the selected entry.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let container: AppContainer = {
        #if DEBUG
        if E2EMode.isActive { return E2EFixtures.makeContainer() }
        #endif
        return AppContainer()
    }()
    private(set) lazy var panel = ClipboardPanelController(container: container)
    private var hotKeys: [GlobalHotKey] = []
    private var pasteWatcher: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.showSettings = { [weak self] in self?.showSettings() }
        container.onToast = { [weak self] message in
            // Next turn of the run loop: pasting hides the window first, so the toast goes on screen instead.
            DispatchQueue.main.async {
                guard let self else { return }
                if self.panel.isVisible { self.panel.showToast(message) } else { ToastPresenter.shared.show(message) }
            }
        }
        #if DEBUG
        if E2EMode.isActive { return E2EFixtures.start(self) }
        #endif
        registerHotKeys()
        pasteWatcher = PasteSimulator.watchPastes { [weak self] in self?.container.session?.userPasted() ?? UsageStats.pastes.record() }
        HotKeyStore.shared.onChange = { [weak self] in self?.registerHotKeys() }
        if container.session == nil { showWelcome() }
    }

    private func registerHotKeys() {
        hotKeys.forEach { $0.unregister() }
        hotKeys = [
            register(.openHistory) { [weak self] in
                guard let self else { return }
                // Before a vault is chosen, the introduction's "try the shortcut" page takes the press.
                if container.session == nil, MacWindows.isVisible(id: "welcome") {
                    NotificationCenter.default.post(name: Onboarding.shortcutPressed, object: nil)
                } else {
                    panel.toggle()
                }
            },
            register(.pasteSpecialLatest) { [weak self] in self?.panel.pasteSpecialLatest() },
        ]
    }

    private func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> GlobalHotKey {
        let binding = HotKeyStore.shared[shortcut]
        return GlobalHotKey(keyCode: Int(binding.keyCode), modifiers: binding.carbonModifiers, action: action)
    }

    func showSettings() {
        MacWindows.show(id: "settings", title: L(.settingsTitle), size: Metrics.Settings.windowSize, fullSize: true) {
            SettingsPage().environment(container)
        }
    }

    func showWelcome() {
        MacWindows.show(id: "welcome", title: L(.appName), size: Metrics.Settings.welcomeSize) {
            VaultPickerPage { MacWindows.close(id: "welcome") }.environment(container)
        }
    }
}

/// The menu bar item's menu.
struct MacMenu: View {
    let delegate: MacAppDelegate

    var body: some View {
        Button(L(.menuOpenHistory(HotKeyStore.shared.binding.displayText))) { delegate.panel.show() }
        if let session = delegate.container.session {
            Toggle(L(.menuPause), isOn: Binding(get: { session.isPaused }, set: { session.isPaused = $0 }))
        }
        Divider()
        Button(L(.supportFeedback)) { SupportLinks.feedback().map { _ = NSWorkspace.shared.open($0) } }
        Button(L(.supportBugReport)) { SupportLinks.bugReport().map { _ = NSWorkspace.shared.open($0) } }
        Button(L(.supportWebsite)) { NSWorkspace.shared.open(SupportLinks.website) }
        Divider()
        Button(L(.menuSettings)) { delegate.showSettings() }.keyboardShortcut(",")
        Button(L(.menuQuit)) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
