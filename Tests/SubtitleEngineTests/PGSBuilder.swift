import Foundation

/// Builds synthetic PGS (`.sup`) streams for tests.
enum PGSBuilder {
    struct Object {
        let id: UInt16
        let x: UInt16
        let y: UInt16
    }

    static func segment(type: UInt8, pts: TimeInterval, payload: [UInt8]) -> [UInt8] {
        let ticks = UInt32(pts * 90000)
        var bytes: [UInt8] = [0x50, 0x47]
        bytes += withUnsafeBytes(of: ticks.bigEndian) { Array($0) }
        bytes += [0, 0, 0, 0] // DTS
        bytes.append(type)
        bytes += withUnsafeBytes(of: UInt16(payload.count).bigEndian) { Array($0) }
        return bytes + payload
    }

    /// Presentation Composition Segment.
    static func pcs(pts: TimeInterval,
                    state: UInt8,
                    paletteID: UInt8 = 0,
                    paletteUpdate: Bool = false,
                    objects: [Object],
                    width: UInt16 = 1920,
                    height: UInt16 = 1080) -> [UInt8] {
        var payload: [UInt8] = []
        payload += be16(width) + be16(height)
        payload.append(0x10) // frame rate
        payload += be16(1)   // composition number
        payload.append(state)
        payload.append(paletteUpdate ? 0x80 : 0x00)
        payload.append(paletteID)
        payload.append(UInt8(objects.count))
        for object in objects {
            payload += be16(object.id)
            payload.append(0)    // window id
            payload.append(0)    // crop flag
            payload += be16(object.x) + be16(object.y)
        }
        return segment(type: 0x16, pts: pts, payload: payload)
    }

    static func wds(pts: TimeInterval) -> [UInt8] {
        segment(type: 0x17, pts: pts, payload: [1, 0, 0, 0, 0, 0, 0x07, 0x80, 0x04, 0x38])
    }

    /// Palette Definition Segment. Entries are (index, Y, Cr, Cb, alpha).
    static func pds(pts: TimeInterval, id: UInt8, entries: [(UInt8, UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        var payload: [UInt8] = [id, 0]
        for (index, y, cr, cb, a) in entries {
            payload += [index, y, cr, cb, a]
        }
        return segment(type: 0x14, pts: pts, payload: payload)
    }

    /// Object Definition Segment holding a solid rectangle of `color`.
    static func ods(pts: TimeInterval, id: UInt16, width: Int, height: Int, color: UInt8) -> [UInt8] {
        let rle = rleRectangle(width: width, height: height, color: color)
        return ods(pts: pts, id: id, width: width, height: height, rle: rle)
    }

    static func ods(pts: TimeInterval, id: UInt16, width: Int, height: Int, rle: [UInt8],
                    sequence: UInt8 = 0xC0) -> [UInt8] {
        var payload: [UInt8] = []
        payload += be16(id)
        payload.append(0)         // version
        payload.append(sequence)  // first + last
        let dataLength = UInt32(rle.count + 4)
        payload += [UInt8((dataLength >> 16) & 0xFF), UInt8((dataLength >> 8) & 0xFF), UInt8(dataLength & 0xFF)]
        payload += be16(UInt16(width)) + be16(UInt16(height))
        payload += rle
        return segment(type: 0x15, pts: pts, payload: payload)
    }

    static func end(pts: TimeInterval) -> [UInt8] {
        segment(type: 0x80, pts: pts, payload: [])
    }

    /// RLE for `height` lines each consisting of one run of `color`.
    static func rleRectangle(width: Int, height: Int, color: UInt8) -> [UInt8] {
        var out: [UInt8] = []
        for _ in 0..<height {
            out += rleRun(color: color, length: width)
            out += [0x00, 0x00] // end of line
        }
        return out
    }

    static func rleRun(color: UInt8, length: Int) -> [UInt8] {
        if color == 0 {
            return length <= 63 ? [0x00, UInt8(length)] : [0x00, 0x40 | UInt8(length >> 8), UInt8(length & 0xFF)]
        }
        return length <= 63 ? [0x00, 0x80 | UInt8(length), color]
                            : [0x00, 0xC0 | UInt8(length >> 8), UInt8(length & 0xFF), color]
    }

    /// Opaque white and opaque yellow entries, plus transparent index 0.
    static let standardPalette: [(UInt8, UInt8, UInt8, UInt8, UInt8)] = [
        (0, 16, 128, 128, 0),
        (1, 235, 128, 128, 255),
        (2, 210, 146, 16, 255),
    ]

    /// A complete display set: PCS, WDS, PDS, ODS(s), END.
    static func displaySet(pts: TimeInterval,
                           state: UInt8 = 0x80,
                           paletteID: UInt8 = 0,
                           palette: [(UInt8, UInt8, UInt8, UInt8, UInt8)]? = standardPalette,
                           objects: [(Object, width: Int, height: Int, color: UInt8)]) -> [UInt8] {
        var bytes = pcs(pts: pts, state: state, paletteID: paletteID, objects: objects.map(\.0))
        bytes += wds(pts: pts)
        if let palette { bytes += pds(pts: pts, id: paletteID, entries: palette) }
        for (object, width, height, color) in objects {
            bytes += ods(pts: pts, id: object.id, width: width, height: height, color: color)
        }
        bytes += end(pts: pts)
        return bytes
    }

    /// A display set that clears the screen.
    static func clear(pts: TimeInterval) -> [UInt8] {
        pcs(pts: pts, state: 0x00, objects: []) + wds(pts: pts) + end(pts: pts)
    }

    private static func be16(_ value: UInt16) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }
}
