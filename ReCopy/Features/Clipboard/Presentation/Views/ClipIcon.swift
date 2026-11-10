import SwiftUI
import AppKit

/// The list's icon for an entry: a thumbnail for images, a favicon for links, a swatch for colours, a frame for
/// videos and a waveform for audio files.
struct ClipIcon: View {
    let item: ClipItem
    var size: CGFloat = Metrics.rowIcon
    @Environment(ClipboardSession.self) private var session
    @Environment(\.displayScale) private var displayScale
    @State private var videoFrame: NSImage?

    var body: some View {
        Group {
            if let videoFrame {
                Image(nsImage: videoFrame).resizable().scaledToFill()
            } else if let image = thumbnail {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let color = item.color {
                RoundedRectangle(cornerRadius: Radius.xs).fill(Color(color))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(.primary.opacity(Opacity.border)))
            } else {
                Image(systemName: item.mediaKind?.symbolName ?? item.kind.symbolName).resizable().scaledToFit().padding(size / 6)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        // On the square, not the frame: a filled frame is wider than the icon and its corner would be cut off.
        .overlay(alignment: .bottomTrailing) { if videoFrame != nil { playBadge } }
        .clipShape(.rect(cornerRadius: Radius.xs))
        .accessibilityLabel(item.kind.title)
        .task(id: videoPath) {
            guard let videoPath else { return videoFrame = nil }
            videoFrame = await ImageCache.videoFrame(at: URL(filePath: videoPath), maxPixelSize: size * displayScale)
        }
    }

    private var videoPath: String? { item.mediaKind == .video ? item.files?.first?.path : nil }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: size * Metrics.Clipboard.playBadgeScale))
            .foregroundStyle(.white)
            .shadow(radius: Metrics.Clipboard.playBadgeShadow)
            .padding(size / 10)
    }

    private var thumbnail: NSImage? {
        let pixels = size * displayScale
        switch item.kind {
        case .image:
            // The square crops the longer side, so the shorter side needs the full size.
            let sides = [item.pixelWidth, item.pixelHeight].compactMap { $0 }.filter { $0 > 0 }.map(CGFloat.init)
            let aspect = sides.count == 2 ? (sides.max() ?? 1) / (sides.min() ?? 1) : 1
            return session.blobURL(item.blob).flatMap { ImageCache.image(at: $0, maxPixelSize: pixels * aspect) }
        case .link: return session.blobURL(item.link?.favicon).flatMap { ImageCache.image(at: $0, maxPixelSize: pixels) }
        case .file:
            // Videos show a frame once it's decoded, and audio files a waveform, over the generic file icon.
            if item.mediaKind != nil { return nil }
            return item.files?.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
        default: return nil
        }
    }
}

extension Color {
    init(_ value: ColorValue) {
        self.init(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}
