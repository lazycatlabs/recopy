import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Pastes into the app in front by sending ⌘V, which needs the Accessibility permission.
enum PasteSimulator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to System Settings › Privacy & Security › Accessibility.
    static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Tags the ⌘V ReCopy sends, so `watchPastes` doesn't count it a second time.
    private static let marker: Int64 = 0x5265_436F_7079

    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        var pressed = false
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: marker)
            event?.post(tap: .cghidEventTap)
            if isDown { pressed = event != nil }
        }
        // Without Accessibility (e.g. revoked while running) the posted ⌘V is dropped, so it isn't a paste.
        if pressed && isTrusted { UsageStats.pastes.record() }
    }

    /// Calls `onPaste` for each ⌘V the user presses in another app, e.g. right after copying or after copying an
    /// entry from the clipboard window. Needs Accessibility, like sending ⌘V; without it nothing is reported.
    static func watchPastes(_ onPaste: @escaping () -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == kVK_ANSI_V, !event.isARepeat,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) != marker else { return }
            onPaste()
        }
    }
}
