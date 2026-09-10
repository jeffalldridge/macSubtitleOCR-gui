import Foundation

/// One subtitle cue's position in a stream: when it is shown and where its
/// bytes live, so it can be decoded on demand.
public struct CueInfo: Sendable, Hashable, Identifiable {
    /// Zero-based position in the stream.
    public let index: Int
    public let start: TimeInterval
    /// Nil when the stream never clears the cue (typically the last one).
    public let end: TimeInterval?
    /// Byte range of the display set (PGS) or subpicture (VobSub).
    public let byteRange: Range<Int>

    public var id: Int { index }

    public init(index: Int, start: TimeInterval, end: TimeInterval?, byteRange: Range<Int>) {
        self.index = index
        self.start = start
        self.end = end
        self.byteRange = byteRange
    }

    public var duration: TimeInterval? { end.map { $0 - start } }
}

/// A decoded-on-demand bitmap subtitle stream.
///
/// Indexing is cheap (no run-length decoding); `bitmap(at:)` decodes one cue.
public protocol SubtitleStream: Sendable {
    var format: BitmapSubtitleFormat { get }
    var cues: [CueInfo] { get }
    /// Non-fatal problems found while indexing, written for the user.
    var warnings: [String] { get }
    /// The cue's bitmap, or nil when the cue defines no visible image.
    func bitmap(at index: Int) throws -> IndexedBitmap?
}

extension SubtitleStream {
    public var count: Int { cues.count }
    public var isEmpty: Bool { cues.isEmpty }
}
