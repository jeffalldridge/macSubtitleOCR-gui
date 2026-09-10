import Foundation

extension UnsafeRawBufferPointer {
    /// Big-endian unsigned integer of `length` bytes (1…8) at `offset`.
    /// Returns nil when the read would run past the end of the buffer.
    @inlinable
    func readUIntBE(at offset: Int, length: Int) -> UInt64? {
        guard length >= 1, length <= 8, offset >= 0, offset + length <= count else { return nil }
        var value: UInt64 = 0
        for i in 0..<length {
            value = (value << 8) | UInt64(self[offset + i])
        }
        return value
    }

    /// Big-endian signed integer of `length` bytes (1…8) at `offset`.
    @inlinable
    func readIntBE(at offset: Int, length: Int) -> Int64? {
        guard let raw = readUIntBE(at: offset, length: length) else { return nil }
        let shift = UInt64(64 - length * 8)
        // Sign-extend by shifting up to the top and back down arithmetically.
        return Int64(bitPattern: raw << shift) >> Int64(shift)
    }

    @inlinable
    func readUInt16BE(at offset: Int) -> UInt16? {
        readUIntBE(at: offset, length: 2).map(UInt16.init)
    }

    @inlinable
    func readUInt32BE(at offset: Int) -> UInt32? {
        readUIntBE(at: offset, length: 4).map(UInt32.init)
    }

    /// The bytes in `range` as `Data`, or nil when out of bounds.
    @inlinable
    func slice(_ range: Range<Int>) -> Data? {
        guard range.lowerBound >= 0, range.upperBound <= count else { return nil }
        return Data(self[range])
    }
}

extension Data {
    /// Memory-map a file when possible; falls back to reading it.
    static func mapped(contentsOf url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                throw EngineError.fileNotFound(url)
            }
            throw error
        }
    }
}

extension BinaryInteger {
    /// `0x1A45DFA3`-style hex for diagnostics.
    var hexString: String {
        "0x" + String(self, radix: 16, uppercase: true)
    }
}
