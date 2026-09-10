import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct EBMLReaderTests {
    private func withReader<T>(_ bytes: [UInt8], _ body: (EBMLReader) -> T) -> T {
        bytes.withUnsafeBytes { body(EBMLReader(bytes: $0)) }
    }

    @Test func readsOneByteVINT() {
        withReader([0x81]) { reader in
            let asID = reader.readVINT(at: 0, stripMarker: false)
            #expect(asID?.value == 0x81)
            #expect(asID?.length == 1)
            let asSize = reader.readVINT(at: 0, stripMarker: true)
            #expect(asSize?.value == 1)
        }
    }

    @Test func readsMultiByteVINTs() {
        withReader([0x40, 0x02, 0x1A, 0x45, 0xDF, 0xA3]) { reader in
            #expect(reader.readVINT(at: 0, stripMarker: true)?.value == 2)
            #expect(reader.readVINT(at: 0, stripMarker: false)?.value == 0x4002)
            let id = reader.readVINT(at: 2, stripMarker: false)
            #expect(id?.value == 0x1A45_DFA3)
            #expect(id?.length == 4)
        }
    }

    @Test func recognisesUnknownSizes() {
        withReader([0xFF]) { reader in
            #expect(reader.readVINT(at: 0, stripMarker: true)?.isAllOnes == true)
        }
        withReader(EBMLBuilder.unknownSize) { reader in
            let v = reader.readVINT(at: 0, stripMarker: true)
            #expect(v?.isAllOnes == true)
            #expect(v?.length == 8)
        }
        withReader([0x7F, 0xFF]) { reader in
            // 0x7FFF is the two-byte all-ones pattern (marker 0x40, data 0x3FFF)
            #expect(reader.readVINT(at: 0, stripMarker: true)?.isAllOnes == true)
        }
        withReader([0x40, 0x7F]) { reader in
            #expect(reader.readVINT(at: 0, stripMarker: true)?.isAllOnes == false)
        }
    }

    @Test func parsesElementHeader() {
        withReader([0xAE, 0x82, 0x01, 0x02, 0xEC, 0x80]) { reader in
            let element = reader.element(at: 0)
            #expect(element?.id == 0xAE)
            #expect(element?.size == 2)
            #expect(element?.dataOffset == 2)
            #expect(element?.endOffset == 4)

            let next = reader.element(at: 4)
            #expect(next?.id == 0xEC)
            #expect(next?.size == 0)
            #expect(next?.endOffset == 6)
        }
    }

    @Test func unknownSizeElementRunsToEndOfBuffer() {
        withReader([0x1F, 0x43, 0xB6, 0x75, 0xFF, 0xE7, 0x81, 0x00]) { reader in
            let element = reader.element(at: 0)
            #expect(element?.id == 0x1F43_B675)
            #expect(element?.size == nil)
            #expect(element?.dataOffset == 5)
            #expect(element?.endOffset == 8)
        }
    }

    @Test func truncatedHeaderReturnsNil() {
        withReader([0x40]) { reader in
            #expect(reader.element(at: 0) == nil)
        }
        withReader([0xAE, 0x85, 0x01]) { reader in
            // Size claims 5 bytes but only 1 remains: the element is clamped, not rejected.
            let element = reader.element(at: 0)
            #expect(element?.size == 5)
            #expect(element?.endOffset == 3)
        }
        withReader([]) { reader in
            #expect(reader.element(at: 0) == nil)
        }
    }

    @Test func readsScalarPayloads() {
        let bytes = EBMLBuilder.uint(0xD7, 0x0102) + EBMLBuilder.string(0x86, "S_HDMV/PGS")
            + EBMLBuilder.float(0x4489, 629813.0) + EBMLBuilder.string(0x536E, "Name\u{0}")
        withReader(bytes) { reader in
            let number = reader.element(at: 0)!
            #expect(reader.uint(number) == 0x0102)
            let codec = reader.element(at: number.endOffset)!
            #expect(reader.string(codec) == "S_HDMV/PGS")
            let duration = reader.element(at: codec.endOffset)!
            #expect(reader.float(duration) == 629813.0)
            let name = reader.element(at: duration.endOffset)!
            #expect(reader.string(name) == "Name", "trailing NUL padding is stripped")
        }
    }
}
