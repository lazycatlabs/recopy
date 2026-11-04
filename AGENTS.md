# AGENTS.md

Guide for AI agents working on ReCopy, a clipboard manager for macOS.

The stack follows Masa (`../masa/AGENTS.md`): Clean Architecture, feature-first folders, `@Observable` state,
protocol-driven repositories, async/await, Swift Testing.

> **Rule of thumb:** when this document and the code disagree, the code wins. Copy the closest existing pattern.

## 1. Project facts

| Item | Value |
|------|-------|
| Module | `ReCopy` (`@testable import ReCopy`) |
| Platform | macOS 26.0+ only. iOS support was removed; don't add `#if os(iOS)` code back unless asked. |
| Swift | Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency. Pure value types are `nonisolated`. |
| Project | Xcode project with synchronized folders (new files are picked up automatically). No Swift packages. |
| Targets | `ReCopy` (app), `ReCopyTests` (Swift Testing, macOS host), `ReCopyUITests` (XCUITest E2E, `ReCopyE2E` scheme) |
| Localization | `ReCopy/App/Resources/Localizable.xcstrings`, **generated** from `scripts/strings.py` (English, Indonesian) |
| Storage | The user's vault folder (JSON, one file per entry). `UserDefaults` (through `AppDefaults.store`) only for per-Mac preferences: the vault bookmark, shortcuts (`HotKeyStore`), text size and the clipboard window position (`PanelPlacement`). |
| Network | LinkPresentation, to fetch a copied link's title, favicon and preview image; and GitHub's releases API when Settings › Updates is opened (`GitHubReleasesDataSource`). |
| Support | Feedback and bug reports go to `admin@lazycatlabs.com` (`SupportLinks`); website `https://recopy.lazycatlabs.com`. |
| Commits | Conventional Commits, one commit per change. No AI co-author lines. |
| CI | GitHub Actions: `pull_request-ci.yml` (SwiftLint, generated strings, unit tests; E2E by hand via Run workflow) and `merge-ci.yml` (ad-hoc DMG + zip artifact, deletes the merged branch). |

## 2. Commands

```bash
python3 scripts/strings.py
swiftlint
xcodebuild -project ReCopy.xcodeproj -scheme ReCopy -destination 'platform=macOS' build
xcodebuild -project ReCopy.xcodeproj -scheme ReCopy -destination 'platform=macOS' test
bundle exec fastlane mac release   # App Store: build, upload, listing, submit (see Releases)
scripts/appstore_screenshots.sh    # App Store screenshots from the E2E sample vault, into fastlane/screenshots/
scripts/e2e.sh   # E2E UI tests; screenshots in e2e-output/ (git-ignored). Drives the real mouse; quits a running ReCopy.
```

E2E runs launch the app with `-e2e` (Debug only, see `AppDefaults.swift` / `E2EFixtures.swift`): a throwaway vault with
sample entries, a private clipboard and separate preferences, plus commands sent as distributed notifications.

## 3. Layout

```text
ReCopy/
├── App/
│   ├── ReCopyApp.swift            # @main: the menu bar item
│   ├── DI/AppContainer.swift       # Composition root: vault location + session
│   ├── DI/ClipboardSession.swift   # The open vault's history; the one place entries change
│   ├── MacAppDelegate.swift        # Global shortcut, Settings/welcome windows, menu bar menu
│   ├── MacWindows.swift            # Hand-hosted windows, ordered front even when ReCopy isn't active
│   └── Resources/
├── Core/                           # DesignSystem (tokens, L()), Storage (JSONFileStore), Logging, Platform, Input
└── Features/
    ├── Clipboard/                  # Domain (ClipItem, ClipClassifier, ColorValue, TimeSection, ClipAction, ClipUseCases)
    │                               # Data (FileClipRepository, SystemPasteboard, LinkMetadata, TextRecognition, PasteSimulator)
    │                               # Presentation (ClipboardViewModel, ClipboardPage and its sections, the floating panel)
    ├── Annotate/                   # SwiftUI Canvas editor; marks use 0…1 coordinates
    ├── Settings/                   # AppSettings (vault config), SupportLinks, SettingsPage and one …SettingsPage per pane
    ├── Updates/                    # GitHub releases check, UpdatesSettingsPage
    ├── Migration/                  # Raycast import, ImportSettingsPage
    └── Vault/                      # Folder picking, the bookmark, OnboardingPage and VaultPickerPage
```

## 4. Rules

- Data flows DataSource → Repository → UseCase / ClipboardSession → View. Business rules live in `ClipUseCases` or entities so they can be unit-tested.
- Pasteboard types become `CapturedContent`, then `ClipKind` via `ClipClassifier`. Views compare enums.
- Vault writes go through `ClipboardSession.persist`, which reports failures to the user. Never fail silently.
- Vault format must stay backward compatible: new `AppSettings` fields need defaults; new `ClipItem` fields must be optional.
- Never record secrets: `SystemPasteboard` skips `org.nspasteboard.ConcealedType` / `TransientType`, and `AppSettings.ignoredApps` is checked in `ClipboardSession.handle`.
- Use `Log`, never `print`.

## 5. UI conventions

- **No magic numbers.** Use `Spacing.xxs…huge`, `Radius`, `Opacity`, and a `Metrics.<Area>` entry for anything else.
- **No hardcoded user-facing strings.** Add the key to `scripts/strings.py` with both languages, run it, then use
  `L(.key)` or `Text(.key)`.
- **Small `body`.** Split views as described in "View naming and where a view lives" below.
- Settings panes use `SettingsGroup`, `SettingsRow` and `SettingsToggle`, laid out by `SettingsPaneLayout`.
- Give anything a test needs an `accessibilityIdentifier`.
- Respect light and dark mode. Check new colours in both.

### View naming and where a view lives

| Kind of UI                                     | Type and file suffix | Example                                  |
|------------------------------------------------|----------------------|------------------------------------------|
| A whole screen, window, sheet or pane          | `Page`               | `ClipboardPage`, `HistorySettingsPage`   |
| One row or cell of a `List`, `ForEach` or grid | `Item`               | `ClipboardPage.EntryItem`                |
| A named block of a page                        | `Section`            | `ClipboardPage.HeaderSection`            |
| Loading state                                  | `Loading`            | _none yet_                               |
| Empty state                                    | `Empty`              | _none yet_                               |
| Shared page logic (not a view)                 | `Behavior`           | a protocol with its default implementation in an extension |

For every piece of a page (sections, items, loading and empty states) the decision is the same:

- **Reusable** (used by more than one page, or plausibly will be): an `internal` struct in its own file, in the
  feature's `Presentation/Views`, or in `Core/DesignSystem` when other features use it too.
- **Used only by that one page**: nest it in the page, `extension ClipboardPage { struct HeaderSection: View { … } }`
  in `ClipboardPage+HeaderSection.swift`, used as `HeaderSection` inside the page. A piece of a few lines can stay a
  `private` struct in the page's own file.

Enums that list a page's parts don't take the `Page` name: `SettingsPane` lists the Settings panes, `OnboardingStep`
the introduction's steps. Names that would clash with an entity get a word of their own (`EntryItem`, not `ClipItem`).
Shared components that aren't a page, section or item (`SettingsRow`, `ClipIcon`, `KeyCaps`, `VaultFolderButton`)
keep their own names. AppKit controllers that host a page (`ClipboardPanelController`) keep theirs too.

## 6. Vault format

```text
<vault>/
├── .copaste/config.json   # AppSettings
├── items/<uuid>.json      # ClipItem
└── blobs/                 # <uuid>.png images, <uuid>-icon favicons, <uuid>-preview link images
```

## 7. Platform notes

- Menu bar app (`LSUIElement`), sandbox off. The clipboard is polled every 0.5 s. The floating window is a
  non-activating `NSPanel`, so the previous app stays in front and receives ⌘V (needs Accessibility; without it
  ReCopy only copies). Keyboard shortcuts are handled by a local key monitor in `ClipboardPanelController`.
- A single click on an entry selects it; double-click copies it and closes the window (a toast confirms on screen).
  ↩ pastes, ⌘↩ copies.
- The global shortcut (default ⇧⌘V) is recorded in Settings and re-registered through `HotKeyStore.onChange`.
- Copy and paste sounds are the system alert sounds (`ClipSound`, played by `SoundPlayer`).
- Tests must never touch the real clipboard: give `ClipboardSession` a `SystemPasteboard(pasteboard:)` with a private
  `NSPasteboard(name:)`. A running ReCopy would otherwise record test data into the user's vault.
- The ad-hoc signature changes every build, so Accessibility may need granting again in debug builds.
- **Releases:** bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, add a `## X.Y.Z — <date>` section to
  `CHANGELOG.md`, run `scripts/make_release.sh` (DMG + zip, prints the zip's sha256), tag `vX.Y.Z`, publish with
  `gh release create` (notes: that changelog section plus the install block), then update `Casks/recopy.rb` in
  `lazycatlabs/homebrew-tap`.
- **App Store:** after the steps above, `bundle exec fastlane mac release` (`fastlane/Fastfile`) archives the same
  Release build with the `APP_STORE` flag and the sandbox entitlements in `AppStore/`, uploads it, sends the listing in
  `fastlane/metadata` with that version's `CHANGELOG.md` section as "What's New", and submits it for review.
  `mac beta` goes to TestFlight only, `mac metadata` updates the listing without a build. The App Store Connect API key
  is read from `fastlane/.env` (see `.env.example`). `#if APP_STORE` hides the Updates pane and sponsor links (App
  Review rules) and makes the Raycast import ask for its folder. The vault bookmark is security-scoped in every build.
  `AppStore/README.md` lists what lives where and the one-time setup in App Store Connect.
