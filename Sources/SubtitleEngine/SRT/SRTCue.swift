import Foundation

/// One SubRip cue.
public struct SRTCue: Sendable, Hashable, Codable, Identifiable {
    /// 1-based cue number as written in the file.
    public var index: Int
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public var id: Int { index }

    public init(index: Int, start: TimeInterval, end: TimeInterval, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }

    public var duration: TimeInterval { end - start }
}
