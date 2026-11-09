import Foundation

/// Per-Mac preferences (vault bookmark, shortcuts, text size, window position) and the paste count.
/// End-to-end test runs get their own store, so they never change the user's.
nonisolated enum AppDefaults {
    // UserDefaults is thread-safe; the SDK just doesn't mark it Sendable.
    nonisolated(unsafe) static let store: UserDefaults = {
        #if DEBUG
        if E2EMode.isActive, let defaults = UserDefaults(suiteName: E2EMode.defaultsSuite) {
            if E2EMode.startsFresh { defaults.removePersistentDomain(forName: E2EMode.defaultsSuite) }
            return defaults
        }
        #endif
        migrateFromCopaste(into: .standard)
        return .standard
    }()

    /// ReCopy used to be Copaste (`com.lazycatlabs.copaste`): brings its preferences over once, so updating keeps the
    /// vault folder, shortcuts and window position.
    static func migrateFromCopaste(into defaults: UserDefaults, from domain: String = "com.lazycatlabs.copaste") {
        let doneKey = "migratedFromCopaste"
        guard !defaults.bool(forKey: doneKey) else { return }
        for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }
}

#if DEBUG
/// Launch flags the E2E tests (ReCopyUITests) pass. Debug builds only.
nonisolated enum E2EMode {
    static let defaultsSuite = "com.lazycatlabs.recopy.e2e"
    static let notification = Notification.Name("com.lazycatlabs.recopy.e2e")
    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isActive: Bool { arguments.contains("-e2e") }
    /// Keeps the preferences of the previous run, e.g. to check the window position is remembered.
    static var startsFresh: Bool { !arguments.contains("-e2eKeepDefaults") }
    /// Leaves the centering guides on screen after a drag, so a screenshot can show them.
    static var keepsGuides: Bool { arguments.contains("-e2eGuides") }
    /// What to open at launch: "panel", "panel:image", "settings", "welcome" or "annotate".
    static var openCommand: String? {
        arguments.firstIndex(of: "-e2eOpen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
}
#endif
