import Foundation
import SubtitleEngine
import Testing
@testable import macSubtitleOCR_gui

/// Reading a container must never run on the main actor. It did once: a
/// `Task { }` inside this main-actor-isolated code inherited that isolation
/// and froze the window for the length of the read.
@Suite(.serialized) struct MainActorResponsivenessTests {
    // A minimal Matroska writer. The engine tests have a fuller one, but it
    // lives in the other test target.
    private enum MKV {
        static func id(_ value: UInt32) -> [UInt8] {
            var bytes: [UInt8] = []
            var v = value
            while v > 0 {
                bytes.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
            return bytes.isEmpty ? [0] : bytes
        }

        static func size(_ value: Int) -> [UInt8] {
            var length = 1
            while value >= (1 << (7 * length)) - 1 { length += 1 }
            var bytes = [UInt8](repeating: 0, count: length)
            var v = UInt64(value)
            for i in stride(from: length - 1, through: 0, by: -1) {
                bytes[i] = UInt8(v & 0xFF)
                v >>= 8
            }
            bytes[0] |= UInt8(0x80 >> (length - 1))
            return bytes
        }

        static func element(_ elementID: UInt32, _ payload: [UInt8]) -> [UInt8] {
            id(elementID) + size(payload.count) + payload
        }

        static func uint(_ elementID: UInt32, _ value: UInt64) -> [UInt8] {
            var bytes: [UInt8] = []
            var v = value
            repeat {
                bytes.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            } while v > 0
            return element(elementID, bytes)
        }

        static func string(_ elementID: UInt32, _ text: String) -> [UInt8] {
            element(elementID, Array(text.utf8))
        }

        static func header() -> [UInt8] {
            element(0x1A45_DFA3, string(0x4282, "matroska"))
        }

        static func subtitleTrack(number: UInt64, codec: String) -> [UInt8] {
            element(0xAE, uint(0xD7, number) + uint(0x83, 17) + string(0x86, codec) + string(0x22B5_9C, "eng"))
        }

        static func simpleBlock(track: UInt8, relativeTimestamp: Int16, payload: [UInt8]) -> [UInt8] {
            let ts = UInt16(bitPattern: relativeTimestamp)
            return element(0xA3, [0x80 | track, UInt8(ts >> 8), UInt8(ts & 0xFF), 0x80] + payload)
        }

        static func cluster(timestamp: UInt64, blocks: [[UInt8]]) -> [UInt8] {
            element(0x1F43_B675, uint(0xE7, timestamp) + blocks.flatMap { $0 })
        }

        static func file(_ segmentChildren: [[UInt8]]) -> Data {
            Data(header() + element(0x1853_8067, segmentChildren.flatMap { $0 }))
        }
    }

    /// A Matroska file with enough cluster data that extraction takes long
    /// enough to observe.
    private func makeLargeMKV(at url: URL, clusters: Int, blocksPerCluster: Int) throws {
        // One PGS display set as Matroska stores it: bare segments of
        // type, length, payload, with none of the .sup framing.
        func segment(_ type: UInt8, _ body: [UInt8]) -> [UInt8] {
            [type, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
        }
        // Presentation composition: 1920x1080, epoch start, one object at 0,0.
        let pcs = segment(0x16, [0x07, 0x80, 0x04, 0x38, 0x10, 0x00, 0x01, 0x80,
                                 0x00, 0x00, 0x01,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        // Palette: index 1, opaque white.
        let pds = segment(0x14, [0x00, 0x00, 0x01, 235, 128, 128, 255])
        // Object: 4x2 solid, run-length encoded a line at a time.
        var rle: [UInt8] = []
        for _ in 0..<2 { rle += [0x00, 0x84, 0x01, 0x00, 0x00] }
        let dataLength = UInt32(rle.count + 4)
        let ods = segment(0x15, [0x00, 0x00, 0x00, 0xC0,
                                 UInt8((dataLength >> 16) & 0xFF),
                                 UInt8((dataLength >> 8) & 0xFF),
                                 UInt8(dataLength & 0xFF),
                                 0x00, 0x04, 0x00, 0x02] + rle)
        let payload = pcs + pds + ods + segment(0x80, [])
        var children: [[UInt8]] = [
            MKV.element(0x1549_A966, MKV.uint(0x2AD7_B1, 1_000_000)),
            MKV.element(0x1654_AE6B, MKV.subtitleTrack(number: 1, codec: "S_HDMV/PGS")),
        ]
        // Padding rides along as a second track's blocks, so the walk has real
        // bytes to step over without inflating the cue count.
        let filler = [UInt8](repeating: 0x00, count: 4096)
        for cluster in 0..<clusters {
            var blocks: [[UInt8]] = []
            for block in 0..<blocksPerCluster {
                blocks.append(MKV.simpleBlock(track: 2, relativeTimestamp: Int16(block), payload: filler))
            }
            blocks.append(MKV.simpleBlock(track: 1, relativeTimestamp: 0, payload: payload))
            children.append(MKV.cluster(timestamp: UInt64(cluster * 1000), blocks: blocks))
        }
        try MKV.file(children).write(to: url)
    }

    /// Shared mutable flags for the ordering check below.
    nonisolated private final class Flags: @unchecked Sendable {
        var loadDone = false
        var mainActorRanDuringLoad = false
    }

    /// A container carrying several PGS subtitle tracks.
    private func makeMultiTrackMKV(at url: URL, subtitleTracks: Int, clusters: Int) throws {
        func segment(_ type: UInt8, _ body: [UInt8]) -> [UInt8] {
            [type, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
        }
        let pcs = segment(0x16, [0x07, 0x80, 0x04, 0x38, 0x10, 0x00, 0x01, 0x80,
                                 0x00, 0x00, 0x01,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let pds = segment(0x14, [0x00, 0x00, 0x01, 235, 128, 128, 255])
        var rle: [UInt8] = []
        for _ in 0..<2 { rle += [0x00, 0x84, 0x01, 0x00, 0x00] }
        let dataLength = UInt32(rle.count + 4)
        let ods = segment(0x15, [0x00, 0x00, 0x00, 0xC0,
                                 UInt8((dataLength >> 16) & 0xFF),
                                 UInt8((dataLength >> 8) & 0xFF),
                                 UInt8(dataLength & 0xFF),
                                 0x00, 0x04, 0x00, 0x02] + rle)
        let payload = pcs + pds + ods + segment(0x80, [])

        var entries: [UInt8] = []
        for n in 1...subtitleTracks {
            entries += MKV.subtitleTrack(number: UInt64(n), codec: "S_HDMV/PGS")
        }
        var children: [[UInt8]] = [
            MKV.element(0x1549_A966, MKV.uint(0x2AD7_B1, 1_000_000)),
            MKV.element(0x1654_AE6B, entries),
        ]
        for cluster in 0..<clusters {
            var blocks: [[UInt8]] = []
            for n in 1...subtitleTracks {
                blocks.append(MKV.simpleBlock(track: UInt8(n), relativeTimestamp: 0, payload: payload))
            }
            children.append(MKV.cluster(timestamp: UInt64(cluster * 1000), blocks: blocks))
        }
        try MKV.file(children).write(to: url)
    }

    @Test func theMainActorIsFreeWhileAContainerIsRead() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("responsive-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mkv = dir.appendingPathComponent("large.mkv")
        try makeLargeMKV(at: mkv, clusters: 400, blocksPerCluster: 40)

        let file = QueueFile(source: try SubtitleSource.open(mkv))
        let track = QueueTrack(fileID: file.id, info: TrackInfo(id: 1, format: .pgs), isIncluded: true)
        file.tracks = [track]
        let cache = StreamCache(directory: dir.appendingPathComponent("cache"))

        let flags = Flags()
        let load = Task { @MainActor in
            let stream = try await ConversionRunner.loadStream(for: track, in: file, cache: cache)
            flags.loadDone = true
            return stream
        }

        // From off the main actor, keep asking to hop onto it. If the read
        // holds the main actor for its whole duration — which is what froze
        // the window — not one of these can land before the load finishes.
        // This is an ordering check, so other tests competing for the main
        // actor cannot make it flaky.
        let prober = Task.detached {
            while !flags.loadDone {
                await MainActor.run {
                    if !flags.loadDone { flags.mainActorRanDuringLoad = true }
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }

        let stream = try await load.value
        prober.cancel()

        #expect(stream.cues.count == 400)
        #expect(flags.mainActorRanDuringLoad,
                "the main actor never got a turn while the container was being read")
    }

    @Test func cancellingIsPropagatedToTheRead() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mkv = dir.appendingPathComponent("large.mkv")
        try makeLargeMKV(at: mkv, clusters: 400, blocksPerCluster: 40)

        let file = QueueFile(source: try SubtitleSource.open(mkv))
        let track = QueueTrack(fileID: file.id, info: TrackInfo(id: 1, format: .pgs), isIncluded: true)
        file.tracks = [track]
        let cache = StreamCache(directory: dir.appendingPathComponent("cache"))

        // Cancel before the read can get going. A detached task does not
        // inherit cancellation, so this only works because the wrapper wires
        // it through by hand.
        let load = Task {
            try await ConversionRunner.loadStream(for: track, in: file, cache: cache)
        }
        load.cancel()

        await #expect(throws: Error.self) { _ = try await load.value }
        #expect(track.stream == nil)
        #expect(track.loadState == .notLoaded, "a cancelled load leaves the track ready to try again")
    }

    @Test func everyBitmapTrackIsCachedFromOnePass() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("onepass-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let mkv = dir.appendingPathComponent("many.mkv")
        try makeMultiTrackMKV(at: mkv, subtitleTracks: 4, clusters: 60)

        let source = try SubtitleSource.open(mkv)
        let info = try source.probe()
        #expect(info.tracks.count == 4)

        let file = QueueFile(source: source)
        file.tracks = info.tracks.map { QueueTrack(fileID: file.id, info: $0, isIncluded: false) }
        file.state = .ready(info)
        let cache = StreamCache(directory: dir.appendingPathComponent("cache"))

        // Reading the first track walks the whole container, so the other
        // three come along for free instead of costing three more passes.
        _ = try await ConversionRunner.loadStream(for: file.tracks[0], in: file, cache: cache)

        for track in file.tracks {
            let key = StreamCache.key(for: mkv, track: track.info)
            #expect(cache.cachedURLs(for: key, format: track.info.format) != nil,
                    "track \(track.info.id) should already be cached")
        }

        // And the others load without touching the container again.
        for track in file.tracks.dropFirst() {
            let stream = try await ConversionRunner.loadStream(for: track, in: file, cache: cache)
            #expect(stream.cues.count == 60)
        }
    }
}
