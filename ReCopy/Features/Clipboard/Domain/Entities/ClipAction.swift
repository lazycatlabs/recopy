import Foundation

/// What can be done with an entry. Which ones apply depends on its kind.
nonisolated enum ClipAction: String, CaseIterable, Identifiable, Sendable {
    case paste, copy, pasteSpecial, open, composeEmail, copyHex, copyRGB, copyHSL, annotate, saveToFile, revealInFinder
    case pin, delete

    var id: String { rawValue }

    static func available(for item: ClipItem) -> [ClipAction] {
        var actions: [ClipAction] = [.paste, .copy]
        if item.isConvertibleImage || item.kind == .text || item.convertibleMedia != nil { actions.append(.pasteSpecial) }
        switch item.kind {
        case .link: actions.append(.open)
        case .email: actions.append(.composeEmail)
        case .color: actions += [.copyHex, .copyRGB, .copyHSL]
        case .image: actions += [.annotate, .saveToFile]
        case .file: actions += [.open, .revealInFinder]
        case .text: actions.append(.saveToFile)
        }
        return actions + [.pin, .delete]
    }

    var symbolName: String {
        switch self {
        case .paste: "doc.on.clipboard"
        case .copy: "doc.on.doc"
        case .pasteSpecial: "wand.and.stars"
        case .open: "arrow.up.forward.app"
        case .composeEmail: "envelope"
        case .copyHex, .copyRGB, .copyHSL: "eyedropper"
        case .annotate: "pencil.tip.crop.circle"
        case .saveToFile: "square.and.arrow.down"
        case .revealInFinder: "folder"
        case .pin: "pin"
        case .delete: "trash"
        }
    }

    func title(for item: ClipItem) -> String {
        switch self {
        case .paste: L(.actionPaste)
        case .copy: L(.actionCopy)
        case .pasteSpecial: L(.actionPasteSpecial)
        case .open: item.kind == .link ? L(.actionOpenInBrowser) : L(.actionOpen)
        case .composeEmail: L(.actionComposeEmail)
        case .copyHex: L(.actionCopyAs("HEX"))
        case .copyRGB: L(.actionCopyAs("RGB"))
        case .copyHSL: L(.actionCopyAs("HSL"))
        case .annotate: L(.actionAnnotate)
        case .saveToFile: L(.actionSaveToFile)
        case .revealInFinder: L(.actionRevealInFinder)
        case .pin: item.pinned ? L(.actionUnpin) : L(.actionPin)
        case .delete: L(.actionDelete)
        }
    }

    /// The shortcut that runs the action in the clipboard window (changeable in Settings).
    var shortcut: Shortcut? {
        switch self {
        case .paste: .paste
        case .copy: .copy
        case .pasteSpecial: .pasteSpecial
        case .open, .composeEmail: .open
        case .annotate: .annotate
        case .saveToFile: .save
        case .pin: .pin
        case .delete: .delete
        default: nil
        }
    }
}
