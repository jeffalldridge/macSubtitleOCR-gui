import Foundation
import SubtitleEngine

/// Filtering and selection shared by the review table and its navigation controls.
enum CueReviewSelection {
    static func rows(in infos: [CueInfo], recognized: [ReviewCue], query: String,
                     needsReviewOnly: Bool) -> [CueRowModel] {
        let cues = Dictionary(uniqueKeysWithValues: recognized.map { ($0.index, $0) })
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return infos.compactMap { info in
            let cue = cues[info.index]
            if needsReviewOnly && !(cue?.needsReview ?? false) { return nil }
            // Formatting thousands of timestamps is unnecessary when no search is active.
            if !query.isEmpty {
                let matchesText = cue?.text.localizedStandardContains(query) ?? false
                if !matchesText && !Formatters.clock(info.start).contains(query) { return nil }
            }
            return CueRowModel(info: info, cue: cue)
        }
    }

    /// Keep the current cue where possible; reviewing a filtered cue advances
    /// to the next one rather than jumping back to the start of a long track.
    static func reconciled(_ selection: Int?, in ids: [Int]) -> Int? {
        guard let selection else { return ids.first }
        if ids.contains(selection) { return selection }
        return ids.first { $0 > selection } ?? ids.last
    }
}
