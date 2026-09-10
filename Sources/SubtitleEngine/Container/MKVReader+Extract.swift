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
        let extracted = try extract(trackNumbers: [trackNumber], progress: progress)
        guard let track = extracted[trackNumber] else { throw EngineError.trackNotFound(trackNumber) }
        return track
    }

    /// Walk the clusters once and gather every frame of *several* tracks.
    ///
    /// Finding one track's blocks means reading a header in every cluster,
    /// spread across the whole file, so a container with eight subtitle
    /// tracks would otherwise cost eight full passes over it. Asking for all
    /// of them together costs one.
    public func extract(trackNumbers: [Int],
                        progress: (@Sendable (Double) -> Void)? = nil) throws -> [Int: ExtractedTrack] {
        let info = try probe()
        var wanted: [UInt64: TrackInfo] = [:]
        for number in trackNumbers {
            guard let track = info.tracks.first(where: { $0.id == number }) else {
                throw EngineError.trackNotFound(number)
            }
            wanted[UInt64(number)] = track
        }
        guard !wanted.isEmpty else { return [:] }

        let signposter = OSSignposter(logger: Self.logger)
        let state = signposter.beginInterval("extract")
        defer { signposter.endInterval("extract", state) }

        return try data.withUnsafeBytes { bytes in
            // The walk touches a header in every cluster, spread over the
            // whole file. Telling the kernel it is a sequential pass turns a
            // storm of small scattered faults into read-ahead.
            if let base = bytes.baseAddress, bytes.count > 0 {
                madvise(UnsafeMutableRawPointer(mutating: base), bytes.count, MADV_SEQUENTIAL)
            }

            let reader = EBMLReader(bytes: bytes)
            guard let segment = Self.segment(in: reader) else { throw EngineError.notMatroska(url) }

            var output: [UInt64: Data] = [:]
            var idxLines: [UInt64: String] = [:]
            for number in wanted.keys {
                output[number] = Data()
                idxLines[number] = ""
            }
            var cancelled = false
            var lastReported = -1
            let total = Double(max(bytes.count, 1))
            let scale = info.timestampScale

            func report(_ offset: Int) {
                guard let progress else { return }
                let percent = Int(Double(offset) / total * 100)
                if percent > lastReported {
                    lastReported = percent
                    progress(min(Double(percent) / 100, 1))
                }
            }

            func handle(block range: Range<Int>, clusterTimestamp: UInt64) {
                guard let block = MKVBlock(bytes, range: range),
                      let track = wanted[block.trackNumber] else { return }
                let number = block.trackNumber
                // Every term here comes straight out of the file, so all of
                // it saturates rather than traps. A nonsense timestamp yields
                // a nonsense cue time, which the user can see; a trap would
                // take the app down.
                let units = Int64(clamping: clusterTimestamp).addingReportingOverflow(Int64(block.relativeTimestamp))
                let ticks = units.overflow ? Int64.max : units.partialValue
                let nanoseconds = UInt64(max(ticks, 0)).multipliedReportingOverflow(by: scale)
                let pts90k = Self.ticks90kHz(nanoseconds: nanoseconds)
                for frame in block.frames where !frame.isEmpty {
                    let slice = bytes[frame]
                    switch track.format {
                    case .pgs:
                        MKVFrameWrapper.wrapPGS(slice, pts90k: UInt32(truncatingIfNeeded: pts90k),
                                                into: &output[number]!)
                    case .vobsub:
                        let position = output[number]!.count
                        MKVFrameWrapper.wrapVobSub(slice, pts90k: pts90k, into: &output[number]!)
                        idxLines[number]! += "timestamp: \(MKVFrameWrapper.idxTimestamp(pts90k: pts90k)), "
                        idxLines[number]! += String(format: "filepos: %09lX\n", position)
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

            var result: [Int: ExtractedTrack] = [:]
            for (number, track) in wanted {
                switch track.format {
                case .pgs:
                    result[Int(number)] = .pgs(output[number] ?? Data())
                case .vobsub:
                    result[Int(number)] = .vobsub(sub: output[number] ?? Data(),
                                                  idx: Self.synthesizeIDX(for: track,
                                                                          timestampLines: idxLines[number] ?? ""))
                }
            }
            return result
        }
    }

    /// Convert nanoseconds to 90 kHz ticks: `ns * 9 / 100_000`.
    ///
    /// Multiplies before dividing, or the division quantizes every timestamp
    /// to nine-tick steps for any timestamp scale that is not a multiple of
    /// 100 000. Saturates instead of trapping, because the inputs come out of
    /// the file.
    static func ticks90kHz(nanoseconds: (partialValue: UInt64, overflow: Bool)) -> UInt64 {
        guard !nanoseconds.overflow else { return UInt64.max / 100_000 }
        let scaled = nanoseconds.partialValue.multipliedReportingOverflow(by: 9)
        guard !scaled.overflow else { return UInt64.max / 100_000 }
        return scaled.partialValue / 100_000
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
