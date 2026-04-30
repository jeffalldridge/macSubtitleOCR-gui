import Testing
import Foundation
@testable import macSubtitleOCR_gui

@Suite struct TrackProberTests {
    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        // Fallback: read from the test source tree
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    @Test func parsesPGSAndVobSubFromMkvmergeJSON() throws {
        let data = try fixture("mkvmerge-three-pgs")
        let tracks = try TrackProber.parseMkvmergeJSON(data)
        #expect(tracks.count == 3)
        #expect(tracks[0].id == 2 && tracks[0].codec == .pgs && tracks[0].language == "eng")
        #expect(tracks[1].id == 3 && tracks[1].codec == .pgs && tracks[1].language == "spa")
        #expect(tracks[2].id == 4 && tracks[2].codec == .vobsub && tracks[2].language == "fra")
    }

    @Test func ignoresVideoAndAudioTracks() throws {
        let data = try fixture("mkvmerge-three-pgs")
        let tracks = try TrackProber.parseMkvmergeJSON(data)
        #expect(!tracks.contains { $0.id == 0 || $0.id == 1 })
    }

    @Test func emptyForFileWithNoSubs() throws {
        let json = #"{"tracks":[{"id":0,"type":"video","codec":"x","properties":{}}]}"#
        let tracks = try TrackProber.parseMkvmergeJSON(Data(json.utf8))
        #expect(tracks.isEmpty)
    }

    @Test func parsesDefaultAndForcedFlags() throws {
        let json = """
        {"tracks":[{"id":7,"type":"subtitles","codec":"SubRip/SRT","properties":{"language":"eng"}},{"id":8,"type":"subtitles","codec":"HDMV PGS","properties":{"language":"eng","default_track":true,"forced_track":true}}]}
        """
        let tracks = try TrackProber.parseMkvmergeJSON(Data(json.utf8))
        #expect(tracks.count == 1)
        #expect(tracks[0].id == 8)
        #expect(tracks[0].isDefault)
        #expect(tracks[0].isForced)
    }

    @Test func syntheticTrackForSupInput() {
        let url = URL(fileURLWithPath: "/tmp/movie.sup")
        let tracks = TrackProber.syntheticTracks(for: url)
        #expect(tracks.count == 1)
        #expect(tracks[0].codec == .pgs)
    }

    @Test func syntheticTrackForSubIdxInput() {
        let url = URL(fileURLWithPath: "/tmp/movie.idx")
        let tracks = TrackProber.syntheticTracks(for: url)
        #expect(tracks.count == 1)
        #expect(tracks[0].codec == .vobsub)
    }
}
