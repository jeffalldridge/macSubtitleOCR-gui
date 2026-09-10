import Foundation

/// Run-length decoding for PGS object data.
///
/// Encoding (per line):
/// - `CC`                  one pixel of color `CC` (`CC != 0`)
/// - `00 00`               end of line
/// - `00 0LLLLLLL`         `L` transparent pixels (1…63)
/// - `00 01LLLLLL LL`      `L` transparent pixels (64…16383)
/// - `00 10LLLLLL CC`      `L` pixels of color `CC` (1…63)
/// - `00 11LLLLLL LL CC`   `L` pixels of color `CC` (64…16383)
enum PGSRLE {
    struct Result {
        let pixels: [UInt8]
        /// False when the data ran out before every line was complete.
        let complete: Bool
    }

    static func decode<C: RandomAccessCollection>(_ data: C, width: Int, height: Int) -> Result
        where C.Element == UInt8, C.Index == Int {
        guard width > 0, height > 0 else { return Result(pixels: [], complete: true) }
        var pixels = [UInt8](repeating: 0, count: width * height)
        var i = data.startIndex
        let end = data.endIndex
        var x = 0
        var y = 0

        func put(_ color: UInt8, _ run: Int) {
            guard y < height, x < width, run > 0 else { x += run; return }
            let n = min(run, width - x)
            if color != 0 {
                let base = y * width + x
                for k in 0..<n { pixels[base + k] = color }
            }
            x += run
        }

        while i < end, y < height {
            let byte = data[i]
            i += 1
            if byte != 0 {
                put(byte, 1)
                continue
            }
            guard i < end else { break }
            let flags = data[i]
            i += 1
            if flags == 0 {
                x = 0
                y += 1
                continue
            }
            var run = Int(flags & 0x3F)
            if flags & 0x40 != 0 {
                guard i < end else { break }
                run = (run << 8) | Int(data[i])
                i += 1
            }
            var color: UInt8 = 0
            if flags & 0x80 != 0 {
                guard i < end else { break }
                color = data[i]
                i += 1
            }
            put(color, run)
        }

        return Result(pixels: pixels, complete: y >= height)
    }
}
