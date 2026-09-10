import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct BinaryReadingTests {
    @Test func readsBigEndianUnsigned() {
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0xFF]
        bytes.withUnsafeBytes { buffer in
            #expect(buffer.readUIntBE(at: 0, length: 4) == 0x0001_0203)
            #expect(buffer.readUInt16BE(at: 3) == 0x03FF)
            #expect(buffer.readUIntBE(at: 4, length: 2) == nil, "must not read past the end")
            #expect(buffer.readUIntBE(at: 0, length: 0) == nil)
        }
    }

    @Test func readsBigEndianSigned() {
        let bytes: [UInt8] = [0xFF, 0xFE, 0x7F, 0xFF]
        bytes.withUnsafeBytes { buffer in
            #expect(buffer.readIntBE(at: 0, length: 2) == -2)
            #expect(buffer.readIntBE(at: 2, length: 2) == 0x7FFF)
            #expect(buffer.readIntBE(at: 0, length: 1) == -1)
        }
    }

    @Test func slicesWithinBounds() {
        let bytes: [UInt8] = [1, 2, 3]
        bytes.withUnsafeBytes { buffer in
            #expect(buffer.slice(1..<3) == Data([2, 3]))
            #expect(buffer.slice(2..<4) == nil)
        }
    }
}
