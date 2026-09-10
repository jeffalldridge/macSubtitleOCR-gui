import Foundation

/// The `Cues` index: which cluster holds each track's data at each moment.
///
/// This is what lets a player seek without reading the file, and it is what
/// lets this engine pull a subtitle track out of a 30 GB remux without
/// reading 30 GB. Muxers commonly index every subtitle block, because
/// subtitles are sparse and indexing them is cheap.
struct MatroskaCues {
    /// Byte offsets are relative to the start of the Segment's data.
    struct Entry: Equatable {
        let time: UInt64
        let clusterPosition: Int
    }

    /// Cluster positions per track number, in file order, de-duplicated.
    let clustersByTrack: [UInt64: [Int]]

    var indexedTracks: Set<UInt64> { Set(clustersByTrack.keys) }

    func clusters(forTracks tracks: [UInt64]) -> [Int]? {
        var positions: Set<Int> = []
        for track in tracks {
            guard let entries = clustersByTrack[track], !entries.isEmpty else { return nil }
            positions.formUnion(entries)
        }
        return positions.sorted()
    }

    /// Parse the `Cues` element, wherever it lives.
    ///
    /// It is usually at the end of the file, reachable through the `SeekHead`
    /// at the front; some muxers put it before the clusters instead.
    static func parse(reader: EBMLReader, segment: EBMLReader.Element) -> MatroskaCues? {
        guard let cues = locate(reader: reader, segment: segment) else { return nil }

        var byTrack: [UInt64: [Int]] = [:]
        reader.forEachChild(of: cues) { point in
            guard point.id == MatroskaID.cuePoint else { return true }
            var time: UInt64 = 0
            reader.forEachChild(of: point) { field in
                switch field.id {
                case MatroskaID.cueTime:
                    time = reader.uint(field) ?? 0
                case MatroskaID.cueTrackPositions:
                    var track: UInt64?
                    var position: Int?
                    reader.forEachChild(of: field) { entry in
                        switch entry.id {
                        case MatroskaID.cueTrack: track = reader.uint(entry)
                        case MatroskaID.cueClusterPosition: position = reader.uint(entry).map(Int.init)
                        default: break
                        }
                        return true
                    }
                    if let track, let position, position >= 0 {
                        byTrack[track, default: []].append(position)
                    }
                default:
                    break
                }
                _ = time
                return true
            }
            return true
        }

        guard !byTrack.isEmpty else { return nil }
        // The same cluster is indexed once per block it holds; one visit each
        // is enough, and every block inside is read when we get there.
        for (track, positions) in byTrack {
            byTrack[track] = Array(Set(positions)).sorted()
        }
        return MatroskaCues(clustersByTrack: byTrack)
    }

    private static func locate(reader: EBMLReader, segment: EBMLReader.Element) -> EBMLReader.Element? {
        // Before the clusters, if it is there at all.
        var found: EBMLReader.Element?
        var seekHead: EBMLReader.Element?
        reader.forEachChild(of: segment) { child in
            switch child.id {
            case MatroskaID.cues:
                found = child
                return false
            case MatroskaID.seekHead:
                if seekHead == nil { seekHead = child }
            case MatroskaID.cluster:
                return false // past the header; ask the SeekHead instead
            default:
                break
            }
            return true
        }
        if let found { return found }

        // Otherwise follow the SeekHead, whose positions are relative to the
        // start of the Segment's data.
        guard let seekHead else { return nil }
        var cuesPosition: Int?
        reader.forEachChild(of: seekHead) { seek in
            guard seek.id == MatroskaID.seek, cuesPosition == nil else { return true }
            var seekID: UInt64 = 0
            var position: Int?
            reader.forEachChild(of: seek) { field in
                switch field.id {
                case MatroskaID.seekID:
                    if let data = reader.data(field) {
                        seekID = data.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    }
                case MatroskaID.seekPosition:
                    position = reader.uint(field).map(Int.init)
                default:
                    break
                }
                return true
            }
            if seekID == UInt64(MatroskaID.cues), let position { cuesPosition = position }
            return true
        }

        guard let cuesPosition else { return nil }
        let absolute = segment.dataOffset + cuesPosition
        guard absolute >= 0, absolute < reader.bytes.count,
              let element = reader.element(at: absolute), element.id == MatroskaID.cues else { return nil }
        return element
    }
}
