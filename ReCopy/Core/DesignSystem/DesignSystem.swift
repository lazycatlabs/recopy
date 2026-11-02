import SwiftUI

// MARK: - Tokens
// Every size, spacing and radius in the UI comes from here, so the look can be tuned in one place.

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
    static let page: CGFloat = 20
    static let section: CGFloat = 24
    static let hero: CGFloat = 32
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 22
}

enum Opacity {
    static let hover = 0.04
    static let tint = 0.08
    static let fill = 0.12
    static let strong = 0.2
    static let border = 0.25
    static let muted = 0.6
    /// The dark layer over the clipboard window's material in dark mode, so text stays readable on any wallpaper.
    static let panelDim = 0.42
    /// Highlighter strokes in the annotation editor.
    static let highlighter = 0.35
}

enum Metrics {
    static let hairline: CGFloat = 1
    static let rowIcon: CGFloat = 22
    static let appIcon: CGFloat = 16
    static let swatch: CGFloat = 14
    static let keyCap: CGFloat = 20

    /// The floating clipboard window on macOS.
    enum Panel {
        static let size = CGSize(width: 780, height: 500)
        static let cornerRadius: CGFloat = 26
        static let listWidth: CGFloat = 290
        static let rowHeight: CGFloat = 38
        static let colorPreview: CGFloat = 120
        static let actionsWidth: CGFloat = 260
        /// Pressing ⌘1…⌘9 pastes one of the first nine visible entries.
        static let quickPasteCount = 9
        static let toastDuration: TimeInterval = 1.8
        /// Longer entry titles are cut short in the toast.
        static let toastTitleLength = 40
        /// Dragging the window's center within this of the screen's center line snaps it there.
        static let snapDistance: CGFloat = 16
        static let guideWidth: CGFloat = 1
    }

    /// The on-screen toast after copying or pasting.
    enum Toast {
        static let bottomOffset: CGFloat = 80
        static let fadeDuration: TimeInterval = 0.25
    }

    enum Detail {
        /// About half the clipboard window; the information below scrolls.
        static let previewHeight: CGFloat = Panel.size.height / 2
        /// The note field grows to this many lines, then scrolls.
        static let noteLines = 3
        static let infoLabelWidth: CGFloat = 120
        static let colorFormatWidth: CGFloat = 46
    }

    enum Settings {
        static let windowSize = CGSize(width: 860, height: 640)
        static let sidebarWidth: CGFloat = 210
        static let pageMaxWidth: CGFloat = 760
        static let rowIcon: CGFloat = 24
        /// Where a row's text starts, so the lines between rows line up with it.
        static let rowTextInset: CGFloat = Spacing.xxl + rowIcon + Spacing.xl
        static let groupNameWidth: CGFloat = 200
        static let welcomeSize = CGSize(width: 480, height: 540)
        static let heroIcon: CGFloat = 72
        static let ignoredAppIcon: CGFloat = 20
        static let shortcutRecorderWidth: CGFloat = 80
    }

    /// The introduction in the welcome window.
    enum Onboarding {
        static let heroIcon: CGFloat = 96
        /// The app icon floats up and down by this much on the first page.
        static let floatOffset: CGFloat = 6
        static let floatDuration: TimeInterval = 1.6
        static let keyCap: CGFloat = 52
        static let keyCapPressedScale: CGFloat = 0.92
        static let hoverScale: CGFloat = 1.08
        static let symbol: CGFloat = 36
        static let featureTile = CGSize(width: 92, height: 76)
        static let dot: CGFloat = 8
        static let activeDotWidth: CGFloat = 22
        static let pageAnimation: TimeInterval = 0.35
    }

    enum PasteSpecial {
        static let width: CGFloat = 400
        /// Wait this long after the last change before converting again, so dragging the quality slider stays smooth.
        static let debounce: Duration = .milliseconds(150)
        /// The font size of text pasted as monospaced rich text.
        static let codeFontSize: CGFloat = 12
        /// The text preview's height, and how much of a long text it shows.
        static let previewHeight: CGFloat = 180
        static let previewLength = 4_000
        /// The language search's list of matches, dropping down over the preview.
        static let languageListHeight: CGFloat = 170
    }

    enum Annotate {
        static let windowSize = CGSize(width: 900, height: 680)
        static let swatch: CGFloat = 20
        static let selectedRing: CGFloat = 2
        /// Stroke widths, as a share of the image's width, so a mark looks the same at any zoom.
        static let widthRange: ClosedRange<CGFloat> = 0.002...0.03
        static let defaultWidth: CGFloat = 0.006
        static let sizeSliderWidth: CGFloat = 100
        /// The dot beside the size slider, in points.
        static let sizePreviewMin: CGFloat = 2
        static let sizePreviewMax: CGFloat = 24
        /// Blur mosaic: the side of a square as a multiple of the stroke width.
        static let mosaicScale: CGFloat = 3
        static let highlighterScale: CGFloat = 4
        /// Text marks: font size as a multiple of the stroke width.
        static let textScale: CGFloat = 4
        static let textFieldMinWidth: CGFloat = 80
        /// Wait after closing the editor before reopening the clipboard window (see `ClipboardPanelController.annotate`).
        static let reopenDelay: TimeInterval = 0.3
        static let arrowHeadAngle = Double.pi / 7
        static let arrowHeadLength: CGFloat = 6
        /// Select tool: how far outside a mark, in points, a click still picks it, and the corner handles' size.
        static let hitSlop: CGFloat = 6
        static let handleSize: CGFloat = 8
        /// Crop tool: the smallest area, in points, that crops; a smaller drag is taken as a slip.
        static let minCropSize: CGFloat = 10
    }

    enum Clipboard {
        /// Seconds between checks of the system clipboard on macOS.
        static let pollInterval: TimeInterval = 0.5
        /// Lets macOS fold the clipboard check into other wake-ups instead of waking just for it.
        static let pollTolerance: TimeInterval = 0.1
        /// Longest side, in pixels, an image is decoded at for the detail preview.
        static let previewMaxPixelSize: CGFloat = 2048
        /// Memory the decoded images and thumbnails may use before the oldest are dropped.
        static let imageCacheBytes = 64 * 1024 * 1024
        /// Between checks that the previous app is in front again, and after it is, before sending ⌘V.
        static let pasteDelay: TimeInterval = 0.05
        /// Gives up waiting for the previous app after this many checks (one second) and sends ⌘V anyway.
        static let pasteWaitAttempts = 20
        /// Between the ⌘V of entries pasted one after another, so the app reads each before the next replaces it.
        static let multiPasteInterval: TimeInterval = 0.2
        static let previewTextLimit = 4000
    }
}

// MARK: - Localization

/// Localized text for APIs that take a `String` (button titles, pickers, interpolation).
/// `Text` takes the resource directly: `Text(.settingsTitle)`.
nonisolated func L(_ resource: LocalizedStringResource) -> String { // swiftlint:disable:this identifier_name
    String(localized: resource)
}

// MARK: - Components

extension View {
    /// The rounded, subtly filled surface used for cards in both light and dark mode.
    func card(cornerRadius: CGFloat = Radius.md) -> some View {
        background(.fill.quaternary, in: .rect(cornerRadius: cornerRadius))
    }
}

/// A key cap such as "↩" or "⌘", as shown next to actions.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.scaled(.subheadline, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.xs)
            .frame(minWidth: Metrics.keyCap * TextScale.shared.factor, minHeight: Metrics.keyCap * TextScale.shared.factor)
            .background(Color.primary.opacity(Opacity.fill), in: .rect(cornerRadius: Radius.xs))
    }
}

/// A combination as one cap per key: ⌘ K.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
        }
    }
}

/// The capsule confirmation used in the clipboard window and on screen ("“…” copied — ready to paste").
struct ToastLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.scaled(.callout))
            .lineLimit(1)
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.md)
            .background(.thickMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.primary.opacity(Opacity.fill)))
            .shadow(radius: Spacing.md)
            .accessibilityIdentifier("toast")
    }
}
