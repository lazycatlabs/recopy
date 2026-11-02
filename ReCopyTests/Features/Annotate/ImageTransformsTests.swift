import AppKit
import Testing
@testable import ReCopy

struct ImageTransformsTests {
    /// A 2×1 image: red on the left, blue on the right.
    private func redBlue() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        return try #require(context.makeImage())
    }

    /// The pixel's colour, counting rows from the top.
    private func color(_ image: CGImage, x: Int, y: Int) throws -> NSColor {
        try #require(NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y))
    }

    @Test func rotatingClockwiseMovesTheLeftSideToTheTop() throws {
        let rotated = try #require(try redBlue().rotatedClockwise())
        #expect(rotated.width == 1 && rotated.height == 2)
        #expect(try color(rotated, x: 0, y: 0).redComponent > 0.9)
        #expect(try color(rotated, x: 0, y: 1).blueComponent > 0.9)
    }

    @Test func croppingKeepsTheChosenShare() throws {
        let right = try #require(try redBlue().cropped(toShare: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        #expect(right.width == 1 && right.height == 1)
        #expect(try color(right, x: 0, y: 0).blueComponent > 0.9)
        #expect(try redBlue().cropped(toShare: CGRect(x: 2, y: 2, width: 1, height: 1)) == nil)
    }
}
