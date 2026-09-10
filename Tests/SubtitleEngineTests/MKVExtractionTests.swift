import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct MKVBlockTests {
    private func parse(_ bytes: [UInt8]) -> MKVBlock? {
        bytes.withUnsafeBytes { MKVBlock($0, range: 0..<bytes.count) }
    }

    @Test func parsesUnlacedBlock() throws {
        let block = try #require(parse([0x81, 0x00, 0x10, 0x80, 0xAA, 0xBB, 0xCC]))
        #expect(block.trackNumber == 1)
        #expect(block.relativeTimestamp == 16)
        #expect(block.frames == [4..<7])
    }

    @Test func parsesNegativeTimestamp() throws {
        let block = try #require(parse([0x82, 0xFF, 0xFE, 0x00, 0x01]))
        #expect(block.trackNumber == 2)
        #expect(block.relativeTimestamp == -2)
        #expect(block.frames == [4..<5])
    }

    @Test func parsesXiphLacing() throws {
        // flags 0x02 = Xiph, 2 frames: first is 3 bytes, second is the rest.
        let block = try #require(parse([0x81, 0x00, 0x00, 0x02, 0x01, 0x03, 1, 2, 3, 4, 5]))
        #expect(block.frames == [6..<9, 9..<11])
    }

    @Test func parsesXiphLacingWithLongSize() throws {
        // A 300-byte first frame is coded as 255 + 45.
        let payload = [UInt8](repeating: 0x11, count: 300) + [0x22, 0x22]
        let block = try #require(parse([0x81, 0x00, 0x00, 0x02, 0x01, 0xFF, 0x2D] + payload))
        #expect(block.frames == [7..<307, 307..<309])
    }

    @Test func parsesEBMLLacing() throws {
        // flags 0x06 = EBML, 3 frames: sizes 3, 5 (delta +2 → 2 + 63 = 65 = 0xC1), rest (1).
        let bytes: [UInt8] = [0x81, 0x00, 0x00, 0x06, 0x02, 0x83, 0xC1] + [UInt8](repeating: 0, count: 9)
        let block = try #require(parse(bytes))
        #expect(block.frames == [7..<10, 10..<15, 15..<16])
    }

    @Test func parsesFixedLacing() throws {
        // flags 0x04 = fixed, 2 frames of 4 bytes each.
        let block = try #require(parse([0x81, 0x00, 0x00, 0x04, 0x01] + [UInt8](repeating: 7, count: 8)))
        #expect(block.frames == [5..<9, 9..<13])
    }

    @Test func rejectsTruncatedHeader() {
        #expect(parse([0x81, 0x00]) == nil)
    }
}

@Suite struct MKVExtractionTests {
    @Test func extractedPGSMatchesStandaloneSup() throws {
        let reader = try MKVReader(url: Fixtures.sintelMKS)
        guard case .pgs(let data) = try reader.extract(trackNumber: 1) else {
            Issue.record("expected a PGS track")
            return
        }
        let extracted = try PGSStream(data: data)
        let standalone = try PGSStream(url: Fixtures.sintelSUP)

        #expect(extracted.cues.count == standalone.cues.count)
        #expect(extracted.warnings.isEmpty)
        for (a, b) in zip(extracted.cues, standalone.cues) {
            #expect(abs(a.start - b.start) < 0.002)
            if let ae = a.end, let be = b.end { #expect(abs(ae - be) < 0.002) }
        }
        let first = try #require(try extracted.bitmap(at: 0))
        let reference = try #require(try standalone.bitmap(at: 0))
        #expect(first.pixels == reference.pixels)
    }

    @Test func extractedVobSubMatchesStandalone() throws {
        let reader = try MKVReader(url: Fixtures.sintelMKS)
        guard case .vobsub(let sub, let idx) = try reader.extract(trackNumber: 2) else {
            Issue.record("expected a VobSub track")
            return
        }
        #expect(idx.hasPrefix("# VobSub index file, v7"))
        #expect(idx.contains("palette:"))
        #expect(idx.contains("id: eng, index: 0"))

        let extracted = try VobSubStream(sub: sub, idx: idx)
        let standalone = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        #expect(extracted.cues.count == standalone.cues.count)
        #expect(extracted.warnings.isEmpty)
        for (a, b) in zip(extracted.cues, standalone.cues) {
            #expect(abs(a.start - b.start) < 0.002)
        }
        let first = try #require(try extracted.bitmap(at: 0))
        let reference = try #require(try standalone.bitmap(at: 0))
        #expect(first.width == reference.width && first.height == reference.height)
        #expect(first.pixels == reference.pixels)
        let last = try #require(try extracted.bitmap(at: 25))
        #expect(last.hasVisiblePixels)
    }

    @Test func reportsProgress() throws {
        final class Box: @unchecked Sendable { var values: [Double] = [] }
        let box = Box()
        let reader = try MKVReader(url: Fixtures.sintelMKS)
        _ = try reader.extract(trackNumber: 1) { box.values.append($0) }
        #expect(box.values.last == 1.0)
        #expect(box.values == box.values.sorted(), "progress never goes backwards")
    }

    @Test func unknownTrackThrows() throws {
        let reader = try MKVReader(url: Fixtures.sintelMKS)
        #expect(throws: EngineError.trackNotFound(9)) {
            _ = try reader.extract(trackNumber: 9)
        }
    }

    @Test func honoursTimestampScale() throws {
        // Two PGS frames in a container whose timestamps are in 10 ms units.
        let displaySet = PGSBuilder.displaySet(pts: 0, objects: [
            (PGSBuilder.Object(id: 0, x: 0, y: 0), width: 8, height: 2, color: 1),
        ])
        // Strip the 13-byte PG headers: Matroska blocks carry bare segments.
        let bare = stripPGHeaders(displaySet)
        let clearBare = stripPGHeaders(PGSBuilder.clear(pts: 0))
        let data = EBMLBuilder.file([
            EBMLBuilder.info(timestampScale: 10_000_000),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
            EBMLBuilder.cluster(timestamp: 100, blocks: [           // 1.000 s
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 25, payload: bare),      // 1.250 s
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 225, payload: clearBare), // 3.250 s
            ]),
        ])
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/synthetic.mkv"))
        guard case .pgs(let pgs) = try reader.extract(trackNumber: 1) else {
            Issue.record("expected PGS")
            return
        }
        let stream = try PGSStream(data: pgs)
        #expect(stream.cues.count == 1)
        #expect(abs(stream.cues[0].start - 1.25) < 0.0001)
        #expect(abs((stream.cues[0].end ?? 0) - 3.25) < 0.0001)
        let bitmap = try #require(try stream.bitmap(at: 0))
        #expect(bitmap.width == 8 && bitmap.height == 2)
    }

    @Test func cancellationStopsExtraction() async throws {
        let task = Task {
            let reader = try MKVReader(url: Fixtures.sintelMKS)
            return try reader.extract(trackNumber: 1)
        }
        task.cancel()
        await #expect(throws: EngineError.cancelled) {
            _ = try await task.value
        }
    }

    private func stripPGHeaders(_ sup: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var offset = 0
        while offset + 13 <= sup.count {
            let length = Int(sup[offset + 11]) << 8 | Int(sup[offset + 12])
            out += sup[(offset + 10)..<(offset + 13 + length)]
            offset += 13 + length
        }
        return out
    }
}
