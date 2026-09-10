import Foundation

/// One recognized line of text with Vision's confidence (0…1).
public struct RecognizedLine: Sendable, Hashable, Codable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

/// The result of recognizing one cue.
public struct RecognizedCue: Sendable, Hashable, Codable, Identifiable {
    /// Below this confidence a cue is flagged for review.
    public static let reviewThreshold: Float = 0.6

    /// Zero-based cue index in its stream.
    public let index: Int
    public let start: TimeInterval
    public let end: TimeInterval?
    /// Lines joined with newlines, after corrections.
    public let text: String
    public let lines: [RecognizedLine]
    /// False when the cue had no visible bitmap to read.
    public let hadBitmap: Bool

    public var id: Int { index }

    public init(index: Int, start: TimeInterval, end: TimeInterval?, text: String,
                lines: [RecognizedLine], hadBitmap: Bool) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.lines = lines
        self.hadBitmap = hadBitmap
    }

    /// The lowest line confidence; 0 when a bitmap produced no lines.
    public var confidence: Float {
        if let lowest = lines.map(\.confidence).min() { return lowest }
        return hadBitmap ? 0 : 1
    }

    /// True when a person should look at this cue.
    public var needsReview: Bool {
        guard hadBitmap else { return false }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return confidence < Self.reviewThreshold
    }
}
