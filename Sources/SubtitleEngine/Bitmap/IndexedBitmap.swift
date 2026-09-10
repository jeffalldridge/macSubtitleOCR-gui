import Foundation

/// A palette-indexed bitmap: one byte per pixel plus an RGBA palette.
///
/// Both PGS and VobSub decode to this. Rendering to `CGImage` lives in
/// `IndexedBitmap+Rendering.swift`.
public struct IndexedBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// `width * height` palette indices, row-major, top row first.
    public let pixels: [UInt8]
    /// RGBA, 4 bytes per entry, 256 entries (1024 bytes). Undefined entries
    /// are transparent black.
    public let palette: [UInt8]

    public static let paletteSize = 256 * 4

    public init(width: Int, height: Int, pixels: [UInt8], palette: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
        if palette.count == Self.paletteSize {
            self.palette = palette
        } else {
            var padded = palette
            padded.append(contentsOf: [UInt8](repeating: 0, count: max(0, Self.paletteSize - palette.count)))
            self.palette = Array(padded.prefix(Self.paletteSize))
        }
    }

    @inlinable
    public func pixel(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    @inlinable
    public func rgba(ofIndex index: UInt8) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let base = Int(index) * 4
        return (palette[base], palette[base + 1], palette[base + 2], palette[base + 3])
    }

    /// True when at least one pixel is not fully transparent.
    public var hasVisiblePixels: Bool {
        var opaque = [Bool](repeating: false, count: 256)
        for i in 0..<256 { opaque[i] = palette[i * 4 + 3] > 0 }
        return pixels.contains { opaque[Int($0)] }
    }
}
