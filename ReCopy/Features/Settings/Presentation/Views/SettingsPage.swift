import SwiftUI

/// The Settings panes, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, history, pasting, appearance, shortcuts, groups, privacy, importing, updates, about

    var id: Self { self }

    /// The panes this build shows. App Store copies are updated by the App Store, and may not point elsewhere.
    static var shown: [SettingsPane] {
        #if APP_STORE
        allCases.filter { $0 != .updates }
        #else
        allCases
        #endif
    }

    var title: String {
        switch self {
        case .general: L(.settingsGeneral)
        case .history: L(.settingsHistory)
        case .pasting: L(.settingsPasting)
        case .appearance: L(.settingsAppearance)
        case .shortcuts: L(.settingsShortcuts)
        case .groups: L(.settingsGroups)
        case .privacy: L(.settingsPrivacy)
        case .importing: L(.importTitle)
        case .updates: L(.settingsUpdates)
        case .about: L(.settingsAbout)
        }
    }

    var subtitle: String {
        switch self {
        case .general: L(.settingsGeneralSubtitle)
        case .history: L(.settingsHistorySubtitle)
        case .pasting: L(.settingsPastingSubtitle)
        case .appearance: L(.settingsAppearanceSubtitle)
        case .shortcuts: L(.settingsShortcutsSubtitle)
        case .groups: L(.settingsGroupsSubtitle)
        case .privacy: L(.settingsPrivacySubtitle)
        case .importing: L(.importSubtitle)
        case .updates: L(.settingsUpdatesSubtitle)
        case .about: L(.aboutSubtitle)
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
        case .pasting: "doc.on.clipboard"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .groups: "folder"
        case .privacy: "hand.raised"
        case .importing: "square.and.arrow.down.on.square"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }

    /// What the sidebar search matches: the pane's name and the settings on it.
    var searchText: String {
        let settings: [LocalizedStringResource] = switch self {
        case .general: [.settingsVault, .settingsVaultFolder, .vaultChange, .settingsLaunchAtLogin]
        case .history: [.settingsKeepHistory, .settingsLinkPreviews, .settingsUniversalClipboard, .settingsTextRecognition,
                        .settingsRecognitionMode, .storageTitle, .storageUsed, .cleanupTitle, .cleanupPeriod]
        case .pasting: [.settingsPasteDirectly, .settingsSounds, .settingsCopySound, .settingsPasteSound]
        case .appearance: [.settingsTextSize, .settingsShowToasts, .settingsWindowPosition]
        case .shortcuts: [.settingsShortcut, .actionPaste, .actionCopy, .actionsTitle, .shortcutQuickPaste, .pasteSpecialTitle,
                          .shortcutGroupAnywhere, .shortcutGroupWindow, .shortcutGroupEntry]
        case .groups: [.groupAdd, .groupNewName]
        case .privacy: [.settingsIgnoredApps, .settingsAddApp]
        case .importing: [.importFromRaycast]
        case .updates: [.updateCheck, .changelogTitle, .updateDownload]
        case .about: [.aboutVersion, .aboutLicense, .aboutSourceCode, .sponsorTitle, .supportFeedback, .supportBugReport, .supportWebsite]
        }
        #if APP_STORE
        let sponsors: [String] = []
        #else
        let sponsors = self == .about ? Sponsor.allCases.map(\.title) : []
        #endif
        return ([title, subtitle] + settings.map(L) + sponsors).joined(separator: " ")
    }

    /// Panes about the open vault's history; without a vault only General and About apply.
    var needsVault: Bool { ![.general, .updates, .about].contains(self) }
}

/// A sidebar pane's icon: accent-colored, but in the selected row's text color while that row is highlighted, so it
/// doesn't vanish into the accent-colored selection.
private struct SidebarIcon: View {
    let symbol: String
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Image(systemName: symbol).foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.accentColor))
    }
}

/// Settings: a searchable sidebar of panes, and the chosen one.
struct SettingsPage: View {
    @Environment(AppContainer.self) private var container
    @State private var search = ""

    private var panes: [SettingsPane] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return SettingsPane.shown.filter { pane in
            (container.session != nil || !pane.needsVault) && (query.isEmpty || pane.searchText.localizedStandardContains(query))
        }
    }

    var body: some View {
        @Bindable var navigation = SettingsNavigation.shared
        NavigationSplitView {
            List(panes, selection: $navigation.pane) { pane in
                Label {
                    Text(pane.title).font(.scaled(.body))
                } icon: {
                    SidebarIcon(symbol: pane.symbol)
                }
                .tag(pane)
                .accessibilityIdentifier("settings.nav.\(pane.rawValue)")
            }
            .searchable(text: $search, placement: .sidebar)
            .overlay {
                if panes.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .navigationSplitViewColumnWidth(min: Metrics.Settings.sidebarWidth, ideal: Metrics.Settings.sidebarWidth)
        } detail: {
            pane(panes.contains(navigation.pane ?? .general) ? navigation.pane ?? .general : panes.first ?? .general)
        }
        .onChange(of: search) {
            // Show the first match, so typing a setting's name opens its pane.
            if let first = panes.first, !panes.contains(navigation.pane ?? .general) { navigation.pane = first }
        }
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        SettingsPaneLayout(pane: pane) {
            switch pane {
            case .general: GeneralSettingsPage()
            case .updates: UpdatesSettingsPage()
            case .about: AboutSettingsPage()
            default:
                if let session = container.session {
                    switch pane {
                    case .history: HistorySettingsPage(session: session)
                    case .pasting: PastingSettingsPage(session: session)
                    case .appearance: AppearanceSettingsPage(session: session)
                    case .shortcuts: ShortcutsSettingsPage()
                    case .groups: GroupsSettingsPage(session: session)
                    case .privacy: PrivacySettingsPage(session: session)
                    default: ImportSettingsPage(session: session)
                    }
                }
            }
        }
        .id(pane)
    }
}
