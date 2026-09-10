import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct MKVReaderTests {
    @Test func probesSintelTracks() throws {
        let reader = try MKVReader(url: Fixtures.sintelMKS)
        let info = try reader.probe()

        #expect(info.tracks.count == 2)

        let pgs = try #require(info.tracks.first)
        #expect(pgs.id == 1)
        #expect(pgs.format == .pgs)
        #expect(pgs.codecID == "S_HDMV/PGS")
        #expect(pgs.language == "eng")
        #expect(pgs.name == nil)
        #expect(pgs.isDefault == true, "FlagDefault is absent, and the spec default is 1")
        #expect(pgs.isForced == false)

        let vobsub = try #require(info.tracks.last)
        #expect(vobsub.id == 2)
        #expect(vobsub.format == .vobsub)
        #expect(vobsub.language == "eng")
        #expect(vobsub.isDefault == false)
        #expect(vobsub.codecPrivate?.count == 136)
        #expect(info.otherSubtitleCodecs.isEmpty)
    }

    @Test func readsDurationAndScale() throws {
        let info = try MKVReader(url: Fixtures.sintelMKS).probe()
        #expect(info.timestampScale == 1_000_000)
        let duration = try #require(info.duration)
        #expect(abs(duration - 629.813) < 0.001)
        #expect(info.title == nil)
    }

    @Test func rejectsNonMatroska() throws {
        #expect(throws: EngineError.notMatroska(Fixtures.sintelSUP)) {
            _ = try MKVReader(url: Fixtures.sintelSUP)
        }
    }

    @Test func missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mkv")
        #expect(throws: EngineError.fileNotFound(url)) {
            _ = try MKVReader(url: url)
        }
    }

    @Test func readsNamesFlagsAndOtherCodecs() throws {
        let data = EBMLBuilder.file([
            EBMLBuilder.info(duration: 1000, title: "Sintel"),
            EBMLBuilder.tracks([
                EBMLBuilder.subtitleTrack(number: 3, codec: "S_HDMV/PGS", language: "eng", name: "English SDH",
                                          isDefault: false, isForced: true,
                                          extra: [EBMLBuilder.string(0x22B5_9D, "en-US")]),
                EBMLBuilder.subtitleTrack(number: 4, codec: "S_TEXT/UTF8", language: "spa"),
                EBMLBuilder.subtitleTrack(number: 5, codec: "S_VOBSUB", language: "jpn", codecPrivate: [1, 2, 3]),
                // A video track must be ignored.
                EBMLBuilder.element(0xAE, [
                    EBMLBuilder.uint(0xD7, 1), EBMLBuilder.uint(0x83, 1), EBMLBuilder.string(0x86, "V_MPEG4/ISO/AVC"),
                ]),
            ]),
        ])
        let info = try MKVReader(data: data, url: URL(fileURLWithPath: "/synthetic.mkv")).probe()

        #expect(info.title == "Sintel")
        #expect(info.duration == 1.0)
        #expect(info.tracks.map(\.id) == [3, 5])
        #expect(info.otherSubtitleCodecs == ["S_TEXT/UTF8"])

        let sdh = info.tracks[0]
        #expect(sdh.name == "English SDH")
        #expect(sdh.isDefault == false)
        #expect(sdh.isForced == true)
        #expect(sdh.languageBCP47 == "en-US")

        let jpn = info.tracks[1]
        #expect(jpn.language == "jpn")
        #expect(jpn.codecPrivate == Data([1, 2, 3]))
    }

    @Test func findsTracksAfterAClusterAndWithUnknownSizes() throws {
        // Tracks placed after a cluster, inside an unknown-size Segment.
        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.cluster(timestamp: 0, blocks: [
                EBMLBuilder.simpleBlock(track: 1, relativeTimestamp: 0, payload: [0xAA, 0xBB]),
            ], unknownSize: true),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
        ], unknownSizeSegment: true)
        let info = try MKVReader(data: data, url: URL(fileURLWithPath: "/synthetic.mkv")).probe()
        #expect(info.tracks.count == 1)
        #expect(info.tracks[0].id == 1)
    }

    @Test func fileWithoutTracksThrows() throws {
        let data = EBMLBuilder.file([EBMLBuilder.info()])
        #expect(throws: EngineError.noTracksElement) {
            _ = try MKVReader(data: data, url: URL(fileURLWithPath: "/synthetic.mkv")).probe()
        }
    }
}
