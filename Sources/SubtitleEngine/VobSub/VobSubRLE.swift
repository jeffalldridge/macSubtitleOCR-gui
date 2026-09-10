import Foundation

/// DVD subpicture run-length decoding.
///
/// Pixels are 2-bit color indices. Runs are coded in 1–4 nibbles:
/// - `RRCC`                    (1 nibble)  run 1…3
/// - `00RR RRCC`               (2 nibbles) run 4…15
/// - `0000 RRRR RRCC`          (3 nibbles) run 16…63
/// - `0000 0000 RRRR RRCC`     (4 nibbles) run 64…255; run 0 = rest of line
/// Lines are byte-aligned. The even lines (0, 2, 4…) and odd lines
/// (1, 3, 5…) are stored as two separate fields.
enum VobSubRLE {
    /// Decode both fields of a `width × height` subpicture from `spu`.
    static func decode(_ spu: [UInt8], width: Int, height: Int, evenOffset: Int, oddOffset: Int) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height)
        decodeField(spu, start: evenOffset, width: width, firstRow: 0, height: height, into: &pixels)
        if height > 1 {
            decodeField(spu, start: oddOffset, width: width, firstRow: 1, height: height, into: &pixels)
        }
        return pixels
    }

    private static func decodeField(_ spu: [UInt8], start: Int, width: Int, firstRow: Int, height: Int,
                                    into pixels: inout [UInt8]) {
        guard start >= 0, start < spu.count else { return }
        var reader = NibbleReader(bytes: spu, byteOffset: start)
        var y = firstRow
        while y < height {
            var x = 0
            while x < width {
                guard let code = reader.readCode() else { return }
                var run = code >> 2
                let color = UInt8(code & 0x03)
                if run == 0 { run = width - x }          // 4-nibble zero run: fill the line
                let n = min(run, width - x)
                if color != 0 {
                    let base = y * width + x
                    for k in 0..<n { pixels[base + k] = color }
                }
                x += n
            }
            reader.alignToByte()
            y += 2
        }
    }

    private struct NibbleReader {
        let bytes: [UInt8]
        var nibbleIndex: Int

        init(bytes: [UInt8], byteOffset: Int) {
            self.bytes = bytes
            nibbleIndex = byteOffset * 2
        }

        mutating func next() -> Int? {
            let byteIndex = nibbleIndex >> 1
            guard byteIndex < bytes.count else { return nil }
            let byte = bytes[byteIndex]
            let nibble = nibbleIndex & 1 == 0 ? byte >> 4 : byte & 0x0F
            nibbleIndex += 1
            return Int(nibble)
        }

        /// Read one run code (1–4 nibbles) and return `run << 2 | color`.
        mutating func readCode() -> Int? {
            guard var value = next() else { return nil }
            if value >= 0x4 { return value }
            guard let n2 = next() else { return nil }
            value = value << 4 | n2
            if value >= 0x10 { return value }
            guard let n3 = next() else { return nil }
            value = value << 4 | n3
            if value >= 0x40 { return value }
            guard let n4 = next() else { return nil }
            return value << 4 | n4
        }

        mutating func alignToByte() {
            if nibbleIndex & 1 == 1 { nibbleIndex += 1 }
        }
    }
}
