import Foundation
import Testing
@testable import SubtitleEngine

/// Pulling one subtitle track out of a 30 GB remux must not mean reading
/// 30 GB. The `Cues` index says which clusters hold the track, so only those
/// are read — but only if the index is found and trusted correctly.
@Suite struct MatroskaCuesTests {
    // MARK: - Building indexed files

    /// A SeekPosition written in a fixed width, so adding the real offset
    /// later cannot change the size of the SeekHead that contains it.
    private static func fixedUInt(_ id: UInt32, _ value: UInt64, width: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width)
        var v = value
        for i in stride(from: width - 1, through: 0, by: -1) {
            bytes[i] = UInt8(v & 0xFF)
            v >>= 8
        }
        return EBMLBuilder.element(id, bytes)
    }

    private static func seekHead(cuesPosition: Int) -> [UInt8] {
        let seek = EBMLBuilder.element(MatroskaID.seek, [
            EBMLBuilder.binary(MatroskaID.seekID, EBMLBuilder.idBytes(MatroskaID.cues)),
            fixedUInt(MatroskaID.seekPosition, UInt64(cuesPosition), width: 8),
        ])
        return EBMLBuilder.element(MatroskaID.seekHead, seek)
    }

    private static func cues(_ entries: [(time: UInt64, track: UInt64, position: Int)]) -> [UInt8] {
        let points = entries.map { entry in
            EBMLBuilder.element(MatroskaID.cuePoint, [
                EBMLBuilder.uint(MatroskaID.cueTime, entry.time),
                EBMLBuilder.element(MatroskaID.cueTrackPositions, [
                    EBMLBuilder.uint(MatroskaID.cueTrack, entry.track),
                    EBMLBuilder.uint(MatroskaID.cueClusterPosition, UInt64(entry.position)),
                ]),
            ])
        }
        return EBMLBuilder.element(MatroskaID.cues, points)
    }

    /// One PGS display set: a white block with a palette, so it decodes.
    private static func displaySet(pts: TimeInterval) -> [UInt8] {
        var bytes = PGSBuilder.pcs(pts: pts, state: 0x80, objects: [PGSBuilder.Object(id: 0, x: 0, y: 0)])
        bytes += PGSBuilder.pds(pts: pts, id: 0, entries: PGSBuilder.standardPalette)
        bytes += PGSBuilder.ods(pts: pts, id: 0, width: 8, height: 4, color: 1)
        bytes += PGSBuilder.end(pts: pts)
        return PGSBuilder.bareSegments(bytes)
    }

    private static func clusters(count: Int, track: UInt8) -> [[UInt8]] {
        (0..<count).map { index in
            EBMLBuilder.cluster(timestamp: UInt64(index) * 1000, blocks: [
                EBMLBuilder.simpleBlock(track: track, relativeTimestamp: 0,
                                        payload: displaySet(pts: TimeInterval(index))),
                EBMLBuilder.simpleBlock(track: track, relativeTimestamp: 500,
                                        payload: PGSBuilder.bareSegments(PGSBuilder.clear(pts: TimeInterval(index) + 0.5))),
            ])
        }
    }

    /// `header` + clusters + `Cues` at the end, with a SeekHead pointing at it —
    /// the layout almost every muxer writes.
    private static func indexedFile(trackCount: Int = 1,
                                    clusterCount: Int = 4,
                                    indexing: (Int) -> [(time: UInt64, track: UInt64, position: Int)]) -> Data {
        let entries = (1...trackCount).map { number in
            EBMLBuilder.subtitleTrack(number: UInt64(number), codec: "S_HDMV/PGS")
        }
        let header = EBMLBuilder.info() + EBMLBuilder.tracks(entries)
        let clusterBlocks = clusters(count: clusterCount, track: 1)

        // The SeekHead is a fixed size, so its own length is known before the
        // position it carries is.
        let seekHeadLength = seekHead(cuesPosition: 0).count
        var offsets: [Int] = []
        var running = seekHeadLength + header.count
        for cluster in clusterBlocks {
            offsets.append(running)
            running += cluster.count
        }

        let cuesBlock = cues(indexing(clusterCount).map { entry in
            (time: entry.time, track: entry.track, position: offsets[entry.position])
        })
        return EBMLBuilder.file([seekHead(cuesPosition: running), header]
                                + clusterBlocks + [cuesBlock])
    }

    /// The reader borrows the file's bytes, so the index is inspected inside
    /// the borrow rather than escaping it.
    private func withCues<T>(_ data: Data, _ body: (MatroskaCues?) throws -> T) rethrows -> T {
        try data.withUnsafeBytes { buffer in
            let reader = EBMLReader(bytes: buffer)
            guard let segment = MKVReader.segment(in: reader) else { return try body(nil) }
            return try body(MatroskaCues.parse(reader: reader, segment: segment))
        }
    }

    // MARK: - Finding the index

    @Test func followsTheSeekHeadToCuesAtTheEndOfTheFile() throws {
        let data = Self.indexedFile { count in
            (0..<count).map { (time: UInt64($0) * 1000, track: 1, position: $0) }
        }
        try withCues(data) { cues in
            let cues = try #require(cues)
            #expect(cues.indexedTracks == [1])
            #expect(cues.clusters(forTracks: [1])?.count == 4)
        }
    }

    @Test func findsCuesWrittenBeforeTheClusters() throws {
        // Some muxers put the index up front; there is no SeekHead to follow.
        let header = EBMLBuilder.info() + EBMLBuilder.tracks([
            EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS"),
        ])
        let clusterBlocks = Self.clusters(count: 3, track: 1)
        let placeholder = Self.cues([(time: 0, track: 1, position: 0)])
        var running = placeholder.count + header.count
        var offsets: [Int] = []
        for cluster in clusterBlocks {
            offsets.append(running)
            running += cluster.count
        }
        let real = Self.cues(offsets.enumerated().map { (time: UInt64($0.offset), track: 1, position: $0.element) })
        #expect(real.count >= placeholder.count, "offsets only ever grow the index")

        // Re-measure with the real index in place so the offsets stay true.
        running = real.count + header.count
        offsets = []
        for cluster in clusterBlocks {
            offsets.append(running)
            running += cluster.count
        }
        let final = Self.cues(offsets.enumerated().map { (time: UInt64($0.offset), track: 1, position: $0.element) })
        let data = EBMLBuilder.file([final, header] + clusterBlocks)

        try withCues(data) { cues in
            let cues = try #require(cues)
            #expect(cues.clusters(forTracks: [1]) == offsets)
        }
    }

    @Test func aFileWithNoIndexIsNotPretendedToHaveOne() throws {
        let data = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
        ] + Self.clusters(count: 2, track: 1))
        withCues(data) { #expect($0 == nil) }
    }

    @Test func repeatedEntriesForOneClusterAreVisitedOnce() throws {
        // A muxer indexes every block, so the same cluster appears many times.
        let data = Self.indexedFile(clusterCount: 3) { count in
            (0..<count).flatMap { index in
                (0..<5).map { (time: UInt64(index * 10 + $0), track: UInt64(1), position: index) }
            }
        }
        try withCues(data) { cues in
            let cues = try #require(cues)
            #expect(cues.clusters(forTracks: [1])?.count == 3, "three clusters, not fifteen visits")
        }
    }

    // MARK: - Deciding whether the index can be used

    @Test func anUnindexedTrackFallsBackToAFullScan() throws {
        // Track 2 exists but only track 1 is in the index. Reading only the
        // indexed clusters would silently lose track 2's subtitles.
        let entries = [1, 2].map { EBMLBuilder.subtitleTrack(number: UInt64($0), codec: "S_HDMV/PGS") }
        let header = EBMLBuilder.info() + EBMLBuilder.tracks(entries)
        let clusterBlocks = Self.clusters(count: 2, track: 1)
        let seekHeadLength = Self.seekHead(cuesPosition: 0).count
        var running = seekHeadLength + header.count
        var offsets: [Int] = []
        for cluster in clusterBlocks {
            offsets.append(running)
            running += cluster.count
        }
        let cuesBlock = Self.cues(offsets.map { (time: 0, track: UInt64(1), position: $0) })
        let data = EBMLBuilder.file([Self.seekHead(cuesPosition: running), header]
                                    + clusterBlocks + [cuesBlock])

        try withCues(data) { cues in
            let cues = try #require(cues)
            #expect(cues.clusters(forTracks: [1]) != nil)
            #expect(cues.clusters(forTracks: [2]) == nil, "no index for this track")
            #expect(cues.clusters(forTracks: [1, 2]) == nil, "so the pair cannot use the index either")
        }

        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/partial.mkv"))
        #expect(reader.indexes(trackNumbers: [1]))
        #expect(!reader.indexes(trackNumbers: [2]))
        #expect(!reader.indexes(trackNumbers: [1, 2]))
    }

    @Test func aCuesPositionOutsideTheFileIsIgnored() throws {
        let header = EBMLBuilder.info() + EBMLBuilder.tracks([
            EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS"),
        ])
        let data = EBMLBuilder.file([Self.seekHead(cuesPosition: 1 << 40), header]
                                    + Self.clusters(count: 1, track: 1))
        withCues(data) { #expect($0 == nil, "a bad pointer means no index, not a crash") }
        // And the track still reads, by scanning.
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/badseek.mkv"))
        guard case .pgs(let extracted) = try reader.extract(trackNumber: 1) else {
            Issue.record("expected PGS")
            return
        }
        #expect(try PGSStream(data: extracted).cues.count == 1)
    }

    // MARK: - The index must not change what is extracted

    @Test func theIndexedReadFindsExactlyWhatAFullScanFinds() throws {
        let indexed = Self.indexedFile(clusterCount: 5) { count in
            (0..<count).map { (time: UInt64($0) * 1000, track: 1, position: $0) }
        }
        let unindexed = EBMLBuilder.file([
            EBMLBuilder.info(),
            EBMLBuilder.tracks([EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS")]),
        ] + Self.clusters(count: 5, track: 1))

        let indexedReader = try MKVReader(data: indexed, url: URL(fileURLWithPath: "/indexed.mkv"))
        #expect(indexedReader.indexes(trackNumbers: [1]), "this file is read through its index")
        let plainReader = try MKVReader(data: unindexed, url: URL(fileURLWithPath: "/plain.mkv"))
        #expect(!plainReader.indexes(trackNumbers: [1]), "and this one by scanning")

        guard case .pgs(let fromIndex) = try indexedReader.extract(trackNumber: 1),
              case .pgs(let fromScan) = try plainReader.extract(trackNumber: 1) else {
            Issue.record("expected PGS from both")
            return
        }
        let indexedCues = try PGSStream(data: fromIndex).cues
        let scannedCues = try PGSStream(data: fromScan).cues
        #expect(indexedCues.count == 5)
        #expect(indexedCues.map(\.start) == scannedCues.map(\.start))
        #expect(indexedCues.map(\.end) == scannedCues.map(\.end))
    }

    @Test func aPartialIndexIsTakenAtItsWord() throws {
        // The index names clusters 0 and 2; cluster 1 also holds the track.
        // Trusting a partial index would drop the middle subtitle.
        let full = Self.indexedFile(clusterCount: 3) { count in
            (0..<count).map { (time: UInt64($0), track: 1, position: $0) }
        }
        let partial = Self.indexedFile(clusterCount: 3) { _ in
            [(time: 0, track: 1, position: 0), (time: 2, track: 1, position: 2)]
        }
        let fullReader = try MKVReader(data: full, url: URL(fileURLWithPath: "/full.mkv"))
        let partialReader = try MKVReader(data: partial, url: URL(fileURLWithPath: "/partial.mkv"))

        guard case .pgs(let a) = try fullReader.extract(trackNumber: 1),
              case .pgs(let b) = try partialReader.extract(trackNumber: 1) else {
            Issue.record("expected PGS from both")
            return
        }
        #expect(try PGSStream(data: a).cues.count == 3)
        #expect(try PGSStream(data: b).cues.count == 2,
                """
                An index that names some of a track's clusters is trusted for all of them. \
                Every muxer that indexes a subtitle track indexes every one of its blocks, \
                and the alternative is reading the whole file on every open.
                """)
    }

    @Test func anIndexThatPointsAtTheWrongClustersFallsBackToScanning() throws {
        // A stale index — the file was edited after it was written — names
        // clusters that hold nothing for this track. Believing it would
        // report an empty track rather than the subtitles that are there.
        let header = EBMLBuilder.info() + EBMLBuilder.tracks([
            EBMLBuilder.subtitleTrack(number: 1, codec: "S_HDMV/PGS"),
        ])
        // One cluster of the wanted track, and one holding an unrelated track
        // that the index points at instead.
        let decoy = EBMLBuilder.cluster(timestamp: 9000, blocks: [
            EBMLBuilder.simpleBlock(track: 7, relativeTimestamp: 0, payload: [0x16, 0x00, 0x00]),
        ])
        let real = Self.clusters(count: 1, track: 1)[0]
        let seekHeadLength = Self.seekHead(cuesPosition: 0).count
        let decoyOffset = seekHeadLength + header.count
        let cuesOffset = decoyOffset + decoy.count + real.count

        let cuesBlock = Self.cues([(time: 0, track: 1, position: decoyOffset)])
        let data = EBMLBuilder.file([Self.seekHead(cuesPosition: cuesOffset), header, decoy, real, cuesBlock])

        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/stale.mkv"))
        #expect(reader.indexes(trackNumbers: [1]), "the index claims to cover the track")
        guard case .pgs(let extracted) = try reader.extract(trackNumber: 1) else {
            Issue.record("expected PGS")
            return
        }
        #expect(try PGSStream(data: extracted).cues.count == 1,
                "the subtitle is found anyway, by reading the file")
    }

    // MARK: - Taking the other tracks along

    @Test func anIndexedTrackIsTakenAloneEvenWhenOthersAreOffered() throws {
        let data = Self.indexedFile(trackCount: 2, clusterCount: 3) { count in
            (0..<count).flatMap { index in
                [(time: UInt64(index), track: UInt64(1), position: index),
                 (time: UInt64(index), track: UInt64(2), position: index)]
            }
        }
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/both.mkv"))
        let extracted = try reader.extract(trackNumbers: [1], orAlso: [2])
        #expect(extracted.keys.sorted() == [1],
                "the index reaches track 1 directly, so track 2 is nobody's business")
    }

    @Test func anUnindexedTrackBringsTheOthersWithIt() throws {
        // No cues at all: one scan of the file, so everything offered comes
        // out of it rather than costing another scan each.
        let entries = [1, 2, 3].map { EBMLBuilder.subtitleTrack(number: UInt64($0), codec: "S_HDMV/PGS") }
        var clusters: [[UInt8]] = []
        for index in 0..<2 {
            clusters.append(EBMLBuilder.cluster(timestamp: UInt64(index) * 1000, blocks: [1, 2, 3].flatMap { track in
                [EBMLBuilder.simpleBlock(track: UInt8(track), relativeTimestamp: 0,
                                         payload: Self.displaySet(pts: TimeInterval(index))),
                 EBMLBuilder.simpleBlock(track: UInt8(track), relativeTimestamp: 500,
                                         payload: PGSBuilder.bareSegments(PGSBuilder.clear(pts: TimeInterval(index) + 0.5)))]
            }))
        }
        let data = EBMLBuilder.file([EBMLBuilder.info(), EBMLBuilder.tracks(entries)] + clusters)

        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/noindex.mkv"))
        #expect(!reader.indexes(trackNumbers: [1]))
        let extracted = try reader.extract(trackNumbers: [1], orAlso: [2, 3])
        #expect(extracted.keys.sorted() == [1, 2, 3])
        for number in [1, 2, 3] {
            guard case .pgs(let bytes) = try #require(extracted[number]) else {
                Issue.record("expected PGS for track \(number)")
                continue
            }
            #expect(try PGSStream(data: bytes).cues.count == 2, "track \(number) came out whole")
        }
    }

    @Test func aTrackOfferedButNotPresentIsSimplySkipped() throws {
        let data = Self.indexedFile(clusterCount: 2) { _ in [] }
        let reader = try MKVReader(data: data, url: URL(fileURLWithPath: "/one.mkv"))
        let extracted = try reader.extract(trackNumbers: [1], orAlso: [9])
        #expect(extracted.keys.sorted() == [1], "an offer is not a demand")
        #expect(throws: EngineError.trackNotFound(9)) {
            _ = try reader.extract(trackNumbers: [9], orAlso: [1])
        }
    }
}
