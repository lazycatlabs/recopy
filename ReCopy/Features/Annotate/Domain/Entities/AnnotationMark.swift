import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, crop, pen, highlighter, rectangle, ellipse, triangle, arrow, text, blur

    var id: String { rawValue }

    /// Shapes that can be drawn as an outline or filled.
    var isShape: Bool { [.rectangle, .ellipse, .triangle].contains(self) }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .arrow: "arrow.up.right"
        case .text: "textformat"
        case .blur: "checkerboard.rectangle"
        }
    }

    var title: String {
        switch self {
        case .select: L(.toolSelect)
        case .crop: L(.toolCrop)
        case .pen: L(.toolPen)
        case .highlighter: L(.toolHighlighter)
        case .rectangle: L(.toolRectangle)
        case .ellipse: L(.toolEllipse)
        case .triangle: L(.toolTriangle)
        case .arrow: L(.toolArrow)
        case .text: L(.toolText)
        case .blur: L(.toolBlur)
        }
    }
}

/// One stroke or shape on an image. Points are shares of the image's size (0…1), so a mark is drawn the same
/// on screen and in the full-size saved image.
struct AnnotationMark: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var color: Color
    /// Line width as a share of the image's width. For blur, it sets the size of the mosaic's squares.
    var width: CGFloat
    var points: [CGPoint]
    /// What a text mark says; its top-left corner is the first point.
    var text = ""
    /// Shapes only: filled with the color instead of outlined.
    var filled = false
    /// Blur only: the image shrunk to one pixel per mosaic square (see `mosaic(of:width:)`).
    var mosaic: Image?

    /// A text mark's font size on an image (or canvas) of this size.
    func fontSize(in size: CGSize) -> CGFloat {
        width * size.width * Metrics.Annotate.textScale
    }

    /// The stroke width on an image (or canvas) of this size.
    func lineWidth(in size: CGSize) -> CGFloat {
        width * size.width * (tool == .highlighter ? Metrics.Annotate.highlighterScale : 1)
    }

    /// The image shrunk to one pixel per mosaic square, for a blur mark of this width. Drawn back at full size
    /// without smoothing, each pixel becomes a solid square, so the covered content can't be recovered. It's opaque,
    /// so semi-transparent content in the original can't show through.
    static func mosaic(of image: NSImage, width: CGFloat) -> Image? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), image.size.width > 0 else { return nil }
        // Never more squares than the image has pixels, so a tall, narrow image doesn't ask for a huge bitmap.
        let columns = min(source.width, max(1, Int((1 / (width * Metrics.Annotate.mosaicScale)).rounded())))
        let rows = min(source.height, max(1, Int((CGFloat(columns) * image.size.height / image.size.width).rounded())))
        guard let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return context.makeImage().map { Image(decorative: $0, scale: 1).interpolation(.none) }
    }

    /// The area the mark covers on a canvas of this size, in points.
    func bounds(in size: CGSize) -> CGRect {
        guard let first = points.first else { return .null }
        if tool == .text {
            let font = NSFont.systemFont(ofSize: fontSize(in: size), weight: .semibold)
            return CGRect(origin: CGPoint(x: first.x * size.width, y: first.y * size.height),
                          size: NSAttributedString(string: text, attributes: [.font: font]).size())
        }
        return points.reduce(CGRect.null) { $0.union(CGRect(x: $1.x * size.width, y: $1.y * size.height, width: 0, height: 0)) }
    }

    // ponytail: bounding-box hit test, so a click inside a diagonal stroke's box picks it too.
    /// Whether a click at this canvas location lands on the mark.
    func contains(_ location: CGPoint, in size: CGSize) -> Bool {
        let slop = lineWidth(in: size) / 2 + Metrics.Annotate.hitSlop
        return bounds(in: size).insetBy(dx: -slop, dy: -slop).contains(location)
    }

    /// The mark shifted by this offset, as a share of the image's size.
    func moved(by offset: CGSize) -> AnnotationMark {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        return copy
    }

    /// The mark stretched so the corner at `start` ends at `end` while `anchor` stays put (all shares of the image's
    /// size). Text keeps its proportions and grows its font instead.
    func resized(anchor: CGPoint, from start: CGPoint, to end: CGPoint) -> AnnotationMark {
        func scale(_ end: CGFloat, _ start: CGFloat, _ anchor: CGFloat) -> CGFloat {
            start == anchor ? 1 : (end - anchor) / (start - anchor)
        }
        var scaleX = scale(end.x, start.x, anchor.x), scaleY = scale(end.y, start.y, anchor.y)
        var copy = self
        if tool == .text {
            scaleX = max(abs(scaleY), Metrics.Annotate.widthRange.lowerBound / width)
            scaleY = scaleX
            copy.width = width * scaleX
        }
        copy.points = points.map { CGPoint(x: anchor.x + ($0.x - anchor.x) * scaleX, y: anchor.y + ($0.y - anchor.y) * scaleY) }
        return copy
    }

    func draw(in context: GraphicsContext, size: CGSize) {
        let points = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = points.first, let last = points.last else { return }
        let bounds = CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                            width: abs(last.x - first.x), height: abs(last.y - first.y))
        let lineWidth = lineWidth(in: size)
        var path = Path()
        switch tool {
        case .select, .crop:
            return
        case .text:
            let label = Text(text).font(.system(size: fontSize(in: size), weight: .semibold)).foregroundStyle(color)
            return context.draw(label, at: first, anchor: .topLeading)
        case .blur:
            guard let mosaic else { return }
            var area = context
            area.clip(to: Path(bounds))
            return area.draw(mosaic, in: CGRect(origin: .zero, size: size))
        case .pen, .highlighter:
            path.addLines(points)
        case .rectangle:
            path.addRect(bounds)
        case .ellipse:
            path.addEllipse(in: bounds)
        case .triangle:
            path.addLines([CGPoint(x: bounds.midX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.maxY),
                           CGPoint(x: bounds.minX, y: bounds.maxY)])
            path.closeSubpath()
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = lineWidth * Metrics.Annotate.arrowHeadLength
            for side in [-1.0, 1.0] {
                let wing = angle + .pi - side * Metrics.Annotate.arrowHeadAngle
                path.move(to: last)
                path.addLine(to: CGPoint(x: last.x + head * cos(wing), y: last.y + head * sin(wing)))
            }
        }
        if filled && tool.isShape { return context.fill(path, with: .color(color)) }
        let shading = tool == .highlighter ? color.opacity(Opacity.highlighter) : color
        context.stroke(path, with: .color(shading), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
