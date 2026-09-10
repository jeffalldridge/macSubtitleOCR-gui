import Foundation
import Testing
@testable import SubtitleEngine

/// These parsers read files off the internet and off discs. Malformed input
/// must produce an error or an empty result — never a trap, a hang, or a read
/// past the end of a buffer.
@Suite struct MalformedInputTests {
    /// Deterministic pseudo-random bytes, so a failure is reproducible.
    private func noise(seed: UInt64, count: Int) -> Data {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        return Data(bytes)
    }

    // MARK: - PGS

    @Test func pgsSurvivesTruncationAtEveryLength() throws {
        let full = try Data(contentsOf: Fixtures.sintelSUP)
        // Step through the file cutting it at many points, including inside
        // segment headers and inside run-length data.
        for cut in stride(from: 0, to: min(full.count, 40000), by: 617) {
            let stream = try? PGSStream(data: full.prefix(cut))
            guard let stream else { continue }
            for index in stream.cues.indices {
                _ = try? stream.bitmap(at: index)
            }
        }
    }

    @Test func pgsSurvivesCorruptedBytes() throws {
        let full = try Data(contentsOf: Fixtures.sintelSUP)
        for seed in UInt64(1)...12 {
            var corrupted = Array(full.prefix(60000))
            let damage = noise(seed: seed, count: 400)
            for (i, byte) in damage.enumerated() {
                let position = Int(UInt64(i) &* 6151 &+ seed &* 97) % corrupted.count
                corrupted[position] = byte
            }
            guard let stream = try? PGSStream(data: Data(corrupted)) else { continue }
            for index in stream.cues.indices {
                _ = try? stream.bitmap(at: index)
            }
        }
    }

    @Test func pgsRejectsNoise() {
        for seed in UInt64(1)...5 {
            #expect(throws: EngineError.self) {
                _ = try PGSStream(data: noise(seed: seed, count: 5000))
            }
        }
    }

    @Test func pgsHandlesEmptyAndTinyInput() throws {
        #expect(try PGSStream(data: Data()).cues.isEmpty)
        #expect(try PGSStream(data: Data([0x50, 0x47])).cues.isEmpty)
    }

    @Test func pgsHandlesAbsurdDimensions() throws {
        // An object claiming 65535 x 65535 with almost no data must not
        // allocate wildly or hang; it decodes to an incomplete bitmap.
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.pds(pts: 1, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 65535, height: 65535, rle: [0x00, 0x00], sequence: 0xC0)
        bytes += PGSBuilder.end(pts: 1)
        let stream = try PGSStream(data: Data(bytes))
        #expect(stream.cues.count == 1)
        _ = try? stream.bitmap(at: 0)
    }

    @Test func pgsHandlesZeroSizedObjects() throws {
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.pds(pts: 1, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 0, height: 0, rle: [], sequence: 0xC0)
        bytes += PGSBuilder.end(pts: 1)
        let stream = try PGSStream(data: Data(bytes))
        #expect(try stream.bitmap(at: 0) == nil)
    }

    @Test func pgsCompositionReferencingAMissingObjectIsEmpty() throws {
        var bytes = PGSBuilder.pcs(pts: 1, state: 0x80, objects: [PGSBuilder.Object(id: 9, x: 0, y: 0)])
        bytes += PGSBuilder.pds(pts: 1, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: 1, id: 0, width: 4, height: 2, color: 1)
        bytes += PGSBuilder.end(pts: 1)
        let stream = try PGSStream(data: Data(bytes))
        #expect(try stream.bitmap(at: 0) == nil, "the referenced object does not exist")
    }

    // MARK: - VobSub

    @Test func vobSubSurvivesTruncation() throws {
        let sub = try Data(contentsOf: Fixtures.sintelSUB)
        let idx = try String(contentsOf: Fixtures.sintelIDX, encoding: .utf8)
        for cut in stride(from: 0, to: min(sub.count, 40000), by: 811) {
            guard let stream = try? VobSubStream(sub: sub.prefix(cut), idx: idx) else { continue }
            for index in stream.cues.indices {
                _ = try? stream.bitmap(at: index)
            }
        }
    }

    @Test func vobSubSurvivesCorruptedBytes() throws {
        let original = try Data(contentsOf: Fixtures.sintelSUB)
        let idx = try String(contentsOf: Fixtures.sintelIDX, encoding: .utf8)
        for seed in UInt64(1)...12 {
            var corrupted = Array(original)
            let damage = noise(seed: seed, count: 500)
            for (i, byte) in damage.enumerated() {
                corrupted[Int(UInt64(i) &* 4211 &+ seed &* 131) % corrupted.count] = byte
            }
            guard let stream = try? VobSubStream(sub: Data(corrupted), idx: idx) else { continue }
            for index in stream.cues.indices {
                _ = try? stream.bitmap(at: index)
            }
        }
    }

    @Test func vobSubHandlesOffsetsPastTheEnd() throws {
        let idx = """
        # VobSub index file, v7 (do not modify this line!)
        id: en, index: 0
        timestamp: 00:00:01:000, filepos: 0FFFFFFF
        timestamp: 00:00:02:000, filepos: 000000000
        """
        let stream = try VobSubStream(sub: Data(repeating: 0, count: 64), idx: idx)
        #expect(!stream.warnings.isEmpty)
        for index in stream.cues.indices { _ = try? stream.bitmap(at: index) }
    }

    @Test func vobSubHandlesGarbageIndexText() throws {
        let stream = try VobSubStream(sub: noise(seed: 7, count: 4096), idx: "not an index file at all\n\n\n")
        #expect(stream.cues.isEmpty)
    }

    // MARK: - Matroska

    @Test func matroskaRejectsNoise() {
        for seed in UInt64(1)...5 {
            #expect(throws: EngineError.self) {
                _ = try MKVReader(data: noise(seed: seed, count: 8000), url: URL(fileURLWithPath: "/n.mkv"))
            }
        }
    }

    @Test func matroskaSurvivesTruncation() throws {
        let full = try Data(contentsOf: Fixtures.sintelMKS)
        for cut in stride(from: 0, to: min(full.count, 60000), by: 907) {
            guard let reader = try? MKVReader(data: full.prefix(cut), url: URL(fileURLWithPath: "/t.mkv")) else { continue }
            guard let info = try? reader.probe() else { continue }
            for track in info.tracks {
                _ = try? reader.extract(trackNumber: track.id)
            }
        }
    }

    @Test func matroskaSurvivesCorruptedBytes() throws {
        let original = try Data(contentsOf: Fixtures.sintelMKS)
        for seed in UInt64(1)...12 {
            var corrupted = Array(original)
            let damage = noise(seed: seed, count: 300)
            for (i, byte) in damage.enumerated() {
                // Leave the EBML header intact so the file still opens.
                let position = 64 + Int(UInt64(i) &* 3571 &+ seed &* 89) % (corrupted.count - 64)
                corrupted[position] = byte
            }
            guard let reader = try? MKVReader(data: Data(corrupted), url: URL(fileURLWithPath: "/c.mkv")),
                  let info = try? reader.probe() else { continue }
            for track in info.tracks {
                _ = try? reader.extract(trackNumber: track.id)
            }
        }
    }

    @Test func matroskaHandlesAnElementClaimingAHugeSize() throws {
        // A Tracks element whose declared size runs past the end of the file.
        var bytes = EBMLBuilder.matroskaHeader()
        bytes += EBMLBuilder.idBytes(0x1853_8067) + EBMLBuilder.sizeBytes(0x00FF_FFFF)
        bytes += EBMLBuilder.info()
        bytes += EBMLBuilder.idBytes(0x1654_AE6B) + EBMLBuilder.sizeBytes(0x000F_FFFF)
        bytes += EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")
        let reader = try MKVReader(data: Data(bytes), url: URL(fileURLWithPath: "/h.mkv"))
        let info = try reader.probe()
        #expect(info.tracks.count == 1)
        _ = try? reader.extract(trackNumber: 1)
    }

    @Test func matroskaHandlesZeroSizedAndEmptyElements() throws {
        let bytes = EBMLBuilder.file([
            EBMLBuilder.element(0x1549_A966, [] as [UInt8]),
            EBMLBuilder.tracks([
                EBMLBuilder.element(0xAE, [] as [UInt8]),
                EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS"),
            ]),
            EBMLBuilder.cluster(timestamp: 0, blocks: [EBMLBuilder.element(0xA3, [] as [UInt8])]),
        ])
        let reader = try MKVReader(data: bytes, url: URL(fileURLWithPath: "/z.mkv"))
        #expect(try reader.probe().tracks.count == 1)
        _ = try? reader.extract(trackNumber: 1)
    }

    @Test func matroskaWithSelfReferentialUnknownSizesTerminates() throws {
        // Nested unknown-size clusters: the walk must still finish.
        var children: [[UInt8]] = [EBMLBuilder.info(),
                                   EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")])]
        for _ in 0..<50 {
            children.append(EBMLBuilder.cluster(timestamp: 0, blocks: [], unknownSize: true))
        }
        let data = EBMLBuilder.file(children, unknownSizeSegment: true)
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/u.mkv"))
        #expect(try reader.probe().tracks.count == 1)
        _ = try? reader.extract(trackNumber: 1)
    }

    // MARK: - SRT

    @Test func srtParserSurvivesGarbage() {
        for seed in UInt64(1)...8 {
            let text = String(decoding: noise(seed: seed, count: 4000), as: UTF8.self)
            _ = SRTFile.parse(text)
        }
        _ = SRTFile.parse("1\n99:99:99,999 --> not a time\ntext\n\n")
        _ = SRTFile.parse("-->\n\n-->\n\n")
        _ = SRTFile.parse(String(repeating: "\n", count: 10000))
    }

    @Test func srtTimingHandlesUnsortedAndIdenticalStarts() {
        let ends = SRTTiming.resolveEnds(starts: [10, 10, 5], ends: [nil, nil, nil])
        #expect(ends.count == 3)
        for (start, end) in zip([10.0, 10.0, 5.0], ends) {
            #expect(end > start, "every cue keeps a positive duration")
        }
    }

    @Test func srtTimingHandlesAnEmptyTrack() {
        #expect(SRTTiming.resolveEnds(starts: [], ends: []).isEmpty)
    }
}
