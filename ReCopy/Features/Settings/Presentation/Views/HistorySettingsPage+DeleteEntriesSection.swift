import SwiftUI

extension HistorySettingsPage {
    /// Settings › History › Delete Entries: removes entries by when they were last copied, type, group, note and pin, with a live
    /// count and size of what would go, and a confirmation.
    struct DeleteEntriesSection: View {
        let session: ClipboardSession
        @State private var criteria = CleanupCriteria()
        @State private var bytes: Int64?
        @State private var confirms = false

        private var matches: [ClipItem] { ClipUseCases.matching(session.items, criteria) }

        var body: some View {
            let matches = matches
            SettingsGroup(L(.cleanupTitle), footer: L(.cleanupFooter)) {
                SettingsRow(L(.cleanupPeriod), symbol: "calendar") {
                    Picker(L(.cleanupPeriod), selection: $criteria.period) {
                        ForEach(CleanupPeriod.allCases) { period in
                            if period.startsOlderSection { Divider() }
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings.cleanupPeriod")
                }
                SettingsRow(L(.cleanupType), symbol: "line.3.horizontal.decrease") {
                    Picker(L(.cleanupType), selection: $criteria.kind) {
                        Label(L(.filterAllTypes), systemImage: "square.grid.2x2").tag(ClipKind?.none)
                        Divider()
                        ForEach(ClipKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbolName).tag(ClipKind?.some($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings.cleanupType")
                }
                if !session.settings.groups.isEmpty {
                    SettingsRow(L(.cleanupGroup), symbol: "folder") {
                        Picker(L(.cleanupGroup), selection: $criteria.group) {
                            Text(.groupAll).tag(UUID?.none)
                            Divider()
                            ForEach(session.settings.groups) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsRow(L(.cleanupIncludePinned), symbol: "pin") {
                    SettingsToggle(L(.cleanupIncludePinned), isOn: $criteria.includePinned)
                }
                SettingsRow(L(.cleanupIncludeNoted), symbol: "note.text") {
                    SettingsToggle(L(.cleanupIncludeNoted), isOn: $criteria.includeNoted)
                        .accessibilityIdentifier("settings.cleanupIncludeNoted")
                }
                if !session.settings.groups.isEmpty && criteria.group == nil {
                    SettingsRow(L(.cleanupIncludeGrouped), symbol: "folder.badge.minus") {
                        SettingsToggle(L(.cleanupIncludeGrouped), isOn: $criteria.includeGrouped)
                            .accessibilityIdentifier("settings.cleanupIncludeGrouped")
                    }
                }
                SettingsRow(L(.cleanupMatches(matches.count)), symbol: "trash", subtitle: bytes.map(StorageSection.format)) {
                    Button(L(.cleanupDelete), role: .destructive) { confirms = true }
                        .disabled(matches.isEmpty)
                        .accessibilityIdentifier("settings.cleanupDelete")
                        .confirmationDialog(L(.cleanupConfirm(matches.count)), isPresented: $confirms) {
                            Button(L(.cleanupDeleteNow), role: .destructive) { session.delete(matching: criteria) }
                        } message: {
                            Text(.cleanupConfirmMessage)
                        }
                }
                .accessibilityIdentifier("settings.cleanupMatches")
            }
            // Re-measures when the matched entries change: a filter, a new entry, or a note, pin or group set on one.
            .task(id: matches.map(\.id)) {
                bytes = await session.storageSize(of: matches)
            }
        }
    }
}
