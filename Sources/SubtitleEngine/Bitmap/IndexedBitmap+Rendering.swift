import CoreGraphics
import Foundation

extension IndexedBitmap {
    public enum RenderStyle: Sendable, Equatable {
        /// Original palette colors on a transparent background.
        case display
        /// Ink on paper for Vision: black on white, or white on black when inverted.
        case recognition(invert: Bool)
    }

    /// Ceiling on a rendered image, in pixels. Generous next to any real
    /// subtitle, and small enough that a hostile file cannot make the app
    /// allocate its way out of memory.
    public static let maxRenderedPixels = 4096 * 2304

    public struct Bounds: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Bounding box of the non-transparent pixels, or nil when there are none.
    public func contentBounds() -> Bounds? {
        var opaque = [Bool](repeating: false, count: 256)
        for i in 0..<256 { opaque[i] = palette[i * 4 + 3] > 0 }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where opaque[Int(pixels[row + x])] {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return Bounds(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Render to a `CGImage`.
    ///
    /// - Parameters:
    ///   - style: display colors or a recognition image.
    ///   - cropToContent: drop transparent borders (recommended for both uses).
    ///   - margin: pixels of background added around the content when cropping.
    ///     Vision recognizes text better with some breathing room.
    public func cgImage(style: RenderStyle, cropToContent: Bool = true, margin: Int = 0) -> CGImage? {
        let bounds: Bounds
        if cropToContent {
            guard let content = contentBounds() else { return nil }
            bounds = content
        } else {
            guard width > 0, height > 0 else { return nil }
            bounds = Bounds(x: 0, y: 0, width: width, height: height)
        }

        let outWidth = bounds.width + 2 * margin
        let outHeight = bounds.height + 2 * margin
        // Four bytes per pixel here, and again in the CGDataProvider's copy.
        guard outWidth > 0, outHeight > 0, outWidth * outHeight <= Self.maxRenderedPixels else { return nil }

        // Precompute per-index RGBA for the chosen style (premultiplied for display).
        var lookup = [UInt8](repeating: 0, count: 256 * 4)
        switch style {
        case .display:
            for i in 0..<256 {
                let a = Int(palette[i * 4 + 3])
                lookup[i * 4] = UInt8(Int(palette[i * 4]) * a / 255)
                lookup[i * 4 + 1] = UInt8(Int(palette[i * 4 + 1]) * a / 255)
                lookup[i * 4 + 2] = UInt8(Int(palette[i * 4 + 2]) * a / 255)
                lookup[i * 4 + 3] = UInt8(a)
            }
        case .recognition(let invert):
            let ink: UInt8 = invert ? 255 : 0
            let paper: UInt8 = invert ? 0 : 255
            for i in 0..<256 {
                let value = palette[i * 4 + 3] > 0 ? ink : paper
                lookup[i * 4] = value
                lookup[i * 4 + 1] = value
                lookup[i * 4 + 2] = value
                lookup[i * 4 + 3] = 255
            }
        }

        let background: [UInt8] = {
            if case .recognition(let invert) = style {
                let paper: UInt8 = invert ? 0 : 255
                return [paper, paper, paper, 255]
            }
            return [0, 0, 0, 0]
        }()

        var rgba = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        if background[3] != 0 {
            for i in stride(from: 0, to: rgba.count, by: 4) {
                rgba[i] = background[0]
                rgba[i + 1] = background[1]
                rgba[i + 2] = background[2]
                rgba[i + 3] = background[3]
            }
        }
        for row in 0..<bounds.height {
            let srcRow = (bounds.y + row) * width + bounds.x
            let dstRow = ((row + margin) * outWidth + margin) * 4
            for column in 0..<bounds.width {
                let index = Int(pixels[srcRow + column]) * 4
                let dst = dstRow + column * 4
                rgba[dst] = lookup[index]
                rgba[dst + 1] = lookup[index + 1]
                rgba[dst + 2] = lookup[index + 2]
                rgba[dst + 3] = lookup[index + 3]
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let alphaInfo: CGImageAlphaInfo = style == .display ? .premultipliedLast : .noneSkipLast
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))
        return CGImage(width: outWidth,
                       height: outHeight,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: outWidth * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
