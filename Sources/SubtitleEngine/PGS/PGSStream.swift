import Foundation
import os

/// A Blu-ray PGS subtitle stream (`.sup`, or a track extracted from MKV).
///
/// Indexing walks the segment headers only. A cue is a display set that
/// defines objects; it ends at the next display set that either clears the
/// screen or defines new objects. Palette-only updates (fades) and
/// acquisition-point repeats keep the cue alive.
public struct PGSStream: SubtitleStream {
    public let format: BitmapSubtitleFormat = .pgs
    public let cues: [CueInfo]
    public let warnings: [String]
    let data: Data

    private static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "engine.pgs")

    public init(url: URL) throws {
        try self.init(data: Data.mapped(contentsOf: url))
    }

    public init(data: Data) throws {
        self.data = data
        let (cues, warnings) = try data.withUnsafeBytes { bytes in
            try Self.index(bytes)
        }
        self.cues = cues
        self.warnings = warnings
        Self.logger.debug("Indexed \(cues.count) PGS cues (\(warnings.count) warnings)")
    }

    // MARK: - Index

    /// One display set as seen by the index pass.
    private struct DisplaySet {
        let pts: TimeInterval
        let range: Range<Int>
        let state: UInt8
        let objectCount: Int
        let definesObjects: Bool
        /// A composition that only recolours what is already on screen, which
        /// is how fades are encoded. It never starts a new cue.
        let isPaletteUpdate: Bool
    }

    private static func index(_ bytes: UnsafeRawBufferPointer) throws -> ([CueInfo], [String]) {
        var displaySets: [DisplaySet] = []
        var warnings: [String] = []
        var offset = 0

        var setStart: Int?
        var setPTS: TimeInterval = 0
        var setState: UInt8 = 0
        var setObjectCount = 0
        var setDefinesObjects = false
        var setIsPaletteUpdate = false

        if bytes.count >= PGSSegmentHeader.length, PGSSegmentHeader.parse(bytes, at: 0) == nil {
            throw EngineError.invalidData("This is not a PGS (.sup) stream.")
        }

        while offset + PGSSegmentHeader.length <= bytes.count {
            guard let (header, truncated) = PGSSegmentHeader.parse(bytes, at: offset) else {
                warnings.append("Unexpected data at byte \(offset); the rest of the stream was skipped.")
                break
            }
            if truncated {
                warnings.append("The stream ends in the middle of a segment; the last cue may be incomplete.")
                break
            }

            switch header.type {
            case PGSSegmentType.pcs:
                if let composition = PGSComposition(bytes, range: header.payloadRange) {
                    setStart = offset
                    setPTS = header.pts
                    setState = composition.state
                    setObjectCount = composition.objects.count
                    setDefinesObjects = false
                    setIsPaletteUpdate = composition.paletteUpdate
                } else {
                    warnings.append("A composition segment at byte \(offset) could not be read.")
                    setStart = nil
                }
            case PGSSegmentType.ods:
                setDefinesObjects = true
            case PGSSegmentType.end:
                if let start = setStart {
                    displaySets.append(DisplaySet(pts: setPTS,
                                                  range: start..<header.payloadRange.upperBound,
                                                  state: setState,
                                                  objectCount: setObjectCount,
                                                  definesObjects: setDefinesObjects,
                                                  isPaletteUpdate: setIsPaletteUpdate))
                }
                setStart = nil
            default:
                break
            }
            offset = header.payloadRange.upperBound
        }

        if displaySets.isEmpty, bytes.count >= PGSSegmentHeader.length {
            warnings.append("No complete display sets were found.")
        }

        // Turn display sets into cues.
        var cues: [CueInfo] = []
        var open: (start: TimeInterval, range: Range<Int>)?

        func close(at end: TimeInterval?) {
            if let open {
                cues.append(CueInfo(index: cues.count, start: open.start, end: end, byteRange: open.range))
            }
            open = nil
        }

        for set in displaySets {
            if set.objectCount == 0 {
                close(at: set.pts)                       // clear screen
            } else if set.definesObjects || (open == nil && !set.isPaletteUpdate) {
                // Either new image data, or a display set that re-presents an
                // object defined earlier in the epoch while nothing is on
                // screen. Both put a subtitle up. A palette-only update never
                // does, so it must not open an empty cue.
                if set.state == PGSCompositionState.acquisitionPoint, open != nil {
                    continue                              // repeat for seeking; same picture
                }
                close(at: set.pts)                       // new picture replaces the old
                open = (set.pts, set.range)
            }
            // Otherwise: palette update or position change; the cue continues.
        }
        close(at: nil)

        return (cues, warnings)
    }

    // MARK: - Decode

    public func bitmap(at index: Int) throws -> IndexedBitmap? {
        guard cues.indices.contains(index) else {
            throw EngineError.invalidData("Cue \(index + 1) does not exist.")
        }
        let range = cues[index].byteRange
        return try data.withUnsafeBytes { bytes in
            try Self.decodeDisplaySet(bytes, range: range)
        }
    }

    static func decodeDisplaySet(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) throws -> IndexedBitmap? {
        var composition: PGSComposition?
        var palettes: [UInt8: PGSPalette] = [:]
        var objects: [UInt16: PGSObject] = [:]

        var offset = range.lowerBound
        while offset + PGSSegmentHeader.length <= range.upperBound,
              let (header, _) = PGSSegmentHeader.parse(bytes, at: offset) {
            let payload = header.payloadRange
            switch header.type {
            case PGSSegmentType.pcs:
                composition = PGSComposition(bytes, range: payload)
            case PGSSegmentType.pds:
                if let palette = PGSPalette(bytes, range: payload) {
                    if var existing = palettes[palette.id] {
                        existing.merge(palette)
                        palettes[palette.id] = existing
                    } else {
                        palettes[palette.id] = palette
                    }
                }
            case PGSSegmentType.ods:
                if PGSObject.isFirstFragment(bytes, range: payload) {
                    if let object = PGSObject(first: bytes, range: payload) {
                        objects[object.id] = object
                    }
                } else if let id = PGSObject.objectID(bytes, range: payload), var object = objects[id] {
                    object.append(bytes, range: payload)
                    objects[id] = object
                }
            case PGSSegmentType.end:
                offset = range.upperBound
                continue
            default:
                break
            }
            offset = payload.upperBound
        }

        guard let composition, !composition.objects.isEmpty, !objects.isEmpty else { return nil }
        // A display set may legally reference a palette defined earlier in the
        // same epoch, which this display set's bytes do not contain. Render
        // nothing rather than failing: one blank cue is a far better outcome
        // than losing every cue already recognized in the track.
        guard let palette = palettes[composition.paletteID] ?? palettes.values.first else { return nil }

        return composite(composition: composition, objects: objects, palette: palette)
    }

    /// Place every composition object on a canvas the size of their union.
    static func composite(composition: PGSComposition,
                          objects: [UInt16: PGSObject],
                          palette: PGSPalette) -> IndexedBitmap? {
        struct Placed {
            let pixels: [UInt8]
            let width: Int
            let height: Int
            let x: Int
            let y: Int
        }

        var placed: [Placed] = []
        for entry in composition.objects {
            guard let object = objects[entry.objectID], object.width > 0, object.height > 0 else { continue }
            let decoded = object.decode()
            var pixels = decoded.pixels
            var width = object.width
            var height = object.height
            if let crop = entry.crop, crop.width > 0, crop.height > 0,
               crop.x + crop.width <= width, crop.y + crop.height <= height {
                var cropped = [UInt8](repeating: 0, count: crop.width * crop.height)
                for row in 0..<crop.height {
                    let src = (crop.y + row) * width + crop.x
                    let dst = row * crop.width
                    cropped.replaceSubrange(dst..<(dst + crop.width), with: pixels[src..<(src + crop.width)])
                }
                pixels = cropped
                width = crop.width
                height = crop.height
            }
            placed.append(Placed(pixels: pixels, width: width, height: height, x: entry.x, y: entry.y))
        }
        guard !placed.isEmpty else { return nil }

        if placed.count == 1 {
            let only = placed[0]
            guard PGSObject.isPlausibleSize(width: only.width, height: only.height),
                  only.pixels.count == only.width * only.height else { return nil }
            return IndexedBitmap(width: only.width, height: only.height, pixels: only.pixels, palette: palette.rgba)
        }

        let minX = placed.map(\.x).min()!
        let minY = placed.map(\.y).min()!
        let maxX = placed.map { $0.x + $0.width }.max()!
        let maxY = placed.map { $0.y + $0.height }.max()!
        let width = maxX - minX
        let height = maxY - minY
        guard PGSObject.isPlausibleSize(width: width, height: height) else { return nil }

        let background = transparentIndex(in: palette)
        var canvas = [UInt8](repeating: background, count: width * height)
        for item in placed {
            for row in 0..<item.height {
                let dst = (item.y - minY + row) * width + (item.x - minX)
                let src = row * item.width
                canvas.replaceSubrange(dst..<(dst + item.width), with: item.pixels[src..<(src + item.width)])
            }
        }
        return IndexedBitmap(width: width, height: height, pixels: canvas, palette: palette.rgba)
    }

    /// A palette index that renders transparent, for canvas gaps.
    static func transparentIndex(in palette: PGSPalette) -> UInt8 {
        for index in stride(from: 255, through: 0, by: -1) where palette.rgba[index * 4 + 3] == 0 {
            return UInt8(index)
        }
        return 0
    }
}
