import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct VobSubStreamTests {
    @Test func indexesSintelCues() throws {
        let stream = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        #expect(stream.format == .vobsub)
        #expect(stream.cues.count == 26)
        #expect(stream.language == "en")
        #expect(stream.warnings.isEmpty)

        let first = try #require(stream.cues.first)
        #expect(first.start == 107.25)
        #expect(first.end == nil, "a stop delay of 0xFFFF means “until the next cue”")
        #expect(abs(stream.cues[1].start - 111.792) < 0.001)
    }

    @Test func decodesFirstAndLast() throws {
        let stream = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        let first = try #require(try stream.bitmap(at: 0))
        #expect(first.width == 1920)
        #expect(first.height == 55)
        #expect(first.hasVisiblePixels)
        // Pixel values are 2-bit color indices.
        #expect(first.pixels.allSatisfy { $0 < 4 })
        // Color 1 is opaque (alpha nibble F) and maps to master palette entry 7 (white).
        let c1 = first.rgba(ofIndex: 1)
        #expect(c1.a == 255)
        #expect(c1.r == 255 && c1.g == 255 && c1.b == 255)
        // Color 0 is transparent.
        #expect(first.rgba(ofIndex: 0).a == 0)

        let last = try #require(try stream.bitmap(at: 25))
        #expect(last.width == 1920)
        #expect(last.hasVisiblePixels)
    }

    @Test func fieldsAreInterleaved() throws {
        // Every cue in the fixture is text on a transparent background: the
        // first and last rows are blank, and opaque rows exist in the middle.
        let stream = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        let bitmap = try #require(try stream.bitmap(at: 0))
        func rowHasInk(_ y: Int) -> Bool {
            (0..<bitmap.width).contains { bitmap.pixel(x: $0, y: y) != 0 }
        }
        let inkRows = (0..<bitmap.height).filter(rowHasInk)
        #expect(inkRows.count > 10)
        // Rows with ink are contiguous-ish: no alternating blank/ink pattern.
        let alternating = zip(inkRows, inkRows.dropFirst()).filter { $1 - $0 == 2 }.count
        #expect(alternating < inkRows.count / 4, "odd and even fields must be interleaved, not stacked")
    }

    @Test func outOfRangeIndexThrows() throws {
        let stream = try VobSubStream(subURL: Fixtures.sintelSUB, idxURL: Fixtures.sintelIDX)
        #expect(throws: EngineError.self) { _ = try stream.bitmap(at: 26) }
    }

    @Test func idxWithoutTimestampsIsEmpty() throws {
        let idx = """
        # VobSub index file, v7 (do not modify this line!)
        palette: 000000, 0000ff, 00ff00, ff0000, ffff00, ff00ff, 00ffff, ffffff, 808000, 8080ff, 800080, 80ff80, 008080, ff8080, 555555, aaaaaa
        id: fr, index: 0
        """
        let stream = try VobSubStream(sub: Data(), idx: idx)
        #expect(stream.cues.isEmpty)
        #expect(stream.language == "fr")
    }

    @Test func idxParsesPaletteAndTimestamps() throws {
        let idx = """
        # VobSub index file, v7 (do not modify this line!)
        size: 720x480
        palette: 000000, 0000ff, 00ff00, ff0000, ffff00, ff00ff, 00ffff, ffffff, 808000, 8080ff, 800080, 80ff80, 008080, ff8080, 555555, aaaaaa
        langidx: 0
        id: de, index: 0
        timestamp: 00:01:47:250, filepos: 000000000
        timestamp: 01:02:03:004, filepos: 000001800
        """
        let parsed = try VobSubIDX(text: idx)
        #expect(parsed.palette.count == 16 * 3)
        #expect(parsed.palette[3..<6] == [0x00, 0x00, 0xFF])
        #expect(parsed.language == "de")
        #expect(parsed.entries.map(\.offset) == [0, 0x1800])
        #expect(parsed.entries[0].timestamp == 107.25)
        #expect(abs(parsed.entries[1].timestamp - 3723.004) < 0.0001)
    }

    @Test func missingIdxPaletteFallsBackToDefault() throws {
        let parsed = try VobSubIDX(text: "id: en, index: 0\ntimestamp: 00:00:01:000, filepos: 000000000\n")
        #expect(parsed.palette.count == 16 * 3)
    }

    @Test func rleDecodesTwoFields() {
        // A 4×2 image: even field (row 0) all color 1, odd field (row 1) all color 2.
        // Encoded per row as one run to end of line: 4-nibble code 0x00 0 <color>
        // → nibbles 0,0,0,color  =>  bytes 0x00, 0x0C for color 1? No:
        // value = (0<<12)|(0<<8)|(0<<4)|color, run = value >> 2 = 0 → "to end of line".
        let even: [UInt8] = [0x00, 0x01]  // nibbles 0,0,0,1  → fill rest of line with color 1
        let odd: [UInt8] = [0x00, 0x02]   // nibbles 0,0,0,2
        var spu: [UInt8] = [0, 0, 0, 0]   // size + control offset header (ignored here)
        let evenOffset = spu.count
        spu += even
        let oddOffset = spu.count
        spu += odd
        let pixels = VobSubRLE.decode(spu, width: 4, height: 2, evenOffset: evenOffset, oddOffset: oddOffset)
        #expect(pixels == [1, 1, 1, 1, 2, 2, 2, 2])
    }

    @Test func rleDecodesShortAndLongRuns() {
        // Row of width 10: run of 3 × color 3 (1 nibble: 3<<2|3 = 0xF), then
        // run of 7 × color 2 (2 nibbles: 7<<2|2 = 0x1E → nibbles 1,E).
        // Nibbles: F, 1, E → bytes F1 E0 (padded to byte boundary at end of line).
        let spu: [UInt8] = [0, 0, 0, 0, 0xF1, 0xE0]
        let pixels = VobSubRLE.decode(spu, width: 10, height: 1, evenOffset: 4, oddOffset: 4)
        #expect(pixels == [3, 3, 3, 2, 2, 2, 2, 2, 2, 2])
    }
}
