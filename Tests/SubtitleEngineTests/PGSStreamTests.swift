import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct PGSStreamTests {
    // MARK: - Fixture

    @Test func indexesSintelCues() throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        #expect(stream.format == .pgs)
        #expect(stream.cues.count == 26)
        #expect(stream.warnings.isEmpty)

        let first = try #require(stream.cues.first)
        #expect(first.index == 0)
        #expect(first.start == 107.25)
        let end = try #require(first.end)
        #expect(abs(end - 109.208) < 0.001, "the clear display set ends the cue")

        let second = stream.cues[1]
        #expect(abs(second.start - 111.792) < 0.001)
    }

    @Test func cuesAreOrderedAndDoNotOverlap() throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        for (a, b) in zip(stream.cues, stream.cues.dropFirst()) {
            #expect(a.start < b.start)
            if let end = a.end { #expect(end <= b.start) }
        }
    }

    @Test func decodesRandomAccess() throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        let last = try #require(try stream.bitmap(at: 25))
        #expect(last.width > 0 && last.height > 0)

        let first = try #require(try stream.bitmap(at: 0))
        #expect(first.width == 1920)
        #expect(first.height == 55)
        #expect(first.pixels.count == 1920 * 55)
        // Some pixel must be opaque text.
        let opaque = first.pixels.contains { first.rgba(ofIndex: $0).a > 0 }
        #expect(opaque)
    }

    @Test func outOfRangeIndexThrows() throws {
        let stream = try PGSStream(url: Fixtures.sintelSUP)
        #expect(throws: EngineError.self) { _ = try stream.bitmap(at: 26) }
        #expect(throws: EngineError.self) { _ = try stream.bitmap(at: -1) }
    }

    @Test func truncatedStreamKeepsCompleteCues() throws {
        let full = try Data(contentsOf: Fixtures.sintelSUP)
        let stream = try PGSStream(data: full.prefix(full.count / 2))
        #expect(stream.cues.count > 5)
        #expect(stream.cues.count < 26)
        #expect(!stream.warnings.isEmpty, "a truncated segment is reported, not fatal")
    }

    @Test func garbageIsRejected() {
        #expect(throws: EngineError.self) {
            _ = try PGSStream(data: Data(repeating: 0x41, count: 400))
        }
    }

    // MARK: - Synthetic

    @Test func compositesTwoObjectsAtTheirPositions() throws {
        let bytes = PGSBuilder.displaySet(pts: 10, objects: [
            (PGSBuilder.Object(id: 0, x: 100, y: 50), width: 200, height: 30, color: 1),
            (PGSBuilder.Object(id: 1, x: 100, y: 200), width: 300, height: 20, color: 2),
        ]) + PGSBuilder.clear(pts: 12)
        let stream = try PGSStream(data: Data(bytes))

        #expect(stream.cues.count == 1)
        let bitmap = try #require(try stream.bitmap(at: 0))
        #expect(bitmap.width == 300)
        #expect(bitmap.height == 170)
        #expect(bitmap.pixel(x: 0, y: 0) == 1)
        #expect(bitmap.pixel(x: 199, y: 29) == 1)
        #expect(bitmap.pixel(x: 250, y: 10) != 1, "outside the first object")
        #expect(bitmap.rgba(ofIndex: bitmap.pixel(x: 250, y: 10)).a == 0, "gap between objects is transparent")
        #expect(bitmap.pixel(x: 250, y: 165) == 2)
        #expect(bitmap.pixel(x: 299, y: 169) == 2)
    }

    @Test func paletteUpdateDoesNotEndACue() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 900)
        var bytes = PGSBuilder.displaySet(pts: 10, objects: [(object, width: 100, height: 10, color: 1)])
        // Fade: same object, new palette only.
        bytes += PGSBuilder.pcs(pts: 11, state: 0x00, paletteUpdate: true, objects: [object])
        bytes += PGSBuilder.pds(pts: 11, id: 0, entries: [(1, 235, 128, 128, 128)])
        bytes += PGSBuilder.end(pts: 11)
        bytes += PGSBuilder.clear(pts: 12)

        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 1)
        #expect(stream.cues[0].start == 10)
        #expect(stream.cues[0].end == 12)
    }

    @Test func newObjectDefinitionEndsThePreviousCue() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 900)
        let bytes = PGSBuilder.displaySet(pts: 10, objects: [(object, width: 100, height: 10, color: 1)])
            + PGSBuilder.displaySet(pts: 11, objects: [(object, width: 100, height: 10, color: 2)])
            + PGSBuilder.clear(pts: 13)
        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.map(\.start) == [10, 11])
        #expect(stream.cues.map(\.end) == [11, 13])
    }

    @Test func acquisitionPointRepeatsDoNotDuplicateCues() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 900)
        let bytes = PGSBuilder.displaySet(pts: 10, objects: [(object, width: 100, height: 10, color: 1)])
            + PGSBuilder.displaySet(pts: 10.5, state: 0x40, objects: [(object, width: 100, height: 10, color: 1)])
            + PGSBuilder.clear(pts: 12)
        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 1)
        #expect(stream.cues[0].end == 12)
    }

    @Test func lastCueWithoutClearHasNoEnd() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 900)
        let bytes = PGSBuilder.displaySet(pts: 10, objects: [(object, width: 100, height: 10, color: 1)])
        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 1)
        #expect(stream.cues[0].end == nil)
    }

    @Test func usesThePaletteReferencedByTheComposition() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 0)
        var bytes = PGSBuilder.pcs(pts: 10, state: 0x80, paletteID: 1, objects: [object])
        bytes += PGSBuilder.pds(pts: 10, id: 0, entries: [(1, 235, 128, 128, 255)]) // white
        bytes += PGSBuilder.pds(pts: 10, id: 1, entries: [(1, 16, 128, 128, 255)])  // black
        bytes += PGSBuilder.ods(pts: 10, id: 0, width: 4, height: 2, color: 1)
        bytes += PGSBuilder.end(pts: 10)

        let stream = try PGSStream(data: Data(bytes))
        let bitmap = try #require(try stream.bitmap(at: 0))
        let color = bitmap.rgba(ofIndex: 1)
        #expect(color.r < 40 && color.g < 40 && color.b < 40)
        #expect(color.a == 255)
    }

    @Test func decodesFragmentedObjects() throws {
        let object = PGSBuilder.Object(id: 0, x: 0, y: 0)
        let rle = PGSBuilder.rleRectangle(width: 8, height: 4, color: 2)
        let split = rle.count / 2
        var bytes = PGSBuilder.pcs(pts: 10, state: 0x80, objects: [object])
        bytes += PGSBuilder.pds(pts: 10, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 10, id: 0, width: 8, height: 4, rle: Array(rle[..<split]), sequence: 0x80)
        // Continuation segments carry only object id, version, flag, then data.
        var continuation: [UInt8] = [0, 0, 0, 0x40]
        continuation += rle[split...]
        bytes += PGSBuilder.segment(type: 0x15, pts: 10, payload: continuation)
        bytes += PGSBuilder.end(pts: 10)

        let stream = try PGSStream(data: Data(bytes))
        let bitmap = try #require(try stream.bitmap(at: 0))
        #expect(bitmap.width == 8 && bitmap.height == 4)
        #expect(bitmap.pixels.allSatisfy { $0 == 2 })
    }

    @Test func rleDecodesAllRunKinds() throws {
        // Line 1: 3 zeros (short), 2 × color 1 (short), a literal pixel 5, end of line.
        // Line 2: 70 × color 2 (long form), end of line.
        var rle: [UInt8] = []
        rle += PGSBuilder.rleRun(color: 0, length: 3)
        rle += PGSBuilder.rleRun(color: 1, length: 2)
        rle += [5]
        rle += [0x00, 0x00]
        rle += PGSBuilder.rleRun(color: 2, length: 70)
        rle += [0x00, 0x00]
        let decoded = PGSRLE.decode(rle, width: 70, height: 2)
        #expect(decoded.complete)
        #expect(Array(decoded.pixels[0..<6]) == [0, 0, 0, 1, 1, 5])
        #expect(decoded.pixels[70...].allSatisfy { $0 == 2 })
    }
}
