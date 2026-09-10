import Foundation

/// PGS segment types and parsers. Layout references:
/// https://blog.thescorpius.com/index.php/2017/07/15/presentation-graphic-stream-sup-files-bluray-subtitle-format/
enum PGSSegmentType {
    static let pds: UInt8 = 0x14   // Palette Definition
    static let ods: UInt8 = 0x15   // Object Definition
    static let pcs: UInt8 = 0x16   // Presentation Composition
    static let wds: UInt8 = 0x17   // Window Definition
    static let end: UInt8 = 0x80   // End of display set
}

/// The 13-byte header in front of every segment of a `.sup` stream.
struct PGSSegmentHeader {
    static let length = 13
    static let magic: (UInt8, UInt8) = (0x50, 0x47) // "PG"

    let pts: TimeInterval
    let type: UInt8
    let payloadRange: Range<Int>

    /// Parse the header at `offset`. Returns nil at end of data or on a bad
    /// magic. The payload range is clamped to the buffer, and `truncated`
    /// tells the caller when that happened.
    static func parse(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> (header: PGSSegmentHeader, truncated: Bool)? {
        guard offset + length <= bytes.count,
              bytes[offset] == magic.0, bytes[offset + 1] == magic.1,
              let ticks = bytes.readUInt32BE(at: offset + 2),
              let payloadLength = bytes.readUInt16BE(at: offset + 11) else { return nil }
        let start = offset + length
        let declaredEnd = start + Int(payloadLength)
        let end = min(declaredEnd, bytes.count)
        let header = PGSSegmentHeader(pts: TimeInterval(ticks) / 90000, type: bytes[offset + 10], payloadRange: start..<end)
        return (header, declaredEnd > bytes.count)
    }
}

enum PGSCompositionState {
    static let normal: UInt8 = 0x00
    static let acquisitionPoint: UInt8 = 0x40
    static let epochStart: UInt8 = 0x80
}

/// Presentation Composition Segment: which objects are on screen and where.
struct PGSComposition {
    struct Object {
        let objectID: UInt16
        let windowID: UInt8
        let x: Int
        let y: Int
        /// Optional crop rectangle inside the object.
        let crop: (x: Int, y: Int, width: Int, height: Int)?
    }

    let width: Int
    let height: Int
    let state: UInt8
    let paletteUpdate: Bool
    let paletteID: UInt8
    let objects: [Object]

    init?(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        guard range.count >= 11,
              let width = bytes.readUInt16BE(at: range.lowerBound),
              let height = bytes.readUInt16BE(at: range.lowerBound + 2) else { return nil }
        self.width = Int(width)
        self.height = Int(height)
        state = bytes[range.lowerBound + 7]
        paletteUpdate = bytes[range.lowerBound + 8] & 0x80 != 0
        paletteID = bytes[range.lowerBound + 9]
        let objectCount = Int(bytes[range.lowerBound + 10])

        var objects: [Object] = []
        var offset = range.lowerBound + 11
        for _ in 0..<objectCount {
            guard offset + 8 <= range.upperBound,
                  let objectID = bytes.readUInt16BE(at: offset),
                  let x = bytes.readUInt16BE(at: offset + 4),
                  let y = bytes.readUInt16BE(at: offset + 6) else { break }
            let windowID = bytes[offset + 2]
            let cropFlag = bytes[offset + 3]
            offset += 8
            var crop: (Int, Int, Int, Int)?
            if cropFlag & 0x80 != 0 {
                guard offset + 8 <= range.upperBound,
                      let cx = bytes.readUInt16BE(at: offset),
                      let cy = bytes.readUInt16BE(at: offset + 2),
                      let cw = bytes.readUInt16BE(at: offset + 4),
                      let ch = bytes.readUInt16BE(at: offset + 6) else { break }
                crop = (Int(cx), Int(cy), Int(cw), Int(ch))
                offset += 8
            }
            objects.append(Object(objectID: objectID, windowID: windowID, x: Int(x), y: Int(y), crop: crop))
        }
        self.objects = objects
    }
}

/// Palette Definition Segment: up to 256 YCrCbA entries, converted to RGBA.
struct PGSPalette {
    let id: UInt8
    /// RGBA × 256.
    var rgba: [UInt8]
    /// Indices that were defined by the segment.
    var defined: Set<UInt8>

    init?(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        guard range.count >= 2 else { return nil }
        id = bytes[range.lowerBound]
        rgba = [UInt8](repeating: 0, count: IndexedBitmap.paletteSize)
        defined = []
        var offset = range.lowerBound + 2
        while offset + 5 <= range.upperBound {
            let index = bytes[offset]
            let (r, g, b) = Self.yCrCbToRGB(y: bytes[offset + 1], cr: bytes[offset + 2], cb: bytes[offset + 3])
            let base = Int(index) * 4
            rgba[base] = r
            rgba[base + 1] = g
            rgba[base + 2] = b
            rgba[base + 3] = bytes[offset + 4]
            defined.insert(index)
            offset += 5
        }
    }

    /// Merge a later palette segment with the same ID over this one
    /// (palette updates redefine only some entries).
    mutating func merge(_ other: PGSPalette) {
        for index in other.defined {
            let base = Int(index) * 4
            for k in 0..<4 { rgba[base + k] = other.rgba[base + k] }
            defined.insert(index)
        }
    }

    /// BT.709 limited-range conversion, as upstream uses.
    static func yCrCbToRGB(y: UInt8, cr: UInt8, cb: UInt8) -> (UInt8, UInt8, UInt8) {
        let yy = Double(y) - 16
        let cr = Double(cr) - 128
        let cb = Double(cb) - 128
        let r = 1.164 * yy + 1.793 * cr
        let g = 1.164 * yy - 0.213 * cb - 0.533 * cr
        let b = 1.164 * yy + 2.112 * cb
        func clamp(_ v: Double) -> UInt8 { UInt8(min(max(v.rounded(), 0), 255)) }
        return (clamp(r), clamp(g), clamp(b))
    }
}

/// Object Definition Segment(s): one object's RLE bitmap, possibly split
/// across several segments (first / middle / last sequence flags).
struct PGSObject {
    static let firstFragment: UInt8 = 0x80
    static let lastFragment: UInt8 = 0x40

    /// A PGS object cannot be larger than the video frame it is drawn on, and
    /// Blu-ray tops out at 1920x1080. This allows well past 4K in both
    /// directions, and still keeps a crafted 92-byte file from asking for a
    /// four-gigabyte allocation.
    static let maxDimension = 8192
    static let maxPixels = 8192 * 4320

    let id: UInt16
    private(set) var width = 0
    private(set) var height = 0
    private(set) var rle: [UInt8] = []
    private(set) var isComplete = false

    /// Start a new object from a first (or whole) fragment.
    init?(first bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        guard range.count >= 11, let id = bytes.readUInt16BE(at: range.lowerBound) else { return nil }
        self.id = id
        let flags = bytes[range.lowerBound + 3]
        guard flags & Self.firstFragment != 0,
              let width = bytes.readUInt16BE(at: range.lowerBound + 7),
              let height = bytes.readUInt16BE(at: range.lowerBound + 9),
              Self.isPlausibleSize(width: Int(width), height: Int(height)) else { return nil }
        self.width = Int(width)
        self.height = Int(height)
        rle = Array(bytes[(range.lowerBound + 11)..<range.upperBound])
        isComplete = flags & Self.lastFragment != 0
    }

    /// Append a continuation fragment.
    mutating func append(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        guard range.count >= 4 else { return }
        let flags = bytes[range.lowerBound + 3]
        rle.append(contentsOf: bytes[(range.lowerBound + 4)..<range.upperBound])
        if flags & Self.lastFragment != 0 { isComplete = true }
    }

    static func objectID(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) -> UInt16? {
        range.count >= 2 ? bytes.readUInt16BE(at: range.lowerBound) : nil
    }

    static func isFirstFragment(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) -> Bool {
        range.count >= 4 && bytes[range.lowerBound + 3] & firstFragment != 0
    }

    static func isPlausibleSize(width: Int, height: Int) -> Bool {
        width > 0 && height > 0
            && width <= maxDimension && height <= maxDimension
            && width * height <= maxPixels
    }

    func decode() -> PGSRLE.Result {
        PGSRLE.decode(rle, width: width, height: height)
    }
}
