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

    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        var pressed = false
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
            if isDown { pressed = event != nil }
        }
        // Without Accessibility (e.g. revoked while running) the posted ⌘V is dropped, so it isn't a paste.
        if pressed && isTrusted { PasteStats.shared.record() }
    }
}
