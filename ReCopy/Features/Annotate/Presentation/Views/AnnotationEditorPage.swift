import SwiftUI
import UniformTypeIdentifiers

/// Crop, rotate, draw and write on an image (pen, highlighter, shapes, arrow, text, blur), then keep the result as a new clipboard entry.
struct AnnotationEditorPage: View {
    let image: NSImage
    /// Called with the annotated image as PNG, and its size in pixels.
    let onDone: (Data, Int, Int) -> Void
    /// Called with the annotated image as PNG, to put it on the clipboard without keeping it as an entry.
    let onCopy: (Data) -> Void
    let onCancel: () -> Void

    private static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]

    @State private var marks: [AnnotationMark] = []
    @State private var current: AnnotationMark?
    @State private var tool = AnnotationTool.pen
    @State private var color = Color.red
    @State private var width = Metrics.Annotate.defaultWidth
    @State private var filled = false
    @State private var canvasSize = CGSize.zero
    /// The text mark being typed, shown as a field on the canvas until it's committed.
    @State private var typing: AnnotationMark?
    @FocusState private var typingFocused: Bool
    /// The image after crops and rotations, which flatten the marks into it; nil until the first one.
    @State private var edited: NSImage?
    /// Crop tool: the area being dragged, as shares of the image's size.
    @State private var cropArea: CGRect?
    /// Earlier versions of the image and its marks, for undo.
    @State private var history: [Snapshot] = []
    /// Select tool: the mark with handles around it, and the drag moving or resizing it.
    @State private var selection: AnnotationMark.ID?
    @State private var edit: Edit?

    private struct Snapshot {
        let marks: [AnnotationMark]
        let image: NSImage?
    }

    /// The image being annotated: the original, or its cropped or rotated version.
    private var picture: NSImage { edited ?? image }

    private struct Edit {
        let index: Int
        let original: AnnotationMark
        /// The corner handle being dragged and the opposite corner, in shares of the image's size; nil when moving.
        var corner: CGPoint?
        var anchor = CGPoint.zero
        var recorded = false
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(Spacing.xl)
            Divider()
            canvas.padding(Spacing.page).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(Spacing.xl)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.xl) {
            Picker(L(.annotateTool), selection: $tool) {
                ForEach(AnnotationTool.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
            }
            .onChange(of: tool) {
                commitText()
                selection = nil
                cropArea = nil
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if tool.isShape {
                Picker(L(.annotateShapeStyle), selection: $filled) {
                    Label(L(.annotateOutline), systemImage: "square").tag(false)
                    Label(L(.annotateFill), systemImage: "square.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: Spacing.sm) {
                ForEach(Self.palette, id: \.self) { swatch in
                    Circle().fill(swatch)
                        .overlay(Circle().strokeBorder(.primary.opacity(Opacity.border)))
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: swatch == color ? Metrics.Annotate.selectedRing : 0)
                            .padding(-Metrics.Annotate.selectedRing * 2))
                        .frame(width: Metrics.Annotate.swatch, height: Metrics.Annotate.swatch)
                        .onTapGesture {
                            color = swatch
                            typing?.color = swatch
                        }
                        .accessibilityAddTraits(.isButton)
                }
            }
            sizeControl
            Spacer(minLength: 0)
            Button(L(.annotateRotate), systemImage: "rotate.right") { transform { $0.rotatedClockwise() } }
                .help(L(.annotateRotate))
                .keyboardShortcut(typing == nil ? KeyboardShortcut("r") : nil)
                .accessibilityIdentifier("annotate.rotate")
            Button(L(.actionUndo), systemImage: "arrow.uturn.backward", action: undo)
                .disabled(history.isEmpty)
                .keyboardShortcut(typing == nil ? KeyboardShortcut("z") : nil)
            Button(L(.actionClear), systemImage: "trash") {
                record()
                marks.removeAll()
            }
                .disabled(marks.isEmpty)
        }
        .labelStyle(.iconOnly)
    }

    /// A slider for the stroke size, next to a dot as wide as the stroke will be on the canvas.
    private var sizeControl: some View {
        HStack(spacing: Spacing.sm) {
            let sample = AnnotationMark(tool: tool, color: color, width: width, points: [])
            Circle().fill(color)
                .overlay(Circle().strokeBorder(.primary.opacity(Opacity.border)))
                .frame(width: min(max(sample.lineWidth(in: canvasSize), Metrics.Annotate.sizePreviewMin), Metrics.Annotate.sizePreviewMax))
                .frame(width: Metrics.Annotate.sizePreviewMax, height: Metrics.Annotate.sizePreviewMax)
            Slider(value: $width, in: Metrics.Annotate.widthRange) { Text(L(.annotateWidth)) }
                .labelsHidden()
                .frame(width: Metrics.Annotate.sizeSliderWidth)
                .accessibilityIdentifier("annotate.size")
                .onChange(of: width) { typing?.width = width }
        }
        .help(L(.annotateWidth))
    }

    private var canvas: some View {
        ZStack {
            Image(nsImage: picture).resizable()
            Canvas { context, size in
                for mark in marks + [current].compactMap({ $0 }) { mark.draw(in: context, size: size) }
                if let mark = marks.first(where: { $0.id == selection }) { drawSelection(around: mark.bounds(in: size), in: context) }
                if let cropArea { drawCrop(cropArea, in: context, size: size) }
            }
        }
        .accessibilityIdentifier("annotate.canvas")
        .overlay(alignment: .topLeading) { textField }
        .aspectRatio(picture.size, contentMode: .fit)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .gesture(drawing)
    }

    @ViewBuilder
    private var textField: some View {
        if let mark = typing, let origin = mark.points.first {
            TextField(L(.annotateTextPlaceholder), text: Binding { typing?.text ?? "" } set: { typing?.text = $0 })
                .textFieldStyle(.plain)
                .font(.system(size: mark.fontSize(in: canvasSize), weight: .semibold))
                .foregroundStyle(mark.color)
                .fixedSize()
                .frame(minWidth: Metrics.Annotate.textFieldMinWidth, alignment: .leading)
                .overlay(Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: Metrics.hairline, dash: [Spacing.xs])))
                .offset(x: origin.x * canvasSize.width, y: origin.y * canvasSize.height)
                .focused($typingFocused)
                .onSubmit(commitText)
                .onExitCommand { typing = nil }
                // A new field for each text mark, focused once it's in the window.
                .id(mark.id)
                // After the click that placed it has finished; focusing during it doesn't stick.
                .task {
                    try? await Task.sleep(for: .milliseconds(50))
                    typingFocused = true
                }
                .accessibilityIdentifier("annotate.text")
        }
    }

    /// Keeps the text being typed as a mark, unless it's empty.
    private func commitText() {
        if let typing, !typing.text.trimmingCharacters(in: .whitespaces).isEmpty {
            record()
            marks.append(typing)
        }
        typing = nil
    }

    private var drawing: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canvasSize.width > 0, canvasSize.height > 0, tool != .text else { return }
                if tool == .select { return dragSelection(value) }
                let point = normalized(value.location)
                if tool == .crop {
                    let start = normalized(value.startLocation)
                    cropArea = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                      width: abs(point.x - start.x), height: abs(point.y - start.y))
                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    return
                }
                if current == nil {
                    current = AnnotationMark(tool: tool, color: color, width: width, points: [point], filled: filled,
                                             mosaic: tool == .blur ? AnnotationMark.mosaic(of: picture, width: width) : nil)
                } else if tool == .pen || tool == .highlighter {
                    current?.points.append(point)
                } else {
                    current?.points = [current?.points.first ?? point, point]
                }
            }
            .onEnded { value in
                edit = nil
                if let area = cropArea {
                    cropArea = nil
                    let size = CGSize(width: area.width * canvasSize.width, height: area.height * canvasSize.height)
                    if min(size.width, size.height) >= Metrics.Annotate.minCropSize { transform { $0.cropped(toShare: area) } }
                }
                if tool == .text, canvasSize.width > 0, canvasSize.height > 0 {
                    // A click places a text field there; clicking elsewhere keeps the previous text.
                    commitText()
                    typing = AnnotationMark(tool: .text, color: color, width: width, points: [normalized(value.location)])
                }
                if let current {
                    record()
                    marks.append(current)
                }
                current = nil
            }
    }

    private func record() { history.append(Snapshot(marks: marks, image: edited)) }

    private func undo() {
        guard let last = history.popLast() else { return }
        marks = last.marks
        edited = last.image
        selection = nil
    }

    /// Flattens the marks into the image, then crops or rotates it. Undo brings both back.
    private func transform(_ change: (CGImage) -> CGImage?) {
        commitText()
        guard let flat = flattened()?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let result = change(flat) else { return }
        record()
        edited = NSImage(cgImage: result, size: CGSize(width: result.width, height: result.height))
        marks.removeAll()
        selection = nil
    }

    /// A canvas location as a share of the image's size.
    private func normalized(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x / canvasSize.width, y: location.y / canvasSize.height)
    }

    /// A rectangle's corners, clockwise from the top left.
    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    /// Select tool: a press on a corner handle resizes the selected mark, on a mark selects and moves it.
    private func dragSelection(_ value: DragGesture.Value) {
        if edit == nil { edit = beginEdit(at: value.startLocation) }
        guard var edit, value.translation != .zero else { return }
        if !edit.recorded {
            record()
            edit.recorded = true
            self.edit = edit
        }
        let offset = CGSize(width: value.translation.width / canvasSize.width, height: value.translation.height / canvasSize.height)
        marks[edit.index] = if let corner = edit.corner {
            edit.original.resized(anchor: edit.anchor, from: corner,
                                  to: CGPoint(x: corner.x + offset.width, y: corner.y + offset.height))
        } else {
            edit.original.moved(by: offset)
        }
    }

    private func beginEdit(at location: CGPoint) -> Edit? {
        if let index = marks.firstIndex(where: { $0.id == selection }) {
            let handles = corners(of: marks[index].bounds(in: canvasSize))
            if let hit = handles.firstIndex(where: { hypot($0.x - location.x, $0.y - location.y) <= Metrics.Annotate.handleSize }) {
                return Edit(index: index, original: marks[index], corner: normalized(handles[hit]),
                            anchor: normalized(handles[(hit + 2) % handles.count]))
            }
        }
        guard let index = marks.lastIndex(where: { $0.contains(location, in: canvasSize) }) else {
            selection = nil
            return nil
        }
        selection = marks[index].id
        return Edit(index: index, original: marks[index])
    }

    /// A dashed box with corner handles around the selected mark.
    private func drawSelection(around rect: CGRect, in context: GraphicsContext) {
        context.stroke(Path(rect), with: .color(.accentColor), style: StrokeStyle(lineWidth: Metrics.hairline, dash: [Spacing.xs]))
        let side = Metrics.Annotate.handleSize
        for corner in corners(of: rect) {
            let handle = Path(CGRect(x: corner.x - side / 2, y: corner.y - side / 2, width: side, height: side))
            context.fill(handle, with: .color(.white))
            context.stroke(handle, with: .color(.accentColor), lineWidth: Metrics.hairline)
        }
    }

    /// Dims the image outside the crop area and outlines it.
    private func drawCrop(_ area: CGRect, in context: GraphicsContext, size: CGSize) {
        let rect = CGRect(x: area.minX * size.width, y: area.minY * size.height,
                          width: area.width * size.width, height: area.height * size.height)
        var outside = Path(CGRect(origin: .zero, size: size))
        outside.addRect(rect)
        context.fill(outside, with: .color(.black.opacity(Opacity.muted)), style: FillStyle(eoFill: true))
        context.stroke(Path(rect), with: .color(.white), style: StrokeStyle(lineWidth: Metrics.hairline, dash: [Spacing.xs]))
    }

    private var footer: some View {
        HStack {
            Button(L(.actionCancel), action: onCancel).keyboardShortcut(typing == nil ? .cancelAction : nil)
            Spacer()
            Button(L(.actionSaveToFile)) {
                commitText()
                if let (png, _, _) = render() { FileExporter.save(png, name: L(.annotatedFileName), type: .png) }
            }
            Button(L(.actionCopy)) {
                commitText()
                if let (png, _, _) = render() { onCopy(png) }
            }
            .keyboardShortcut(typing == nil ? KeyboardShortcut("c") : nil)
            .accessibilityIdentifier("annotate.copy")
            Button(L(.annotateDone)) {
                commitText()
                if let (png, width, height) = render() { onDone(png, width, height) }
            }
            .keyboardShortcut(typing == nil ? .defaultAction : nil)
            .buttonStyle(.borderedProminent)
        }
    }

    /// The image at full size with the marks drawn on it.
    private func flattened() -> NSImage? {
        let pixels = picture.pixelSize
        let content = ZStack {
            Image(nsImage: picture).resizable()
            Canvas { context, size in for mark in marks { mark.draw(in: context, size: size) } }
        }
        .frame(width: pixels.width, height: pixels.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.nsImage
    }

    /// The annotated image as PNG, and its size in pixels.
    private func render() -> (Data, Int, Int)? {
        guard let png = flattened()?.pngRepresentation else { return nil }
        let pixels = picture.pixelSize
        return (png, Int(pixels.width), Int(pixels.height))
    }
}
