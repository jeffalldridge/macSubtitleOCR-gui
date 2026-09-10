import Foundation

/// One subpicture unit (SPU) reassembled from the MPEG program-stream
/// packets of a `.sub` file, with its control sequences parsed.
struct VobSubPacket {
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
        var pts: TimeInterval?
        var declaredSize: Int?
        var position = offset
        var warnings: [String] = []

        while position < nextOffset, position + 4 <= bytes.count {
            guard bytes.readUInt32BE(at: position) == Self.packStartCode else {
                warnings.append("No pack header at byte \(position).")
                break
            }
            // Pack header: start code (4) + SCR (6) + mux rate (3) + stuffing length (1) + stuffing.
            var p = position + 13
            guard p < bytes.count else { break }
            p += 1 + Int(bytes[p] & 0x07)

            guard bytes.readUInt32BE(at: p) == Self.pesStartCode,
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
                let b0 = UInt64(bytes[p]), b1 = UInt64(bytes[p + 1]), b2 = UInt64(bytes[p + 2])
                let b3 = UInt64(bytes[p + 3]), b4 = UInt64(bytes[p + 4])
                let ticks = ((b0 >> 1) & 0x07) << 30 | b1 << 22 | (b2 >> 1) << 15 | b3 << 7 | b4 >> 1
                pts = TimeInterval(ticks) / 90000
            }
            p += headerLength
            p += 1 // substream id (0x20 + n)
            guard p <= pesEnd else { break }

            spu.append(contentsOf: bytes[p..<pesEnd])
            position = pesEnd

            if declaredSize == nil, spu.count >= 2 {
                declaredSize = Int(spu[0]) << 8 | Int(spu[1])
            }
            if let declaredSize, spu.count >= declaredSize { break }
        }

        guard spu.count >= 4 else {
            throw EngineError.invalidData("A VobSub subpicture at byte \(offset) is empty.")
        }
        if let declaredSize, spu.count < declaredSize {
            warnings.append("A subpicture at byte \(offset) is truncated (\(spu.count) of \(declaredSize) bytes).")
        }

        self.spu = spu
        self.pts = pts
        self.warnings = warnings
        parseControlSequences()
    }

    private mutating func parseControlSequences() {
        let controlOffset = Int(spu[2]) << 8 | Int(spu[3])
        var offset = controlOffset
        var visited = Set<Int>()
        var sawStart = false

        while offset + 4 <= spu.count, !visited.contains(offset) {
            visited.insert(offset)
            let delayTicks = Int(spu[offset]) << 8 | Int(spu[offset + 1])
            let next = Int(spu[offset + 2]) << 8 | Int(spu[offset + 3])
            let delay = TimeInterval(delayTicks << 10) / 90000
            var p = offset + 4

            commands: while p < spu.count {
                let command = spu[p]
                p += 1
                switch command {
                case 0x00:
                    isForced = true
                case 0x01:
                    if !sawStart { startDelay = delay; sawStart = true }
                case 0x02:
                    stopDelay = delayTicks == 0xFFFF ? nil : delay
                case 0x03:
                    guard p + 2 <= spu.count else { break commands }
                    colorIndices = [spu[p + 1] & 0x0F, spu[p + 1] >> 4, spu[p] & 0x0F, spu[p] >> 4]
                    p += 2
                case 0x04:
                    guard p + 2 <= spu.count else { break commands }
                    alphaNibbles = [spu[p + 1] & 0x0F, spu[p + 1] >> 4, spu[p] & 0x0F, spu[p] >> 4]
                    p += 2
                case 0x05:
                    guard p + 6 <= spu.count else { break commands }
                    let x1 = Int(spu[p]) << 4 | Int(spu[p + 1] >> 4)
                    let x2 = Int(spu[p + 1] & 0x0F) << 8 | Int(spu[p + 2])
                    let y1 = Int(spu[p + 3]) << 4 | Int(spu[p + 4] >> 4)
                    let y2 = Int(spu[p + 4] & 0x0F) << 8 | Int(spu[p + 5])
                    if width == 0 { // keep the first definition; bad files repeat it
                        x = x1
                        y = y1
                        width = x2 - x1 + 1
                        height = y2 - y1 + 1
                    }
                    p += 6
                case 0x06:
                    guard p + 4 <= spu.count else { break commands }
                    evenOffset = Int(spu[p]) << 8 | Int(spu[p + 1])
                    oddOffset = Int(spu[p + 2]) << 8 | Int(spu[p + 3])
                    p += 4
                case 0x07:
                    // Change color & contrast: 2-byte length followed by data.
                    guard p + 2 <= spu.count else { break commands }
                    let length = Int(spu[p]) << 8 | Int(spu[p + 1])
                    p += max(length, 2)
                case 0xFF:
                    break commands
                default:
                    warnings.append("Unknown subpicture command \(command.hexString).")
                    break commands
                }
            }

            if next == offset || next < controlOffset { break }
            offset = next
        }
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
