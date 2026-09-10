import Foundation
import Testing
@testable import SubtitleEngine

@Suite struct SubtitleSourceTests {
    @Test func opensEachSupportedType() throws {
        #expect(try SubtitleSource.open(Fixtures.sintelMKS) == .mkv(Fixtures.sintelMKS))
        #expect(try SubtitleSource.open(Fixtures.sintelSUP) == .pgs(Fixtures.sintelSUP))
        #expect(try SubtitleSource.open(Fixtures.sintelSUB) == .vobsub(sub: Fixtures.sintelSUB, idx: Fixtures.sintelIDX))
        #expect(try SubtitleSource.open(Fixtures.sintelIDX) == .vobsub(sub: Fixtures.sintelSUB, idx: Fixtures.sintelIDX))
    }

    @Test func extensionsAreCaseInsensitive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("Movie.SUB")
        let idx = dir.appendingPathComponent("Movie.IDX")
        try Data().write(to: sub)
        try Data().write(to: idx)
        #expect(try SubtitleSource.open(sub) == .vobsub(sub: sub, idx: idx))
    }

    @Test func missingCompanionThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("Lonely.sub")
        try Data().write(to: sub)
        #expect(throws: EngineError.missingCompanionFile(expected: dir.appendingPathComponent("Lonely.idx"))) {
            _ = try SubtitleSource.open(sub)
        }
    }

    @Test func unsupportedExtensionThrows() {
        #expect(throws: EngineError.unsupportedFileType("mp4")) {
            _ = try SubtitleSource.open(URL(fileURLWithPath: "/tmp/movie.mp4"))
        }
    }

    @Test func standaloneProbesProduceOneTrack() throws {
        let pgs = try SubtitleSource.open(Fixtures.sintelSUP).probe()
        #expect(pgs.tracks.count == 1)
        #expect(pgs.tracks[0].id == 1)
        #expect(pgs.tracks[0].format == .pgs)
        #expect(pgs.tracks[0].language == nil)
        #expect(pgs.tracks[0].isDefault)

        let vobsub = try SubtitleSource.open(Fixtures.sintelIDX).probe()
        #expect(vobsub.tracks.count == 1)
        #expect(vobsub.tracks[0].format == .vobsub)
        #expect(vobsub.tracks[0].language == "en")
    }

    @Test func containerProbeDelegatesToMKVReader() throws {
        let info = try SubtitleSource.open(Fixtures.sintelMKS).probe()
        #expect(info.tracks.count == 2)
        #expect(info.duration != nil)
    }

    @Test func loadsAStreamForEverySource() throws {
        for url in [Fixtures.sintelMKS, Fixtures.sintelSUP, Fixtures.sintelSUB] {
            let source = try SubtitleSource.open(url)
            let info = try source.probe()
            for track in info.tracks {
                let stream = try source.loadStream(for: track, progress: nil)
                #expect(stream.cues.count == 26, "\(url.lastPathComponent) track \(track.id)")
                #expect(stream.format == track.format)
            }
        }
    }

    @Test func primaryURLAndDisplayName() throws {
        #expect(try SubtitleSource.open(Fixtures.sintelIDX).primaryURL == Fixtures.sintelSUB)
        #expect(try SubtitleSource.open(Fixtures.sintelMKS).displayName == "sintel.mks")
        #expect(try SubtitleSource.open(Fixtures.sintelIDX).displayName == "sintel.sub")
    }
}
