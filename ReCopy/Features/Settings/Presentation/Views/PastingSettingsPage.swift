import SwiftUI

struct PastingSettingsPage: View {
    @Bindable var session: ClipboardSession

    var body: some View {
        SettingsGroup(L(.settingsPasting)) {
            SettingsRow(L(.settingsPasteDirectly), symbol: "doc.on.clipboard", subtitle: pasteDirectlySubtitle) {
                HStack {
                    if session.settings.pasteDirectly && !PasteSimulator.isTrusted {
                        Button(L(.settingsGrantAccess)) { PasteSimulator.requestAccess() }
                    }
                    SettingsToggle(L(.settingsPasteDirectly), isOn: $session.settings.pasteDirectly)
                        .accessibilityIdentifier("settings.pasteDirectly")
                }
            }
        }
        SettingsGroup(L(.settingsSounds)) {
            SettingsRow(L(.settingsCopySound), symbol: "speaker.wave.2") {
                soundPicker(L(.settingsCopySound), $session.settings.copySound)
            }
            SettingsRow(L(.settingsPasteSound), symbol: "speaker.wave.3") {
                soundPicker(L(.settingsPasteSound), $session.settings.pasteSound)
            }
        }
        StatsSection(stats: .pastes, title: L(.pasteStatsTitle), id: "pasteStats",
                     footerText: { L(.pasteStatsFooter($0, $1)) }, emptyText: L(.pasteStatsEmpty))
        StatsSection(stats: .copies, title: L(.copyStatsTitle), id: "copyStats",
                     footerText: { L(.copyStatsFooter($0, $1)) }, emptyText: L(.copyStatsEmpty))
    }

    /// What on and off do, plus the missing permission when it's on but can't send ⌘V.
    private var pasteDirectlySubtitle: String {
        let needsAccess = session.settings.pasteDirectly && !PasteSimulator.isTrusted
        return needsAccess ? L(.settingsPasteDirectlyFooter) + "\n" + L(.settingsAccessibilityNeeded) : L(.settingsPasteDirectlyFooter)
    }

    /// Choosing a sound plays it, so it can be heard before it's kept.
    private func soundPicker(_ title: String, _ selection: Binding<ClipSound>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ClipSound.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        .onChange(of: selection.wrappedValue) { _, sound in SoundPlayer.play(sound) }
    }
}
