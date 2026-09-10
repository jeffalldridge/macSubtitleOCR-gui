import Foundation

/// The header of a Matroska `SimpleBlock` or `Block`, with lacing resolved
/// into frame ranges.
struct MKVBlock: Equatable {
    let trackNumber: UInt64
    let relativeTimestamp: Int16
    let flags: UInt8
    /// Byte ranges (absolute, into the same buffer) of each frame.
    let frames: [Range<Int>]

    enum Lacing: UInt8 {
        case none = 0x00
        case xiph = 0x02
        case fixed = 0x04
        case ebml = 0x06
    }

    init?(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        let reader = EBMLReader(bytes: bytes)
        guard let track = reader.readVINT(at: range.lowerBound, stripMarker: true) else { return nil }
        var offset = range.lowerBound + track.length
        guard offset + 3 <= range.upperBound,
              let timestamp = bytes.readIntBE(at: offset, length: 2) else { return nil }
        let flags = bytes[offset + 2]
        offset += 3

        trackNumber = track.value
        relativeTimestamp = Int16(timestamp)
        self.flags = flags

        let lacing = Lacing(rawValue: flags & 0x06) ?? .none
        guard lacing != .none else {
            frames = [offset..<range.upperBound]
            return
        }

        guard offset < range.upperBound else { return nil }
        let frameCount = Int(bytes[offset]) + 1
        offset += 1
        var sizes: [Int] = []

        switch lacing {
        case .xiph:
            for _ in 0..<(frameCount - 1) {
                var size = 0
                while true {
                    guard offset < range.upperBound else { return nil }
                    let byte = Int(bytes[offset])
                    offset += 1
                    size += byte
                    if byte != 255 { break }
                }
                sizes.append(size)
            }
        case .ebml:
            guard frameCount > 1 else { break }
            guard let first = reader.readVINT(at: offset, stripMarker: true) else { return nil }
            offset += first.length
            sizes.append(Int(first.value))
            for _ in 1..<(frameCount - 1) {
                guard let delta = reader.readVINT(at: offset, stripMarker: true) else { return nil }
                offset += delta.length
                // Signed VINT: value minus (2^(7n-1) - 1).
                let bias = (Int64(1) << Int64(7 * delta.length - 1)) - 1
                let signed = Int64(delta.value) - bias
                sizes.append(sizes[sizes.count - 1] + Int(signed))
            }
        case .fixed:
            let total = range.upperBound - offset
            guard frameCount > 0, total % frameCount == 0 else { return nil }
            sizes = [Int](repeating: total / frameCount, count: frameCount - 1)
        case .none:
            break
        }

        var frames: [Range<Int>] = []
        var cursor = offset
        for size in sizes {
            guard size >= 0, cursor + size <= range.upperBound else { return nil }
            frames.append(cursor..<(cursor + size))
            cursor += size
        }
        guard cursor <= range.upperBound else { return nil }
        frames.append(cursor..<range.upperBound)
        self.frames = frames
    }
}

/// Re-wraps Matroska frames as the standalone formats the decoders read.
enum MKVFrameWrapper {
    /// A PGS frame in Matroska holds bare segments (type, length, payload).
    /// A `.sup` stream prefixes each with `PG`, PTS, DTS.
    static func wrapPGS(_ frame: UnsafeRawBufferPointer.SubSequence, pts90k: UInt32, into out: inout Data) {
        var header = Data(capacity: 13)
        header.append(contentsOf: [0x50, 0x47])
        header.append(contentsOf: withUnsafeBytes(of: pts90k.bigEndian) { Array($0) })
        header.append(contentsOf: [0, 0, 0, 0])

        var offset = frame.startIndex
        while offset + 3 <= frame.endIndex {
            let length = Int(frame[offset + 1]) << 8 | Int(frame[offset + 2])
            let end = min(offset + 3 + length, frame.endIndex)
            out.append(header)
            out.append(contentsOf: frame[offset..<end])
            offset = end
        }
    }

    /// A VobSub frame in Matroska is a bare subpicture unit. A `.sub` file
    /// carries it in MPEG program-stream packets of at most 2048 bytes.
    static func wrapVobSub(_ frame: UnsafeRawBufferPointer.SubSequence, pts90k: UInt64, into out: inout Data) {
        let packHeader: [UInt8] = [
            0x00, 0x00, 0x01, 0xBA,             // pack start code
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // system clock reference
            0x00, 0x00, 0x00,                   // mux rate
            0x00,                               // stuffing length
            0x00, 0x00, 0x01, 0xBD,             // PES start code
        ]
        var remaining = frame[...]
        var first = true
        while !remaining.isEmpty || first {
            let headerData: [UInt8]
            if first {
                headerData = [0x00, 0x80, 0x05] + ptsBytes(pts90k) + [0x20]
            } else {
                headerData = [0x00, 0x00, 0x00, 0x20]
            }
            let chunkLength = min(remaining.count, 2028 - headerData.count)
            let chunk = remaining.prefix(chunkLength)
            let pesLength = UInt16(headerData.count + chunkLength)
            out.append(contentsOf: packHeader)
            out.append(contentsOf: withUnsafeBytes(of: pesLength.bigEndian) { Array($0) })
            out.append(contentsOf: headerData)
            out.append(contentsOf: chunk)
            remaining = remaining.dropFirst(chunkLength)
            first = false
        }
    }

    /// PTS in the MPEG-2 "PTS only" 5-byte form.
    static func ptsBytes(_ pts: UInt64) -> [UInt8] {
        [
            0x21 | UInt8((pts >> 29) & 0x0E),
            UInt8((pts >> 22) & 0xFF),
            UInt8(((pts >> 14) & 0xFE) | 0x01),
            UInt8((pts >> 7) & 0xFF),
            UInt8(((pts << 1) & 0xFE) | 0x01),
        ]
    }

    /// `HH:MM:SS:mmm` as used by `.idx` timestamp lines.
    static func idxTimestamp(pts90k: UInt64) -> String {
        let totalMilliseconds = Int(pts90k / 90)
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1000) % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d:%03d", hours, minutes, seconds, milliseconds)
    }
}
