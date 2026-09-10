import SubtitleEngine
import Testing
@testable import macSubtitleOCR_gui

@Suite struct CueReviewSelectionTests {
    @Test func selectionAdvancesWhenAReviewedCueDisappears() {
        #expect(CueReviewSelection.reconciled(4, in: [1, 8, 12]) == 8)
        #expect(CueReviewSelection.reconciled(12, in: [1, 8]) == 8)
        #expect(CueReviewSelection.reconciled(8, in: [1, 8, 12]) == 8)
        #expect(CueReviewSelection.reconciled(nil, in: [1, 8]) == 1)
        #expect(CueReviewSelection.reconciled(8, in: []) == nil)
    }

    @Test func searchCombinesWithReviewAndMatchesAccentsAndTimestamps() {
        let infos = (0..<3).map {
            CueInfo(index: $0, start: Double($0 * 60), end: nil, byteRange: 0..<0)
        }
        let cues = [
            ReviewCue(index: 0, start: 0, end: 1, text: "Café", flagged: true),
            ReviewCue(index: 1, start: 60, end: 61, text: "CAFE", flagged: true),
            ReviewCue(index: 2, start: 120, end: 121, text: "Goodbye")
        ]
        cues[1].isMarkedReviewed = true
        func ids(_ query: String, review: Bool = false) -> [Int] {
            CueReviewSelection.rows(in: infos, recognized: cues, query: query,
                                    needsReviewOnly: review).map(\.id)
        }
        #expect(ids(" cafe ") == [0, 1])
        #expect(ids("cafe", review: true) == [0])
        #expect(ids("\n ") == [0, 1, 2])
        #expect(ids(Formatters.clock(120)) == [2])
        cues[0].isMarkedReviewed = true
        #expect(ids("", review: true).isEmpty)
    }
}
