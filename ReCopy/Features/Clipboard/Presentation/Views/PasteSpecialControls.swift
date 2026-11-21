import SwiftUI

/// A Paste Special option: the title on its own line, so the control below gets the full width.
struct PasteSpecialRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).font(.scaled(.body, weight: .medium)).foregroundStyle(.secondary)
            content.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Cancel, Copy and Paste at the bottom of a Paste Special sheet, with their shortcuts.
struct PasteSpecialButtons: View {
    let finish: (_ pasting: Bool) -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Spacer()
            Button(L(.actionCancel), action: cancel)
            button(L(.actionCopy), keys: HotKeyStore.shared[.copy].keys) { finish(false) }
                .accessibilityIdentifier("pasteSpecial.copy")
            button(L(.actionPaste), keys: HotKeyStore.shared[.paste].keys) { finish(true) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("pasteSpecial.paste")
                .hiddenInAppStore()
        }
    }

    private func button(_ title: String, keys: [String], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                KeyCaps(keys: keys)
            }
        }
    }
}

extension View {
    /// The floating card a Paste Special sheet is drawn on.
    func pasteSpecialCard() -> some View {
        pickerStyle(.segmented)
            .padding(Spacing.page)
            .frame(width: Metrics.PasteSpecial.width)
            .background(.thickMaterial, in: .rect(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(.primary.opacity(Opacity.fill)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pasteSpecial")
    }
}
