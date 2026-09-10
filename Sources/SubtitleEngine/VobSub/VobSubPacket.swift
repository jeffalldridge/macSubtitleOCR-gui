import Foundation

/// One subpicture unit (SPU) reassembled from the MPEG program-stream
/// packets of a `.sub` file, with its control sequences parsed.
struct VobSubPacket: Sendable {
    static let packStartCode: UInt32 = 0x0000_01BA
    static let pesStartCode: UInt32 = 0x0000_01BD

    /// The full SPU: 2-byte size, 2-byte control offset, RLE data, control sequences.
    let spu: [UInt8]
    /// Presentation time from the first PES header, if present.
    let pts: TimeInterval?

    // Parsed control data
    private(set) var startDelay: TimeInterval = 0
    /// Nil when the stream says "display until the next subpicture".
    private(set) var stopDelay: TimeInterval?
    private(set) var isForced = false
    /// Master-palette indices for colors 0…3.
    private(set) var colorIndices: [UInt8] = [0, 0, 0, 0]
    /// Alpha nibbles (0…15) for colors 0…3.
    private(set) var alphaNibbles: [UInt8] = [0, 0, 0, 0]
    private(set) var x: Int = 0
    private(set) var y: Int = 0
    private(set) var width: Int = 0
    private(set) var height: Int = 0
    private(set) var evenOffset: Int = 0
    private(set) var oddOffset: Int = 0
    private(set) var warnings: [String] = []

    /// Reassemble the SPU that starts at `offset` and ends before `nextOffset`.
    init(_ bytes: UnsafeRawBufferPointer, offset: Int, nextOffset: Int) throws {
        var spu: [UInt8] = []
        spu.reserveCapacity(nextOffset - offset)
        var declaredSize: Int?
        var warnings: [String] = []
        let pts = Self.walkPackets(bytes, offset: offset, nextOffset: nextOffset,
                                   warnings: &warnings) { payload, _ in
            spu.append(contentsOf: payload)
            if declaredSize == nil, spu.count >= 2 {
                declaredSize = Int(spu[0]) << 8 | Int(spu[1])
            }
            // The subpicture says how long it is; past that the next pack
            // belongs to another cue and is not ours to read.
            guard let declaredSize else { return true }
            return spu.count < declaredSize
        }

        guard spu.count >= 4 else {
            throw EngineError.invalidData("A VobSub subpicture at byte \(offset) is empty.")
        }
        if let declaredSize, declaredSize > 0, spu.count < declaredSize {
            warnings.append("A subpicture at byte \(offset) is truncated (\(spu.count) of \(declaredSize) bytes).")
        }

        self.spu = spu
        self.pts = pts
        self.warnings = warnings
        let control = Self.parseControl(spu, from: Int(spu[2]) << 8 | Int(spu[3]), base: 0)
        apply(control)
    }

    /// Everything the cue list needs, without reassembling the subpicture.
    ///
    /// Timings live in the control block at the end of the subpicture; the RLE
    /// bitmap in front of it is never read here. Copying only the control
    /// block turns the indexing pass from a copy of the whole track into a few
    /// dozen bytes per cue.
    static func timing(_ bytes: UnsafeRawBufferPointer,
                       offset: Int,
                       nextOffset: Int) throws -> Timing {
        var header: [UInt8] = []
        var tail: [UInt8] = []
        var length = 0
        var controlOffset = -1
        var declaredSize: Int?
        var warnings: [String] = []

        let pts = walkPackets(bytes, offset: offset, nextOffset: nextOffset,
                              warnings: &warnings) { payload, _ in
            if header.count < 4 {
                header.append(contentsOf: payload.prefix(4 - header.count))
                if header.count >= 2, declaredSize == nil {
                    declaredSize = Int(header[0]) << 8 | Int(header[1])
                }
                if header.count == 4 {
                    controlOffset = Int(header[2]) << 8 | Int(header[3])
                }
            }
            if controlOffset >= 0, length + payload.count > controlOffset {
                let start = max(controlOffset - length, 0)
                tail.append(contentsOf: payload.dropFirst(start))
            }
            length += payload.count
            guard let declaredSize else { return true }
            return length < declaredSize
        }

        guard header.count >= 4 else {
            throw EngineError.invalidData("A VobSub subpicture at byte \(offset) is empty.")
        }
        if let declaredSize, declaredSize > 0, length < declaredSize {
            warnings.append("A subpicture at byte \(offset) is truncated (\(length) of \(declaredSize) bytes).")
        }

        let control = parseControl(tail, from: controlOffset, base: controlOffset)
        return Timing(pts: pts,
                      startDelay: control.startDelay,
                      stopDelay: control.stopDelay,
                      isForced: control.isForced,
                      warnings: warnings)
    }

    /// What indexing needs from a subpicture.
    struct Timing: Sendable {
        let pts: TimeInterval?
        let startDelay: TimeInterval
        let stopDelay: TimeInterval?
        let isForced: Bool
        let warnings: [String]
    }

    /// Walk the program-stream packets holding one subpicture, handing each
    /// PES payload to `consume`. Returns the presentation time from the first
    /// header that carries one.
    private static func walkPackets(_ bytes: UnsafeRawBufferPointer,
                                    offset: Int,
                                    nextOffset: Int,
                                    warnings: inout [String],
                                    consume: (UnsafeRawBufferPointer.SubSequence, Int) -> Bool) -> TimeInterval? {
        var pts: TimeInterval?
        var position = offset

        while position < nextOffset, position + 4 <= bytes.count {
            guard bytes.readUInt32BE(at: position) == packStartCode else {
                warnings.append("No pack header at byte \(position).")
                break
            }
            // Pack header: start code (4) + SCR (6) + mux rate (3) + stuffing length (1) + stuffing.
            var p = position + 13
            guard p < bytes.count else { break }
            p += 1 + Int(bytes[p] & 0x07)

            guard bytes.readUInt32BE(at: p) == pesStartCode,
                  let pesLength = bytes.readUInt16BE(at: p + 4) else {
                warnings.append("No PES header at byte \(p).")
                break
            }
            p += 6
            let pesEnd = min(p + Int(pesLength), bytes.count)
            guard pesLength > 0, p + 3 <= pesEnd else { break }

            let flags2 = bytes[p + 1]
            let headerLength = Int(bytes[p + 2])
            p += 3
            if pts == nil, flags2 & 0x80 != 0, headerLength >= 5, p + 5 <= pesEnd {
                // A 33-bit PTS spread across five bytes, one marker bit each.
                let b0 = UInt64(bytes[p])
                let b1 = UInt64(bytes[p + 1])
                let b2 = UInt64(bytes[p + 2])
                let b3 = UInt64(bytes[p + 3])
                let b4 = UInt64(bytes[p + 4])
                let ticks = ((b0 >> 1) & 0x07) << 30 | b1 << 22 | (b2 >> 1) << 15 | b3 << 7 | b4 >> 1
                pts = TimeInterval(ticks) / 90000
            }
            p += headerLength
            p += 1 // substream id (0x20 + n)
            guard p <= pesEnd else { break }

            if !consume(bytes[p..<pesEnd], position) { break }
            position = pesEnd
        }
        return pts
    }

    /// The result of reading a subpicture's control sequences.
    struct Control {
        var startDelay: TimeInterval = 0
        var stopDelay: TimeInterval?
        var isForced = false
        var colorIndices: [UInt8] = [0, 0, 0, 0]
        var alphaNibbles: [UInt8] = [0, 0, 0, 0]
        var x = 0
        var y = 0
        var width = 0
        var height = 0
        var evenOffset = 0
        var oddOffset = 0
        var warnings: [String] = []
    }

    private mutating func apply(_ control: Control) {
        startDelay = control.startDelay
        stopDelay = control.stopDelay
        isForced = control.isForced
        colorIndices = control.colorIndices
        alphaNibbles = control.alphaNibbles
        x = control.x
        y = control.y
        width = control.width
        height = control.height
        evenOffset = control.evenOffset
        oddOffset = control.oddOffset
        warnings.append(contentsOf: control.warnings)
    }

    /// Read the control sequences starting at subpicture offset `from`.
    ///
    /// `buffer[i]` is subpicture byte `i + base`, so the same parser works on
    /// a whole subpicture (base 0) and on a buffer holding only the control
    /// block (base the control offset).
    static func parseControl(_ buffer: [UInt8], from controlOffset: Int, base: Int) -> Control {
        var control = Control()
        guard controlOffset >= base else { return control }
        var offset = controlOffset
        var visited = Set<Int>()
        var sawStart = false

        func byte(_ index: Int) -> UInt8? {
            let position = index - base
            guard position >= 0, position < buffer.count else { return nil }
            return buffer[position]
        }

        while !visited.contains(offset), let d0 = byte(offset), let d1 = byte(offset + 1),
              let n0 = byte(offset + 2), let n1 = byte(offset + 3) {
            visited.insert(offset)
            let delayTicks = Int(d0) << 8 | Int(d1)
            let next = Int(n0) << 8 | Int(n1)
            let delay = TimeInterval(delayTicks << 10) / 90000
            var p = offset + 4

            commands: while let command = byte(p) {
                p += 1
                switch command {
                case 0x00:
                    control.isForced = true
                case 0x01:
                    if !sawStart {
                        control.startDelay = delay
                        sawStart = true
                    }
                case 0x02:
                    control.stopDelay = delayTicks == 0xFFFF ? nil : delay
                case 0x03:
                    guard let a = byte(p), let b = byte(p + 1) else { break commands }
                    control.colorIndices = [b & 0x0F, b >> 4, a & 0x0F, a >> 4]
                    p += 2
                case 0x04:
                    guard let a = byte(p), let b = byte(p + 1) else { break commands }
                    control.alphaNibbles = [b & 0x0F, b >> 4, a & 0x0F, a >> 4]
                    p += 2
                case 0x05:
                    guard let b0 = byte(p), let b1 = byte(p + 1), let b2 = byte(p + 2),
                          let b3 = byte(p + 3), let b4 = byte(p + 4), byte(p + 5) != nil else { break commands }
                    let b5 = byte(p + 5)!
                    let x1 = Int(b0) << 4 | Int(b1 >> 4)
                    let x2 = Int(b1 & 0x0F) << 8 | Int(b2)
                    let y1 = Int(b3) << 4 | Int(b4 >> 4)
                    let y2 = Int(b4 & 0x0F) << 8 | Int(b5)
                    if control.width == 0 { // keep the first definition; bad files repeat it
                        control.x = x1
                        control.y = y1
                        control.width = x2 - x1 + 1
                        control.height = y2 - y1 + 1
                    }
                    p += 6
                case 0x06:
                    guard let b0 = byte(p), let b1 = byte(p + 1),
                          let b2 = byte(p + 2), let b3 = byte(p + 3) else { break commands }
                    control.evenOffset = Int(b0) << 8 | Int(b1)
                    control.oddOffset = Int(b2) << 8 | Int(b3)
                    p += 4
                case 0x07:
                    // Change color & contrast: 2-byte length followed by data.
                    guard let b0 = byte(p), let b1 = byte(p + 1) else { break commands }
                    p += max(Int(b0) << 8 | Int(b1), 2)
                case 0xFF:
                    break commands
                default:
                    control.warnings.append("Unknown subpicture command \(command.hexString).")
                    break commands
                }
            }

            if next == offset || next < controlOffset { break }
            offset = next
        }
        return control
    }

    /// The decoded bitmap using the master palette from the `.idx`.
    func bitmap(masterPalette: [UInt8]) -> IndexedBitmap? {
        guard width > 0, height > 0, width * height <= 8192 * 8192 else { return nil }
        let pixels = VobSubRLE.decode(spu, width: width, height: height,
                                      evenOffset: evenOffset, oddOffset: oddOffset)
        var palette = [UInt8](repeating: 0, count: IndexedBitmap.paletteSize)
        for color in 0..<4 {
            let master = Int(colorIndices[color]) * 3
            guard master + 2 < masterPalette.count else { continue }
            palette[color * 4] = masterPalette[master]
            palette[color * 4 + 1] = masterPalette[master + 1]
            palette[color * 4 + 2] = masterPalette[master + 2]
            palette[color * 4 + 3] = alphaNibbles[color] * 0x11
        }
        return IndexedBitmap(width: width, height: height, pixels: pixels, palette: palette)
    }
}
