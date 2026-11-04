import Foundation

/// How long unpinned entries are kept.
nonisolated enum Retention: String, Codable, CaseIterable, Sendable {
    case day, week, month, threeMonths, year, forever

    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .day: calendar.date(byAdding: .day, value: -1, to: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .forever: nil
        }
    }

    var title: String {
        switch self {
        case .day: L(.retentionDay)
        case .week: L(.retentionWeek)
        case .month: L(.retentionMonth)
        case .threeMonths: L(.retentionThreeMonths)
        case .year: L(.retentionYear)
        case .forever: L(.retentionForever)
        }
    }
}

/// One of the Mac's system alert sounds (`/System/Library/Sounds`), or silence.
nonisolated enum ClipSound: String, Codable, CaseIterable, Sendable {
    case none, pop, tink, glass, ping, purr, bottle, frog, funk, hero, morse, submarine, blow, basso, sosumi

    /// The system sound's name, as `NSSound(named:)` takes it.
    var soundName: String? { self == .none ? nil : rawValue.capitalized }

    var title: String { soundName ?? L(.soundNone) }
}

/// An app whose copies are never recorded (password managers, for example).
nonisolated struct IgnoredApp: Codable, Hashable, Sendable {
    var bundleID: String
    var name: String
}

/// A named collection of entries the user puts together, to filter the history by.
nonisolated struct ClipGroup: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
}

/// Vault-wide settings, stored in `.recopy/config.json` (`.copaste/` before the rename). New fields need defaults: old files are merged with these.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var retention: Retention = .threeMonths
    var textRecognition = true
    var accurateRecognition = false
    var fetchLinkPreviews = true
    /// Paste into the app in front when an entry is chosen, instead of only copying it.
    var pasteDirectly = true
    /// Save items copied on an iPhone, iPad or another Mac (Universal Clipboard) as soon as they arrive.
    var saveUniversalClipboard = true
    /// A short confirmation on screen after copying or pasting.
    var showToasts = true
    /// A sound when something is copied, and when ReCopy pastes.
    var copySound = ClipSound.none
    var pasteSound = ClipSound.none
    /// The user's groups, in the order they made them. Entries point at one with `ClipItem.groupID`.
    var groups: [ClipGroup] = []
    var ignoredApps: [IgnoredApp] = [
        IgnoredApp(bundleID: "com.apple.Passwords", name: "Passwords"),
        IgnoredApp(bundleID: "com.apple.keychainaccess", name: "Keychain Access"),
        IgnoredApp(bundleID: "com.1password.1password", name: "1Password"),
        IgnoredApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
    ]
}
