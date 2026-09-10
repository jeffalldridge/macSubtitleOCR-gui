import Foundation
import os

/// A DVD VobSub subtitle stream: a `.sub` program stream plus its `.idx`.
public struct VobSubStream: SubtitleStream {
    public let format: BitmapSubtitleFormat = .vobsub
    public let cues: [CueInfo]
    public let warnings: [String]
    /// Language code from the `.idx` (`en`), if any.
    public let language: String?
    let data: Data
    let idx: VobSubIDX

    private static let logger = Logger(subsystem: "com.tentstudios.macSubtitleOCR", category: "engine.vobsub")

    public init(subURL: URL, idxURL: URL) throws {
        let idx = try VobSubIDX(url: idxURL)
        try self.init(sub: Data.mapped(contentsOf: subURL), idx: idx)
    }

    public init(sub: Data, idx idxText: String) throws {
        try self.init(sub: sub, idx: VobSubIDX(text: idxText))
    }

    init(sub: Data, idx: VobSubIDX) throws {
        data = sub
        self.idx = idx
        language = idx.language

        var cues: [CueInfo] = []
        var warnings: [String] = []
        sub.withUnsafeBytes { bytes in
            let entries = idx.entries
            for (i, entry) in entries.enumerated() {
                let next = i + 1 < entries.count ? entries[i + 1].offset : bytes.count
                guard entry.offset < bytes.count, next > entry.offset else {
                    warnings.append("Subpicture \(i + 1) points past the end of the .sub file.")
                    continue
                }
                do {
                    let packet = try VobSubPacket(bytes, offset: entry.offset, nextOffset: next)
                    warnings.append(contentsOf: packet.warnings)
                    let start = entry.timestamp + packet.startDelay
                    let end = packet.stopDelay.map { entry.timestamp + $0 }
                    cues.append(CueInfo(index: cues.count, start: start, end: end, byteRange: entry.offset..<next))
                } catch {
                    warnings.append("Subpicture \(i + 1) could not be read and was skipped.")
                }
            }
        }
        self.cues = cues
        self.warnings = warnings
        Self.logger.debug("Indexed \(cues.count) VobSub cues (\(warnings.count) warnings)")
    }

    public func bitmap(at index: Int) throws -> IndexedBitmap? {
        guard cues.indices.contains(index) else {
            throw EngineError.invalidData("Cue \(index + 1) does not exist.")
        }
        let range = cues[index].byteRange
        return try data.withUnsafeBytes { bytes in
            let packet = try VobSubPacket(bytes, offset: range.lowerBound, nextOffset: range.upperBound)
            return packet.bitmap(masterPalette: idx.palette)
        }
    }
}
