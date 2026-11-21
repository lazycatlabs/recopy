import SwiftUI

extension ClipboardPage {
    /// The bottom bar: app name (or paused), then the primary action and the actions menu with their shortcuts.
    /// Dragging its background moves the window.
    struct FooterSection: View {
        @Environment(ClipboardSession.self) private var session
        @Bindable var model: ClipboardViewModel
        let perform: (ClipAction, ClipItem) -> Void
        let performMany: ([ClipItem]) -> Void
        let onDrag: (_ ended: Bool) -> Void

        var body: some View {
            HStack(spacing: Spacing.md) {
                AppIconImage(size: Metrics.appIcon * TextScale.shared.factor)
                Text(session.isPaused ? L(.statusPaused) : L(.appName)).font(.scaled(.body)).foregroundStyle(.secondary)
                Spacer()
                let chosen = model.chosen(in: session)
                if let item = chosen.first {
                    let primary: ClipAction = session.settings.pastesDirectly ? .paste : .copy
                    let shortcuts = HotKeyStore.shared
                    if chosen.count > 1 {
                        let title = primary == .paste ? L(.actionPasteMany(chosen.count)) : L(.actionCopyMany(chosen.count))
                        button(title, keys: shortcuts[.paste].keys) { performMany(chosen) }
                            .accessibilityIdentifier("panel.primary")
                    } else {
                        button(primary.title(for: item), keys: shortcuts[.paste].keys) { perform(primary, item) }
                            .accessibilityIdentifier("panel.primary")
                    }
                    button(L(.actionsTitle), keys: shortcuts[.actions].keys) { model.showsActions.toggle() }
                        .accessibilityIdentifier("panel.actions")
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
            .background { WindowDragHandle(onDrag: onDrag) }
        }

        private func button(_ title: String, keys: [String], action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: Spacing.sm) {
                    Text(title).font(.scaled(.body, weight: .medium))
                    KeyCaps(keys: keys)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
    }
}
