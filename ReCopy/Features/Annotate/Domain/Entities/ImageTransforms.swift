import CoreGraphics

/// Crop and rotate for the annotation editor, done on the image's pixels.
nonisolated extension CGImage {
    /// The part of the image inside `area`, given as shares of its size (0…1, top-left origin). Nil when the area
    /// holds no whole pixel.
    func cropped(toShare area: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let pixels = CGRect(x: area.minX * bounds.width, y: area.minY * bounds.height,
                            width: area.width * bounds.width, height: area.height * bounds.height)
            .integral.intersection(bounds)
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }
        return cropping(to: pixels)
    }

    /// The image turned a quarter clockwise.
    func rotatedClockwise() -> CGImage? {
        guard let context = CGContext(data: nil, width: height, height: width, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Core Graphics' origin is bottom-left: turn the context clockwise, then shift it back into view.
        context.translateBy(x: 0, y: CGFloat(width))
        context.rotate(by: -.pi / 2)
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
