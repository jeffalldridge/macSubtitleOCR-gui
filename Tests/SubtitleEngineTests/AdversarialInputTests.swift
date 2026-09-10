import zlib
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

/// Matroska lets a track compress its frames, and remuxers routinely deflate
/// subtitles. Missing that produced a track with no subtitles at all and no
/// error to explain it.
@Suite struct ContentCompressionTests {
    @Test func inflatesAZlibStream() throws {
        let original = Data("PGS subtitle payload, repeated. ".utf8.map { $0 } * 40)
        let compressed = try #require(zlibCompress(original))
        #expect(compressed.first == 0x78, "a real zlib stream, header and all")
        #expect(ContentCompression.zlib.decode(compressed) == original)
    }

    @Test func headerStrippingPutsThePrefixBack() {
        let stripped = Data([0x03, 0x04])
        let compression = ContentCompression.headerStripping(Data([0x01, 0x02]))
        #expect(compression.decode(stripped) == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test func noCompressionIsAPassThrough() {
        let frame = Data([1, 2, 3])
        #expect(ContentCompression.none.decode(frame) == frame)
        #expect(ContentCompression.none.isIdentity)
    }

    @Test func garbageInflatesToNothingRatherThanCrashing() {
        #expect(ContentCompression.zlib.decode(Data([0x78, 0xDA, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(ContentCompression.zlib.decode(Data()) == nil)
        #expect(ContentCompression.zlib.decode(Data([0x78])) == nil)
    }

    @Test func aCompressedTrackIsReadEndToEnd() throws {
        // A PGS display set, deflated exactly as a remuxer would store it.
        func segment(_ type: UInt8, _ body: [UInt8]) -> [UInt8] {
            [type, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
        }
        let pcs = segment(0x16, [0x07, 0x80, 0x04, 0x38, 0x10, 0x00, 0x01, 0x80,
                                 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0, 0])
        let pds = segment(0x14, [0x00, 0x00, 0x01, 235, 128, 128, 255])
        var rle: [UInt8] = []
        for _ in 0..<2 { rle += [0x00, 0x84, 0x01, 0x00, 0x00] }
        let dataLength = UInt32(rle.count + 4)
        let ods = segment(0x15, [0x00, 0x00, 0x00, 0xC0,
                                 UInt8((dataLength >> 16) & 0xFF),
                                 UInt8((dataLength >> 8) & 0xFF),
                                 UInt8(dataLength & 0xFF),
                                 0x00, 0x04, 0x00, 0x02] + rle)
        let plain = Data(pcs + pds + ods + segment(0x80, []))
        let deflated = try #require(zlibCompress(plain))

        // ContentEncodings declaring zlib on frame data.
        let compression = EBMLBuilder.element(0x5034, EBMLBuilder.uint(0x4254, 0))
        let encoding = EBMLBuilder.element(0x6240,
                                           EBMLBuilder.uint(0x5032, 1) + EBMLBuilder.uint(0x5033, 0) + compression)
        let encodings = EBMLBuilder.element(0x6D80, encoding)

        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([
                EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS", extra: [encodings]),
            ]),
            EBMLBuilder.cluster(timestamp: 0, blocks: [
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 0, payload: Array(deflated)),
            ]),
        ])

        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/compressed.mkv"))
        guard case .pgs(let extracted) = try reader.extract(trackNumber: 1) else {
            Issue.record("expected PGS")
            return
        }
        let stream = try PGSStream(data: extracted)
        #expect(stream.cues.count == 1, "the frame was inflated before it reached the decoder")
        #expect(try stream.bitmap(at: 0) != nil)
    }

    @Test func anEncryptedTrackIsReportedRatherThanReturnedEmpty() throws {
        // ContentEncodingType 1 is encryption; nothing can be decoded.
        let encoding = EBMLBuilder.element(0x6240,
                                           EBMLBuilder.uint(0x5032, 1) + EBMLBuilder.uint(0x5033, 1))
        let encodings = EBMLBuilder.element(0x6D80, encoding)
        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([
                EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS", extra: [encodings]),
            ]),
        ])
        let info = try MKVReader(data: data, url: URL(fileURLWithPath: "/enc.mkv")).probe()
        #expect(info.tracks.isEmpty, "not offered as something we can convert")
        #expect(info.otherSubtitleCodecs == ["S_HDMV/PGS"])
    }
}

/// Deflate with a zlib header, the way a muxer writes it.
private func zlibCompress(_ data: Data) -> Data? {
    var stream = z_stream()
    guard deflateInit_(&stream, 6, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
    defer { deflateEnd(&stream) }
    var output = Data(count: data.count * 2 + 64)
    let produced: Int? = data.withUnsafeBytes { source -> Int? in
        output.withUnsafeMutableBytes { destination -> Int? in
            guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress,
                  let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: sourceBase)
            stream.avail_in = uInt(data.count)
            stream.next_out = destinationBase
            stream.avail_out = uInt(destination.count)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return nil }
            return destination.count - Int(stream.avail_out)
        }
    }
    guard let produced else { return nil }
    output.removeSubrange(produced...)
    return output
}

private func * (lhs: [UInt8], rhs: Int) -> [UInt8] {
    Array(repeating: lhs, count: rhs).flatMap { $0 }
}
