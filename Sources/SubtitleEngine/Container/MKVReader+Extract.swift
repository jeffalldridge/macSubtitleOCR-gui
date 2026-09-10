import Foundation
import os

/// A bitmap subtitle track pulled out of a container, in the format the
/// standalone decoders read.
public enum ExtractedTrack: Sendable {
    case pgs(Data)
    case vobsub(sub: Data, idx: String)

    public var format: BitmapSubtitleFormat {
        switch self {
        case .pgs: .pgs
        case .vobsub: .vobsub
        }
    }
}

extension MKVReader {
    /// Walk the clusters once and gather every frame of `trackNumber`.
    ///
    /// `progress` is called with 0…1 as the file is scanned. Honors task
    /// cancellation between clusters (throws `EngineError.cancelled`).
    public func extract(trackNumber: Int,
                        progress: (@Sendable (Double) -> Void)? = nil) throws -> ExtractedTrack {
        let info = try probe()
        guard let track = info.tracks.first(where: { $0.id == trackNumber }) else {
            throw EngineError.trackNotFound(trackNumber)
        }
        let signposter = OSSignposter(logger: Self.logger)
        let state = signposter.beginInterval("extract")
        defer { signposter.endInterval("extract", state) }

        return try data.withUnsafeBytes { bytes in
            let reader = EBMLReader(bytes: bytes)
            guard let segment = Self.segment(in: reader) else { throw EngineError.notMatroska(url) }

            var output = Data()
            var idxLines = ""
            var cancelled = false
            var lastReported = -1
            let total = Double(max(bytes.count, 1))
            let scale = info.timestampScale
            let wanted = UInt64(trackNumber)

            func report(_ offset: Int) {
                guard let progress else { return }
                let percent = Int(Double(offset) / total * 100)
                if percent > lastReported {
                    lastReported = percent
                    progress(min(Double(percent) / 100, 1))
                }
            }

            func handle(block range: Range<Int>, clusterTimestamp: UInt64) {
                guard let block = MKVBlock(bytes, range: range), block.trackNumber == wanted else { return }
                // Every term here comes straight out of the file, so all of
                // it saturates rather than traps. A nonsense timestamp yields
                // a nonsense cue time, which the user can see; a trap would
                // take the app down.
                let units = Int64(clamping: clusterTimestamp).addingReportingOverflow(Int64(block.relativeTimestamp))
                let ticks = units.overflow ? Int64.max : units.partialValue
                let nanoseconds = UInt64(max(ticks, 0)).multipliedReportingOverflow(by: scale)
                let pts90k = nanoseconds.overflow ? UInt64.max / 100_000 : nanoseconds.partialValue / 100_000 * 9
                for frame in block.frames where !frame.isEmpty {
                    let slice = bytes[frame]
                    switch track.format {
                    case .pgs:
                        MKVFrameWrapper.wrapPGS(slice, pts90k: UInt32(truncatingIfNeeded: pts90k), into: &output)
                    case .vobsub:
                        let position = output.count
                        MKVFrameWrapper.wrapVobSub(slice, pts90k: pts90k, into: &output)
                        idxLines += "timestamp: \(MKVFrameWrapper.idxTimestamp(pts90k: pts90k)), "
                        idxLines += String(format: "filepos: %09lX\n", position)
                    }
                }
            }

            reader.forEachChild(of: segment) { child in
                if Task.isCancelled {
                    cancelled = true
                    return false
                }
                guard child.id == MatroskaID.cluster else { return true }
                var clusterTimestamp: UInt64 = 0
                reader.forEachChild(of: child) { element in
                    switch element.id {
                    case MatroskaID.timestamp:
                        clusterTimestamp = reader.uint(element) ?? 0
                    case MatroskaID.simpleBlock:
                        handle(block: element.dataRange, clusterTimestamp: clusterTimestamp)
                    case MatroskaID.blockGroup:
                        reader.forEachChild(of: element) { inner in
                            if inner.id == MatroskaID.block {
                                handle(block: inner.dataRange, clusterTimestamp: clusterTimestamp)
                            }
                            return true
                        }
                    default:
                        break
                    }
                    return true
                }
                report(child.endOffset)
                return true
            }

            if cancelled { throw EngineError.cancelled }
            progress?(1)

            switch track.format {
            case .pgs:
                return .pgs(output)
            case .vobsub:
                return .vobsub(sub: output, idx: Self.synthesizeIDX(for: track, timestampLines: idxLines))
            }
        }
    }

    /// Build the `.idx` text for a VobSub track: the container's codec
    /// private data (palette, size) plus one line per subpicture.
    static func synthesizeIDX(for track: TrackInfo, timestampLines: String) -> String {
        var text = "# VobSub index file, v7 (do not modify this line!)\n"
        if let codecPrivate = track.codecPrivate,
           let header = String(data: codecPrivate, encoding: .utf8) ?? String(data: codecPrivate, encoding: .isoLatin1) {
            let cleaned = header.replacingOccurrences(of: "\0", with: "")
            text += cleaned
            if !cleaned.hasSuffix("\n") { text += "\n" }
        }
        text += "langidx: 0\n"
        text += "\nid: \(track.language ?? "und"), index: 0\n"
        text += timestampLines
        return text
    }
}
