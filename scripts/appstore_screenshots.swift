// Turns E2E window screenshots into App Store screenshots: the window on ReCopy's orange, with a caption above.
//   swift scripts/appstore_screenshots.swift <e2e screenshots folder> <fastlane/screenshots>
// Writes <locale>/NN-name.png at 1440×900, one of the Mac App Store's sizes. Run by scripts/appstore_screenshots.sh.
import AppKit

let shots: [(file: String, en: String, id: String)] = [
    ("01-panel-new-look", "Everything you copied, one shortcut away", "Semua yang Anda salin, satu pintasan saja"),
    ("28-note-found-by-search", "Find anything, even by your own notes", "Temukan apa saja, bahkan lewat catatan Anda"),
    ("35-annotate-shapes-size-blur", "Mark up and blur screenshots", "Tandai dan samarkan screenshot"),
    ("45-paste-special-json-code-block", "Paste JSON and code just right", "Tempel JSON dan kode dengan rapi"),
    ("16-groups-filtered-by-work", "Keep work and life in groups", "Pisahkan kerja dan pribadi dengan grup"),
]

let size = NSSize(width: 1440, height: 900)
let captionTop: CGFloat = 70, captionHeight: CGFloat = 70, margin: CGFloat = 50
let top = NSColor(srgbRed: 1, green: 0.62, blue: 0.33, alpha: 1)    // #FF9E54
let bottom = NSColor(srgbRed: 0.93, green: 0.42, blue: 0.16, alpha: 1) // #ED6B29

let args = CommandLine.arguments
let input = URL(filePath: args[1]), output = URL(filePath: args[2])

func render(_ window: NSImage, caption: String) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let text = NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 52, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: style,
    ])
    text.draw(in: NSRect(x: margin, y: size.height - captionTop - captionHeight, width: size.width - 2 * margin, height: captionHeight))

    // Fit below the caption; never scale up, which would blur the 1x capture.
    let room = NSSize(width: size.width - 2 * margin, height: size.height - captionTop - captionHeight - 2 * margin)
    let scale = min(1, room.width / window.size.width, room.height / window.size.height)
    let drawn = NSSize(width: window.size.width * scale, height: window.size.height * scale)
    let frame = NSRect(x: (size.width - drawn.width) / 2, y: (room.height - drawn.height) / 2 + margin,
                       width: drawn.width, height: drawn.height)
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    let clip = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
    NSColor.black.setFill()
    clip.fill()
    NSShadow().set()
    clip.addClip()
    window.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for locale in ["en-US", "id"] {
    let folder = output.appending(path: locale)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, shot) in shots.enumerated() {
        guard let window = NSImage(contentsOf: input.appending(path: "\(shot.file).png")) else {
            fatalError("Missing \(shot.file).png: run the E2E tests first")
        }
        let name = String(format: "%02d-%@.png", index + 1, String(shot.file.drop { $0.isNumber || $0 == "-" }))
        try render(window, caption: locale == "id" ? shot.id : shot.en).write(to: folder.appending(path: name))
        print("✓ \(locale)/\(name)")
    }
}
