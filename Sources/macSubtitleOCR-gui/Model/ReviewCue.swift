import Foundation
import Observation
import SubtitleEngine

/// A recognized cue as shown and edited in the review list.
@Observable
final class ReviewCue: Identifiable {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let originalText: String
    let confidence: Float
    /// Whether recognition flagged this cue.
    let flagged: Bool
    /// Whether the cue's bitmap was readable at all.
    let hadBitmap: Bool

    var text: String
    /// Set when the user confirms a flagged cue is right as-is.
    var isMarkedReviewed = false

    var id: Int { index }

    init(recognized: RecognizedCue, end: TimeInterval) {
        index = recognized.index
        start = recognized.start
        self.end = end
        originalText = recognized.text
        text = recognized.text
        confidence = recognized.confidence
        flagged = recognized.needsReview
        hadBitmap = recognized.hadBitmap
    }

    init(index: Int, start: TimeInterval, end: TimeInterval, text: String, confidence: Float = 1,
         flagged: Bool = false, hadBitmap: Bool = true) {
        self.index = index
        self.start = start
        self.end = end
        originalText = text
        self.text = text
        self.confidence = confidence
        self.flagged = flagged
        self.hadBitmap = hadBitmap
    }

    var isEdited: Bool { text != originalText }

    /// Flagged and not yet fixed or confirmed.
    var needsReview: Bool { flagged && !isEdited && !isMarkedReviewed }

    /// 1-based number as written in the SRT.
    var number: Int { index + 1 }

    var srtCue: SRTCue {
        SRTCue(index: number, start: start, end: end, text: text)
    }

    func revert() {
        text = originalText
        isMarkedReviewed = false
    }
}
