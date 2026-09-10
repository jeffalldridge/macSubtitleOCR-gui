import Foundation
import Testing
@testable import SubtitleEngine

/// Input crafted to break the parsers, as opposed to the random corruption in
/// `MalformedInputTests`. Every case here crashed or exhausted memory at some
/// point; each must now fail politely instead.
@Suite struct AdversarialInputTests {
    // MARK: - EBML structure

    @Test func deeplyNestedUnknownSizeElementsDoNotOverflowTheStack() throws {
        // Each nesting level costs two bytes: a one-byte ID that is not a
        // segment-level terminator, and the all-ones size marker.
        var bytes = EBMLBuilder.matroskaHeader()
        bytes += EBMLBuilder.idBytes(MatroskaID.segment) + [0xFF]
        bytes += EBMLBuilder.idBytes(MatroskaID.cluster) + [0xFF]
        bytes += [UInt8](repeating: 0, count: 0)
        for _ in 0..<120_000 { bytes += [0xFE, 0xFF] }

        let reader = try MKVReader(data: Data(bytes), url: URL(fileURLWithPath: "/deep.mkv"))
        // No Tracks element, so this must report that rather than crash.
        #expect(throws: EngineError.noTracksElement) { _ = try reader.probe() }
    }

    @Test func hugeTrackNumberIsRejected() throws {
        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([
                EBMLBuilder.element(0xAE, [
                    EBMLBuilder.element(0xD7, [UInt8](repeating: 0xFF, count: 8)),
                    EBMLBuilder.uint(0x83, 17),
                    EBMLBuilder.string(0x86, "S_HDMV/PGS"),
                ]),
                EBMLBuilder.subtitleTrack(number: 2, codec: "S_HDMV/PGS"),
            ]),
        ])
        let info = try MKVReader(data: data, url: URL(fileURLWithPath: "/big.mkv")).probe()
        #expect(info.tracks.map(\.id) == [2], "an unrepresentable track number is skipped, not fatal")
    }

    @Test func hugeClusterTimestampDoesNotTrap() throws {
        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
            EBMLBuilder.element(MatroskaID.cluster, [
                EBMLBuilder.element(0xE7, [UInt8](repeating: 0xFF, count: 8)),
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 0, payload: [0x16, 0x00, 0x00]),
            ]),
        ])
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/ts.mkv"))
        _ = try reader.extract(trackNumber: 1)
    }

    @Test func hugeTimestampScaleDoesNotTrap() throws {
        let data = EBMLBuilder.file([
            EBMLBuilder.element(MatroskaID.info, [
                EBMLBuilder.element(0x2AD7_B1, [UInt8](repeating: 0xFF, count: 8)),
            ]),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
            EBMLBuilder.cluster(timestamp: 1, blocks: [
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 1, payload: [0x16, 0x00, 0x00]),
            ]),
        ])
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/scale.mkv"))
        let info = try reader.probe()
        #expect(info.timestampScale > 0)
        _ = try reader.extract(trackNumber: 1)
    }

    @Test func infoAfterTracksIsStillRead() throws {
        // Matroska does not require Info before Tracks. Missing it would leave
        // the timestamp scale wrong, and every extracted timing with it.
        let data = EBMLBuilder.file([
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
            EBMLBuilder.info(timestampScale: 10_000_000, duration: 500, title: "Late Info"),
        ])
        let info = try MKVReader(data: data, url: URL(fileURLWithPath: "/order.mkv")).probe()
        #expect(info.tracks.count == 1)
        #expect(info.timestampScale == 10_000_000)
        #expect(info.title == "Late Info")
        #expect(info.duration == 5.0)
    }

    @Test func aChildCannotRunPastItsParent() throws {
        // Tracks declares 10 bytes but holds a TrackEntry declaring far more.
        // The entry must be clamped, not parsed across unrelated file data.
        var trailing = EBMLBuilder.uint(0xD7, 7)
        trailing += EBMLBuilder.uint(0x83, 17)
        trailing += EBMLBuilder.string(0x86, "S_HDMV/PGS")
        var tracksPayload = EBMLBuilder.idBytes(0xAE) + EBMLBuilder.sizeBytes(0x0F_FFFF)
        tracksPayload += Array(trailing.prefix(4))
        let inner = Array(trailing.dropFirst(4))

        var bytes = EBMLBuilder.matroskaHeader()
        var segment = EBMLBuilder.idBytes(MatroskaID.tracks) + EBMLBuilder.sizeBytes(tracksPayload.count)
        segment += tracksPayload
        segment += inner
        bytes += EBMLBuilder.idBytes(MatroskaID.segment) + EBMLBuilder.sizeBytes(segment.count) + segment

        let info = try MKVReader(data: Data(bytes), url: URL(fileURLWithPath: "/clamp.mkv")).probe()
        #expect(info.tracks.isEmpty, "the truncated entry has no codec, so it is not a bitmap track")
    }

    // MARK: - PGS resource limits

    @Test func absurdObjectDimensionsAreRejectedWithoutAllocating() throws {
        // A 92-byte file must not turn into a multi-gigabyte allocation.
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.pds(pts: 1, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 65535, height: 65535, rle: [0x00, 0x00], sequence: 0xC0)
        bytes += PGSBuilder.end(pts: 1)

        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 1)
        let started = Date()
        #expect(try stream.bitmap(at: 0) == nil, "beyond any real video frame, so there is nothing to decode")
        #expect(Date().timeIntervalSince(started) < 1, "and it must fail immediately")
    }

    @Test func objectsUpToAUHDFrameAreStillAccepted() throws {
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)],
                                   width: 3840, height: 2160)
        bytes += PGSBuilder.pds(pts: 1, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 3840, height: 200, color: 1)
        bytes += PGSBuilder.end(pts: 1)
        let stream = try PGSStream(data: Data(bytes))
        let bitmap = try #require(try stream.bitmap(at: 0))
        #expect(bitmap.width == 3840 && bitmap.height == 200)
    }

    // MARK: - PGS display-set handling

    @Test func aCueWithNoPaletteIsBlankRatherThanFatal() throws {
        // Legal PGS can define a palette in an earlier display set of the same
        // epoch. Losing one cue must not lose the whole track.
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 8, height: 4, color: 1)
        bytes += PGSBuilder.end(pts: 1)
        bytes += PGSBuilder.clear(pts: 3)
        bytes += PGSBuilder.displaySet(pts: 4, objects: [
            (PGSBuilder.Object(id: 0, x: 0, y: 0), width: 8, height: 4, color: 1),
        ])
        bytes += PGSBuilder.clear(pts: 6)

        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 2)
        #expect(try stream.bitmap(at: 0) == nil, "no palette: blank, not an error")
        #expect(try stream.bitmap(at: 1) != nil, "the rest of the track still decodes")
    }

    @Test func oneUndecodableCueDoesNotAbortTheRun() async throws {
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 8, height: 4, color: 1)
        bytes += PGSBuilder.end(pts: 1)
        bytes += PGSBuilder.clear(pts: 3)
        bytes += PGSBuilder.displaySet(pts: 4, objects: [
            (PGSBuilder.Object(id: 0, x: 0, y: 0), width: 40, height: 20, color: 1),
        ])
        bytes += PGSBuilder.clear(pts: 6)

        let stream = try PGSStream(data: Data(bytes))
        var finished: [RecognizedCue]?
        for try await event in TrackConverter.run(stream: stream, options: RecognitionOptions()) {
            if case .finished(let cues) = event { finished = cues }
        }
        let cues = try #require(finished, "the run completes instead of throwing")
        #expect(cues.count == 2)
        #expect(cues[0].hadBitmap == false)
    }

    @Test func aDisplaySetReusingAnEarlierObjectStillShows() throws {
        // Draw an object, clear it, then re-present the same object id without
        // redefining it. That second appearance is a real cue.
        var bytes = PGSBuilder.displaySet(pts: 1, objects: [
            (PGSBuilder.Object(id: 0, x: 0, y: 0), width: 8, height: 4, color: 1),
        ])
        bytes += PGSBuilder.clear(pts: 2)
        bytes += PGSBuilder.pcs(pts: 3, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.end(pts: 3)
        bytes += PGSBuilder.clear(pts: 4)

        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.map(\.start) == [1, 3])
        #expect(stream.cues.map(\.end) == [2, 4])
    }

    // MARK: - Timestamps

    @Test func nonFiniteIDXTimestampsAreIgnored() throws {
        // "inf" and "nan" both parse as Double.
        let idx = """
        # VobSub index file, v7 (do not modify this line!)
        id: en, index: 0
        timestamp: inf:00:00:000, filepos: 000000000
        timestamp: nan:00:00:000, filepos: 000000000
        timestamp: 00:00:01:000, filepos: 000000000
        """
        let parsed = try VobSubIDX(text: idx)
        #expect(parsed.entries.count == 1, "only the real timestamp survives")
        #expect(parsed.entries[0].timestamp == 1)
    }

    @Test func srtRenderingSurvivesNonFiniteAndHugeTimes() {
        #expect(SRTFile.timestamp(.infinity).hasPrefix("99:"))
        #expect(SRTFile.timestamp(.nan) == "00:00:00,000")
        #expect(SRTFile.timestamp(-.infinity) == "00:00:00,000")
        #expect(SRTFile.timestamp(1e18).hasPrefix("99:"))
        let rendered = SRTFile.render([SRTCue(index: 1, start: .infinity, end: .nan, text: "x")])
        #expect(rendered.contains("-->"))
    }

    @Test func srtParsingSurvivesEnormousComponents() {
        #expect(SRTFile.parseTimestamp("9223372036854775807:00:00,000") == nil)
        #expect(SRTFile.parseTimestamp("99999999999999999999:00:00,000") == nil)
        let cues = SRTFile.parse("1\n9223372036854775807:00:00,000 --> 00:00:05,000\ntext\n\n")
        #expect(cues.isEmpty)
    }

    @Test func srtTimingSurvivesNonFiniteStarts() {
        let ends = SRTTiming.resolveEnds(starts: [.infinity, .nan, 5], ends: [nil, nil, nil])
        #expect(ends.count == 3)
        #expect(ends.allSatisfy { $0.isFinite })
    }
}
