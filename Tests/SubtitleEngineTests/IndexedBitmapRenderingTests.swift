import CoreGraphics
import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct IndexedBitmapRenderingTests {
    /// 6×4 bitmap: index 1 (opaque white) at (2,1) and (3,2); index 2 (half-transparent red) at (4,2).
    private func sample() -> IndexedBitmap {
        var pixels = [UInt8](repeating: 0, count: 24)
        pixels[1 * 6 + 2] = 1
        pixels[2 * 6 + 3] = 1
        pixels[2 * 6 + 4] = 2
        var palette = [UInt8](repeating: 0, count: IndexedBitmap.paletteSize)
        palette[4...7] = [255, 255, 255, 255]
        palette[8...11] = [255, 0, 0, 128]
        return IndexedBitmap(width: 6, height: 4, pixels: pixels, palette: palette)
    }

    @Test func contentBoundsIgnoreTransparentPixels() {
        let bounds = sample().contentBounds()
        #expect(bounds == IndexedBitmap.Bounds(x: 2, y: 1, width: 3, height: 2))
    }

    @Test func fullyTransparentHasNoBoundsAndNoImage() {
        let empty = IndexedBitmap(width: 3, height: 3, pixels: [UInt8](repeating: 0, count: 9), palette: [])
        #expect(empty.contentBounds() == nil)
        #expect(empty.cgImage(style: .display) == nil)
        #expect(!empty.hasVisiblePixels)
    }

    @Test func recognitionImageIsBlackOnWhiteAndCropped() throws {
        let image = try #require(sample().cgImage(style: .recognition(invert: false), margin: 0))
        // Content origin is bitmap (2,1), which is the opaque pixel.
        #expect(image.width == 3 && image.height == 2)
        #expect(Pixels(image).at(0, 0) == (0, 0, 0, 255), "opaque → black")
        #expect(Pixels(image).at(1, 0) == (255, 255, 255, 255), "transparent → white")
        #expect(Pixels(image).at(1, 1) == (0, 0, 0, 255), "opaque → black")
        #expect(Pixels(image).at(2, 1) == (0, 0, 0, 255), "semi-transparent counts as ink")
    }

    @Test func invertedRecognitionImageIsWhiteOnBlack() throws {
        let image = try #require(sample().cgImage(style: .recognition(invert: true), margin: 0))
        #expect(Pixels(image).at(0, 0) == (255, 255, 255, 255))
        #expect(Pixels(image).at(1, 0) == (0, 0, 0, 255))
    }

    @Test func marginPadsTheRecognitionImage() throws {
        let image = try #require(sample().cgImage(style: .recognition(invert: false), margin: 4))
        #expect(image.width == 3 + 8 && image.height == 2 + 8)
        #expect(Pixels(image).at(0, 0) == (255, 255, 255, 255), "margin is paper")
        #expect(Pixels(image).at(4, 4) == (0, 0, 0, 255), "content (0,0) is ink")
        #expect(Pixels(image).at(5, 4) == (255, 255, 255, 255), "content (1,0) is transparent")
        #expect(Pixels(image).at(5, 5) == (0, 0, 0, 255))
    }

    @Test func displayImageKeepsColorsAndAlpha() throws {
        let image = try #require(sample().cgImage(style: .display, margin: 0))
        #expect(image.width == 3 && image.height == 2)
        let white = Pixels(image).at(0, 0)
        #expect(white == (255, 255, 255, 255))
        let clear = Pixels(image).at(1, 0)
        #expect(clear.a == 0)
        let red = Pixels(image).at(2, 1)
        #expect(red.a == 128)
        #expect(red.r > 120 && red.g == 0 && red.b == 0)
    }

    @Test func uncroppedDisplayKeepsFullCanvas() throws {
        let image = try #require(sample().cgImage(style: .display, cropToContent: false))
        #expect(image.width == 6 && image.height == 4)
    }
}

/// Reads back pixels from a CGImage through a known-format context.
struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) {
        let w = image.width
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        bytes = buffer
    }

    /// Un-premultiplied RGBA at (x, y) with y measured from the top. A bitmap
    /// context's first row in memory is the top of the drawn image.
    func at(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = (y * width + x) * 4
        let a = bytes[i + 3]
        guard a > 0 else { return (0, 0, 0, 0) }
        func un(_ v: UInt8) -> UInt8 { UInt8(min(255, Int(v) * 255 / Int(a))) }
        return (un(bytes[i]), un(bytes[i + 1]), un(bytes[i + 2]), a)
    }
}

func == (lhs: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), rhs: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
    lhs.r == rhs.0 && lhs.g == rhs.1 && lhs.b == rhs.2 && lhs.a == rhs.3
}
